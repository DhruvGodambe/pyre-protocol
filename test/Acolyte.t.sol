// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {Acolyte} from "../src/nft/Acolyte.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract AcolyteTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;
    Acolyte internal acolyte;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), block.timestamp, address(bootstrap));
        acolyte = new Acolyte(admin, address(token), address(staking));

        vm.startPrank(admin);
        token.setStakingContract(address(staking));
        token.setBurnTracker(address(acolyte));
        staking.setWeightFactors(address(acolyte));
        token.mint(alice, 500_000 ether);
        token.mint(bob, 500_000 ether);
        vm.stopPrank();
    }

    function test_PartialBurnsAccumulateBeforeMint() public {
        vm.startPrank(alice);
        token.burn(4_000 ether);
        token.burn(3_000 ether);
        assertEq(acolyte.walletToTokenId(alice), 0);

        token.burn(3_500 ether);
        vm.stopPrank();

        assertEq(acolyte.walletToTokenId(alice), 1);
        assertEq(uint8(acolyte.stageOf(alice)), uint8(Acolyte.Stage.EMBER));
        assertEq(acolyte.nftStageMultiplier(alice), 1e18);
    }

    function test_StageProgressionOnSameTokenId() public {
        vm.startPrank(alice);
        token.burn(10_000 ether);
        assertEq(uint8(acolyte.stageOf(alice)), uint8(Acolyte.Stage.EMBER));

        token.burn(65_000 ether);
        assertEq(uint8(acolyte.stageOf(alice)), uint8(Acolyte.Stage.FLAME));
        assertEq(acolyte.nftStageMultiplier(alice), 15e17);

        token.burn(75_000 ether);
        assertEq(uint8(acolyte.stageOf(alice)), uint8(Acolyte.Stage.FORGE));
        assertEq(acolyte.nftStageMultiplier(alice), 2e18);

        token.burn(150_000 ether);
        assertEq(uint8(acolyte.stageOf(alice)), uint8(Acolyte.Stage.PYRE));
        assertEq(acolyte.nftStageMultiplier(alice), 3e18);
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
        acolyte.flagLpBurner(alice);

        assertEq(acolyte.lpBurnBonus(alice), 12e17);
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
        acolyte.transferFrom(alice, bob, 1);

        assertEq(alice.balance, balanceBefore + expected);
        assertEq(staking.earned(alice), 0);
        assertEq(acolyte.ownerOf(1), bob);

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
        acolyte.transferFrom(alice, bob, 1);

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
        acolyte.transferFrom(alice, bob, 1);
        token.burn(10_000 ether);
        vm.stopPrank();

        assertEq(acolyte.walletToTokenId(bob), 1);
        assertEq(acolyte.walletToTokenId(alice), 2);
        assertEq(acolyte.ownerOf(2), alice);
    }
}
