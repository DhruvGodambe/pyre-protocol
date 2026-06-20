// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../v4/types/Currency.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {IPyreToken} from "../../interfaces/IPyreToken.sol";
import {LibFeeLogicStorage} from "./LibFeeLogicStorage.sol";
import {LibBurnStorage} from "./LibBurnStorage.sol";
import {LibYieldStorage} from "./LibYieldStorage.sol";
import {IPyreStakingYield} from "../../interfaces/IPyreStakingYield.sol";
import {LibYieldDistribution} from "./LibYieldDistribution.sol";
import {PoolKey} from "../v4/types/PoolKey.sol";
import {SwapParams} from "../v4/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../v4/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

library LibBurn {
    using CurrencyLibrary for Currency;
    error BurnFailed();

    event PyreFeeBurned(uint256 amount);

    function executeSellFee() internal {
        LibFeeLogicStorage.FeeLogicStorage storage feeStore = LibFeeLogicStorage.feeLogicStorage();
        if (!feeStore.pendingFeeActive || feeStore.pendingFeeIsEth) return;

        uint256 amount = feeStore.pendingFeeAmount;
        feeStore.pendingFeeActive = false;
        feeStore.pendingFeeAmount = 0;

        LibBurnStorage.BurnStorage storage burnStore = LibBurnStorage.burnStorage();
        IPoolManager poolManager = feeStore.poolManager;

        poolManager.mint(address(this), uint160(Currency.unwrap(feeStore.pyreCurrency)), amount);
    }

    function extractAndDistributeSellFee() internal {
        LibFeeLogicStorage.FeeLogicStorage storage feeStore = LibFeeLogicStorage.feeLogicStorage();
        LibYieldStorage.YieldStorage storage yieldStore = LibYieldStorage.yieldStorage();
        IPoolManager poolManager = feeStore.poolManager;

        uint256 amountToSwap = poolManager.balanceOf(address(this), uint160(Currency.unwrap(feeStore.pyreCurrency)));
        if (amountToSwap == 0) return;

        PoolKey memory key = feeStore.poolKey;
        bool zeroForOne = Currency.unwrap(key.currency0) == Currency.unwrap(feeStore.pyreCurrency);

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountToSwap),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            abi.encode(true)
        );

        poolManager.burn(address(this), uint160(Currency.unwrap(feeStore.pyreCurrency)), amountToSwap);

        int128 ethDelta = zeroForOne ? BalanceDeltaLibrary.amount1(delta) : BalanceDeltaLibrary.amount0(delta);
        uint256 ethReceived = uint256(int256(ethDelta));

        poolManager.take(feeStore.ethCurrency, address(this), ethReceived);

        uint256 toYield = (ethReceived * yieldStore.yieldPoolBps) / 10_000;
        uint256 toTeam = ethReceived - toYield;

        if (toYield > 0) {
            IPyreStakingYield(yieldStore.pyreStaking).depositYield{value: toYield}();
            yieldStore.totalEthToYieldPool += toYield;
        }

        if (toTeam > 0) {
            (bool success,) = payable(yieldStore.teamWallet).call{value: toTeam}("");
            if (!success) revert LibYieldDistribution.YieldTransferFailed();
            yieldStore.totalEthToTeam += toTeam;
        }

        emit LibYieldDistribution.EthFeeDistributed(toYield, toTeam);
    }
}
