// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IImmolatedGate {
    function immolate() external;

    function isImmolated(address account) external view returns (bool);

    function immolatedCount() external view returns (uint256);
}
