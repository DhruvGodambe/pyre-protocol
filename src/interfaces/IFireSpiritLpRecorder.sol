// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for the hook to flag an address as an LP burner in FireSpirit.
interface IFireSpiritLpRecorder {
    function flagLpBurner(address wallet) external;
}
