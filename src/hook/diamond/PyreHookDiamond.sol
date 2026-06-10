// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";

/// @title PyreHookDiamond
/// @notice EIP-2535 diamond proxy for the PYRE Uniswap v4 hook. Holds ETH and all hook storage.
contract PyreHookDiamond {
    constructor(address contractOwner, IDiamondCut.FacetCut[] memory diamondCut, address init, bytes memory initData)
        payable
    {
        LibDiamond.setContractOwner(contractOwner);
        LibDiamond.diamondCut(diamondCut, init, initData);
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
