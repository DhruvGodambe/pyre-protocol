// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {ImmolatedGate} from "../src/gate/ImmolatedGate.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

/// @notice Mirrors script/DeployPyre.s.sol wiring and exercises cross-contract flows.
contract PyreIntegrationTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;
    FireSpirit internal spirit;
    ImmolatedGate internal gate;

    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");

    uint256 internal launchTime;

    function setUp() public {
        launchTime = block.timestamp;
        _deployProtocol();
    }

    function _deployProtocol() internal {
        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), launchTime, address(bootstrap));
        spirit = new FireSpirit(admin, address(token), address(staking));
        gate = new ImmolatedGate(address(token), address(spirit));

        vm.startPrank(admin);
        token.setStakingContract(address(staking));
        token.setBurnTracker(address(spirit));
        staking.setWeightFactors(address(spirit));
        vm.stopPrank();
    }

    function test_DeploymentWiring() public view {
        assertEq(token.stakingContract(), address(staking));
        assertEq(token.burnTracker(), address(spirit));
        assertEq(address(staking.weightFactors()), address(spirit));
        assertEq(address(gate.pyreToken()), address(token));
        assertEq(address(gate.fireSpirit()), address(spirit));
        assertEq(spirit.pyreToken(), address(token));
        assertEq(address(spirit.pyreStaking()), address(staking));
    }

    function test_FullUserJourney() public {
        vm.prank(admin);
        token.mint(user, 350_000 ether);

        // Burns accumulate → FireSpirit mint + stage progression
        vm.startPrank(user);
        token.burn(10_000 ether);
        assertEq(spirit.walletToTokenId(user), 1);

        token.burn(290_000 ether);
        assertEq(uint8(spirit.stageOf(user)), uint8(FireSpirit.Stage.PYRE));
        vm.stopPrank();

        // Staking uses FireSpirit multipliers (3× PYRE stage)
        vm.deal(admin, 30 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 30 ether}(30 ether, 30 days);

        vm.prank(user);
        staking.stake(10_000 ether);
        assertEq(staking.weightOf(user), 30_000 ether);
        assertEq(token.stakedBalanceOf(user), 10_000 ether);

        vm.warp(block.timestamp + 1 days);
        assertGt(staking.earned(user), 0);

        // Unstake → 7-day drip, yield stops accruing
        uint256 earnedAtUnstake = staking.earned(user);
        vm.prank(user);
        staking.unstake(10_000 ether);
        assertEq(token.dripBalanceOf(user), 10_000 ether);

        vm.warp(block.timestamp + 3 days);
        assertEq(staking.earned(user), earnedAtUnstake);

        // Claim drip → liquid balance restored (minus decay on remainder)
        vm.warp(block.timestamp + 4 days);
        vm.prank(user);
        token.claimDrip();
        assertGt(token.liquidBalanceOf(user), 0);

        // LP burner flag → +20% weight on restake
        vm.prank(admin);
        spirit.flagLpBurner(user);

        vm.prank(user);
        staking.stake(10_000 ether);
        assertEq(staking.weightOf(user), 36_000 ether); // 10k × 3 × 1.2

        // ImmolatedGate → PYRE spirit + 10k burn
        vm.prank(user);
        staking.unstake(10_000 ether);
        vm.warp(block.timestamp + 7 days);
        vm.prank(user);
        token.claimDrip();

        vm.startPrank(user);
        token.approve(address(gate), 10_000 ether);
        gate.immolate();
        vm.stopPrank();

        assertTrue(gate.isImmolated(user));
        assertEq(spirit.spiritCumulativeBurn(1), 310_000 ether);
    }

    function test_BurnTrackerOnlyAcceptsToken() public {
        vm.expectRevert();
        spirit.onPyreBurn(user, 1 ether);
    }

    function test_StakingOnlyAcceptsStakingContract() public {
        vm.expectRevert();
        token.stakeFor(user, 1 ether);
    }

    function test_WeightFactorsHookOnlyAcceptsFireSpirit() public {
        vm.expectRevert();
        staking.onWeightFactorsChanged(user);
    }

    function test_LiquidDecayDoesNotAffectStakedOrDrip() public {
        vm.prank(admin);
        token.mint(user, 50_000 ether);

        vm.prank(user);
        staking.stake(20_000 ether);

        uint256 staked = token.stakedBalanceOf(user);
        vm.warp(block.timestamp + 72 hours);

        assertEq(token.stakedBalanceOf(user), staked);
        assertLt(token.liquidBalanceOf(user), 30_000 ether);
    }

    function test_WhitelistBoostIntegratesWithFireSpiritWeight() public {
        vm.prank(admin);
        token.mint(user, 25_000 ether);
        vm.prank(admin);
        staking.setWhitelisted(user, true);

        vm.warp(launchTime + 12 hours);

        vm.startPrank(user);
        token.burn(10_000 ether);
        staking.stake(10_000 ether);
        vm.stopPrank();

        // 10k × 1× EMBER × 1.2 whitelist = 12k
        assertEq(staking.weightOf(user), 12_000 ether);
    }
}
