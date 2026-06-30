// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {Acolyte} from "../src/nft/Acolyte.sol";
import {ImmolatedGate} from "../src/gate/ImmolatedGate.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

import {PyreHookDiamondDeployer} from "./utils/PyreHookDiamondDeployer.s.sol";
import {PyreHookDiamond} from "../src/hook/diamond/PyreHookDiamond.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {LpBurnFacet} from "../src/hook/facets/LpBurnFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";

// Minimal interfaces defined here to avoid type conflicts between v4-core/ and @uniswap/v4-core/ remapping variants.
interface IPoolManagerInitializer {
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
}

interface IPermit2Approver {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IPositionManagerLiquidity {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}

contract DeployAll is Script, PyreHookDiamondDeployer {
    // Initial price: 1 ETH = 100,000 PYRE  →  sqrtPriceX96 = sqrt(100000) * 2^96
    uint160 internal constant INITIAL_SQRT_PRICE = 25054144837504793118641380156900;
    // Liquidity for full-range position seeded with ~0.1 ETH + ~10,000 PYRE (= sqrt(0.1e18 * 10000e18))
    uint128 internal constant INITIAL_LIQUIDITY = 31622776601683793319;
    // Full-range tick bounds for tick spacing 60 (nearest multiples of 60 within TickMath min/max)
    int24 internal constant FULL_TICK_LOWER = -887220;
    int24 internal constant FULL_TICK_UPPER = 887220;
    // Canonical Permit2 address — same on all EVM chains
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    struct PyreDeployment {
        PyreToken token;
        PyreStaking staking;
        Acolyte acolyte;
        ImmolatedGate immolatedGate;
    }

    function run() external returns (PyreDeployment memory pyreDeployment, address hookAddress, bool validHookAddress) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        address teamWallet = vm.envOr("PYRE_TEAM_WALLET", admin);
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("V4_POSITION_MANAGER");
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        // Phase 1: Deploy core contracts + all diamond facets
        vm.startBroadcast();
        pyreDeployment = deployPyreContracts();

        PyreHookInitParams memory initParams = PyreHookInitParams({
            pyreToken: address(pyreDeployment.token),
            pyreStaking: address(pyreDeployment.staking),
            teamWallet: teamWallet
        });

        // Deploy all facets + tiny on-chain CREATE2 deployer + mine salt + deploy diamond — all in one call
        (PyreHookDiamondDeployer.Deployment memory hookDeployment,) = _deployHook(admin, initParams);

        // Grant the hook the LP_RECORDER_ROLE in Acolyte so it can flag burners
        pyreDeployment.acolyte
            .grantRole(pyreDeployment.acolyte.LP_RECORDER_ROLE(), address(hookDeployment.diamond));

        // Configure the hook's LpBurnFacet with the position manager and acolyte
        LpBurnFacet(address(hookDeployment.diamond)).configurePositionManager(positionManager);
        LpBurnFacet(address(hookDeployment.diamond)).configureAcolyte(address(pyreDeployment.acolyte));

        vm.stopBroadcast();

        // Phase 2+3 are handled inside _deployHook (salt mining is a view call to the on-chain deployer)
        // Re-open broadcast for pool configuration and liquidity seeding
        vm.startBroadcast();
        validHookAddress = _validateHookAddress(address(hookDeployment.diamond));
        hookAddress = address(hookDeployment.diamond);

        PoolKey memory poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(address(pyreDeployment.token)),
            fee: uint24(vm.envOr("PYRE_POOL_FEE", uint256(3000))),
            tickSpacing: int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60)))),
            hooks: IHooks(address(hookDeployment.diamond))
        });

        FeeLogicFacet(address(hookDeployment.diamond))
            .configurePool(poolManager, poolKey, poolKey.currency1, poolKey.currency0, launchTime);
        pyreDeployment.staking.setYieldRouter(address(hookDeployment.diamond));

        // Initialize the V4 pool at 1 ETH = 100,000 PYRE
        IPoolManagerInitializer(poolManager).initialize(poolKey, INITIAL_SQRT_PRICE);

        // Approve Permit2 to pull PYRE from this broadcaster, then allow PositionManager via Permit2
        pyreDeployment.token.approve(PERMIT2, type(uint256).max);
        IPermit2Approver(PERMIT2)
            .approve(
                address(pyreDeployment.token), positionManager, type(uint160).max, uint48(block.timestamp + 1 hours)
            );

        // Encode MINT_POSITION + SETTLE_PAIR + SWEEP actions
        // MINT_POSITION=0x02, SETTLE_PAIR=0x0d, SWEEP=0x14
        bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d), uint8(0x14));
        bytes[] memory mintParams = new bytes[](3);
        // MINT_POSITION params: poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData
        mintParams[0] = abi.encode(
            poolKey,
            FULL_TICK_LOWER,
            FULL_TICK_UPPER,
            uint256(INITIAL_LIQUIDITY),
            uint128(0.11 ether), // amount0Max: slight buffer over expected ~0.1 ETH
            uint128(11_000 ether), // amount1Max: slight buffer over expected ~10,000 PYRE
            admin,
            bytes("")
        );
        // SETTLE_PAIR params: settle both currencies (ETH from msg.value, PYRE via Permit2)
        mintParams[1] =
            abi.encode(CurrencyLibrary.wrap(address(0)), CurrencyLibrary.wrap(address(pyreDeployment.token)));
        // SWEEP params: return any unspent ETH to admin
        mintParams[2] = abi.encode(CurrencyLibrary.wrap(address(0)), admin);

        // Send 0.11 ETH; SWEEP returns any unused portion to admin
        IPositionManagerLiquidity(positionManager).modifyLiquidities{value: 0.11 ether}(
            abi.encode(actions, mintParams), block.timestamp + 1 hours
        );

        console2.log("Pool initialized and seeded with ~0.1 ETH + ~10,000 PYRE liquidity");
        console2.log("Hook address:", hookAddress);
        console2.log("Valid hook address:", validHookAddress);

        vm.stopBroadcast();
    }

    function deployPyreContracts() internal returns (PyreDeployment memory deployment) {
        address admin = vm.envOr("PYRE_ADMIN", msg.sender);
        uint256 launchTime = vm.envOr("PYRE_LAUNCH_TIME", block.timestamp);

        deployment.token = new PyreToken(admin, "Pyre", "PYRE");

        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        deployment.staking = new PyreStaking(admin, address(deployment.token), launchTime, address(bootstrap));

        deployment.acolyte = new Acolyte(admin, address(deployment.token), address(deployment.staking));

        deployment.token.setStakingContract(address(deployment.staking));
        deployment.token.setBurnTracker(address(deployment.acolyte));
        deployment.staking.setWeightFactors(address(deployment.acolyte));

        address initialMintTo = vm.envOr("PYRE_INITIAL_MINT_TO", address(0));
        uint256 initialMintAmount = vm.envOr("PYRE_INITIAL_MINT_AMOUNT", uint256(0));
        if (initialMintTo != address(0) && initialMintAmount != 0) {
            deployment.token.mint(initialMintTo, initialMintAmount);
        }

        deployment.immolatedGate = new ImmolatedGate(address(deployment.token), address(deployment.acolyte));
    }
}

//source .env && forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY  --broadcast --verify

// source .env && forge script script/DeployAll.s.sol:DeployAll \
//  --rpc-url $RPC_URL \
//  --private-key $DEPLOYER_PRIVATE_KEY \
//  --broadcast \
//  --verify \
//  --slow