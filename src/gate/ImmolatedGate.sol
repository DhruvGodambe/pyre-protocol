// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPyreToken} from "../interfaces/IPyreToken.sol";
import {IAcolyte} from "../interfaces/IAcolyte.sol";
import {IImmolatedGate} from "../interfaces/IImmolatedGate.sol";

/// @title ImmolatedGate
/// @notice Entry to the Hall of the Immolated — requires a PYRE-stage Acolyte and an extra $PYRE burn.
contract ImmolatedGate is IImmolatedGate, ReentrancyGuard {
    uint256 public constant ADDITIONAL_BURN = 10_000 ether;

    IPyreToken public immutable pyreToken;
    IAcolyte public immutable acolyte;

    uint256 public immolatedCount;

    mapping(address => bool) public isImmolated;

    event Immolated(address indexed account, uint256 burnAmount);

    error AlreadyImmolated(address account);
    error RequiresPyreAcolyte(address account);
    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);

    constructor(address pyreToken_, address acolyte_) {
        pyreToken = IPyreToken(pyreToken_);
        acolyte = IAcolyte(acolyte_);
    }

    function immolate() external nonReentrant {
        address account = msg.sender;
        if (isImmolated[account]) revert AlreadyImmolated(account);

        _requirePyreAcolyte(account);

        uint256 liquid = pyreToken.liquidBalanceOf(account);
        if (liquid < ADDITIONAL_BURN) {
            revert InsufficientLiquidBalance(account, liquid, ADDITIONAL_BURN);
        }

        pyreToken.burnFrom(account, ADDITIONAL_BURN);

        isImmolated[account] = true;
        unchecked {
            ++immolatedCount;
        }

        emit Immolated(account, ADDITIONAL_BURN);
    }

    function _requirePyreAcolyte(address account) internal view {
        if (acolyte.walletToTokenId(account) == 0) {
            revert RequiresPyreAcolyte(account);
        }
        if (acolyte.stageOf(account) != IAcolyte.Stage.PYRE) {
            revert RequiresPyreAcolyte(account);
        }
    }
}
