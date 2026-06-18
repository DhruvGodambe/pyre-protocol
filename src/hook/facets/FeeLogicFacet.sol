// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {LibFeeLogic} from "../libraries/LibFeeLogic.sol";
import {LibFeeLogicStorage} from "../libraries/LibFeeLogicStorage.sol";
import {PoolKey} from "../v4/types/PoolKey.sol";
import {PoolKeyLibrary} from "../v4/types/PoolKey.sol";
import {PoolId} from "../v4/types/PoolId.sol";
import {Currency} from "../v4/types/Currency.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {LibYieldDistribution} from "../libraries/LibYieldDistribution.sol";
import {LibBurn} from "../libraries/LibBurn.sol";

/// @title FeeLogicFacet
/// @notice Fee schedule configuration and views for the PYRE hook diamond.
contract FeeLogicFacet is IUnlockCallback {
    using PoolKeyLibrary for PoolKey;

    uint256 public constant DEFAULT_INITIAL_BUY_FEE_BPS = 1000;
    uint256 public constant DEFAULT_FINAL_BUY_FEE_BPS = 500;
    uint256 public constant DEFAULT_INITIAL_SELL_FEE_BPS = 2300;
    uint256 public constant DEFAULT_FINAL_SELL_FEE_BPS = 500;
    uint256 public constant DEFAULT_ANTI_SNIPE_DURATION = 12 hours;

    event PoolRegistered(bytes32 indexed poolId, address poolManager);
    event AntiSnipeConfigUpdated(
        uint256 initialBuyFeeBps,
        uint256 finalBuyFeeBps,
        uint256 initialSellFeeBps,
        uint256 finalSellFeeBps,
        uint256 antiSnipeDuration
    );

    function configurePool(
        address poolManager_,
        PoolKey calldata key,
        Currency pyreCurrency_,
        Currency ethCurrency_,
        uint256 launchTime_
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();
        s.poolManager = IPoolManager(poolManager_);
        s.registeredPoolId = PoolKeyLibrary.toIdCalldata(key);
        s.poolKey = key;
        s.pyreCurrency = pyreCurrency_;
        s.ethCurrency = ethCurrency_;
        s.launchTime = launchTime_;
        emit PoolRegistered(bytes32(PoolId.unwrap(PoolKeyLibrary.toId(key))), poolManager_);
    }

    function configureAntiSnipe(
        uint256 initialBuyFeeBps,
        uint256 finalBuyFeeBps,
        uint256 initialSellFeeBps,
        uint256 finalSellFeeBps,
        uint256 antiSnipeDuration
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibFeeLogicStorage.FeeLogicStorage storage s = LibFeeLogicStorage.feeLogicStorage();
        s.initialBuyFeeBps = initialBuyFeeBps;
        s.finalBuyFeeBps = finalBuyFeeBps;
        s.initialSellFeeBps = initialSellFeeBps;
        s.finalSellFeeBps = finalSellFeeBps;
        s.antiSnipeDuration = antiSnipeDuration;
        emit AntiSnipeConfigUpdated(
            initialBuyFeeBps, finalBuyFeeBps, initialSellFeeBps, finalSellFeeBps, antiSnipeDuration
        );
    }

    function getCurrentBuyFeeBps() external view returns (uint256) {
        return LibFeeLogic.currentBuyFeeBps();
    }

    function getCurrentSellFeeBps() external view returns (uint256) {
        return LibFeeLogic.currentSellFeeBps();
    }

    function getRegisteredPoolId() external view returns (bytes32) {
        return PoolId.unwrap(LibFeeLogicStorage.feeLogicStorage().registeredPoolId);
    }

    function claimFees(bool isBuyPyre) external {
        LibFeeLogicStorage.feeLogicStorage().poolManager.unlock(abi.encode(isBuyPyre));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(LibFeeLogicStorage.feeLogicStorage().poolManager), "Not poolManager");
        bool isBuyPyre = abi.decode(data, (bool));
        if (isBuyPyre) {
            LibYieldDistribution.extractAndDistributeBuyFee();
        } else {
            LibBurn.extractAndDistributeSellFee();
        }
        return "";
    }
}
