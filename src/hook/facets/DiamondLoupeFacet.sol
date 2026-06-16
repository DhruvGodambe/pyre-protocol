// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondLoupe} from "../diamond/interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";

contract DiamondLoupeFacet is IDiamondLoupe {
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.selectors.length;
        facets_ = new Facet[](numFacets);
        for (uint256 i; i < numFacets; i++) {
            bytes4 selector = ds.selectors[i];
            address facet = ds.selectorToFacetAndPosition[selector].facetAddress;
            facets_[i].facetAddress = facet;
            facets_[i].functionSelectors = new bytes4[](1);
            facets_[i].functionSelectors[0] = selector;
        }
    }

    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory selectors) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 count;
        for (uint256 i; i < ds.selectors.length; i++) {
            if (ds.selectorToFacetAndPosition[ds.selectors[i]].facetAddress == _facet) count++;
        }
        selectors = new bytes4[](count);
        uint256 index;
        for (uint256 i; i < ds.selectors.length; i++) {
            if (ds.selectorToFacetAndPosition[ds.selectors[i]].facetAddress == _facet) {
                selectors[index] = ds.selectors[i];
                index++;
            }
        }
    }

    function facetAddresses() external view override returns (address[] memory addresses) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        addresses = new address[](ds.selectors.length);
        for (uint256 i; i < ds.selectors.length; i++) {
            addresses[i] = ds.selectorToFacetAndPosition[ds.selectors[i]].facetAddress;
        }
    }

    function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {
        facetAddress_ = LibDiamond.diamondStorage().selectorToFacetAndPosition[_functionSelector].facetAddress;
    }
}
