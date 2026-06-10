// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPyreWeightFactors} from "../interfaces/IPyreWeightFactors.sol";

contract MockPyreWeightFactors is IPyreWeightFactors {
    uint256 public constant WAD = 1e18;

    mapping(address => uint256) public nftMultipliers;
    mapping(address => uint256) public lpBonuses;

    function setNftStageMultiplier(address account, uint256 multiplier) external {
        nftMultipliers[account] = multiplier;
    }

    function setLpBurnBonus(address account, uint256 bonus) external {
        lpBonuses[account] = bonus;
    }

    function nftStageMultiplier(address account) external view returns (uint256) {
        uint256 multiplier = nftMultipliers[account];
        return multiplier == 0 ? WAD : multiplier;
    }

    function lpBurnBonus(address account) external view returns (uint256) {
        uint256 bonus = lpBonuses[account];
        return bonus == 0 ? WAD : bonus;
    }
}
