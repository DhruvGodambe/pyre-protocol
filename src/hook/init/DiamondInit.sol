// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibFeeLogicStorage} from "../libraries/LibFeeLogicStorage.sol";
import {LibBurnStorage} from "../libraries/LibBurnStorage.sol";
import {LibYieldStorage} from "../libraries/LibYieldStorage.sol";

struct PyreHookInitParams {
    address pyreToken;
    address pyreStaking;
    address teamWallet;
}

/// @title DiamondInit
/// @notice Initializes EIP-7201 namespaced storage on first diamond cut.
contract DiamondInit {
    function init(PyreHookInitParams calldata params) external {
        LibFeeLogicStorage.FeeLogicStorage storage feeStore = LibFeeLogicStorage.feeLogicStorage();
        feeStore.initialBuyFeeBps = 1000;
        feeStore.finalBuyFeeBps = 500;
        feeStore.initialSellFeeBps = 2300;
        feeStore.finalSellFeeBps = 500;
        feeStore.antiSnipeDuration = 2 hours;

        LibBurnStorage.burnStorage().pyreToken = params.pyreToken;

        LibYieldStorage.YieldStorage storage yieldStore = LibYieldStorage.yieldStorage();
        yieldStore.pyreStaking = params.pyreStaking;
        yieldStore.teamWallet = params.teamWallet;
        yieldStore.yieldPoolBps = 0;
        yieldStore.teamBps = 10000;
    }
}
