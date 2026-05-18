// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMintable, ISaleConfig, IDepositVerifier} from "../interfaces/ISale.sol";
import {SaleConstants} from "./SaleConstants.sol";

/**
 * @title  DepositVerifier
 * @author Pars Protocol
 * @notice Multi-chain deposit verifier for the sale token (IMintable, e.g., ASHA).
 * @dev    Users deposit on any supported chain (BTC, ETH, SOL, TON, XRP, LUX, PARS).
 *         An off-chain relay verifies deposits and builds merkle trees of verified deposits.
 *         The relay submits merkle roots on-chain. Users then claim tokens by proving
 *         their deposit's inclusion in a submitted root.
 *
 *         Mint calculation:
 *           tokensMinted = amountSats * 1e9 / satsPerToken
 *
 *         Where amountSats is the BTC-equivalent value of the deposit (computed off-chain
 *         by the relay and baked into the merkle leaf), and satsPerToken is the current
 *         rate (e.g., if 1 token = 100 sats, satsPerToken = 100).
 *
 *         The DepositVerifier must be granted minting authority on the sale token
 *         (for ASHA: set as the vault in ParsAuthority).
 *
 *         Security:
 *         - Merkle proof verification (OpenZeppelin MerkleProof)
 *         - AccessControl with ADMIN_ROLE and RELAYER_ROLE
 *         - ReentrancyGuard on claim functions
 *         - Pausable for emergency stops
 *         - Double-claim prevention via sourceTxHash mapping
 */
