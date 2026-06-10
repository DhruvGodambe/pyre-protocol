// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPyreToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function stakingContract() external view returns (address);

    function burnTracker() external view returns (address);

    function stakeFor(address account, uint256 amount) external;

    function unstakeFor(address account, uint256 amount) external;

    function claimDrip() external returns (uint256 claimed);

    function liquidBalanceOf(address account) external view returns (uint256);

    function stakedBalanceOf(address account) external view returns (uint256);

    function dripBalanceOf(address account) external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function decayRateBps(uint256 epoch) external pure returns (uint256);

    function globalDecayIndex() external view returns (uint256);

    function protocolStartTime() external view returns (uint256);
}
