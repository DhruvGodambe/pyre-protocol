// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {FireSpirit} from "../src/nft/FireSpirit.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract FireSpiritTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;
    FireSpirit internal spirit;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), block.timestamp, address(bootstrap));
        spirit = new FireSpirit(admin, address(token), address(staking));

        vm.startPrank(admin);
        token.setStakingContract(address(staking));
        token.setBurnTracker(address(spirit));
        staking.setWeightFactors(address(spirit));
        token.mint(alice, 500_000 ether);
        token.mint(bob, 500_000 ether);
        vm.stopPrank();
    }

    function test_PartialBurnsAccumulateBeforeMint() public {
        vm.startPrank(alice);
        token.burn(4_000 ether);
        token.burn(3_000 ether);
        assertEq(spirit.walletToTokenId(alice), 0);

        token.burn(3_500 ether);
        vm.stopPrank();

        assertEq(spirit.walletToTokenId(alice), 1);
        assertEq(uint8(spirit.stageOf(alice)), uint8(FireSpirit.Stage.EMBER));
        assertEq(spirit.nftStageMultiplier(alice), 1e18);
    }

    function test_StageProgressionOnSameTokenId() public {
        vm.startPrank(alice);
        token.burn(10_000 ether);
        assertEq(uint8(spirit.stageOf(alice)), uint8(FireSpirit.Stage.EMBER));

        token.burn(65_000 ether);
        assertEq(uint8(spirit.stageOf(alice)), uint8(FireSpirit.Stage.FLAME));
        assertEq(spirit.nftStageMultiplier(alice), 15e17);

        token.burn(75_000 ether);
        assertEq(uint8(spirit.stageOf(alice)), uint8(FireSpirit.Stage.FORGE));
        assertEq(spirit.nftStageMultiplier(alice), 2e18);

        token.burn(150_000 ether);
        assertEq(uint8(spirit.stageOf(alice)), uint8(FireSpirit.Stage.PYRE));
        assertEq(spirit.nftStageMultiplier(alice), 3e18);
        vm.stopPrank();
    }

    function test_PyreStageMatchesThirtyThousandStakeWeight() public {
        address nftHolder = makeAddr("nftHolder");
        address plainHolder = makeAddr("plainHolder");

        vm.startPrank(admin);
        token.mint(nftHolder, 310_000 ether);
        token.mint(plainHolder, 300_000 ether);
        vm.stopPrank();

        vm.prank(nftHolder);
        token.burn(300_000 ether);

        vm.deal(admin, 30 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 30 ether}(30 ether, 30 days);

        vm.prank(nftHolder);
        staking.stake(10_000 ether);

        vm.prank(plainHolder);
        staking.stake(30_000 ether);

        vm.warp(block.timestamp + 1 days);

        assertApproxEqRel(staking.earned(nftHolder), staking.earned(plainHolder), 0.0001e18);
    }

    function test_LpBurnerReceivesTwentyPercentBonus() public {
        vm.prank(alice);
        token.burn(10_000 ether);

        vm.prank(admin);
        spirit.flagLpBurner(alice);

        assertEq(spirit.lpBurnBonus(alice), 12e17);
        assertEq(staking.weightOf(alice), 0);

        vm.prank(alice);
        staking.stake(10_000 ether);

        assertEq(staking.weightOf(alice), 12_000 ether);
    }

    function test_YieldSettlesToSellerOnTransfer() public {
        vm.prank(alice);
        token.burn(10_000 ether);

        vm.prank(alice);
        staking.stake(10_000 ether);

        vm.deal(admin, 10 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 10 ether}(10 ether, 10 days);

        vm.warp(block.timestamp + 5 days);
        uint256 expected = staking.earned(alice);
        assertGt(expected, 0);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        spirit.transferFrom(alice, bob, 1);

        assertEq(alice.balance, balanceBefore + expected);
        assertEq(staking.earned(alice), 0);
        assertEq(spirit.ownerOf(1), bob);

        vm.prank(bob);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 5 days);
        assertGt(staking.earned(bob), 0);
        assertGt(staking.earned(alice), 0);
    }

    function test_BuyerEarnsFromTransferPointForward() public {
        vm.prank(alice);
        token.burn(300_000 ether);

        vm.prank(alice);
        staking.stake(10_000 ether);

        vm.deal(admin, 10 ether);
        vm.prank(admin);
        staking.notifyRewardAmount{value: 10 ether}(10 ether, 10 days);

        vm.warp(block.timestamp + 2 days);
        uint256 aliceBeforeTransfer = staking.earned(alice);

        vm.prank(alice);
        spirit.transferFrom(alice, bob, 1);

        vm.prank(bob);
        staking.stake(10_000 ether);

        assertEq(staking.earned(alice), 0);

        vm.warp(block.timestamp + 3 days);

        assertGt(staking.earned(bob), 0);
        assertGt(staking.earned(alice), 0);
        assertGt(aliceBeforeTransfer, 0);
    }

    function test_NewSpiritAfterTransferAndMoreBurns() public {
        vm.startPrank(alice);
        token.burn(10_000 ether);
        spirit.transferFrom(alice, bob, 1);
        token.burn(10_000 ether);
        vm.stopPrank();

        assertEq(spirit.walletToTokenId(bob), 1);
        assertEq(spirit.walletToTokenId(alice), 2);
        assertEq(spirit.ownerOf(2), alice);
    }
}
