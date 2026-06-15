// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../v4/types/Currency.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {IPyreToken} from "../../interfaces/IPyreToken.sol";
import {LibFeeLogicStorage} from "./LibFeeLogicStorage.sol";
import {LibBurnStorage} from "./LibBurnStorage.sol";

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
        LibBurnStorage.BurnStorage storage burnStore = LibBurnStorage.burnStorage();
        IPoolManager poolManager = feeStore.poolManager;

        uint256 amount = poolManager.balanceOf(address(this), uint160(Currency.unwrap(feeStore.pyreCurrency)));
        if (amount == 0) return;

        poolManager.burn(address(this), uint160(Currency.unwrap(feeStore.pyreCurrency)), amount);
        poolManager.take(feeStore.pyreCurrency, address(this), amount);

        IPyreToken(burnStore.pyreToken).burn(amount);

        burnStore.totalPyreBurned += amount;
        emit PyreFeeBurned(amount);
    }
}
