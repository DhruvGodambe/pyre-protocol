// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../../src/hook/diamond/interfaces/IDiamondCut.sol";
import {PyreHookDiamond} from "../../src/hook/diamond/PyreHookDiamond.sol";
import {DiamondCutFacet} from "../../src/hook/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/hook/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/hook/facets/OwnershipFacet.sol";
import {SwapHookFacet} from "../../src/hook/facets/SwapHookFacet.sol";
import {FeeLogicFacet} from "../../src/hook/facets/FeeLogicFacet.sol";
import {BurnFacet} from "../../src/hook/facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../../src/hook/facets/YieldDistributionFacet.sol";
import {LpBurnFacet} from "../../src/hook/facets/LpBurnFacet.sol";
import {DiamondInit, PyreHookInitParams} from "../../src/hook/init/DiamondInit.sol";
import {IHooks} from "../../src/hook/v4/interfaces/IHooks.sol";

/// @title PyreHookCreate2Deployer
/// @notice Tiny on-chain contract whose ONLY job is to deploy PyreHookDiamond via CREATE2.
///         Because it is deployed on-chain, `address(this)` is a stable address and
///         Foundry's script guard does not apply.  The script deploys all facets separately
///         and passes them in, keeping this contract well under the 24 KB size limit.
contract PyreHookCreate2Deployer {
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 internal constant EXACT_HOOK_FLAGS = (1 << 13) | (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8)
        | (1 << 7) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 3);
    uint256 internal constant MAX_SALT_SEARCH = 10_000_000;

    error HookSaltNotFound();

    // -----------------------------------------------------------------------
    // Salt mining — view function, called off-chain from the script.
    // `address(this)` here is the stable on-chain deployer address.
    // -----------------------------------------------------------------------
    function mineSalt(bytes memory creationCode) external view returns (bytes32 salt) {
        bytes32 bytecodeHash = keccak256(creationCode);
        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
            if (_validHookAddress(predicted)) return salt;
        }
        revert HookSaltNotFound();
    }

    // -----------------------------------------------------------------------
    // CREATE2 deployment — the actual on-chain transaction.
    // -----------------------------------------------------------------------
    function deploy(
        address owner,
        IDiamondCut.FacetCut[] memory cuts,
        address diamondInit,
        bytes memory initData,
        bytes32 salt
    ) external returns (address diamond) {
        diamond = address(new PyreHookDiamond{salt: salt}(owner, cuts, diamondInit, initData));
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    function buildCreationCode(
        address owner,
        IDiamondCut.FacetCut[] memory cuts,
        address diamondInit,
        bytes memory initData
    ) external pure returns (bytes memory) {
        return abi.encodePacked(type(PyreHookDiamond).creationCode, abi.encode(owner, cuts, diamondInit, initData));
    }

    function validateHookAddress(address hook) external pure returns (bool) {
        return _validHookAddress(hook);
    }

    function _validHookAddress(address hook) internal pure returns (bool) {
        return (uint160(hook) & ALL_HOOK_MASK) == EXACT_HOOK_FLAGS;
    }
}

