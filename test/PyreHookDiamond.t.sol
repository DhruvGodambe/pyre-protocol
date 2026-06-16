// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";
import {PyreHookDiamondDeployer} from "../script/utils/PyreHookDiamondDeployer.s.sol";
import {PyreHookInitParams} from "../src/hook/init/DiamondInit.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {BurnFacet} from "../src/hook/facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../src/hook/facets/YieldDistributionFacet.sol";
import {LpBurnFacet} from "../src/hook/facets/LpBurnFacet.sol";
import {IHooks} from "../src/hook/v4/interfaces/IHooks.sol";
import {PoolKey} from "../src/hook/v4/types/PoolKey.sol";
import {PoolKeyLibrary} from "../src/hook/v4/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/hook/v4/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "../src/hook/v4/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../src/hook/v4/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../src/hook/v4/types/BeforeSwapDelta.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";

contract PyreHookDiamondTest is Test {
    using PoolKeyLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    PyreHookDiamondDeployer.Deployment internal deployment;
    PyreToken internal token;
    PyreStaking internal staking;
    FireSpirit internal fireSpirit;
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
        fireSpirit = new FireSpirit(admin, address(token), address(staking));

        poolManager = new MockPoolManager();

        PyreHookInitParams memory initParams =
            PyreHookInitParams({pyreToken: address(token), pyreStaking: address(staking), teamWallet: team});

        deployment = new PyreHookDiamondDeployer().deploy(admin, initParams);

        poolKey = PoolKey({
            currency0: CurrencyLibrary.wrap(address(0)),
            currency1: CurrencyLibrary.wrap(address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(deployment.diamond))
        });

        // Wire full protocol in a single prank block so no one-shot vm.prank is
        // accidentally consumed by a view call (e.g. LP_RECORDER_ROLE()).
        vm.startPrank(admin);
        token.setStakingContract(address(staking));
        staking.setWeightFactors(address(fireSpirit));
        staking.setYieldRouter(address(deployment.diamond));
        FeeLogicFacet(address(deployment.diamond))
            .configurePool(address(poolManager), poolKey, poolKey.currency1, poolKey.currency0, launchTime);
        fireSpirit.grantRole(fireSpirit.LP_RECORDER_ROLE(), address(deployment.diamond));
        LpBurnFacet(address(deployment.diamond)).configureFireSpirit(address(fireSpirit));
        vm.stopPrank();
    }

    function test_DeploysWithValidHookAddress() public {
        assertTrue(new PyreHookDiamondDeployer().validateHookAddress(address(deployment.diamond)));
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
        (bytes4 selector, BeforeSwapDelta delta,) = IHooks(address(deployment.diamond))
            .beforeSwap(
                trader,
                poolKey,
                SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: 0}),
                ""
            );

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(delta), int128(int256(expectedFee)));

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterSwap(
                trader,
                poolKey,
                SwapParams({zeroForOne: true, amountSpecified: 0, sqrtPriceLimitX96: 0}),
                BalanceDeltaLibrary.ZERO_DELTA,
                ""
            );

        // claimFees triggers poolManager.unlock → unlockCallback → extractAndDistributeBuyFee
        FeeLogicFacet(address(deployment.diamond)).claimFees(true);

        (uint256 toYield, uint256 toTeam) = YieldDistributionFacet(address(deployment.diamond)).getTotalEthDistributed();
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
        IHooks(address(deployment.diamond))
            .beforeSwap(
                trader,
                poolKey,
                SwapParams({zeroForOne: false, amountSpecified: -int256(pyreIn), sqrtPriceLimitX96: 0}),
                ""
            );

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterSwap(
                trader,
                poolKey,
                SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0}),
                BalanceDeltaLibrary.ZERO_DELTA,
                ""
            );

        // claimFees triggers poolManager.unlock → unlockCallback → extractAndDistributeSellFee
        FeeLogicFacet(address(deployment.diamond)).claimFees(false);

        assertEq(BurnFacet(address(deployment.diamond)).getTotalPyreBurned(), expectedFee);
        assertEq(token.totalSupply(), supplyBefore - expectedFee);
    }

    function test_RevertOnUnregisteredPool() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.fee = 500;

        vm.prank(address(poolManager));
        vm.expectRevert();
        IHooks(address(deployment.diamond))
            .beforeSwap(
                trader, fakeKey, SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}), ""
            );
    }

    function test_RevertOnNonPoolManagerCaller() public {
        vm.expectRevert();
        IHooks(address(deployment.diamond))
            .beforeSwap(
                trader, poolKey, SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}), ""
            );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP Position Burn Tests
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Simulates a remove-liquidity call where the LP opts to burn their position.
    ///      Verifies that PYRE is burned, ETH is routed, and the user is flagged in FireSpirit.
    function test_LpBurnFlagsUserAndBurnsTokens() public {
        uint256 pyreAmount = 1_000 ether;
        uint256 ethAmount = 1 ether;

        // Pre-fund pool manager to simulate pool reserves being returned to LP
        vm.prank(admin);
        token.mint(address(poolManager), pyreAmount);
        vm.deal(address(poolManager), ethAmount);

        uint256 supplyBefore = token.totalSupply();

        // delta: (currency0=ETH, currency1=PYRE) amounts the LP would have received
        BalanceDelta delta = toBalanceDelta(int128(int256(ethAmount)), int128(int256(pyreAmount)));

        vm.prank(address(poolManager));
        (bytes4 selector, BalanceDelta hookDelta) = IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                abi.encode(true)
            );

        // Correct selector returned
        assertEq(selector, IHooks.afterRemoveLiquidity.selector);

        // Hook claims the full delta so LP receives nothing
        assertEq(hookDelta.amount0(), -int128(int256(ethAmount)));
        assertEq(hookDelta.amount1(), -int128(int256(pyreAmount)));

        // PYRE was permanently burned
        assertEq(token.totalSupply(), supplyBefore - pyreAmount);

        // FireSpirit flagged the user for the +20% yield bonus
        assertTrue(fireSpirit.lpBurners(trader));

        // Accounting updated
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalLpBurns(), 1);
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalPyreBurnedFromLp(), pyreAmount);
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalEthRoutedFromLp(), ethAmount);
    }

    /// @dev ETH from the LP burn is split 80/20 identically to buy-side swap fees.
    function test_LpBurnRoutesEthToStakingAndTeam() public {
        uint256 ethAmount = 10 ether;

        vm.deal(address(poolManager), ethAmount);
        // No PYRE in this delta (PYRE-less position for isolated ETH routing test)
        BalanceDelta delta = toBalanceDelta(int128(int256(ethAmount)), 0);

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                abi.encode(true)
            );

        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalEthRoutedFromLp(), ethAmount);
        assertEq(address(team).balance, 2 ether); // 20% team share
    }

    /// @dev Without the burn flag, afterRemoveLiquidity is a no-op: ZERO_DELTA and no flagging.
    function test_LpBurnWithoutFlagIsNoop() public {
        uint256 pyreAmount = 1_000 ether;
        uint256 ethAmount = 1 ether;

        vm.prank(admin);
        token.mint(address(poolManager), pyreAmount);
        vm.deal(address(poolManager), ethAmount);

        uint256 supplyBefore = token.totalSupply();
        BalanceDelta delta = toBalanceDelta(int128(int256(ethAmount)), int128(int256(pyreAmount)));

        vm.prank(address(poolManager));
        (, BalanceDelta hookDelta) = IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                "" // no burn flag
            );

        // Hook returns ZERO_DELTA → LP keeps their tokens
        assertEq(BalanceDelta.unwrap(hookDelta), 0);

        // Nothing burned, nobody flagged
        assertEq(token.totalSupply(), supplyBefore);
        assertFalse(fireSpirit.lpBurners(trader));
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalLpBurns(), 0);
    }

    /// @dev LP burn can be repeated; each removal is independent.
    function test_LpBurnCanBePerformedMultipleTimes() public {
        uint256 pyreAmount = 500 ether;

        vm.prank(admin);
        token.mint(address(poolManager), pyreAmount * 2);

        BalanceDelta delta = toBalanceDelta(0, int128(int256(pyreAmount)));

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                abi.encode(true)
            );

        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                abi.encode(true)
            );

        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalLpBurns(), 2);
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalPyreBurnedFromLp(), pyreAmount * 2);
        assertTrue(fireSpirit.lpBurners(trader));
    }

    /// @dev Staking weight increases by 20% for an LP burner (FireSpirit lpBurnBonus).
    function test_LpBurnBoostAppliedToStakingWeight() public {
        uint256 stakeAmount = 10_000 ether;

        vm.prank(admin);
        token.mint(trader, stakeAmount);

        // Without LP burn flag: weight = stakeAmount × 1× NFT × 1× lpBonus = 10k
        vm.prank(trader);
        staking.stake(stakeAmount);
        assertEq(staking.weightOf(trader), stakeAmount);

        // Trigger LP burn → flag user in FireSpirit
        vm.prank(admin);
        token.mint(address(poolManager), 100 ether);

        BalanceDelta delta = toBalanceDelta(0, int128(int256(100 ether)));
        vm.prank(address(poolManager));
        IHooks(address(deployment.diamond))
            .afterRemoveLiquidity(
                trader,
                poolKey,
                ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)}),
                delta,
                BalanceDeltaLibrary.ZERO_DELTA,
                abi.encode(true)
            );

        // FireSpirit.flagLpBurner triggers onWeightFactorsChanged → weight refreshed
        // weight = 10k × 1× NFT × 1.2× lpBonus = 12k
        assertEq(staking.weightOf(trader), stakeAmount * 12 / 10);
    }
}
