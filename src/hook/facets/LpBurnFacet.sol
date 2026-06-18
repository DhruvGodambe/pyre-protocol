// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {LibLpBurnStorage} from "../libraries/LibLpBurnStorage.sol";
import {IFireSpirit} from "../../interfaces/IFireSpirit.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";

// Interfaces and types from v4
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionInfo} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title LpBurnFacet
/// @notice Admin configuration and LP position burn feature.
contract LpBurnFacet {
    event FireSpiritConfigured(address indexed fireSpirit);
    event PositionManagerConfigured(address indexed positionManager);
    event LpPositionBurned(address indexed burner, uint256 indexed tokenId);

    /// @notice Set the FireSpirit contract address so the hook can flag LP burners.
    function configureFireSpirit(address fireSpirit_) external {
        LibDiamond.enforceIsContractOwner();
        LibLpBurnStorage.lpBurnStorage().fireSpirit = fireSpirit_;
        emit FireSpiritConfigured(fireSpirit_);
    }

    /// @notice Set the V4 PositionManager address.
    function configurePositionManager(address positionManager_) external {
        LibDiamond.enforceIsContractOwner();
        LibLpBurnStorage.lpBurnStorage().positionManager = positionManager_;
        emit PositionManagerConfigured(positionManager_);
    }

    function getFireSpirit() external view returns (address) {
        return LibLpBurnStorage.lpBurnStorage().fireSpirit;
    }

    function getPositionManager() external view returns (address) {
        return LibLpBurnStorage.lpBurnStorage().positionManager;
    }

    /// @notice Burns a Uniswap V4 LP position to receive a staking multiplier.
    /// @param tokenId The V4 position NFT token ID.
    function burnLpPosition(uint256 tokenId) external {
        address positionManager = LibLpBurnStorage.lpBurnStorage().positionManager;
        address fireSpirit = LibLpBurnStorage.lpBurnStorage().fireSpirit;

        require(positionManager != address(0), "PositionManager not configured");
        require(fireSpirit != address(0), "FireSpirit not configured");

        // 1. Get position info to verify it's our pool
        (PoolKey memory key,) = IPositionManager(positionManager).getPoolAndPositionInfo(tokenId);

        // 2. Verify it belongs to this hook (Pyre Pool)
        require(address(key.hooks) == address(this), "Not a Pyre LP token");

        // 3. Transfer the NFT to the dead address to lock it permanently
        //    (User must have approved the hook to transfer their token)
        IERC721(positionManager).transferFrom(msg.sender, address(0x000000000000000000000000000000000000dEaD), tokenId);

        // 4. Update FireSpirit to flag the LP burner
        IFireSpirit(fireSpirit).flagLpBurner(msg.sender);

        // 5. Accounting
        LibLpBurnStorage.lpBurnStorage().totalLpPositionBurns += 1;
        emit LpPositionBurned(msg.sender, tokenId);
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
