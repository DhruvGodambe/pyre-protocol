// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

bytes32 constant LP_BURN_STORAGE_POSITION = keccak256("pyre.storage.lp.burn");

library LibLpBurnStorage {
    struct LpBurnStorage {
        address acolyte;
        address positionManager;
        uint256 totalLpPositionBurns;
    }

    function lpBurnStorage() internal pure returns (LpBurnStorage storage s) {
        bytes32 position = LP_BURN_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
