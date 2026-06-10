// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice External multipliers used when computing staking yield weight.
interface IPyreWeightFactors {
    /// @dev Returns 1e18-scaled NFT stage multiplier (e.g. 3e18 for PYRE stage).
    function nftStageMultiplier(address account) external view returns (uint256);

    /// @dev Returns 1e18-scaled LP burn bonus multiplier.
    function lpBurnBonus(address account) external view returns (uint256);
}
