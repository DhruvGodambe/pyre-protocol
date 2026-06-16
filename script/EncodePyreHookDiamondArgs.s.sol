// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IDiamondCut} from "../src/hook/diamond/interfaces/IDiamondCut.sol";
import {PyreHookDiamond} from "../src/hook/diamond/PyreHookDiamond.sol";
import {DiamondCutFacet} from "../src/hook/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/hook/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/hook/facets/OwnershipFacet.sol";
import {SwapHookFacet} from "../src/hook/facets/SwapHookFacet.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {BurnFacet} from "../src/hook/facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../src/hook/facets/YieldDistributionFacet.sol";
import {DiamondInit, PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";

contract EncodePyreHookDiamondArgs is Script {
    function run() external {
        address owner = vm.envAddress("PYRE_HOOK_OWNER");
        address deployer = vm.envAddress("PYRE_HOOK_DEPLOYER");
        address pyreToken = vm.envAddress("PYRE_TOKEN");
        address pyreStaking = vm.envAddress("PYRE_STAKING");
        address teamWallet = vm.envAddress("PYRE_TEAM_WALLET");

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](7);
        cuts[0] = _cut(_computeCreateAddress(deployer, 1), _diamondCutSelectors());
        cuts[1] = _cut(_computeCreateAddress(deployer, 2), _loupeSelectors());
        cuts[2] = _cut(_computeCreateAddress(deployer, 3), _ownershipSelectors());
        cuts[3] = _cut(_computeCreateAddress(deployer, 4), _hookSelectors());
        cuts[4] = _cut(_computeCreateAddress(deployer, 5), _feeLogicSelectors());
        cuts[5] = _cut(_computeCreateAddress(deployer, 6), _burnSelectors());
        cuts[6] = _cut(_computeCreateAddress(deployer, 7), _yieldSelectors());

        address init = _computeCreateAddress(deployer, 8);
        bytes memory initData = abi.encodeCall(
            DiamondInit.init,
            (PyreHookInitParams({pyreToken: pyreToken, pyreStaking: pyreStaking, teamWallet: teamWallet}))
        );

        bytes memory args = abi.encode(owner, cuts, init, initData);
        console2.log(vm.toString(args));
    }

    function _computeCreateAddress(address deployer, uint256 nonce) private pure returns (address) {
        require(nonce > 0 && nonce < 0x80, "nonce out of range");
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, uint8(nonce))))));
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
