// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type BalanceDelta is int256;

function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta result) {
    assembly ("memory-safe") {
        result := or(shl(128, _amount0), and(_amount1, 0xffffffffffffffffffffffffffffffff))
    }
}

library BalanceDeltaLibrary {
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);

    function amount0(BalanceDelta delta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, delta)
        }
    }

    function amount1(BalanceDelta delta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, delta)
        }
    }
}
