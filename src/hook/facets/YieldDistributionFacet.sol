// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {LibYieldStorage} from "../libraries/LibYieldStorage.sol";

/// @title YieldDistributionFacet
/// @notice Buy-side ETH fee routing: 80% yield pool, 20% team wallet.
contract YieldDistributionFacet {
    error InvalidSplit();

    uint256 public constant DEFAULT_YIELD_POOL_BPS = 8000;
    uint256 public constant DEFAULT_TEAM_BPS = 2000;

    event YieldConfigUpdated(address pyreStaking, address teamWallet, uint256 yieldPoolBps, uint256 teamBps);

    function configureYieldDistribution(address pyreStaking_, address teamWallet_, uint256 yieldPoolBps, uint256 teamBps)
        external
    {
        LibDiamond.enforceIsContractOwner();
        if (yieldPoolBps + teamBps != 10_000) revert InvalidSplit();
        LibYieldStorage.YieldStorage storage s = LibYieldStorage.yieldStorage();
        s.pyreStaking = pyreStaking_;
        s.teamWallet = teamWallet_;
        s.yieldPoolBps = yieldPoolBps;
        s.teamBps = teamBps;
        emit YieldConfigUpdated(pyreStaking_, teamWallet_, yieldPoolBps, teamBps);
    }

    function getYieldConfig()
        external
        view
        returns (address pyreStaking, address teamWallet, uint256 yieldPoolBps, uint256 teamBps)
    {
        LibYieldStorage.YieldStorage storage s = LibYieldStorage.yieldStorage();
        return (s.pyreStaking, s.teamWallet, s.yieldPoolBps, s.teamBps);
    }

    function getTotalEthDistributed() external view returns (uint256 toYieldPool, uint256 toTeam) {
        LibYieldStorage.YieldStorage storage s = LibYieldStorage.yieldStorage();
        return (s.totalEthToYieldPool, s.totalEthToTeam);
    }
}
