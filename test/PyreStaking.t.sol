// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract PyreStakingTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;
    MockPyreWeightFactors internal factors;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal nftHolder = makeAddr("nftHolder");

    uint256 internal launchTime;

    function setUp() public {
        launchTime = block.timestamp;

        token = new PyreToken(admin, "Pyre", "PYRE");
        factors = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), launchTime, address(factors));

        vm.prank(admin);
        token.setStakingContract(address(staking));

        vm.startPrank(admin);
        token.mint(alice, 100_000 ether);
        token.mint(bob, 100_000 ether);
        token.mint(nftHolder, 10_000 ether);
        vm.stopPrank();

        factors.setNftStageMultiplier(nftHolder, 3e18);
    }

    function test_StakedTokensDoNotDecay() public {
        vm.prank(alice);
        staking.stake(50_000 ether);

        vm.warp(block.timestamp + 48 hours);

        assertEq(token.stakedBalanceOf(alice), 50_000 ether);
        assertEq(staking.stakedBalanceOf(alice), 50_000 ether);
        assertLt(token.liquidBalanceOf(alice), 50_000 ether);
    }

    function test_UnstakeUsesSevenDayDrip() public {
        vm.startPrank(alice);
        staking.stake(100_000 ether);
        staking.unstake(100_000 ether);
        vm.stopPrank();

        assertEq(token.stakedBalanceOf(alice), 0);
        assertEq(token.dripBalanceOf(alice), 100_000 ether);

        vm.warp(block.timestamp + 7 days);
        vm.prank(alice);
        token.claimDrip();

        assertEq(token.liquidBalanceOf(alice), 100_000 ether);
    }

    function test_NftMultiplierMatchesEquivalentStake() public {
        uint256 rewardAmount = 30 ether;
        uint256 duration = 30 days;

        vm.deal(admin, rewardAmount);
        vm.prank(admin);
        staking.notifyRewardAmount{value: rewardAmount}(rewardAmount, duration);

        vm.prank(nftHolder);
        staking.stake(10_000 ether);

        vm.prank(bob);
        staking.stake(30_000 ether);

        vm.warp(block.timestamp + 1 days);

        uint256 nftEarned = staking.earned(nftHolder);
        uint256 bobEarned = staking.earned(bob);

        assertApproxEqRel(nftEarned, bobEarned, 0.0001e18);
        assertGt(nftEarned, 0);
    }

    function test_WhitelistBoostWithinLaunchWindow() public {
        vm.prank(admin);
        staking.setWhitelisted(alice, true);

        vm.warp(launchTime + 24 hours);

        vm.prank(alice);
        staking.stake(10_000 ether);

        uint256 boosted = staking.weightOf(alice);
        assertEq(boosted, 12_000 ether);
    }

    function test_WhitelistBoostExpiresAfterSevenDays() public {
        vm.prank(admin);
        staking.setWhitelisted(alice, true);

        vm.warp(launchTime + 24 hours);
        vm.prank(alice);
        staking.stake(10_000 ether);

        vm.warp(launchTime + 8 days);
        assertEq(staking.weightOf(alice), 10_000 ether);
    }

    function test_WhitelistBoostRequiresStakeWithin48Hours() public {
        vm.prank(admin);
        staking.setWhitelisted(alice, true);

        vm.warp(launchTime + 3 days);
        vm.prank(alice);
        staking.stake(10_000 ether);

        assertEq(staking.weightOf(alice), 10_000 ether);
    }

    function test_EthRewardsAccrueWhileStaked() public {
        vm.prank(alice);
        staking.stake(10_000 ether);

        uint256 rewardAmount = 10 ether;
        vm.deal(admin, rewardAmount);
        vm.prank(admin);
        staking.notifyRewardAmount{value: rewardAmount}(rewardAmount, 10 days);

        vm.warp(block.timestamp + 5 days);

        uint256 pending = staking.earned(alice);
        assertApproxEqAbs(pending, 5 ether, 0.01 ether);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        staking.claimReward();

        assertEq(alice.balance, balanceBefore + pending);
        assertEq(staking.earned(alice), 0);
    }

    function test_NoYieldDuringDrip() public {
        vm.prank(alice);
        staking.stake(10_000 ether);

        vm.deal(admin, 10 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 10 ether}(10 ether, 10 days);

        vm.warp(block.timestamp + 2 days);
        uint256 earnedBefore = staking.earned(alice);

        vm.prank(alice);
        staking.unstake(10_000 ether);

        vm.warp(block.timestamp + 5 days);
        assertEq(staking.earned(alice), earnedBefore);
    }

    function test_TotalWeightScalesWithoutLooping() public {
        address[] memory stakers = new address[](5);
        for (uint256 i; i < 5; ++i) {
            address staker = makeAddr(string(abi.encodePacked("staker", i)));
            stakers[i] = staker;
            vm.prank(admin);
            token.mint(staker, 1_000 ether);
            vm.prank(staker);
            staking.stake(1_000 ether);
        }

        assertEq(staking.totalWeight(), 5_000 ether);

        vm.deal(admin, 1 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 1 ether}(1 ether, 1 days);

        vm.warp(block.timestamp + 12 hours);

        for (uint256 i; i < 5; ++i) {
            assertApproxEqAbs(staking.earned(stakers[i]), 0.1 ether, 0.001 ether);
        }
    }
}
