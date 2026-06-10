// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {LibBurnStorage} from "../libraries/LibBurnStorage.sol";

/// @title BurnFacet
/// @notice Sell-side $PYRE fee burn configuration and accounting.
contract BurnFacet {
    event PyreTokenConfigured(address indexed pyreToken);

    function configurePyreToken(address pyreToken_) external {
        LibDiamond.enforceIsContractOwner();
        LibBurnStorage.burnStorage().pyreToken = pyreToken_;
        emit PyreTokenConfigured(pyreToken_);
    }

    function getPyreToken() external view returns (address) {
        return LibBurnStorage.burnStorage().pyreToken;
    }

    function getTotalPyreBurned() external view returns (uint256) {
        return LibBurnStorage.burnStorage().totalPyreBurned;
    }
}
