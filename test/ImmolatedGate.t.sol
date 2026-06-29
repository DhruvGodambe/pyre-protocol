// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PyreToken} from "../src/tokens/PyreToken.sol";
import {PyreStaking} from "../src/staking/PyreStaking.sol";
import {Acolyte} from "../src/nft/Acolyte.sol";
import {ImmolatedGate} from "../src/gate/ImmolatedGate.sol";
import {MockPyreWeightFactors} from "../src/mocks/MockPyreWeightFactors.sol";

contract ImmolatedGateTest is Test {
    PyreToken internal token;
    PyreStaking internal staking;
    Acolyte internal acolyte;
    ImmolatedGate internal gate;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new PyreToken(admin, "Pyre", "PYRE");
        MockPyreWeightFactors bootstrap = new MockPyreWeightFactors();
        staking = new PyreStaking(admin, address(token), block.timestamp, address(bootstrap));
        acolyte = new Acolyte(admin, address(token), address(staking));
        gate = new ImmolatedGate(address(token), address(acolyte));

        vm.startPrank(admin);
        token.setStakingContract(address(staking));
        token.setBurnTracker(address(acolyte));
        staking.setWeightFactors(address(acolyte));
        token.mint(alice, 320_000 ether);
        token.mint(bob, 320_000 ether);
        vm.stopPrank();
    }

    function _reachPyreStage(address account) internal {
        vm.startPrank(account);
        token.burn(300_000 ether);
        vm.stopPrank();
        assertEq(uint8(acolyte.stageOf(account)), uint8(Acolyte.Stage.PYRE));
    }

    function test_ImmolateSetsFlag() public {
        _reachPyreStage(alice);

        vm.startPrank(alice);
        token.approve(address(gate), 10_000 ether);
        gate.immolate();
        vm.stopPrank();

        assertTrue(gate.isImmolated(alice));
        assertEq(gate.immolatedCount(), 1);
    }

    function test_ImmolateBurnsAdditionalTenThousand() public {
        _reachPyreStage(alice);

        uint256 supplyBefore = token.totalSupply();

        vm.startPrank(alice);
        token.approve(address(gate), 10_000 ether);
        gate.immolate();
        vm.stopPrank();

        assertEq(token.totalSupply(), supplyBefore - 10_000 ether);
        assertEq(acolyte.acolyteCumulativeBurn(1), 310_000 ether);
    }

    function test_RevertWithoutPyreAcolyte() public {
        vm.startPrank(bob);
        token.burn(10_000 ether);
        token.approve(address(gate), 10_000 ether);
        vm.expectRevert();
        gate.immolate();
        vm.stopPrank();
    }

    function test_RevertIfAlreadyImmolated() public {
        _reachPyreStage(alice);

        vm.startPrank(alice);
        token.approve(address(gate), 20_000 ether);
        gate.immolate();
        vm.expectRevert();
        gate.immolate();
        vm.stopPrank();
    }

    function test_NoSupplyCapMultipleImmolations() public {
        _reachPyreStage(alice);
        _reachPyreStage(bob);

        vm.startPrank(alice);
        token.approve(address(gate), 10_000 ether);
        gate.immolate();
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(gate), 10_000 ether);
        gate.immolate();
        vm.stopPrank();

        assertTrue(gate.isImmolated(alice));
        assertTrue(gate.isImmolated(bob));
        assertEq(gate.immolatedCount(), 2);
    }

    function test_RevertInsufficientLiquidForAdditionalBurn() public {
        _reachPyreStage(alice);

        vm.prank(alice);
        staking.stake(15_000 ether);

        vm.startPrank(alice);
        token.approve(address(gate), 10_000 ether);
        vm.expectRevert();
        gate.immolate();
        vm.stopPrank();
    }
}
