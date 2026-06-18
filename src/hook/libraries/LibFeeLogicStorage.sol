// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../v4/types/Currency.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {PoolId} from "../v4/types/PoolId.sol";
import {PoolKey} from "../v4/types/PoolKey.sol";

bytes32 constant FEE_LOGIC_STORAGE_POSITION = keccak256("pyre.storage.fee.logic");

library LibFeeLogicStorage {
    struct FeeLogicStorage {
        IPoolManager poolManager;
        PoolId registeredPoolId;
        Currency pyreCurrency;
        Currency ethCurrency;
        uint256 launchTime;
        uint256 initialBuyFeeBps;
        uint256 finalBuyFeeBps;
        uint256 initialSellFeeBps;
        uint256 finalSellFeeBps;
        uint256 antiSnipeDuration;
        bool pendingFeeActive;
        bool pendingFeeIsEth;
        uint256 pendingFeeAmount;
        PoolKey poolKey;
    }

    function feeLogicStorage() internal pure returns (FeeLogicStorage storage s) {
        bytes32 position = FEE_LOGIC_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
