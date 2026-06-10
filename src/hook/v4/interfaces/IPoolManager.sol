// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";

interface IPoolManager {
    function take(Currency currency, address to, uint256 amount) external;
}
