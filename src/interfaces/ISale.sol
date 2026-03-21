// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

/**
 * @title  IMintable
 * @notice Minimal mint interface satisfied by both ASHA and MIGA tokens.
 * @dev    ASHA.mint requires vault authority; MIGA.mint requires BRIDGE_ROLE.
 *         The DepositVerifier must be granted the appropriate role on whichever
 *         token is configured as the sale token.
 */
interface IMintable {
    function mint(address to, uint256 amount) external;
}

/**
 * @title  IPriceOracle
 * @notice Price oracle for converting deposit amounts to BTC satoshis.
 */
interface IPriceOracle {
    /// @notice Get the price of an asset in satoshis (per 1 whole unit).
    /// @param  chain The source chain enum value.
    /// @return Price in satoshis per 1 whole unit of the asset.
    function getPrice(uint8 chain) external view returns (uint256);

    /// @notice Convert an asset amount to BTC satoshi equivalent.
    /// @param  chain    The source chain enum value.
    /// @param  amount   The raw amount in the asset's native decimals.
    /// @param  decimals The number of decimals for the asset.
    /// @return Equivalent value in BTC satoshis.
    function convertToSats(uint8 chain, uint256 amount, uint8 decimals) external view returns (uint256);
}

/**
 * @title  ISaleConfig
 * @notice Configuration for the token sale.
 */
interface ISaleConfig {
    /// @notice The token being sold (CYRUS or MIGA address).
    function saleToken() external view returns (address);

    /// @notice The deposit verifier contract address.
    function depositVerifier() external view returns (address);

    /// @notice Minimum deposit amount for a given chain (in native decimals).
    function minDeposit(uint8 chain) external view returns (uint256);

    /// @notice Maximum deposit amount for a given chain (in native decimals).
    function maxDeposit(uint8 chain) external view returns (uint256);

    /// @notice Sale start timestamp.
    function saleStart() external view returns (uint256);

    /// @notice Sale end timestamp.
    function saleEnd() external view returns (uint256);

    /// @notice Total BTC-equivalent raised in satoshis.
    function totalRaised() external view returns (uint256);

    /// @notice Total tokens minted during the sale.
    function totalMinted() external view returns (uint256);

    /// @notice Add to the running totals (only callable by deposit verifier).
    function recordSale(uint256 satsRaised, uint256 tokensMinted) external;
}

/**
 * @title  IDepositVerifier
 * @notice Multi-chain deposit verifier with merkle proof verification.
 */
interface IDepositVerifier {
    /// @notice Source chain identifiers.
    enum SourceChain {
        BTC,  // 0
        ETH,  // 1
        SOL,  // 2
        TON,  // 3
        XRP,  // 4
        LUX,  // 5
        PARS  // 6
    }

    /// @notice A verified deposit from an external chain.
    struct Deposit {
        bytes32 sourceTxHash;   // tx hash on source chain
        uint8 sourceChain;      // enum: BTC=0, ETH=1, SOL=2, TON=3, XRP=4, LUX=5, PARS=6
        address depositor;      // pars.network address to mint to
        uint256 amountSats;     // deposit amount normalized to satoshis (BTC-equivalent)
        uint256 depositTime;    // block timestamp of source tx
        bool claimed;           // whether tokens were minted
    }

    /// @notice Emitted when a deposit is claimed and tokens are minted.
    event DepositClaimed(
        address indexed depositor,
        bytes32 indexed sourceTxHash,
        uint8 sourceChain,
        uint256 amountSats,
        uint256 tokensMinted
    );

    /// @notice Emitted when a new merkle root is submitted.
    event RootSubmitted(bytes32 indexed root, uint256 totalDeposits, uint256 batchIndex);

    /// @notice Submit a merkle root for a batch of verified deposits.
    function submitRoot(bytes32 root, uint256 totalDeposits) external;

    /// @notice Claim tokens by proving deposit inclusion in a submitted root.
    function claim(bytes32[] calldata proof, Deposit calldata deposit) external;

    /// @notice Batch claim multiple deposits.
    function claimBatch(bytes32[][] calldata proofs, Deposit[] calldata deposits) external;

    /// @notice Set the sats-per-token mint rate.
    function setMintRate(uint256 satsPerToken) external;

    /// @notice Set which token to mint (CYRUS or MIGA address).
    function setMintToken(address token) external;
}
