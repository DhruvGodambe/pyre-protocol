// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IBurnTracker} from "../interfaces/IBurnTracker.sol";
import {IPyreToken} from "../interfaces/IPyreToken.sol";

/// @title PyreToken
/// @notice ERC-20 with epoch decay on liquid balances, staking, and a 7-day unstake drip.
contract PyreToken is ERC20, AccessControl, IPyreToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion PYRE
    uint256 public constant INITIAL_DEPLOYER_MINT_BPS = 100; // 1% of MAX_SUPPLY

    uint256 public constant EPOCH_DURATION = 1 hours;
    uint256 public constant DRIP_DURATION = 7 days;
    uint256 public constant EPOCHS_PER_ERA = 2000;
    uint256 public constant BASE_DECAY_BPS = 45; // 0.45% per epoch (hour)
    uint256 public constant FLOOR_DECAY_BPS = 1; // 0.01% per epoch (hour)
    uint256 public constant BPS = 10_000;
    uint256 public constant WAD = 1e18;

    struct Account {
        uint256 rawLiquid;
        uint256 liquidDecayIndex;
        uint256 staked;
    }

    struct DripSchedule {
        uint128 amount;
        uint128 claimed;
        uint64 startTime;
    }

    uint256 public immutable protocolStartTime;

    address public stakingContract;
    address public burnTracker;

    uint256 private _totalSupply;
    uint256 private _decayIndex = WAD;
    uint256 private _lastDecayEpoch;

    mapping(address => Account) private _accounts;
    mapping(address => DripSchedule[]) private _drips;

    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount, uint256 dripStartTime);
    event DripClaimed(address indexed account, uint256 amount);

    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);
    error InsufficientStakedBalance(address account, uint256 available, uint256 required);
    error InsufficientBurnBalance(address account, uint256 available, uint256 required);
    error StakingContractAlreadySet();
    error BurnTrackerAlreadySet();
    error OnlyStakingContract();
    error SupplyCapExceeded(uint256 currentSupply, uint256 mintAmount, uint256 cap);

    constructor(address admin, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        protocolStartTime = block.timestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _mint(admin, (MAX_SUPPLY * INITIAL_DEPLOYER_MINT_BPS) / BPS);
    }

    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - protocolStartTime) / EPOCH_DURATION;
    }

    function decayRateBps(uint256 epoch) public pure returns (uint256) {
        uint256 era = epoch / EPOCHS_PER_ERA;
        uint256 rate = BASE_DECAY_BPS >> era;
        return rate < FLOOR_DECAY_BPS ? FLOOR_DECAY_BPS : rate;
    }

    function globalDecayIndex() external view returns (uint256) {
        return _previewDecayIndex(currentEpoch());
    }

    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return liquidBalanceOf(account) + stakedBalanceOf(account) + dripBalanceOf(account);
    }

    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return _totalSupply;
    }

    function liquidBalanceOf(address account) public view returns (uint256) {
        Account storage acc = _accounts[account];
        if (acc.rawLiquid == 0) return 0;
        uint256 index = _previewDecayIndex(currentEpoch());
        return (acc.rawLiquid * index) / acc.liquidDecayIndex;
    }

    function stakedBalanceOf(address account) public view returns (uint256) {
        return _accounts[account].staked;
    }

    function dripBalanceOf(address account) public view returns (uint256) {
        DripSchedule[] storage schedules = _drips[account];
        uint256 locked;
        uint256 len = schedules.length;
        for (uint256 i; i < len; ++i) {
            DripSchedule storage schedule = schedules[i];
            uint256 vested = _vestedAmount(schedule.amount, schedule.startTime);
            locked += uint256(schedule.amount) - vested;
        }
        return locked;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (_totalSupply + amount > MAX_SUPPLY) revert SupplyCapExceeded(_totalSupply, amount, MAX_SUPPLY);
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burnLiquid(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burnLiquid(account, amount);
    }

    function setStakingContract(address staker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (stakingContract != address(0)) revert StakingContractAlreadySet();
        stakingContract = staker;
    }

    function setBurnTracker(address tracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (burnTracker != address(0)) revert BurnTrackerAlreadySet();
        burnTracker = tracker;
    }

    function stakeFor(address account, uint256 amount) external {
        if (msg.sender != stakingContract) revert OnlyStakingContract();
        if (amount == 0) return;

        _syncDecayIndex();
        _touchLiquid(account);

        Account storage acc = _accounts[account];
        if (acc.rawLiquid < amount) {
            revert InsufficientLiquidBalance(account, acc.rawLiquid, amount);
        }

        acc.rawLiquid -= amount;
        acc.staked += amount;
        emit Staked(account, amount);
    }

    function unstakeFor(address account, uint256 amount) external {
        if (msg.sender != stakingContract) revert OnlyStakingContract();
        if (amount == 0) return;

        Account storage acc = _accounts[account];
        if (acc.staked < amount) {
            revert InsufficientStakedBalance(account, acc.staked, amount);
        }

        acc.staked -= amount;
        uint64 startTime = uint64(block.timestamp);
        _drips[account].push(DripSchedule({amount: uint128(amount), claimed: 0, startTime: startTime}));
        emit Unstaked(account, amount, startTime);
    }

    function claimDrip() external returns (uint256 claimed) {
        _syncDecayIndex();
        _touchLiquid(msg.sender);

        DripSchedule[] storage schedules = _drips[msg.sender];
        uint256 len = schedules.length;
        if (len == 0) return 0;

        Account storage acc = _accounts[msg.sender];
        uint256 write;
        for (uint256 i; i < len; ++i) {
            DripSchedule storage schedule = schedules[i];
            uint256 vested = _vestedAmount(schedule.amount, schedule.startTime);
            uint256 claimable = vested - schedule.claimed;

            if (claimable > 0) {
                schedule.claimed += uint128(claimable);
                claimed += claimable;
            }

            if (schedule.claimed < schedule.amount) {
                schedules[write] = schedule;
                ++write;
            }
        }

        while (len > write) {
            schedules.pop();
            --len;
        }

        if (claimed > 0) {
            acc.rawLiquid += claimed;
            emit DripClaimed(msg.sender, claimed);
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        if (value == 0) return;

        _syncDecayIndex();

        if (from != address(0)) {
            _touchLiquid(from);
            Account storage sender = _accounts[from];
            if (sender.rawLiquid < value) {
                revert InsufficientLiquidBalance(from, sender.rawLiquid, value);
            }
            sender.rawLiquid -= value;
        }

        if (to != address(0)) {
            _touchLiquid(to);
            _accounts[to].rawLiquid += value;
        }

        if (from == address(0)) {
            _totalSupply += value;
        } else if (to == address(0)) {
            _totalSupply -= value;
        }

        emit Transfer(from, to, value);
    }

    function _burnLiquid(address account, uint256 value) internal {
        if (value == 0) return;

        _syncDecayIndex();
        _touchLiquid(account);

        Account storage acc = _accounts[account];
        if (acc.rawLiquid < value) {
            revert InsufficientBurnBalance(account, acc.rawLiquid, value);
        }

        acc.rawLiquid -= value;
        _totalSupply -= value;
        emit Transfer(account, address(0), value);

        if (burnTracker != address(0)) {
            IBurnTracker(burnTracker).onPyreBurn(account, value);
        }
    }

    function _touchLiquid(address account) internal {
        Account storage acc = _accounts[account];
        if (acc.rawLiquid == 0) {
            acc.liquidDecayIndex = _decayIndex;
            return;
        }

        if (acc.liquidDecayIndex == 0) {
            acc.liquidDecayIndex = _decayIndex;
            return;
        }

        acc.rawLiquid = (acc.rawLiquid * _decayIndex) / acc.liquidDecayIndex;
        acc.liquidDecayIndex = _decayIndex;
    }

    function _syncDecayIndex() internal {
        uint256 epoch = currentEpoch();
        uint256 last = _lastDecayEpoch;
        if (epoch <= last) return;

        uint256 index = _decayIndex;
        uint256 cursor = last;

        while (cursor < epoch) {
            uint256 era = cursor / EPOCHS_PER_ERA;
            uint256 eraEnd = (era + 1) * EPOCHS_PER_ERA;
            uint256 end = epoch < eraEnd ? epoch : eraEnd;
            uint256 epochs = end - cursor;
            uint256 rate = decayRateBps(cursor);
            index = (index * _rpow(BPS - rate, epochs, BPS)) / BPS;
            cursor = end;
        }

        _decayIndex = index;
        _lastDecayEpoch = epoch;
    }

    function _previewDecayIndex(uint256 epoch) internal view returns (uint256) {
        uint256 last = _lastDecayEpoch;
        if (epoch <= last) return _decayIndex;

        uint256 index = _decayIndex;
        uint256 cursor = last;

        while (cursor < epoch) {
            uint256 era = cursor / EPOCHS_PER_ERA;
            uint256 eraEnd = (era + 1) * EPOCHS_PER_ERA;
            uint256 end = epoch < eraEnd ? epoch : eraEnd;
            uint256 epochs = end - cursor;
            uint256 rate = decayRateBps(cursor);
            index = (index * _rpow(BPS - rate, epochs, BPS)) / BPS;
            cursor = end;
        }

        return index;
    }

    function _vestedAmount(uint256 amount, uint64 startTime) internal view returns (uint256) {
        if (amount == 0) return 0;
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= DRIP_DURATION) return amount;
        return (amount * elapsed) / DRIP_DURATION;
    }

    /// @dev Fixed-point exponentiation used for per-epoch decay compounding.
    function _rpow(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2)
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}
