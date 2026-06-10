// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type PoolId is bytes32;

library PoolIdLibrary {
    function unwrap(PoolId id) internal pure returns (bytes32) {
        return PoolId.unwrap(id);
    }
}
