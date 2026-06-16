// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {LibLpBurnStorage} from "../libraries/LibLpBurnStorage.sol";

/// @title LpBurnFacet
/// @notice Admin configuration and accounting views for the optional LP position burn feature.
contract LpBurnFacet {
    event FireSpiritConfigured(address indexed fireSpirit);

    /// @notice Set the FireSpirit contract address so the hook can flag LP burners.
    ///         The hook must have LP_RECORDER_ROLE granted in FireSpirit before this is useful.
    function configureFireSpirit(address fireSpirit_) external {
        LibDiamond.enforceIsContractOwner();
        LibLpBurnStorage.lpBurnStorage().fireSpirit = fireSpirit_;
        emit FireSpiritConfigured(fireSpirit_);
    }

    function getFireSpirit() external view returns (address) {
        return LibLpBurnStorage.lpBurnStorage().fireSpirit;
    }

    function getTotalLpBurns() external view returns (uint256) {
        return LibLpBurnStorage.lpBurnStorage().totalLpPositionBurns;
    }

    function getTotalPyreBurnedFromLp() external view returns (uint256) {
        return LibLpBurnStorage.lpBurnStorage().totalPyreBurnedFromLp;
    }

    function getTotalEthRoutedFromLp() external view returns (uint256) {
        return LibLpBurnStorage.lpBurnStorage().totalEthRoutedFromLp;
    }
}
