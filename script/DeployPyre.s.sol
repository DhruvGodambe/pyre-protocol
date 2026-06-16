// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {ImmolatedGate} from "../src/gate/ImmolatedGate.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract DeployPyre is Script {
    struct Deployment {
        PyreToken token;
        PyreStaking staking;
        FireSpirit fireSpirit;
        ImmolatedGate immolatedGate;
    }

    function run() external returns (Deployment memory deployment) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        vm.startBroadcast();

        deployment.token = new PyreToken(admin, "Pyre", "PYRE");

        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        deployment.staking = new PyreStaking(admin, address(deployment.token), launchTime, address(bootstrap));

        deployment.fireSpirit = new FireSpirit(admin, address(deployment.token), address(deployment.staking));

        deployment.token.setStakingContract(address(deployment.staking));
        deployment.token.setBurnTracker(address(deployment.fireSpirit));
        deployment.staking.setWeightFactors(address(deployment.fireSpirit));

        address initialMintTo = vm.envOr("PYRE_INITIAL_MINT_TO", address(0));
        uint256 initialMintAmount = vm.envOr("PYRE_INITIAL_MINT_AMOUNT", uint256(0));
        if (initialMintTo != address(0) && initialMintAmount != 0) {
            deployment.token.mint(initialMintTo, initialMintAmount);
        }

        deployment.immolatedGate = new ImmolatedGate(address(deployment.token), address(deployment.fireSpirit));

        vm.stopBroadcast();
        // Deploy PyreHookDiamond separately via DeployPyreHook.s.sol and call:
        // staking.setYieldRouter(hookDiamondAddress)
    }
}
