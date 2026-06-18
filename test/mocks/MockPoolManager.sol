// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "../../src/hook/v4/interfaces/IPoolManager.sol";
import {Currency} from "../../src/hook/v4/types/Currency.sol";
import {CurrencyLibrary} from "../../src/hook/v4/types/Currency.sol";
import {PoolKey} from "../../src/hook/v4/types/PoolKey.sol";
import {SwapParams} from "../../src/hook/v4/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/hook/v4/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPoolManager is IPoolManager {
    using CurrencyLibrary for Currency;

    // ERC-1155-style claim ticket balances used by executeBuyFee / executeSellFee
    mapping(address => mapping(uint256 => uint256)) private _balances;

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

    function mint(address to, uint256 id, uint256 amount) external {
        _balances[to][id] += amount;
    }

    function burn(address from, uint256 id, uint256 amount) external {
        _balances[from][id] -= amount;
    }

    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return _balances[owner][id];
    }

    /// @dev Simulates V4's unlock: forwards to the caller's unlockCallback so that
    ///      extractAndDistributeBuyFee / extractAndDistributeSellFee actually run.
    function unlock(bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = msg.sender.call(abi.encodeWithSignature("unlockCallback(bytes)", data));
        require(success, "unlockCallback failed");
        return result;
    }

    function swap(
        PoolKey memory,
        /*key*/
        SwapParams memory params,
        bytes calldata /*hookData*/
    )
        external
        returns (BalanceDelta)
    {
        int256 input = params.amountSpecified;
        int128 inputDelta = int128(input); // negative: caller owes manager
        int128 outputDelta = int128(-input); // positive: manager owes caller
        if (params.zeroForOne) {
            return toBalanceDelta(inputDelta, outputDelta);
        } else {
            return toBalanceDelta(outputDelta, inputDelta);
        }
    }

    receive() external payable {}
}
