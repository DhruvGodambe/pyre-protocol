// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";
import {PyreHookDiamondDeployer, PyreHookCreate2Deployer} from "../script/utils/PyreHookDiamondDeployer.s.sol";
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

contract PyreHookDiamondTest is Test, PyreHookDiamondDeployer {
    using PoolKeyLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    PyreHookDiamondDeployer.Deployment internal deployment;
    PyreToken internal token;
    PyreStaking internal staking;
    FireSpirit internal fireSpirit;
    MockPoolManager internal poolManager;

    address internal admin = address(this);
    address internal team = address(0x456);
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

        (deployment,) = _deployHook(admin, initParams);

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
        assertTrue(new PyreHookCreate2Deployer().validateHookAddress(address(deployment.diamond)));
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

        // claimFees is now autonomous within afterSwap

        (uint256 toYield, uint256 toTeam) = YieldDistributionFacet(address(deployment.diamond)).getTotalEthDistributed();
        assertEq(toYield, 0.8 ether);
        assertEq(toTeam, 0.2 ether);
    }

    function test_SellFeeSwapsAndDistributesEth() public {
        uint256 pyreIn = 10_000 ether;
        uint256 expectedFee = 2300 ether; // 23%
        uint256 expectedEthReceived = 2300 ether; // Since our mock returns 1:1

        vm.deal(address(poolManager), expectedEthReceived);

        vm.prank(admin);
        token.mint(address(poolManager), pyreIn);

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

        // claimFees is now autonomous within afterSwap

        (uint256 toYield, uint256 toTeam) = YieldDistributionFacet(address(deployment.diamond)).getTotalEthDistributed();

        // 80% to yield, 20% to team
        assertEq(toYield, (expectedEthReceived * 80) / 100);
        assertEq(toTeam, (expectedEthReceived * 20) / 100);
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

    function test_BurnLpPositionFlagsUserAndBurnsNft() public {
        uint256 tokenId = 123;
        address mockPm = makeAddr("positionManager");

        vm.prank(admin);
        LpBurnFacet(address(deployment.diamond)).configurePositionManager(mockPm);

        // Mock getPoolAndPositionInfo to return our poolKey
        vm.mockCall(
            mockPm, abi.encodeWithSignature("getPoolAndPositionInfo(uint256)", tokenId), abi.encode(poolKey, bytes32(0))
        );

        // Mock transferFrom
        vm.mockCall(
            mockPm,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                trader,
                address(0x000000000000000000000000000000000000dEaD),
                tokenId
            ),
            ""
        );

        // Execute burn from trader
        vm.prank(trader);
        LpBurnFacet(address(deployment.diamond)).burnLpPosition(tokenId);

        // Verify FireSpirit flagged the user
        assertTrue(fireSpirit.lpBurners(trader));

        // Verify accounting
        assertEq(LpBurnFacet(address(deployment.diamond)).getTotalLpBurns(), 1);
    }

    function test_BurnLpPositionRevertsIfWrongPool() public {
        uint256 tokenId = 456;
        address mockPm = makeAddr("positionManager");

        vm.prank(admin);
        LpBurnFacet(address(deployment.diamond)).configurePositionManager(mockPm);

        // Create a fake pool key with a different hook address
        PoolKey memory fakeKey = poolKey;
        fakeKey.hooks = IHooks(address(0x999));

        vm.mockCall(
            mockPm, abi.encodeWithSignature("getPoolAndPositionInfo(uint256)", tokenId), abi.encode(fakeKey, bytes32(0))
        );

        vm.prank(trader);
        vm.expectRevert("Not a Pyre LP token");
        LpBurnFacet(address(deployment.diamond)).burnLpPosition(tokenId);
    }

    function test_BurnLpPositionBoostAppliedToStakingWeight() public {
        uint256 stakeAmount = 10_000 ether;

        vm.prank(admin);
        token.mint(trader, stakeAmount);

        // Without LP burn flag: weight = stakeAmount × 1× NFT × 1× lpBonus = 10k
        vm.prank(trader);
        staking.stake(stakeAmount);
        assertEq(staking.weightOf(trader), stakeAmount);

        // Perform LP burn
        uint256 tokenId = 789;
        address mockPm = makeAddr("positionManager");
        vm.prank(admin);
        LpBurnFacet(address(deployment.diamond)).configurePositionManager(mockPm);

        vm.mockCall(
            mockPm, abi.encodeWithSignature("getPoolAndPositionInfo(uint256)", tokenId), abi.encode(poolKey, bytes32(0))
        );
        vm.mockCall(
            mockPm,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                trader,
                address(0x000000000000000000000000000000000000dEaD),
                tokenId
            ),
            ""
        );

        vm.prank(trader);
        LpBurnFacet(address(deployment.diamond)).burnLpPosition(tokenId);

        // weight = 10k × 1× NFT × 1.2× lpBonus = 12k
        assertEq(staking.weightOf(trader), stakeAmount * 12 / 10);
    }
}
