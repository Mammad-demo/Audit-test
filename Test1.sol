// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

import "../../../../interfaces/ICompoundComptroller.sol";
import "../utils/bases/CompoundAdapterBase.sol";

/// @title CompoundAdapter Contract
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Adapter for Compound <https://compound.finance/>
contract CompoundAdapter is CompoundAdapterBase {
    constructor(
        address _integrationManager,
        address _compoundPriceFeed,
        address _wethToken
    ) public CompoundAdapterBase(_integrationManager, _compoundPriceFeed, _wethToken) {}

    /// @notice Claims rewards from Compound's Comptroller
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _actionData Data specific to this action
    function claimRewards(
        address _vaultProxy,
        bytes calldata _actionData,
        bytes calldata
    ) external override onlyIntegrationManager {
        (address[] memory cTokens, address compoundComptroller) = __decodeClaimArgs(_actionData);
        ICompoundComptroller(compoundComptroller).claimComp(_vaultProxy, cTokens);
    }

    /// @dev Helper to decode callArgs for claimRewards
    function __decodeClaimArgs(bytes memory _actionData)
        private
        pure
        returns (address[] memory cTokens_, address compoundComptroller_)
    {
        return abi.decode(_actionData, (address[], address));
    }
}
// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

import "../../../../../infrastructure/price-feeds/derivatives/feeds/CompoundPriceFeed.sol";
import "../actions/CompoundActionsMixin.sol";
import "../AdapterBase.sol";

/// @title CompoundAdapterBase Contract
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Adapter base for Compound v2 and its forks <https://compound.finance/>
abstract contract CompoundAdapterBase is AdapterBase, CompoundActionsMixin {
    address private immutable COMPOUND_PRICE_FEED;

    constructor(
        address _integrationManager,
        address _compoundPriceFeed,
        address _wethToken
    ) public AdapterBase(_integrationManager) CompoundActionsMixin(_wethToken) {
        COMPOUND_PRICE_FEED = _compoundPriceFeed;
    }

    /// @dev Needed to receive ETH during cEther lend/redeem
    receive() external payable {}

    /// @notice Lends an amount of a token to Compound
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _assetData Parsed spend assets and incoming assets data for this action
    function lend(
        address _vaultProxy,
        bytes calldata,
        bytes calldata _assetData
    )
        external
        onlyIntegrationManager
        postActionIncomingAssetsTransferHandler(_vaultProxy, _assetData)
    {
        // More efficient to parse all from _assetData
        (
            address[] memory spendAssets,
            uint256[] memory spendAssetAmounts,
            address[] memory incomingAssets
        ) = __decodeAssetData(_assetData);

        __compoundLend(spendAssets[0], spendAssetAmounts[0], incomingAssets[0]);
    }

    /// @notice Redeems an amount of cTokens from Compound
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _assetData Parsed spend assets and incoming assets data for this action
    function redeem(
        address _vaultProxy,
        bytes calldata,
        bytes calldata _assetData
    )
        external
        onlyIntegrationManager
        postActionIncomingAssetsTransferHandler(_vaultProxy, _assetData)
    {
        // More efficient to parse all from _assetData
        (
            address[] memory spendAssets,
            uint256[] memory spendAssetAmounts,
            address[] memory incomingAssets
        ) = __decodeAssetData(_assetData);

        __compoundRedeem(spendAssets[0], spendAssetAmounts[0], incomingAssets[0]);
    }

    /// @notice Claims rewards from the cTokens comptroller
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _actionData Data specific to this action
    function claimRewards(
        address _vaultProxy,
        bytes calldata _actionData,
        bytes calldata
    ) external virtual;

    /////////////////////////////
    // PARSE ASSETS FOR METHOD //
    /////////////////////////////

    /// @notice Parses the expected assets in a particular action
    /// @param _selector The function selector for the callOnIntegration
    /// @param _actionData Data specific to this action
    /// @return spendAssetsHandleType_ A type that dictates how to handle granting
    /// the adapter access to spend assets (`None` by default)
    /// @return spendAssets_ The assets to spend in the call
    /// @return spendAssetAmounts_ The max asset amounts to spend in the call
    /// @return incomingAssets_ The assets to receive in the call
    /// @return minIncomingAssetAmounts_ The min asset amounts to receive in the call
    function parseAssetsForAction(
        address,
        bytes4 _selector,
        bytes calldata _actionData
    )
        external
        view
        override
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        if (_selector == LEND_SELECTOR) {
            return __parseAssetsForLend(_actionData);
        } else if (_selector == REDEEM_SELECTOR) {
            return __parseAssetsForRedeem(_actionData);
        } else if (_selector == CLAIM_REWARDS_SELECTOR) {
            return (
                IIntegrationManager.SpendAssetsHandleType.None,
                spendAssets_,
                spendAssetAmounts_,
                incomingAssets_,
                minIncomingAssetAmounts_
            );
        } else {
            revert("parseAssetsForAction: _selector invalid");
        }
    }

    /// @dev Helper function to parse spend and incoming assets from encoded call args
    /// during lend() calls
    function __parseAssetsForLend(bytes calldata _actionData)
        private
        view
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        (address cToken, uint256 tokenAmount, uint256 minCTokenAmount) = __decodeCallArgs(
            _actionData
        );
        address token = CompoundPriceFeed(COMPOUND_PRICE_FEED).getTokenFromCToken(cToken);
        require(token != address(0), "__parseAssetsForLend: Unsupported cToken");

        spendAssets_ = new address[](1);
        spendAssets_[0] = token;
        spendAssetAmounts_ = new uint256[](1);
        spendAssetAmounts_[0] = tokenAmount;

        incomingAssets_ = new address[](1);
        incomingAssets_[0] = cToken;
        minIncomingAssetAmounts_ = new uint256[](1);
        minIncomingAssetAmounts_[0] = minCTokenAmount;

        return (
            IIntegrationManager.SpendAssetsHandleType.Transfer,
            spendAssets_,
            spendAssetAmounts_,
            incomingAssets_,
            minIncomingAssetAmounts_
        );
    }

    /// @dev Helper function to parse spend and incoming assets from encoded call args
    /// during redeem() calls
    function __parseAssetsForRedeem(bytes calldata _actionData)
        private
        view
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        (address cToken, uint256 cTokenAmount, uint256 minTokenAmount) = __decodeCallArgs(
            _actionData
        );
        address token = CompoundPriceFeed(COMPOUND_PRICE_FEED).getTokenFromCToken(cToken);
        require(token != address(0), "__parseAssetsForRedeem: Unsupported cToken");

        spendAssets_ = new address[](1);
        spendAssets_[0] = cToken;
        spendAssetAmounts_ = new uint256[](1);
        spendAssetAmounts_[0] = cTokenAmount;

        incomingAssets_ = new address[](1);
        incomingAssets_[0] = token;
        minIncomingAssetAmounts_ = new uint256[](1);
        minIncomingAssetAmounts_[0] = minTokenAmount;

        return (
            IIntegrationManager.SpendAssetsHandleType.Transfer,
            spendAssets_,
            spendAssetAmounts_,
            incomingAssets_,
            minIncomingAssetAmounts_
        );
    }

    // PRIVATE FUNCTIONS

    /// @dev Helper to decode callArgs for lend and redeem
    function __decodeCallArgs(bytes memory _actionData)
        private
        pure
        returns (
            address cToken_,
            uint256 outgoingAssetAmount_,
            uint256 minIncomingAssetAmount_
        )
    {
        return abi.decode(_actionData, (address, uint256, uint256));
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `COMPOUND_PRICE_FEED` variable
    /// @return compoundPriceFeed_ The `COMPOUND_PRICE_FEED` variable value
    function getCompoundPriceFeed() external view returns (address compoundPriceFeed_) {
        return COMPOUND_PRICE_FEED;
    }
}

// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../../../utils/AssetHelpers.sol";
import "../IIntegrationAdapter.sol";
import "./IntegrationSelectors.sol";

/// @title AdapterBase Contract
/// @author Enzyme Council <security@enzyme.finance>
/// @notice A base contract for integration adapters
abstract contract AdapterBase is IIntegrationAdapter, IntegrationSelectors, AssetHelpers {
    using SafeERC20 for ERC20;

    address internal immutable INTEGRATION_MANAGER;

    /// @dev Provides a standard implementation for transferring incoming assets
    /// from an adapter to a VaultProxy at the end of an adapter action
    modifier postActionIncomingAssetsTransferHandler(
        address _vaultProxy,
        bytes memory _assetData
    ) {
        _;

        (, , address[] memory incomingAssets) = __decodeAssetData(_assetData);

        __pushFullAssetBalances(_vaultProxy, incomingAssets);
    }

    /// @dev Provides a standard implementation for transferring unspent spend assets
    /// from an adapter to a VaultProxy at the end of an adapter action
    modifier postActionSpendAssetsTransferHandler(address _vaultProxy, bytes memory _assetData) {
        _;

        (address[] memory spendAssets, , ) = __decodeAssetData(_assetData);

        __pushFullAssetBalances(_vaultProxy, spendAssets);
    }

    modifier onlyIntegrationManager() {
        require(
            msg.sender == INTEGRATION_MANAGER,
            "Only the IntegrationManager can call this function"
        );
        _;
    }

    constructor(address _integrationManager) public {
        INTEGRATION_MANAGER = _integrationManager;
    }

    // INTERNAL FUNCTIONS

    /// @dev Helper to decode the _assetData param passed to adapter call
    function __decodeAssetData(bytes memory _assetData)
        internal
        pure
        returns (
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_
        )
    {
        return abi.decode(_assetData, (address[], uint256[], address[]));
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `INTEGRATION_MANAGER` variable
    /// @return integrationManager_ The `INTEGRATION_MANAGER` variable value
    function getIntegrationManager() external view returns (address integrationManager_) {
        return INTEGRATION_MANAGER;
    }
}