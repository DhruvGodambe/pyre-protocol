// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PyreHookDiamondDeployer} from "./utils/PyreHookDiamondDeployer.s.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";

contract DeployPyreHook is Script, PyreHookDiamondDeployer {
    function run() external returns (PyreHookDiamondDeployer.Deployment memory deployment, bool validHookAddress) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        address pyreToken = vm.envAddress("PYRE_TOKEN");
        address pyreStaking = vm.envAddress("PYRE_STAKING");
        address teamWallet = vm.envAddress("PYRE_TEAM_WALLET");
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        PyreHookInitParams memory initParams =
            PyreHookInitParams({pyreToken: pyreToken, pyreStaking: address(pyreStaking), teamWallet: teamWallet});

        vm.startBroadcast();
        // _deployHook: deploys tiny CREATE2 helper on-chain, then deploys all facets,
        // calls mineSalt() as a view on the on-chain deployer (no address(this) in script),
        // then deploys the diamond via CREATE2.
        (deployment,) = _deployHook(admin, initParams);
        validHookAddress = _validateHookAddress(address(deployment.diamond));

        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(pyreToken),
            fee: uint24(vm.envOr("PYRE_POOL_FEE", uint256(3000))),
            tickSpacing: int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60)))),
            hooks: IHooks(address(deployment.diamond))
        });

        FeeLogicFacet(address(deployment.diamond))
            .configurePool(poolManager, poolKey, poolKey.currency1, poolKey.currency0, launchTime);

        PyreStaking(payable(pyreStaking)).setYieldRouter(address(deployment.diamond));

        vm.stopBroadcast();
    }
}
