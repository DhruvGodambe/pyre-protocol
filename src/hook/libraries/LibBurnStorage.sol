// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

bytes32 constant BURN_STORAGE_POSITION = keccak256("pyre.storage.burn");

library LibBurnStorage {
    struct BurnStorage {
        address pyreToken;
        uint256 totalPyreBurned;
    }

    function burnStorage() internal pure returns (BurnStorage storage s) {
        bytes32 position = BURN_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
