// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../v4/types/Currency.sol";
import {CurrencyLibrary} from "../v4/types/Currency.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {IPyreStakingYield} from "../../interfaces/IPyreStakingYield.sol";
import {LibFeeLogicStorage} from "./LibFeeLogicStorage.sol";
import {LibYieldStorage} from "./LibYieldStorage.sol";

library LibYieldDistribution {
    error YieldTransferFailed();

    event EthFeeDistributed(uint256 toYieldPool, uint256 toTeam);

    function executeBuyFee() internal {
        LibFeeLogicStorage.FeeLogicStorage storage feeStore = LibFeeLogicStorage.feeLogicStorage();
        if (!feeStore.pendingFeeActive || !feeStore.pendingFeeIsEth) return;

        uint256 amount = feeStore.pendingFeeAmount;
        feeStore.pendingFeeActive = false;
        feeStore.pendingFeeAmount = 0;

        LibYieldStorage.YieldStorage storage yieldStore = LibYieldStorage.yieldStorage();
        IPoolManager poolManager = feeStore.poolManager;

        poolManager.take(feeStore.ethCurrency, address(this), amount);

        uint256 toYield = (amount * yieldStore.yieldPoolBps) / 10_000;
        uint256 toTeam = amount - toYield;

        if (toYield > 0) {
            IPyreStakingYield(yieldStore.pyreStaking).depositYield{value: toYield}();
            yieldStore.totalEthToYieldPool += toYield;
        }

        if (toTeam > 0) {
            (bool success,) = payable(yieldStore.teamWallet).call{value: toTeam}("");
            if (!success) revert YieldTransferFailed();
            yieldStore.totalEthToTeam += toTeam;
        }

        emit EthFeeDistributed(toYield, toTeam);
    }
}