contract DepositVerifier is AccessControl, Pausable, ReentrancyGuard, IDepositVerifier {
    using SafeERC20 for IERC20;

    // =========  ROLES ========= //

    /// @notice Role for admin operations (set rates, tokens, pause).
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for the relay that submits merkle roots.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // =========  ERRORS ========= //

    error DepositVerifier_InvalidProof();
    error DepositVerifier_AlreadyClaimed(bytes32 sourceTxHash);
    error DepositVerifier_InvalidMintRate();
    error DepositVerifier_InvalidToken();
    error DepositVerifier_InvalidRoot();
    error DepositVerifier_LengthMismatch();
    error DepositVerifier_SaleNotActive();
    error DepositVerifier_ZeroAmount();
    error DepositVerifier_InvalidChain(uint8 chain);

    // =========  STATE ========= //

    /// @notice The token to mint for depositors.
    address public mintToken;

    /// @notice Satoshis per 1 token (with 1e9 precision for the token).
    /// @dev    tokensMinted = amountSats * 1e9 / satsPerToken
    uint256 public satsPerToken;

    /// @notice Sale configuration contract.
    ISaleConfig public saleConfig;

    /// @notice Mapping of batch index to merkle root.
    mapping(uint256 => bytes32) public roots;

    /// @notice Total number of batches submitted.
    uint256 public batchCount;

    /// @notice Total deposits recorded across all batches.
    uint256 public totalDepositsRecorded;

    /// @notice Whether a source tx hash has been claimed (prevents double-claims).
    mapping(bytes32 => bool) public claimed;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new DepositVerifier.
     * @param  admin_      The initial admin address.
     * @param  saleConfig_ The sale configuration contract.
     * @param  mintToken_  The token to mint for depositors.
     * @param  satsPerToken_ Initial sats-per-token rate.
     */
    constructor(
        address admin_,
        address saleConfig_,
        address mintToken_,
        uint256 satsPerToken_
    ) {
        require(admin_ != address(0), "DepositVerifier: invalid admin");
        require(saleConfig_ != address(0), "DepositVerifier: invalid config");
        require(mintToken_ != address(0), "DepositVerifier: invalid token");
        require(satsPerToken_ > 0, "DepositVerifier: invalid rate");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(RELAYER_ROLE, admin_);

        saleConfig = ISaleConfig(saleConfig_);
        mintToken = mintToken_;
        satsPerToken = satsPerToken_;
    }

    // =========  RELAYER FUNCTIONS ========= //

    /**
     * @notice Submit a merkle root for a batch of verified deposits.
     * @dev    Only callable by addresses with RELAYER_ROLE.
     *         The relay builds a merkle tree off-chain from verified deposits,
     *         where each leaf = keccak256(abi.encode(deposit)).
     * @param  root          The merkle root of the deposit batch.
     * @param  totalDeposits The number of deposits in this batch.
     */
    function submitRoot(
        bytes32 root,
        uint256 totalDeposits
    ) external override onlyRole(RELAYER_ROLE) whenNotPaused {
        if (root == bytes32(0)) revert DepositVerifier_InvalidRoot();

        uint256 batchIndex = batchCount;
        roots[batchIndex] = root;
        batchCount = batchIndex + 1;
        totalDepositsRecorded += totalDeposits;

        emit RootSubmitted(root, totalDeposits, batchIndex);
    }

    // =========  CLAIM FUNCTIONS ========= //

    /**
     * @notice Claim tokens by proving deposit inclusion in a submitted merkle root.
     * @dev    Anyone can call this for any deposit (allows third-party claiming).
     *         Tokens are always minted to deposit.depositor.
     * @param  proof   Merkle proof of the deposit's inclusion.
     * @param  deposit The deposit data.
     */
    function claim(
        bytes32[] calldata proof,
        Deposit calldata deposit
    ) external override nonReentrant whenNotPaused {
        _claim(proof, deposit);
    }

    /**
     * @notice Batch claim multiple deposits in a single transaction.
     * @param  proofs   Array of merkle proofs.
     * @param  deposits Array of deposit data.
     */
    function claimBatch(
        bytes32[][] calldata proofs,
        Deposit[] calldata deposits
    ) external override nonReentrant whenNotPaused {
        if (proofs.length != deposits.length) revert DepositVerifier_LengthMismatch();

        for (uint256 i = 0; i < deposits.length; i++) {
            _claim(proofs[i], deposits[i]);
        }
    }

    // =========  DIRECT RELAY FUNCTIONS ========= //

    /**
     * @notice Direct deposit processing by authorized relayer (simple mode).
     * @dev    Called by the relay service after verifying the source chain tx.
     *         Bypasses merkle proof — the relayer is trusted to have verified the deposit.
     * @param  sourceTxHash The transaction hash on the source chain.
     * @param  sourceChain  The source chain enum (0=BTC, 1=ETH, 2=SOL, 3=TON, 4=XRP, 5=LUX, 6=PARS, 7=BSC, 8=BASE, 9=ARB, 10=POLYGON, 11=ZOO, 12=HANZO).
     * @param  depositor    The Pars address to mint tokens to.
     * @param  amountSats   The deposit amount in BTC-equivalent satoshis.
     * @param  depositTime  The timestamp of the source chain tx.
     */
    function processDeposit(
        bytes32 sourceTxHash,
        uint8 sourceChain,
        address depositor,
        uint256 amountSats,
        uint256 depositTime
    ) external onlyRole(RELAYER_ROLE) whenNotPaused nonReentrant {
        _processDeposit(sourceTxHash, sourceChain, depositor, amountSats, depositTime);
    }

    /**
     * @notice Batch-process multiple deposits in a single transaction.
     * @dev    All arrays must have the same length.
     * @param  sourceTxHashes Array of source chain transaction hashes.
     * @param  sourceChains   Array of source chain enum values.
     * @param  depositors     Array of Pars addresses to mint tokens to.
     * @param  amountsSats    Array of deposit amounts in BTC-equivalent satoshis.
     * @param  depositTimes   Array of source chain tx timestamps.
     */
    function processDepositBatch(
        bytes32[] calldata sourceTxHashes,
        uint8[] calldata sourceChains,
        address[] calldata depositors,
        uint256[] calldata amountsSats,
        uint256[] calldata depositTimes
    ) external onlyRole(RELAYER_ROLE) whenNotPaused nonReentrant {
        uint256 len = sourceTxHashes.length;
        if (
            len != sourceChains.length || len != depositors.length || len != amountsSats.length
                || len != depositTimes.length
        ) revert DepositVerifier_LengthMismatch();

        for (uint256 i = 0; i < len; i++) {
            _processDeposit(
                sourceTxHashes[i], sourceChains[i], depositors[i], amountsSats[i], depositTimes[i]
            );
        }
    }

    /**
     * @notice Internal logic for direct deposit processing.
     */
    function _processDeposit(
        bytes32 sourceTxHash,
        uint8 sourceChain,
        address depositor,
        uint256 amountSats,
        uint256 depositTime
    ) internal {
        // Validate chain
        if (sourceChain > SaleConstants.MAX_SUPPORTED_CHAIN) {
            revert DepositVerifier_InvalidChain(sourceChain);
        }

        // Validate amount
        if (amountSats == 0) revert DepositVerifier_ZeroAmount();

        // Prevent double-processing
        if (claimed[sourceTxHash]) revert DepositVerifier_AlreadyClaimed(sourceTxHash);
        claimed[sourceTxHash] = true;

        // Calculate mint amount: tokensMinted = amountSats * 1e9 / satsPerToken
        uint256 mintAmount = (amountSats * 1e9) / satsPerToken;

        // Mint tokens
        IMintable(mintToken).mint(depositor, mintAmount);

        // Record in sale config
        saleConfig.recordSale(amountSats, mintAmount);

        emit DepositClaimed(depositor, sourceTxHash, sourceChain, amountSats, mintAmount);
    }

    // =========  INTERNAL ========= //

    /**
     * @notice Internal claim logic shared by claim() and claimBatch().
     */
    function _claim(bytes32[] calldata proof, Deposit calldata deposit) internal {
        // Validate chain
        if (deposit.sourceChain > SaleConstants.MAX_SUPPORTED_CHAIN) {
            revert DepositVerifier_InvalidChain(deposit.sourceChain);
        }

        // Validate amount
        if (deposit.amountSats == 0) revert DepositVerifier_ZeroAmount();

        // Check not already claimed
        if (claimed[deposit.sourceTxHash]) {
            revert DepositVerifier_AlreadyClaimed(deposit.sourceTxHash);
        }

        // Compute leaf from deposit data (excluding `claimed` field since it's always false in proof)
        bytes32 leaf = keccak256(
            abi.encode(
                deposit.sourceTxHash,
                deposit.sourceChain,
                deposit.depositor,
                deposit.amountSats,
                deposit.depositTime
            )
        );

        // Verify proof against any submitted root
        bool verified = false;
        for (uint256 i = 0; i < batchCount; i++) {
            if (MerkleProof.verify(proof, roots[i], leaf)) {
                verified = true;
                break;
            }
        }
        if (!verified) revert DepositVerifier_InvalidProof();

        // Mark as claimed
        claimed[deposit.sourceTxHash] = true;

        // Calculate tokens to mint
        // tokensMinted = amountSats * 1e9 / satsPerToken
        uint256 tokensMinted = (deposit.amountSats * 1e9) / satsPerToken;

        // Mint tokens to depositor
        IMintable(mintToken).mint(deposit.depositor, tokensMinted);

        // Record in sale config
        saleConfig.recordSale(deposit.amountSats, tokensMinted);

        emit DepositClaimed(
            deposit.depositor,
            deposit.sourceTxHash,
            deposit.sourceChain,
            deposit.amountSats,
            tokensMinted
        );
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Set the sats-per-token mint rate.
     * @dev    tokensMinted = amountSats * 1e9 / satsPerToken
     * @param  satsPerToken_ New rate (e.g., 100 means 1 token = 100 sats).
     */
    function setMintRate(uint256 satsPerToken_) external override onlyRole(ADMIN_ROLE) {
        if (satsPerToken_ == 0) revert DepositVerifier_InvalidMintRate();
        satsPerToken = satsPerToken_;
    }

    /**
     * @notice Set which token to mint (the IMintable sale token address).
     * @param  token The token contract address.
     */
    function setMintToken(address token) external override onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert DepositVerifier_InvalidToken();
        mintToken = token;
    }

    /**
     * @notice Pause all claim and root submission operations.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Withdraw tokens accidentally sent to this contract.
     * @dev    Only callable by ADMIN_ROLE. Cannot withdraw the mint token
     *         (which should never be held by this contract anyway).
     * @param  token  The ERC20 token address to withdraw.
     * @param  amount The amount to withdraw.
     */
    function withdraw(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Check if a deposit has been claimed.
     * @param  sourceTxHash The source chain transaction hash.
     * @return Whether the deposit has been claimed.
     */
    function isClaimed(bytes32 sourceTxHash) external view returns (bool) {
        return claimed[sourceTxHash];
    }

    /**
     * @notice Get the merkle root for a specific batch.
     * @param  batchIndex The batch index.
     * @return The merkle root.
     */
    function getRoot(uint256 batchIndex) external view returns (bytes32) {
        return roots[batchIndex];
    }

    /**
     * @notice Calculate how many tokens a given sats amount would yield.
     * @param  amountSats The BTC-equivalent satoshi amount.
     * @return The number of tokens that would be minted.
     */
    function calculateMint(uint256 amountSats) external view returns (uint256) {
        return (amountSats * 1e9) / satsPerToken;
    }
}
