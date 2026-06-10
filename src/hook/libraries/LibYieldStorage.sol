// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

bytes32 constant YIELD_STORAGE_POSITION = keccak256("pyre.storage.yield");

library LibYieldStorage {
    struct YieldStorage {
        address pyreStaking;
        address teamWallet;
        uint256 yieldPoolBps;
        uint256 teamBps;
        uint256 totalEthToYieldPool;
        uint256 totalEthToTeam;
    }

    function yieldStorage() internal pure returns (YieldStorage storage s) {
        bytes32 position = YIELD_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
