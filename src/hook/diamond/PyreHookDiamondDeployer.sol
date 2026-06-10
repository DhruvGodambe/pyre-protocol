// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {PyreHookDiamond} from "./PyreHookDiamond.sol";
import {DiamondCutFacet} from "../facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../facets/OwnershipFacet.sol";
import {SwapHookFacet} from "../facets/SwapHookFacet.sol";
import {FeeLogicFacet} from "../facets/FeeLogicFacet.sol";
import {BurnFacet} from "../facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../facets/YieldDistributionFacet.sol";
import {DiamondInit, PyreHookInitParams} from "../init/DiamondInit.sol";
import {IHooks} from "../v4/interfaces/IHooks.sol";

/// @title PyreHookDiamondDeployer
/// @notice Helper to deploy the PYRE hook diamond with all facets attached.
contract PyreHookDiamondDeployer {
    struct Deployment {
        PyreHookDiamond diamond;
        DiamondCutFacet diamondCutFacet;
        DiamondLoupeFacet diamondLoupeFacet;
        OwnershipFacet ownershipFacet;
        SwapHookFacet swapHookFacet;
        FeeLogicFacet feeLogicFacet;
        BurnFacet burnFacet;
        YieldDistributionFacet yieldDistributionFacet;
        DiamondInit diamondInit;
    }

    /// @dev Required hook permission flags: beforeSwap | afterSwap | beforeSwapReturnDelta
    uint160 internal constant REQUIRED_HOOK_FLAGS = (1 << 7) | (1 << 6) | (1 << 3);

    function deploy(address owner, PyreHookInitParams memory initParams)
        public
        returns (Deployment memory deployment)
    {
        deployment.diamondCutFacet = new DiamondCutFacet();
        deployment.diamondLoupeFacet = new DiamondLoupeFacet();
        deployment.ownershipFacet = new OwnershipFacet();
        deployment.swapHookFacet = new SwapHookFacet();
        deployment.feeLogicFacet = new FeeLogicFacet();
        deployment.burnFacet = new BurnFacet();
        deployment.yieldDistributionFacet = new YieldDistributionFacet();
        deployment.diamondInit = new DiamondInit();

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](7);
        cuts[0] = _cut(address(deployment.diamondCutFacet), _diamondCutSelectors());
        cuts[1] = _cut(address(deployment.diamondLoupeFacet), _loupeSelectors());
        cuts[2] = _cut(address(deployment.ownershipFacet), _ownershipSelectors());
        cuts[3] = _cut(address(deployment.swapHookFacet), _hookSelectors());
        cuts[4] = _cut(address(deployment.feeLogicFacet), _feeLogicSelectors());
        cuts[5] = _cut(address(deployment.burnFacet), _burnSelectors());
        cuts[6] = _cut(address(deployment.yieldDistributionFacet), _yieldSelectors());

        bytes memory initData = abi.encodeCall(DiamondInit.init, (initParams));

        deployment.diamond = new PyreHookDiamond(
            owner, cuts, address(deployment.diamondInit), initData
        );
    }

    function validateHookAddress(address hook) public pure returns (bool) {
        return uint160(hook) & REQUIRED_HOOK_FLAGS == REQUIRED_HOOK_FLAGS;
    }

    function _cut(address facet, bytes4[] memory selectors)
        private
        pure
        returns (IDiamondCut.FacetCut memory)
    {
        return IDiamondCut.FacetCut({facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors});
    }

    function _diamondCutSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = DiamondCutFacet.diamondCut.selector;
    }

    function _loupeSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = DiamondLoupeFacet.facets.selector;
        s[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        s[2] = DiamondLoupeFacet.facetAddresses.selector;
        s[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function _ownershipSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = OwnershipFacet.owner.selector;
        s[1] = OwnershipFacet.transferOwnership.selector;
    }

    function _hookSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](10);
        s[0] = IHooks.beforeSwap.selector;
        s[1] = IHooks.afterSwap.selector;
        s[2] = IHooks.beforeInitialize.selector;
        s[3] = IHooks.afterInitialize.selector;
        s[4] = IHooks.beforeAddLiquidity.selector;
        s[5] = IHooks.afterAddLiquidity.selector;
        s[6] = IHooks.beforeRemoveLiquidity.selector;
        s[7] = IHooks.afterRemoveLiquidity.selector;
        s[8] = IHooks.beforeDonate.selector;
        s[9] = IHooks.afterDonate.selector;
    }

    function _feeLogicSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = FeeLogicFacet.configurePool.selector;
        s[1] = FeeLogicFacet.configureAntiSnipe.selector;
        s[2] = FeeLogicFacet.getCurrentBuyFeeBps.selector;
        s[3] = FeeLogicFacet.getCurrentSellFeeBps.selector;
        s[4] = FeeLogicFacet.getRegisteredPoolId.selector;
    }

    function _burnSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = BurnFacet.configurePyreToken.selector;
        s[1] = BurnFacet.getPyreToken.selector;
        s[2] = BurnFacet.getTotalPyreBurned.selector;
    }

    function _yieldSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = YieldDistributionFacet.configureYieldDistribution.selector;
        s[1] = YieldDistributionFacet.getYieldConfig.selector;
        s[2] = YieldDistributionFacet.getTotalEthDistributed.selector;
    }
}
