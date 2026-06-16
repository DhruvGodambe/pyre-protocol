// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "./Currency.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {PoolId} from "./PoolId.sol";

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

library PoolKeyLibrary {
    function toId(PoolKey memory key) internal pure returns (PoolId) {
        return _toId(
            Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), key.fee, key.tickSpacing, address(key.hooks)
        );
    }

    function toIdCalldata(PoolKey calldata key) internal pure returns (PoolId) {
        return _toId(
            Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), key.fee, key.tickSpacing, address(key.hooks)
        );
    }

    function _toId(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)
        private
        pure
        returns (PoolId)
    {
        return PoolId.wrap(keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks)));
    }
}
