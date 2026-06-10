// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPyreStakingHooks {
    /// @notice Settles pending rewards and refreshes staking weight after multiplier changes.
    function onWeightFactorsChanged(address account) external;
}
