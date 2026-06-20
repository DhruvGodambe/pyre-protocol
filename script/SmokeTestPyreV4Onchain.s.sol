// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";

import {PyreToken} from "../src/tokens/PyreToken.sol";
import {FeeLogicFacet} from "../src/hook/facets/FeeLogicFacet.sol";
import {BurnFacet} from "../src/hook/facets/BurnFacet.sol";
import {YieldDistributionFacet} from "../src/hook/facets/YieldDistributionFacet.sol";
import {IUniswapV4Router04} from "../src/interfaces/IUniswapV4Router04.sol";

contract SmokeTestPyreV4Onchain is Script {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    address internal constant DEFAULT_POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    address internal constant DEFAULT_PYRE_TOKEN = 0xaA46dd2434dE4b06Da8D4F7f0Ace4e152EecbbA6;
    address internal constant DEFAULT_PYRE_STAKING = 0x61564EE98d9eFDc198AE6a48dFCd864C7F06A3B3;
    address internal constant DEFAULT_FIRE_SPIRIT = 0xB14Fe355E67a2c6F08a8B0291aA188B62718264A;
    address internal constant DEFAULT_HOOK = address(0xaB0Ae552Ee5933935e39393D32b4034E75fD3Ff8);
    address internal constant DEFAULT_TEAM = 0xF93E7518F79C2E1978D6862Dbf161270040e623E;
    address internal constant DEFAULT_SWAP_ROUTER = 0x00000000000044a361Ae3cAc094c9D1b14Eece97;
    address internal constant DEFAULT_MODIFY_ROUTER = 0x0000000000000000000000000000000000000000;

    struct Config {
        address tester;
        address poolManager;
        address modifyRouter;
        address swapRouter;
        address pyreToken;
        address staking;
        address fireSpirit;
        address hook;
        address team;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        uint256 mintAmount;
        uint256 liquidityEthValue;
        uint256 ethBuyAmount;
        uint256 pyreSellAmount;
    }

    struct Snapshot {
        uint256 totalEthToYield;
        uint256 totalEthToTeam;
        uint256 totalPyreBurned;
    }

    function run() external {
        Config memory c = _config();
        PoolKey memory key = _poolKey(c);

        _logConfig(c);
        Snapshot memory beforeState = _snapshot(c);
        _logState("before", c);
        uint256 buyFeeBps = FeeLogicFacet(c.hook).getCurrentBuyFeeBps();
        uint256 sellFeeBps = FeeLogicFacet(c.hook).getCurrentSellFeeBps();

        vm.startBroadcast();

        _tryMint(c);
        _tryInitialize(c, key);
        // IERC20(c.pyreToken).approve(c.modifyRouter, type(uint256).max);
        // Permit2 configuration
        address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        IERC20(c.pyreToken).approve(PERMIT2, type(uint256).max);

        // Approve PositionManager via Permit2
        IAllowanceTransfer(PERMIT2)
            .approve(
                c.pyreToken,
                0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80,
                type(uint160).max,
                uint48(block.timestamp + 1000)
            );
        // Approve SwapRouter via Permit2
        IAllowanceTransfer(PERMIT2)
            .approve(c.pyreToken, c.swapRouter, type(uint160).max, uint48(block.timestamp + 1000));

        // Add liquidity using Position Manager
        _addLiquidity(c, key);

        console2.log("=== Swap Simulation Test ===");
        IERC20(c.pyreToken).approve(c.swapRouter, type(uint256).max);

        BalanceSnapshot memory beforeBalances = _takeBalanceSnapshot(c);

        _buyPyreWithEth(c, key);
        // FeeLogicFacet(c.hook).claimFees(true); // Claim buy fee - autonomous now

        BalanceSnapshot memory afterBuyBalances = _takeBalanceSnapshot(c);
        _logDeltas("After Buy", beforeBalances, afterBuyBalances);

        _sellPyreForEth(c, key);
        // FeeLogicFacet(c.hook).claimFees(false); // Claim sell fee - autonomous now

        BalanceSnapshot memory afterSellBalances = _takeBalanceSnapshot(c);
        _logDeltas("After Sell", afterBuyBalances, afterSellBalances);

        vm.stopBroadcast();

        _logState("after", c);
        _assertAccounting(c, beforeState, buyFeeBps, sellFeeBps);
    }

    function _config() internal view returns (Config memory c) {
        c.poolManager = vm.envOr("POOL_MANAGER", DEFAULT_POOL_MANAGER);
        c.swapRouter = vm.envOr("SWAP_ROUTER", DEFAULT_SWAP_ROUTER);
        c.modifyRouter = vm.envOr("MODIFY_ROUTER", DEFAULT_MODIFY_ROUTER);
        c.pyreToken = vm.envOr("PYRE_TOKEN", DEFAULT_PYRE_TOKEN);
        c.staking = vm.envOr("PYRE_STAKING", DEFAULT_PYRE_STAKING);
        c.fireSpirit = vm.envOr("FIRE_SPIRIT", DEFAULT_FIRE_SPIRIT);
        c.hook = vm.envOr("PYRE_HOOK", DEFAULT_HOOK);
        c.team = vm.envOr("PYRE_TEAM_WALLET", DEFAULT_TEAM);
        c.tester = vm.envOr("PYRE_TESTER", DEFAULT_TEAM);

        c.fee = uint24(vm.envOr("PYRE_POOL_FEE", uint256(3000)));
        c.tickSpacing = int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60))));
        c.tickLower = int24(int256(vm.envOr("PYRE_TICK_LOWER", int256(-887220))));
        c.tickUpper = int24(int256(vm.envOr("PYRE_TICK_UPPER", int256(887220))));
        c.liquidityDelta = int256(vm.envOr("PYRE_TEST_LIQUIDITY", uint256(1e12)));
        c.mintAmount = vm.envOr("PYRE_TEST_MINT_AMOUNT", uint256(0));
        c.liquidityEthValue = vm.envOr("PYRE_TEST_LIQUIDITY_ETH_VALUE", uint256(0.0001 ether));
        c.ethBuyAmount = vm.envOr("PYRE_TEST_ETH_BUY_AMOUNT", uint256(0.00001 ether));
        c.pyreSellAmount = vm.envOr("PYRE_TEST_PYRE_SELL_AMOUNT", uint256(1 ether));
    }

    function _poolKey(Config memory c) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(c.pyreToken),
            fee: c.fee,
            tickSpacing: c.tickSpacing,
            hooks: IHooks(c.hook)
        });
    }

    function _tryMint(Config memory c) internal {
        if (c.mintAmount == 0) return;

        try PyreToken(c.pyreToken).mint(c.tester, c.mintAmount) {
            console2.log("minted PYRE to tester", c.mintAmount);
        } catch {
            console2.log("mint skipped or failed; broadcaster must have MINTER_ROLE");
        }
    }

    function _tryInitialize(Config memory c, PoolKey memory key) internal {
        IPoolManager(c.poolManager).initialize(key, SQRT_PRICE_1_1);
        console2.log("pool initialized at tick 0");
    }

    function _addLiquidity(Config memory c, PoolKey memory key) internal {
        if (c.liquidityDelta <= 0) return;

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            key,
            c.tickLower,
            c.tickUpper,
            uint256(c.liquidityDelta),
            type(uint128).max, // amount0Max
            type(uint128).max, // amount1Max
            c.tester, // owner
            "" // hookData
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        IPositionManager(0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80).modifyLiquidities{value: c.liquidityEthValue}(
            abi.encode(actions, params), block.timestamp + 300
        );
        console2.log("liquidity added", uint256(c.liquidityDelta));
    }

    function _buyPyreWithEth(Config memory c, PoolKey memory key) internal {
        if (c.ethBuyAmount == 0) return;

        IUniswapV4Router04(payable(c.swapRouter)).swapExactTokensForTokens{value: c.ethBuyAmount}(
            c.ethBuyAmount,
            0,
            true, // zeroForOne
            key,
            "",
            c.tester,
            block.timestamp + 300
        );
        console2.log("buy swap exact ETH in", c.ethBuyAmount);
    }

    function _sellPyreForEth(Config memory c, PoolKey memory key) internal {
        if (c.pyreSellAmount == 0) return;

        IUniswapV4Router04(payable(c.swapRouter))
            .swapExactTokensForTokens(
                c.pyreSellAmount,
                0,
                false, // oneForZero
                key,
                "",
                c.tester,
                block.timestamp + 300
            );
        console2.log("sell swap exact PYRE in", c.pyreSellAmount);
    }

    function _logConfig(Config memory c) internal pure {
        console2.log("poolManager", c.poolManager);
        console2.log("modifyRouter", c.modifyRouter);
        console2.log("swapRouter", c.swapRouter);
        console2.log("pyreToken", c.pyreToken);
        console2.log("staking", c.staking);
        console2.log("fireSpirit", c.fireSpirit);
        console2.log("hook", c.hook);
        console2.log("team", c.team);
        console2.log("tester", c.tester);
    }

    function _logState(string memory label, Config memory c) internal view {
        (uint256 toYield, uint256 toTeam) = YieldDistributionFacet(c.hook).getTotalEthDistributed();
        (address stakingConfigured, address teamConfigured, uint256 yieldBps, uint256 teamBps) =
            YieldDistributionFacet(c.hook).getYieldConfig();

        console2.log("state", label);
        console2.log("tester ETH", c.tester.balance);
        console2.log("tester PYRE", IERC20(c.pyreToken).balanceOf(c.tester));
        console2.log("team ETH", c.team.balance);
        console2.log("staking ETH", c.staking.balance);
        console2.log("hook ETH", c.hook.balance);
        console2.log("poolManager ETH", c.poolManager.balance);
        console2.log("poolManager PYRE", IERC20(c.pyreToken).balanceOf(c.poolManager));
        console2.log("totalSupply PYRE", IERC20(c.pyreToken).totalSupply());
        console2.log("buyFeeBps", FeeLogicFacet(c.hook).getCurrentBuyFeeBps());
        console2.log("sellFeeBps", FeeLogicFacet(c.hook).getCurrentSellFeeBps());
        console2.log("registeredPoolId");
        console2.logBytes32(FeeLogicFacet(c.hook).getRegisteredPoolId());
        console2.log("yieldConfig staking", stakingConfigured);
        console2.log("yieldConfig team", teamConfigured);
        console2.log("yieldConfig bps", yieldBps, teamBps);
        console2.log("totalEthToYield", toYield);
        console2.log("totalEthToTeam", toTeam);
        console2.log("totalPyreBurned", BurnFacet(c.hook).getTotalPyreBurned());
    }

    function _snapshot(Config memory c) internal view returns (Snapshot memory s) {
        (s.totalEthToYield, s.totalEthToTeam) = YieldDistributionFacet(c.hook).getTotalEthDistributed();
        s.totalPyreBurned = BurnFacet(c.hook).getTotalPyreBurned();
    }

    function _assertAccounting(Config memory c, Snapshot memory beforeState, uint256 buyFeeBps, uint256 sellFeeBps)
        internal
        view
    {
        Snapshot memory afterState = _snapshot(c);

        uint256 expectedBuyFee = (c.ethBuyAmount * buyFeeBps) / 10_000;
        uint256 expectedYield = (expectedBuyFee * 8_000) / 10_000;
        uint256 expectedTeam = expectedBuyFee - expectedYield;
        uint256 actualYield = afterState.totalEthToYield - beforeState.totalEthToYield;
        uint256 actualTeam = afterState.totalEthToTeam - beforeState.totalEthToTeam;

        console2.log("expected buy fee", expectedBuyFee);
        console2.log("actual yield delta", actualYield);
        console2.log("actual team delta", actualTeam);
        require(actualYield == expectedYield, "80 percent yield split mismatch");
        require(actualTeam == expectedTeam, "20 percent team split mismatch");

        uint256 expectedSellFee = (c.pyreSellAmount * sellFeeBps) / 10_000;
        uint256 actualBurn = afterState.totalPyreBurned - beforeState.totalPyreBurned;

        console2.log("expected PYRE burn", expectedSellFee);
        console2.log("actual PYRE burn", actualBurn);
        require(actualBurn == expectedSellFee, "sell burn mismatch");

        console2.log("accounting checks passed");
    }

    struct BalanceSnapshot {
        uint256 testerEth;
        uint256 testerPyre;
        uint256 teamEth;
        uint256 stakingEth;
        uint256 hookEth;
    }

    function _takeBalanceSnapshot(Config memory c) internal view returns (BalanceSnapshot memory s) {
        s.testerEth = c.tester.balance;
        s.testerPyre = IERC20(c.pyreToken).balanceOf(c.tester);
        s.teamEth = c.team.balance;
        s.stakingEth = c.staking.balance;
        s.hookEth = c.hook.balance;
    }

    function _logDeltas(string memory label, BalanceSnapshot memory beforeB, BalanceSnapshot memory afterB)
        internal
        pure
    {
        console2.log("  > Balance deltas (%s):", label);
        _logDelta("tester ETH", beforeB.testerEth, afterB.testerEth);
        _logDelta("tester PYRE", beforeB.testerPyre, afterB.testerPyre);
        _logDelta("team ETH", beforeB.teamEth, afterB.teamEth);
        _logDelta("staking ETH", beforeB.stakingEth, afterB.stakingEth);
        _logDelta("hook ETH", beforeB.hookEth, afterB.hookEth);
        console2.log("");
    }

    function _logDelta(string memory label, uint256 beforeAmt, uint256 afterAmt) internal pure {
        if (beforeAmt == afterAmt) {
            console2.log("    %s: no change", label);
        } else if (afterAmt > beforeAmt) {
            console2.log("    %s: +%s", label, afterAmt - beforeAmt);
        } else {
            console2.log("    %s: -%s", label, beforeAmt - afterAmt);
        }
    }
}
