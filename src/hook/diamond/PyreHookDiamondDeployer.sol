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
import {LpBurnFacet} from "../facets/LpBurnFacet.sol";
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
        LpBurnFacet lpBurnFacet;
        DiamondInit diamondInit;
    }

    /// @dev v4 hook permission flags encoded in the low bits of the hook address.
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 internal constant EXACT_HOOK_FLAGS = (1 << 13) | (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8)
        | (1 << 7) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 3);
    uint256 internal constant MAX_SALT_SEARCH = 10_000_000;

    error HookSaltNotFound();

    DiamondCutFacet public diamondCutFacet;
    DiamondLoupeFacet public diamondLoupeFacet;
    OwnershipFacet public ownershipFacet;
    SwapHookFacet public swapHookFacet;
    FeeLogicFacet public feeLogicFacet;
    BurnFacet public burnFacet;
    YieldDistributionFacet public yieldDistributionFacet;
    LpBurnFacet public lpBurnFacet;
    DiamondInit public diamondInit;

    function deploy(address owner, PyreHookInitParams memory initParams) public returns (Deployment memory deployment) {
        bytes memory creationCode = getCreationCode(owner, initParams);
        bytes32 salt = mineSaltLocally(creationCode);

        deployment.diamond = deployDiamond(owner, initParams, salt);
        deployment.diamondCutFacet = diamondCutFacet;
        deployment.diamondLoupeFacet = diamondLoupeFacet;
        deployment.ownershipFacet = ownershipFacet;
        deployment.swapHookFacet = swapHookFacet;
        deployment.feeLogicFacet = feeLogicFacet;
        deployment.burnFacet = burnFacet;
        deployment.yieldDistributionFacet = yieldDistributionFacet;
        deployment.lpBurnFacet = lpBurnFacet;
        deployment.diamondInit = diamondInit;
    }

    function getCreationCode(address owner, PyreHookInitParams memory initParams) public returns (bytes memory) {
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        swapHookFacet = new SwapHookFacet();
        feeLogicFacet = new FeeLogicFacet();
        burnFacet = new BurnFacet();
        yieldDistributionFacet = new YieldDistributionFacet();
        lpBurnFacet = new LpBurnFacet();
        diamondInit = new DiamondInit();

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](8);
        cuts[0] = _cut(address(diamondCutFacet), _diamondCutSelectors());
        cuts[1] = _cut(address(diamondLoupeFacet), _loupeSelectors());
        cuts[2] = _cut(address(ownershipFacet), _ownershipSelectors());
        cuts[3] = _cut(address(swapHookFacet), _hookSelectors());
        cuts[4] = _cut(address(feeLogicFacet), _feeLogicSelectors());
        cuts[5] = _cut(address(burnFacet), _burnSelectors());
        cuts[6] = _cut(address(yieldDistributionFacet), _yieldSelectors());
        cuts[7] = _cut(address(lpBurnFacet), _lpBurnSelectors());

        bytes memory initData = abi.encodeCall(DiamondInit.init, (initParams));

        return
            abi.encodePacked(
                type(PyreHookDiamond).creationCode, abi.encode(owner, cuts, address(diamondInit), initData)
            );
    }

    function mineSaltLocally(bytes memory creationCode) public view returns (bytes32 salt) {
        return _mineHookSalt(creationCode);
    }

    function deployDiamond(address owner, PyreHookInitParams memory initParams, bytes32 salt)
        public
        returns (PyreHookDiamond diamond)
    {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](8);
        cuts[0] = _cut(address(diamondCutFacet), _diamondCutSelectors());
        cuts[1] = _cut(address(diamondLoupeFacet), _loupeSelectors());
        cuts[2] = _cut(address(ownershipFacet), _ownershipSelectors());
        cuts[3] = _cut(address(swapHookFacet), _hookSelectors());
        cuts[4] = _cut(address(feeLogicFacet), _feeLogicSelectors());
        cuts[5] = _cut(address(burnFacet), _burnSelectors());
        cuts[6] = _cut(address(yieldDistributionFacet), _yieldSelectors());
        cuts[7] = _cut(address(lpBurnFacet), _lpBurnSelectors());

        bytes memory initData = abi.encodeCall(DiamondInit.init, (initParams));

        diamond = new PyreHookDiamond{salt: salt}(owner, cuts, address(diamondInit), initData);
    }

    function validateHookAddress(address hook) public pure returns (bool) {
        return (uint160(hook) & ALL_HOOK_MASK) == EXACT_HOOK_FLAGS;
    }

    function _mineHookSalt(bytes memory creationCode) private view returns (bytes32 salt) {
        bytes32 bytecodeHash = keccak256(creationCode);

        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));

            if (validateHookAddress(predicted)) {
                return salt;
            }
        }

        revert HookSaltNotFound();
    }

    function _cut(address facet, bytes4[] memory selectors) private pure returns (IDiamondCut.FacetCut memory) {
        return IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
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
        s = new bytes4[](7);
        s[0] = FeeLogicFacet.configurePool.selector;
        s[1] = FeeLogicFacet.configureAntiSnipe.selector;
        s[2] = FeeLogicFacet.getCurrentBuyFeeBps.selector;
        s[3] = FeeLogicFacet.getCurrentSellFeeBps.selector;
        s[4] = FeeLogicFacet.getRegisteredPoolId.selector;
        s[5] = FeeLogicFacet.claimFees.selector;
        s[6] = FeeLogicFacet.unlockCallback.selector;
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

    function _lpBurnSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = LpBurnFacet.configureFireSpirit.selector;
        s[1] = LpBurnFacet.getFireSpirit.selector;
        s[2] = LpBurnFacet.getTotalLpBurns.selector;
        s[3] = LpBurnFacet.getTotalPyreBurnedFromLp.selector;
        s[4] = LpBurnFacet.getTotalEthRoutedFromLp.selector;
    }
}
