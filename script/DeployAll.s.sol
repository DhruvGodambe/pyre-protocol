// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {ImmolatedGate} from "../src/gate/ImmolatedGate.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

import {PyreHookDiamondDeployer} from "../src/hook/diamond/PyreHookDiamondDeployer.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";

contract DeployAll is Script {
    struct PyreDeployment {
        PyreToken token;
        PyreStaking staking;
        FireSpirit fireSpirit;
        ImmolatedGate immolatedGate;
    }

    function run() external returns (PyreDeployment memory pyreDeployment, address hookAddress, bool validHookAddress) {
        vm.startBroadcast();

        // Step 1: Deploy the main Pyre contracts
        pyreDeployment = deployPyreContracts();
        
        // Step 2: Deploy the hook contract with Pyre addresses
        (hookAddress, validHookAddress) = deployHookContract(pyreDeployment);

        vm.stopBroadcast();
    }

    function deployPyreContracts() internal returns (PyreDeployment memory deployment) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

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

        deployment.immolatedGate = new ImmolatedGate(
            address(deployment.token), address(deployment.fireSpirit)
        );
    }

    function deployHookContract(PyreDeployment memory pyreDeployment) 
        internal 
        returns (address hookAddress, bool validHookAddress)
    {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        address teamWallet = vm.envOr("PYRE_TEAM_WALLET", admin);
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        PyreHookInitParams memory initParams = PyreHookInitParams({
            pyreToken: address(pyreDeployment.token),
            pyreStaking: address(pyreDeployment.staking),
            teamWallet: teamWallet
        });

        PyreHookDiamondDeployer deployer = new PyreHookDiamondDeployer();
        PyreHookDiamondDeployer.Deployment memory hookDeployment = deployer.deploy(admin, initParams);
        validHookAddress = deployer.validateHookAddress(address(hookDeployment.diamond));
        hookAddress = address(hookDeployment.diamond);

        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(address(pyreDeployment.token)),
            fee: uint24(vm.envOr("PYRE_POOL_FEE", uint256(3000))),
            tickSpacing: int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60)))),
            hooks: IHooks(address(hookDeployment.diamond))
        });

        FeeLogicFacet(address(hookDeployment.diamond)).configurePool(
            poolManager,
            poolKey,
            poolKey.currency1,
            poolKey.currency0,
            launchTime
        );

        // Set the yield router in staking contract
        pyreDeployment.staking.setYieldRouter(address(hookDeployment.diamond));
    }
}
