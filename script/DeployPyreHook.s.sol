// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PyreHookDiamondDeployer} from "../src/hook/diamond/PyreHookDiamondDeployer.sol";
import {PyreHookDiamond} from "../src/hook/diamond/PyreHookDiamond.sol";
import {LpBurnFacet} from "../src/hook/facets/LpBurnFacet.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";

contract DeployPyreHook is Script {
    function run() external returns (PyreHookDiamondDeployer.Deployment memory deployment, bool validHookAddress) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        address pyreToken = vm.envOr("PYRE_TOKEN", address(0xaA46dd2434dE4b06Da8D4F7f0Ace4e152EecbbA6));
        address pyreStaking = vm.envOr("PYRE_STAKING", address(0x61564EE98d9eFDc198AE6a48dFCd864C7F06A3B3));
        address teamWallet = vm.envOr("PYRE_TEAM_WALLET", address(0xF93E7518F79C2E1978D6862Dbf161270040e623E));
        address poolManager = vm.envOr("POOL_MANAGER", address(0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408));
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        PyreHookInitParams memory initParams =
            PyreHookInitParams({pyreToken: pyreToken, pyreStaking: address(pyreStaking), teamWallet: teamWallet});

        vm.startBroadcast();
        PyreHookDiamondDeployer deployer = new PyreHookDiamondDeployer();
        bytes memory creationCode = deployer.getCreationCode(admin, initParams);
        vm.stopBroadcast();

        bytes32 salt = deployer.mineSaltLocally(creationCode);

        vm.startBroadcast();
        PyreHookDiamond diamond = deployer.deployDiamond(admin, initParams, salt);
        validHookAddress = deployer.validateHookAddress(address(diamond));
        deployment = PyreHookDiamondDeployer.Deployment({
            diamond: diamond,
            diamondCutFacet: deployer.diamondCutFacet(),
            diamondLoupeFacet: deployer.diamondLoupeFacet(),
            ownershipFacet: deployer.ownershipFacet(),
            swapHookFacet: deployer.swapHookFacet(),
            feeLogicFacet: deployer.feeLogicFacet(),
            burnFacet: deployer.burnFacet(),
            yieldDistributionFacet: deployer.yieldDistributionFacet(),
            lpBurnFacet: deployer.lpBurnFacet(),
            diamondInit: deployer.diamondInit()
        });

        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(pyreToken),
            fee: uint24(vm.envOr("PYRE_POOL_FEE", uint256(3000))),
            tickSpacing: int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60)))),
            hooks: IHooks(address(diamond))
        });

        FeeLogicFacet(address(deployment.diamond))
            .configurePool(poolManager, poolKey, poolKey.currency1, poolKey.currency0, launchTime);

        PyreStaking(payable(pyreStaking)).setYieldRouter(address(deployment.diamond));

        vm.stopBroadcast();
    }
}
