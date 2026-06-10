// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBurnTracker {
    function onPyreBurn(address account, uint256 amount) external;
}
