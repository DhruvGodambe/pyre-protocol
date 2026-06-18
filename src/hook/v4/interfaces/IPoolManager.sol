// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

interface IPoolManager {
    function take(Currency currency, address to, uint256 amount) external;
    function mint(address to, uint256 id, uint256 amount) external;
    function burn(address from, uint256 id, uint256 amount) external;
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData) external returns (BalanceDelta);
    function balanceOf(address owner, uint256 id) external view returns (uint256);
}
