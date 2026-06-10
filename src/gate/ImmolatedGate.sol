// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPyreToken} from "../interfaces/IPyreToken.sol";
import {IFireSpirit} from "../interfaces/IFireSpirit.sol";
import {IImmolatedGate} from "../interfaces/IImmolatedGate.sol";

/// @title ImmolatedGate
/// @notice Entry to the Hall of the Immolated — requires a PYRE-stage FireSpirit and an extra $PYRE burn.
contract ImmolatedGate is IImmolatedGate, ReentrancyGuard {
    uint256 public constant ADDITIONAL_BURN = 10_000 ether;

    IPyreToken public immutable pyreToken;
    IFireSpirit public immutable fireSpirit;

    uint256 public immolatedCount;

    mapping(address => bool) public isImmolated;

    event Immolated(address indexed account, uint256 burnAmount);

    error AlreadyImmolated(address account);
    error RequiresPyreSpirit(address account);
    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);

    constructor(address pyreToken_, address fireSpirit_) {
        pyreToken = IPyreToken(pyreToken_);
        fireSpirit = IFireSpirit(fireSpirit_);
    }

    function immolate() external nonReentrant {
        address account = msg.sender;
        if (isImmolated[account]) revert AlreadyImmolated(account);

        _requirePyreSpirit(account);

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

    function _requirePyreSpirit(address account) internal view {
        if (fireSpirit.walletToTokenId(account) == 0) {
            revert RequiresPyreSpirit(account);
        }
        if (fireSpirit.stageOf(account) != IFireSpirit.Stage.PYRE) {
            revert RequiresPyreSpirit(account);
        }
    }
}
