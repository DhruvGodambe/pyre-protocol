// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";

/// @notice Quotes ETH->PYRE and PYRE->ETH swaps via V4Quoter.quoteExactInputSingle.
///         No broadcast — pure simulation. Run with --rpc-url and -vvv.
contract QuoteSwapTest is Script {
    // Ethereum Sepolia infrastructure
    address internal constant DEFAULT_V4_QUOTER = 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227;

    // Latest deployed addresses — override via env vars if redeployed
    address internal constant DEFAULT_PYRE_TOKEN = 0xCde4023f09E607bb01EE578197FA34a013a92e51;
    address internal constant DEFAULT_HOOK       = address(0); // set PYRE_HOOK env var

    function run() external {
        address quoter    = vm.envOr("V4_QUOTER",          DEFAULT_V4_QUOTER);
        address pyreToken = vm.envOr("PYRE_TOKEN",         DEFAULT_PYRE_TOKEN);
        address hook      = vm.envOr("PYRE_HOOK",          DEFAULT_HOOK);
        uint24  fee       = uint24(vm.envOr("PYRE_POOL_FEE",      uint256(3000)));
        int24   spacing   = int24(int256(vm.envOr("PYRE_TICK_SPACING", int256(60))));
        uint128 ethIn     = uint128(vm.envOr("QUOTE_ETH_IN",  uint256(0.01 ether)));
        uint128 pyreIn    = uint128(vm.envOr("QUOTE_PYRE_IN", uint256(100 ether)));

        require(hook != address(0), "Set PYRE_HOOK env var to your deployed hook address");

        PoolKey memory key = PoolKey({
            currency0:   Currency.wrap(address(0)),
            currency1:   Currency.wrap(pyreToken),
            fee:         fee,
            tickSpacing: spacing,
            hooks:       IHooks(hook)
        });

        console2.log("=== Pyre V4 Swap Quote Test ===");
        console2.log("quoter     :", quoter);
        console2.log("pyreToken  :", pyreToken);
        console2.log("hook       :", hook);
        console2.log("fee        :", fee);
        console2.log("tickSpacing:", spacing);
        console2.log("");

        _quoteBuy(quoter, key, ethIn);
        _quoteSell(quoter, key, pyreIn);
    }

    function _quoteBuy(address quoter, PoolKey memory key, uint128 ethIn) internal {
        console2.log("--- Buy: ETH -> PYRE ---");
        console2.log("  ETH in (wei):", ethIn);

        try IV4Quoter(quoter).quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey:     key,
                zeroForOne:  true,   // currency0 (ETH) -> currency1 (PYRE)
                exactAmount: ethIn,
                hookData:    ""
            })
        ) returns (uint256 amountOut, uint256 gasEstimate) {
            console2.log("  PYRE out (wei)  :", amountOut);
            console2.log("  gas estimate    :", gasEstimate);
            if (amountOut > 0) {
                // price = ethIn / amountOut expressed as PYRE per ETH (18 dec)
                console2.log("  implied rate    : 1 ETH = %s PYRE (scaled 1e18)", (amountOut * 1e18) / ethIn);
            }
        } catch (bytes memory reason) {
            console2.log("  FAILED - pool may have no liquidity or pool not initialized");
            console2.logBytes(reason);
        }

        console2.log("");
    }

    function _quoteSell(address quoter, PoolKey memory key, uint128 pyreIn) internal {
        console2.log("--- Sell: PYRE -> ETH ---");
        console2.log("  PYRE in (wei):", pyreIn);

        try IV4Quoter(quoter).quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey:     key,
                zeroForOne:  false,  // currency1 (PYRE) -> currency0 (ETH)
                exactAmount: pyreIn,
                hookData:    ""
            })
        ) returns (uint256 amountOut, uint256 gasEstimate) {
            console2.log("  ETH out (wei)   :", amountOut);
            console2.log("  gas estimate    :", gasEstimate);
            if (amountOut > 0) {
                console2.log("  implied rate    : 1 PYRE = %s ETH (scaled 1e18)", (amountOut * 1e18) / pyreIn);
            }
        } catch (bytes memory reason) {
            console2.log("  FAILED - pool may have no liquidity or pool not initialized");
            console2.logBytes(reason);
        }

        console2.log("");
    }
}
