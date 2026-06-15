// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "../../src/hook/v4/interfaces/IPoolManager.sol";
import {Currency} from "../../src/hook/v4/types/Currency.sol";
import {CurrencyLibrary} from "../../src/hook/v4/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPoolManager is IPoolManager {
    using CurrencyLibrary for Currency;

    function deposit(Currency currency, uint256 amount) external payable {
        if (Currency.unwrap(currency) == address(0)) {
            require(msg.value == amount);
        } else {
            IERC20(Currency.unwrap(currency)).transferFrom(msg.sender, address(this), amount);
        }
    }

    function take(Currency currency, address to, uint256 amount) external {
        if (Currency.unwrap(currency) == address(0)) {
            (bool success,) = payable(to).call{value: amount}("");
            require(success);
        } else {
            IERC20(Currency.unwrap(currency)).transfer(to, amount);
        }
    }

    function mint(address to, uint256 id, uint256 amount) external {}
    function burn(address from, uint256 id, uint256 amount) external {}
    function balanceOf(address owner, uint256 id) external view returns (uint256) { return 0; }
    function unlock(bytes calldata data) external returns (bytes memory) { return new bytes(0); }

    receive() external payable {}
}
