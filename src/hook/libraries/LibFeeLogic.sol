// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../v4/types/PoolKey.sol";
import {PoolKeyLibrary} from "../v4/types/PoolKey.sol";
import {PoolId} from "../v4/types/PoolId.sol";
import {SwapParams} from "../v4/types/PoolOperation.sol";
import {Currency} from "../v4/types/Currency.sol";
import {CurrencyLibrary} from "../v4/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../v4/types/BeforeSwapDelta.sol";
import {LibFeeLogicStorage} from "./LibFeeLogicStorage.sol";

library LibFeeLogic {
    using PoolKeyLibrary for PoolKey;

    error OnlyPoolManager();
    error InvalidPool();
    error InvalidHookAddress();

    event SwapFeeCollected(bool indexed isBuy, bool indexed isEthFee, uint256 feeAmount);

    function validateHookCall(PoolKey calldata key) internal view {
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();
        if (msg.sender != address(s.poolManager)) revert OnlyPoolManager();
        if (PoolId.unwrap(PoolKeyLibrary.toIdCalldata(key)) != PoolId.unwrap(s.registeredPoolId)) {
            revert InvalidPool();
        }
        if (address(key.hooks) != address(this)) revert InvalidPool();
    }

    function currentBuyFeeBps() internal view returns (uint256) {
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();
        return _currentFee(s.launchTime, s.antiSnipeDuration, s.initialBuyFeeBps, s.finalBuyFeeBps);
    }

    function currentSellFeeBps() internal view returns (uint256) {
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();
        return _currentFee(s.launchTime, s.antiSnipeDuration, s.initialSellFeeBps, s.finalSellFeeBps);
    }

    function processBeforeSwap(PoolKey calldata key, SwapParams calldata params) internal returns (BeforeSwapDelta) {
        validateHookCall(key);
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();

        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        bool isBuyPyre = Currency.unwrap(inputCurrency) == Currency.unwrap(s.ethCurrency);
        bool isSellPyre = Currency.unwrap(inputCurrency) == Currency.unwrap(s.pyreCurrency);

        if (!isBuyPyre && !isSellPyre) {
            return BeforeSwapDelta.wrap(0);
        }

        uint256 inputAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint256 feeBps = isBuyPyre ? currentBuyFeeBps() : currentSellFeeBps();
        uint256 feeAmount = (inputAmount * feeBps) / 10_000;

        if (feeAmount == 0) {
            s.pendingFeeActive = false;
            return BeforeSwapDelta.wrap(0);
        }

        s.pendingFeeActive = true;
        s.pendingFeeIsEth = isBuyPyre;
        s.pendingFeeAmount = feeAmount;

        emit SwapFeeCollected(isBuyPyre, isBuyPyre, feeAmount);

        return toBeforeSwapDelta(int128(int256(feeAmount)), 0);
    }

    function _currentFee(uint256 launchTime, uint256 duration, uint256 initialBps, uint256 finalBps)
        private
        view
        returns (uint256)
    {
        if (duration == 0 || block.timestamp >= launchTime + duration) return finalBps;
        uint256 elapsed = block.timestamp - launchTime;
        if (initialBps <= finalBps) return finalBps;
        return initialBps - ((initialBps - finalBps) * elapsed) / duration;
    }
}
