// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "../v4/interfaces/IHooks.sol";
import {PoolKey} from "../v4/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../v4/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "../v4/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../v4/types/BeforeSwapDelta.sol";
import {LibFeeLogic} from "../libraries/LibFeeLogic.sol";
import {LibBurn} from "../libraries/LibBurn.sol";
import {LibYieldDistribution} from "../libraries/LibYieldDistribution.sol";
import {LibLpBurn} from "../libraries/LibLpBurn.sol";

/// @title SwapHookFacet
/// @notice Uniswap v4 swap hook entry points for the PYRE diamond proxy.
contract SwapHookFacet is IHooks {
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        BeforeSwapDelta delta = LibFeeLogic.processBeforeSwap(key, params);
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        LibFeeLogic.validateHookCall(key);
        LibYieldDistribution.executeBuyFee();
        LibBurn.executeSellFee();
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @notice Called by the pool manager after liquidity is removed.
    ///         If hookData encodes `true`, the LP position is treated as a burn:
    ///         the removed tokens are taken from the pool and destroyed/routed,
    ///         the sender is flagged in FireSpirit for the +20% yield bonus,
    ///         and the returned hookDelta signals that the LP receives nothing.
    ///         Without the flag, this is a no-op and the LP receives their tokens normally.
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta) {
        LibFeeLogic.validateHookCall(key);

        if (hookData.length >= 32 && abi.decode(hookData, (bool))) {
            BalanceDelta hookDelta = LibLpBurn.processLpBurn(sender, delta);
            return (IHooks.afterRemoveLiquidity.selector, hookDelta);
        }

        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}