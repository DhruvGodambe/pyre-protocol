// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPyreStaking {
    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;

    function claimReward() external;

    function earned(address account) external view returns (uint256);

    function weightOf(address account) external view returns (uint256);

    function stakedBalanceOf(address account) external view returns (uint256);

    function totalWeight() external view returns (uint256);

    function notifyRewardAmount(uint256 amount, uint256 duration) external payable;
}
