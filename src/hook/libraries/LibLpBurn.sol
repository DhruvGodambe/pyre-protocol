// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../v4/types/BalanceDelta.sol";
import {IPoolManager} from "../v4/interfaces/IPoolManager.sol";
import {Currency} from "../v4/types/Currency.sol";
import {IPyreToken} from "../../interfaces/IPyreToken.sol";
import {IPyreStakingYield} from "../../interfaces/IPyreStakingYield.sol";
import {IFireSpiritLpRecorder} from "../../interfaces/IFireSpiritLpRecorder.sol";
import {LibFeeLogicStorage} from "./LibFeeLogicStorage.sol";
import {LibBurnStorage} from "./LibBurnStorage.sol";
import {LibYieldStorage} from "./LibYieldStorage.sol";
import {LibLpBurnStorage} from "./LibLpBurnStorage.sol";

library LibLpBurn {
    using BalanceDeltaLibrary for BalanceDelta;

    error LpBurnEthRouteFailed();

    event LpPositionBurned(address indexed sender, uint256 ethAmount, uint256 pyreAmount);

    /// @notice Processes an optional LP position burn triggered from afterRemoveLiquidity.
    /// @dev Takes the removed liquidity from the pool manager, burns PYRE, routes ETH,
    ///      and flags the sender in FireSpirit for the +20% yield bonus.
    ///      Returns hookDelta = negated delta so the LP receives nothing.
    function processLpBurn(address sender, BalanceDelta delta) internal returns (BalanceDelta hookDelta) {
        LibFeeLogicStorage.FeeLogicStorage storage feeStore = LibFeeLogicStorage.feeLogicStorage();
        LibLpBurnStorage.LpBurnStorage storage s = LibLpBurnStorage.lpBurnStorage();
        LibYieldStorage.YieldStorage storage yieldStore = LibYieldStorage.yieldStorage();
        LibBurnStorage.BurnStorage storage burnStore = LibBurnStorage.burnStorage();

        IPoolManager poolManager = feeStore.poolManager;

        // currency0 = ETH, currency1 = PYRE (as configured in configurePool)
        int128 ethDelta = delta.amount0();
        int128 pyreDelta = delta.amount1();

        uint256 ethAmount = ethDelta > 0 ? uint256(uint128(ethDelta)) : 0;
        uint256 pyreAmount = pyreDelta > 0 ? uint256(uint128(pyreDelta)) : 0;

        // Take PYRE from pool, burn it permanently
        if (pyreAmount > 0) {
            poolManager.take(feeStore.pyreCurrency, address(this), pyreAmount);
            IPyreToken(burnStore.pyreToken).burn(pyreAmount);
            s.totalPyreBurnedFromLp += pyreAmount;
        }

        // Take ETH from pool, route identically to buy-side fees (80/20 split)
        if (ethAmount > 0) {
            poolManager.take(feeStore.ethCurrency, address(this), ethAmount);

            uint256 toYield = (ethAmount * yieldStore.yieldPoolBps) / 10_000;
            uint256 toTeam = ethAmount - toYield;

            if (toYield > 0) {
                IPyreStakingYield(yieldStore.pyreStaking).depositYield{value: toYield}();
            }
            if (toTeam > 0) {
                (bool ok,) = payable(yieldStore.teamWallet).call{value: toTeam}("");
                if (!ok) revert LpBurnEthRouteFailed();
            }
            s.totalEthRoutedFromLp += ethAmount;
        }

        // Flag the LP in FireSpirit → grants +20% yield weight bonus
        if (s.fireSpirit != address(0)) {
            IFireSpiritLpRecorder(s.fireSpirit).flagLpBurner(sender);
        }

        s.totalLpPositionBurns++;

        emit LpPositionBurned(sender, ethAmount, pyreAmount);

        // Hook claims the full removal delta so the LP receives nothing
        hookDelta = toBalanceDelta(-ethDelta, -pyreDelta);
    }
}
