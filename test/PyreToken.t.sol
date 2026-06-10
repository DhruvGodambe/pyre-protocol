// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract PyreTokenTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors factors = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), block.timestamp, address(factors));

        vm.prank(admin);
        token.setStakingContract(address(staking));

        vm.prank(admin);
        token.mint(alice, 1_000_000 ether);
    }

    function test_MintAndBurn() public {
        assertEq(token.balanceOf(alice), 1_000_000 ether);
        assertEq(token.liquidBalanceOf(alice), 1_000_000 ether);

        vm.prank(alice);
        token.burn(100 ether);

        assertEq(token.balanceOf(alice), 999_900 ether);
        assertEq(token.totalSupply(), 999_900 ether);
    }

    function test_DecayAfterOneEpoch() public {
        uint256 before = token.liquidBalanceOf(alice);
        vm.warp(block.timestamp + 1 hours);
        uint256 afterDecay = token.liquidBalanceOf(alice);

        assertEq(token.decayRateBps(token.currentEpoch()), 45);
        assertApproxEqAbs(afterDecay, (before * 9955) / 10_000, 1 wei);
    }

    function test_DecayFloorRate() public {
        uint256 era6Epoch = 6 * token.EPOCHS_PER_ERA();
        vm.warp(token.protocolStartTime() + era6Epoch * token.EPOCH_DURATION());

        assertEq(token.decayRateBps(era6Epoch), 1);

        vm.prank(alice);
        token.transfer(alice, 1 wei);

        uint256 before = token.liquidBalanceOf(alice);
        vm.warp(block.timestamp + 1 hours);
        uint256 afterDecay = token.liquidBalanceOf(alice);

        assertApproxEqRel(afterDecay, (before * 9999) / 10_000, 0.0001e18);
    }

    function test_EraHalving() public {
        assertEq(token.decayRateBps(0), 45);
        assertEq(token.decayRateBps(token.EPOCHS_PER_ERA()), 22);
        assertEq(token.decayRateBps(2 * token.EPOCHS_PER_ERA()), 11);
    }

    function test_StakedBalanceDoesNotDecay() public {
        vm.prank(alice);
        staking.stake(500_000 ether);

        vm.warp(block.timestamp + 24 hours);

        assertEq(token.stakedBalanceOf(alice), 500_000 ether);
        assertApproxEqRel(token.liquidBalanceOf(alice), _applyDecay(500_000 ether, 9955, 24), 0.0002e18);
    }

    function test_UnstakeDripRelease() public {
        vm.startPrank(alice);
        staking.stake(1_000_000 ether);
        staking.unstake(1_000_000 ether);
        vm.stopPrank();

        assertEq(token.stakedBalanceOf(alice), 0);
        assertEq(token.liquidBalanceOf(alice), 0);
        assertEq(token.dripBalanceOf(alice), 1_000_000 ether);

        vm.warp(block.timestamp + 3.5 days);
        assertEq(token.dripBalanceOf(alice), 500_000 ether);

        vm.prank(alice);
        uint256 claimed = token.claimDrip();
        assertApproxEqAbs(claimed, 500_000 ether, 1 wei);
        assertApproxEqAbs(token.liquidBalanceOf(alice), 500_000 ether, 1 wei);
        assertEq(token.dripBalanceOf(alice), 500_000 ether);
    }

    function test_DripUnlockedTokensDecay() public {
        vm.startPrank(alice);
        staking.stake(1_000_000 ether);
        staking.unstake(1_000_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        vm.prank(alice);
        token.claimDrip();

        uint256 liquid = token.liquidBalanceOf(alice);
        vm.warp(block.timestamp + 1 hours);
        assertApproxEqAbs(token.liquidBalanceOf(alice), (liquid * 9955) / 10_000, 1 wei);
    }

    function test_TransferUsesLiquidBalanceOnly() public {
        vm.prank(alice);
        staking.stake(900_000 ether);

        vm.prank(alice);
        token.transfer(bob, 50_000 ether);

        assertEq(token.liquidBalanceOf(bob), 50_000 ether);
        assertEq(token.stakedBalanceOf(alice), 900_000 ether);
    }

    function test_LazyDecayAppliedOnTransfer() public {
        vm.warp(block.timestamp + 5 hours);

        vm.prank(alice);
        token.transfer(bob, 100_000 ether);

        uint256 expectedAlice = _applyDecay(1_000_000 ether, 9955, 5) - 100_000 ether;
        assertApproxEqRel(token.liquidBalanceOf(alice), expectedAlice, 0.0001e18);
        assertEq(token.liquidBalanceOf(bob), 100_000 ether);
    }

    function test_RevertWhenTransferExceedsLiquid() public {
        vm.prank(alice);
        staking.stake(999_000 ether);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 2_000 ether);
    }

    function test_OnlyStakingContractCanStake() public {
        vm.prank(alice);
        vm.expectRevert();
        token.stakeFor(alice, 1 ether);
    }

    function _applyDecay(uint256 amount, uint256 rateBps, uint256 epochs) internal pure returns (uint256) {
        for (uint256 i; i < epochs; ++i) {
            amount = (amount * rateBps) / 10_000;
        }
        return amount;
    }

    function testFuzz_MintPreservesSupply(uint96 amount) public {
        uint256 maxMint = 1_000_000 ether;
        amount = uint96(bound(amount, 1, maxMint));
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        token.mint(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), 1_000_000 ether + amount);
    }
}
