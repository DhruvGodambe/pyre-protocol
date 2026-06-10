// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";
import {PyreHookDiamondDeployer} from "../src/hook/diamond/PyreHookDiamondDeployer.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {BurnFacet} from "../src/hook/facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../src/hook/facets/YieldDistributionFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {PoolKeyLibrary} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";
import {SwapParams} from "../src/hook/v4/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../src/hook/v4/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../src/hook/v4/types/BeforeSwapDelta.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";

contract PyreHookDiamondTest is Test {
    using PoolKeyLibrary for PoolKey;

    PyreHookDiamondDeployer.Deployment internal deployment;
    PyreToken internal token;
    PyreStaking internal staking;
    MockPoolManager internal poolManager;

    address internal admin = makeAddr("admin");
    address internal team = makeAddr("team");
    address internal trader = makeAddr("trader");

    PoolKey internal poolKey;
    uint256 internal launchTime;

    function setUp() public {
        launchTime = block.timestamp;

        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), launchTime, address(bootstrap));
        new FireSpirit(admin, address(token), address(staking));

        poolManager = new MockPoolManager();

        PyreHookInitParams memory initParams =
            PyreHookInitParams({pyreToken: address(token), pyreStaking: address(staking), teamWallet: team});

        deployment = new PyreHookDiamondDeployer().deploy(admin, initParams);

        vm.prank(admin);
        staking.setYieldRouter(address(deployment.diamond));

        poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(deployment.diamond))
        });

        vm.prank(admin);
        FeeLogicFacet(address(deployment.diamond)).configurePool(
            address(poolManager), poolKey, poolKey.currency1, poolKey.currency0, launchTime
        );
    }

    function test_FeeDecayFromTenToFivePercentBuy() public {
        assertEq(FeeLogicFacet(address(deployment.diamond)).getCurrentBuyFeeBps(), 1000);

        vm.warp(launchTime + 6 hours);
        assertEq(FeeLogicFacet(address(deployment.diamond)).getCurrentBuyFeeBps(), 750);

        vm.warp(launchTime + 12 hours);
        assertEq(FeeLogicFacet(address(deployment.diamond)).getCurrentBuyFeeBps(), 500);
    }

    function test_FeeDecayFromTwentyThreeToFivePercentSell() public {
        assertEq(FeeLogicFacet(address(deployment.diamond)).getCurrentSellFeeBps(), 2300);

        vm.warp(launchTime + 12 hours);
        assertEq(FeeLogicFacet(address(deployment.diamond)).getCurrentSellFeeBps(), 500);
    }

    function test_BuyFeeRoutesEthToYieldAndTeam() public {
        uint256 ethIn = 10 ether;
        uint256 expectedFee = 1 ether;

        vm.deal(address(poolManager), ethIn);
        vm.prank(admin);
        token.mint(trader, 100_000 ether);

        vm.prank(address(poolManager));
        (bytes4 selector, BeforeSwapDelta delta,) = IHooks(address(deployment.diamond)).beforeSwap(
            trader,
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: 0}),
            ""
        );

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(delta), int128(int256(expectedFee)));

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond)).afterSwap(
            trader, poolKey, SwapParams({zeroForOne: true, amountSpecified: 0, sqrtPriceLimitX96: 0}), BalanceDeltaLibrary.ZERO_DELTA, ""
        );

        (uint256 toYield, uint256 toTeam) =
            YieldDistributionFacet(address(deployment.diamond)).getTotalEthDistributed();
        assertEq(toYield, 0.8 ether);
        assertEq(toTeam, 0.2 ether);
    }

    function test_SellFeeBurnsPyre() public {
        uint256 pyreIn = 10_000 ether;
        uint256 expectedFee = 2300 ether;

        vm.prank(admin);
        token.mint(address(poolManager), pyreIn);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond)).beforeSwap(
            trader,
            poolKey,
            SwapParams({zeroForOne: false, amountSpecified: -int256(pyreIn), sqrtPriceLimitX96: 0}),
            ""
        );

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond)).afterSwap(
            trader,
            poolKey,
            SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0}),
            BalanceDeltaLibrary.ZERO_DELTA,
            ""
        );

        assertEq(BurnFacet(address(deployment.diamond)).getTotalPyreBurned(), expectedFee);
        assertEq(token.totalSupply(), supplyBefore - expectedFee);
    }

    function test_RevertOnUnregisteredPool() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.fee = 500;

        vm.prank(address(poolManager));
        vm.expectRevert();
        IHooks(address(deployment.diamond)).beforeSwap(
            trader, fakeKey, SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}), ""
        );
    }

    function test_RevertOnNonPoolManagerCaller() public {
        vm.expectRevert();
        IHooks(address(deployment.diamond)).beforeSwap(
            trader,
            poolKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}),
            ""
        );
    }
}