// ---------------------------------------------------------------------------
// Script-side mixin — pure selector helpers, NO address(this), NO state.
// ---------------------------------------------------------------------------
abstract contract PyreHookDiamondDeployer {
    struct FacetAddresses {
        address diamondCut;
        address diamondLoupe;
        address ownership;
        address swapHook;
        address feeLogic;
        address burn;
        address yieldDistribution;
        address lpBurn;
        address diamondInit;
    }

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

    // -----------------------------------------------------------------------
    // Deploy all facets from the script (no address(this) usage here)
    // -----------------------------------------------------------------------
    function _deployFacets() internal returns (FacetAddresses memory f) {
        f.diamondCut = address(new DiamondCutFacet());
        f.diamondLoupe = address(new DiamondLoupeFacet());
        f.ownership = address(new OwnershipFacet());
        f.swapHook = address(new SwapHookFacet());
        f.feeLogic = address(new FeeLogicFacet());
        f.burn = address(new BurnFacet());
        f.yieldDistribution = address(new YieldDistributionFacet());
        f.lpBurn = address(new LpBurnFacet());
        f.diamondInit = address(new DiamondInit());
    }

    function _buildCuts(FacetAddresses memory f) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](8);
        cuts[0] = _cut(f.diamondCut, _diamondCutSelectors());
        cuts[1] = _cut(f.diamondLoupe, _loupeSelectors());
        cuts[2] = _cut(f.ownership, _ownershipSelectors());
        cuts[3] = _cut(f.swapHook, _hookSelectors());
        cuts[4] = _cut(f.feeLogic, _feeLogicSelectors());
        cuts[5] = _cut(f.burn, _burnSelectors());
        cuts[6] = _cut(f.yieldDistribution, _yieldSelectors());
        cuts[7] = _cut(f.lpBurn, _lpBurnSelectors());
    }

    // -----------------------------------------------------------------------
    // Full hook deployment orchestration (called from scripts)
    // -----------------------------------------------------------------------
    function _deployHook(address owner, PyreHookInitParams memory initParams)
        internal
        returns (Deployment memory deployment, PyreHookCreate2Deployer create2Deployer)
    {
        // 1. Deploy the tiny on-chain CREATE2 deployer
        create2Deployer = new PyreHookCreate2Deployer();

        // 2. Deploy all facets from the script context
        FacetAddresses memory f = _deployFacets();
        IDiamondCut.FacetCut[] memory cuts = _buildCuts(f);
        bytes memory initData = abi.encodeCall(DiamondInit.init, (initParams));

        // 3. Mine salt — calls address(this) inside the on-chain deployer (safe)
        bytes memory creationCode = create2Deployer.buildCreationCode(owner, cuts, f.diamondInit, initData);
        bytes32 salt = create2Deployer.mineSalt(creationCode);

        // 4. Deploy the diamond via CREATE2 from the on-chain deployer
        address diamondAddr = create2Deployer.deploy(owner, cuts, f.diamondInit, initData, salt);

        // 5. Populate return struct
        deployment.diamond = PyreHookDiamond(payable(diamondAddr));
        deployment.diamondCutFacet = DiamondCutFacet(f.diamondCut);
        deployment.diamondLoupeFacet = DiamondLoupeFacet(f.diamondLoupe);
        deployment.ownershipFacet = OwnershipFacet(f.ownership);
        deployment.swapHookFacet = SwapHookFacet(f.swapHook);
        deployment.feeLogicFacet = FeeLogicFacet(f.feeLogic);
        deployment.burnFacet = BurnFacet(f.burn);
        deployment.yieldDistributionFacet = YieldDistributionFacet(f.yieldDistribution);
        deployment.lpBurnFacet = LpBurnFacet(f.lpBurn);
        deployment.diamondInit = DiamondInit(f.diamondInit);
    }

    function _validateHookAddress(address hook) internal pure returns (bool) {
        uint160 ALL_MASK = uint160((1 << 14) - 1);
        uint160 EXACT_FLAGS = (1 << 13) | (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8) | (1 << 7) | (1 << 6)
            | (1 << 5) | (1 << 4) | (1 << 3);
        return (uint160(hook) & ALL_MASK) == EXACT_FLAGS;
    }

    // -----------------------------------------------------------------------
    // Selector helpers — pure, no state, no address(this)
    // -----------------------------------------------------------------------
    function _cut(address facet, bytes4[] memory selectors) internal pure returns (IDiamondCut.FacetCut memory) {
        return IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _diamondCutSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = DiamondCutFacet.diamondCut.selector;
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = DiamondLoupeFacet.facets.selector;
        s[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        s[2] = DiamondLoupeFacet.facetAddresses.selector;
        s[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = OwnershipFacet.owner.selector;
        s[1] = OwnershipFacet.transferOwnership.selector;
    }

    function _hookSelectors() internal pure returns (bytes4[] memory s) {
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

    function _feeLogicSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = FeeLogicFacet.configurePool.selector;
        s[1] = FeeLogicFacet.configureAntiSnipe.selector;
        s[2] = FeeLogicFacet.getCurrentBuyFeeBps.selector;
        s[3] = FeeLogicFacet.getCurrentSellFeeBps.selector;
        s[4] = FeeLogicFacet.getRegisteredPoolId.selector;
        s[5] = FeeLogicFacet.claimFees.selector;
        s[6] = FeeLogicFacet.unlockCallback.selector;
    }

    function _burnSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = BurnFacet.configurePyreToken.selector;
        s[1] = BurnFacet.getPyreToken.selector;
        s[2] = BurnFacet.getTotalPyreBurned.selector;
    }

    function _yieldSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = YieldDistributionFacet.configureYieldDistribution.selector;
        s[1] = YieldDistributionFacet.getYieldConfig.selector;
        s[2] = YieldDistributionFacet.getTotalEthDistributed.selector;
    }

    function _lpBurnSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = LpBurnFacet.configureFireSpirit.selector;
        s[1] = LpBurnFacet.getFireSpirit.selector;
        s[2] = LpBurnFacet.configurePositionManager.selector;
        s[3] = LpBurnFacet.getPositionManager.selector;
        s[4] = LpBurnFacet.burnLpPosition.selector;
        s[5] = LpBurnFacet.getTotalLpBurns.selector;
        s[6] = LpBurnFacet.getTotalPyreBurnedFromLp.selector;
        s[7] = LpBurnFacet.getTotalEthRoutedFromLp.selector;
    }
}
