// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPyreToken} from "../interfaces/IPyreToken.sol";
import {IPyreWeightFactors} from "../interfaces/IPyreWeightFactors.sol";
import {IPyreStaking} from "../interfaces/IPyreStaking.sol";
import {IPyreStakingHooks} from "../interfaces/IPyreStakingHooks.sol";
import {IPyreStakingYield} from "../interfaces/IPyreStakingYield.sol";

/// @title PyreStaking
/// @notice Stakes $PYRE (pausing decay) and accrues ETH yield via a reward-per-weight accumulator.
contract PyreStaking is IPyreStaking, IPyreStakingHooks, IPyreStakingYield, Ownable, ReentrancyGuard {
    uint256 public constant WAD = 1e18;
    uint256 public constant WHITELIST_BOOST = 12e17; // 1.2x
    uint256 public constant WHITELIST_STAKE_WINDOW = 48 hours;
    uint256 public constant WHITELIST_ACTIVE_DURATION = 7 days;

    IPyreToken public immutable pyreToken;
    uint256 public immutable launchTime;

    IPyreWeightFactors public weightFactors;

    uint256 public totalWeight;
    uint256 public rewardPerWeightStored;
    uint256 public lastUpdateTime;
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public rewardsDuration = 7 days;

    mapping(address => uint256) public stakedBalanceOf;
    mapping(address => uint256) public userWeight;
    mapping(address => uint256) public userRewardPerWeightPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public firstStakeTime;
    mapping(address => bool) public whitelisted;

    address public yieldRouter;

    event Staked(address indexed account, uint256 amount, uint256 weight);
    event Unstaked(address indexed account, uint256 amount, uint256 weight);
    event RewardAdded(uint256 reward, uint256 duration);
    event RewardPaid(address indexed account, uint256 reward);
    event WeightFactorsUpdated(address indexed factors);
    event WhitelistUpdated(address indexed account, bool status);

    error ZeroAmount();
    error InsufficientStakedBalance(address account, uint256 available, uint256 required);
    error RewardTransferFailed();
    error RewardTooSmall();
    error InvalidDuration();
    error OnlyWeightFactors();
    error OnlyYieldRouter();

    modifier updateReward(address account) {
        rewardPerWeightStored = rewardPerWeight();
        lastUpdateTime = _lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerWeightPaid[account] = rewardPerWeightStored;
        }
        _;
    }

    constructor(address admin, address token_, uint256 launchTime_, address weightFactors_) Ownable(admin) {
        pyreToken = IPyreToken(token_);
        launchTime = launchTime_;
        weightFactors = IPyreWeightFactors(weightFactors_);
        lastUpdateTime = block.timestamp;
    }

    function setWeightFactors(address factors) external onlyOwner {
        weightFactors = IPyreWeightFactors(factors);
        emit WeightFactorsUpdated(factors);
    }

    function setWhitelisted(address account, bool status) external onlyOwner {
        whitelisted[account] = status;
        emit WhitelistUpdated(account, status);
    }

    function setYieldRouter(address router) external onlyOwner {
        yieldRouter = router;
    }

    function depositYield() external payable updateReward(address(0)) {
        if (msg.sender != yieldRouter) revert OnlyYieldRouter();
        if (msg.value == 0) revert ZeroAmount();
        _addRewards(msg.value, rewardsDuration);
    }

    function setRewardsDuration(uint256 duration) external onlyOwner {
        if (block.timestamp < periodFinish) revert InvalidDuration();
        rewardsDuration = duration;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        if (firstStakeTime[msg.sender] == 0) {
            firstStakeTime[msg.sender] = block.timestamp;
        }

        pyreToken.stakeFor(msg.sender, amount);

        uint256 previousWeight = userWeight[msg.sender];
        stakedBalanceOf[msg.sender] += amount;
        uint256 newWeight = _calculateWeight(msg.sender, stakedBalanceOf[msg.sender]);

        userWeight[msg.sender] = newWeight;
        totalWeight = totalWeight - previousWeight + newWeight;

        emit Staked(msg.sender, amount, newWeight);
    }

    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        uint256 staked = stakedBalanceOf[msg.sender];
        if (staked < amount) {
            revert InsufficientStakedBalance(msg.sender, staked, amount);
        }

        pyreToken.unstakeFor(msg.sender, amount);

        uint256 previousWeight = userWeight[msg.sender];
        stakedBalanceOf[msg.sender] = staked - amount;
        uint256 newWeight = _calculateWeight(msg.sender, stakedBalanceOf[msg.sender]);

        userWeight[msg.sender] = newWeight;
        totalWeight = totalWeight - previousWeight + newWeight;

        emit Unstaked(msg.sender, amount, newWeight);
    }

    function onWeightFactorsChanged(address account) external nonReentrant {
        if (msg.sender != address(weightFactors)) revert OnlyWeightFactors();
        _settleAndRefresh(account);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) return;

        rewards[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: reward}("");
        if (!success) revert RewardTransferFailed();

        emit RewardPaid(msg.sender, reward);
    }

    function notifyRewardAmount(uint256 amount, uint256 duration) public payable onlyOwner updateReward(address(0)) {
        if (duration == 0) revert InvalidDuration();
        if (amount == 0) revert ZeroAmount();
        if (msg.value != amount) revert RewardTooSmall();
        _addRewards(amount, duration);
    }

    function _addRewards(uint256 amount, uint256 duration) internal {
        if (block.timestamp >= periodFinish) {
            rewardRate = amount / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (amount + leftover) / duration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        rewardsDuration = duration;

        emit RewardAdded(amount, duration);
    }

    function lastTimeRewardApplicable() external view returns (uint256) {
        return _lastTimeRewardApplicable();
    }

    function rewardPerWeight() public view returns (uint256) {
        if (totalWeight == 0) {
            return rewardPerWeightStored;
        }
        return rewardPerWeightStored
            + (((_lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * WAD) / totalWeight);
    }

    function earned(address account) public view returns (uint256) {
        return ((userWeight[account] * (rewardPerWeight() - userRewardPerWeightPaid[account])) / WAD)
            + rewards[account];
    }

    function weightOf(address account) public view returns (uint256) {
        return _calculateWeight(account, stakedBalanceOf[account]);
    }

    function _calculateWeight(address account, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        uint256 nftMultiplier = weightFactors.nftStageMultiplier(account);
        uint256 lpBonus = weightFactors.lpBurnBonus(account);
        uint256 whitelistMultiplier = _whitelistBoost(account);

        return (amount * nftMultiplier / WAD) * lpBonus / WAD * whitelistMultiplier / WAD;
    }

    function _whitelistBoost(address account) internal view returns (uint256) {
        if (!whitelisted[account]) return WAD;

        uint256 stakedAt = firstStakeTime[account];
        if (stakedAt == 0 || stakedAt > launchTime + WHITELIST_STAKE_WINDOW) return WAD;
        if (block.timestamp >= launchTime + WHITELIST_ACTIVE_DURATION) return WAD;

        return WHITELIST_BOOST;
    }

    function _lastTimeRewardApplicable() internal view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function _settleAndRefresh(address account) internal {
        rewardPerWeightStored = rewardPerWeight();
        lastUpdateTime = _lastTimeRewardApplicable();
        rewards[account] = earned(account);
        userRewardPerWeightPaid[account] = rewardPerWeightStored;

        uint256 reward = rewards[account];
        if (reward > 0) {
            rewards[account] = 0;
            (bool success,) = payable(account).call{value: reward}("");
            if (!success) revert RewardTransferFailed();
            emit RewardPaid(account, reward);
        }

        _refreshWeight(account);
        rewardPerWeightStored = rewardPerWeight();
        lastUpdateTime = _lastTimeRewardApplicable();
        userRewardPerWeightPaid[account] = rewardPerWeightStored;
        rewards[account] = 0;
    }

    function _refreshWeight(address account) internal {
        uint256 staked = stakedBalanceOf[account];
        uint256 previousWeight = userWeight[account];
        uint256 newWeight = _calculateWeight(account, staked);
        userWeight[account] = newWeight;
        totalWeight = totalWeight - previousWeight + newWeight;
    }
}
