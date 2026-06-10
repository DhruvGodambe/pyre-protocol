// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type BalanceDelta is int256;

library BalanceDeltaLibrary {
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);
}
