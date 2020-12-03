/*
 * MIT License
 * ===========
 *
 * Copyright (c) 2020 Freeliquid
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 */

pragma solidity ^0.5.12;

import "./lpTokenWrapper.sol";
import "./rewardsDecayHolder.sol";
import "./lib.sol";
import "./ReentrancyGuard.sol";

/**
 * @title class for handling distributions FL tokens as reward
 *        for providing liquidity for FL & USDFL tokens
*/
contract StakingRewardsDecay is LPTokenWrapper, Auth, ReentrancyGuard {
    address public gov;
    address public aggregator;
    uint256 public totalRewards = 0;

    struct EpochData {
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
        uint256 initreward;
        uint256 duration;
        uint256 starttime;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 lastTotalSupply;
        bool closed;
    }

    uint256 public EPOCHCOUNT = 0;
    uint256 public epochInited = 0;
    EpochData[] public epochs;

    mapping(bytes32 => address) public pairNameToGem;

    mapping(address => uint256) public lastClaimedEpoch;
    mapping(address => uint256) public yetNotClaimedOldEpochRewards;
    uint256 public currentEpoch;

    StakingRewardsDecayHolder public holder;

    event RewardAdded(uint256 reward, uint256 epoch, uint256 duration, uint256 starttime);
    event StopRewarding();
    event Staked(address indexed user, address indexed gem, uint256 amount);
    event Withdrawn(address indexed user, address indexed gem, uint256 amount);
    event RewardTakeStock(address indexed user, uint256 reward, uint256 epoch);
    event RewardPaid(address indexed user, uint256 reward);

    constructor() public {
        deployer = msg.sender;
    }

    /**
     * @dev initialization can be called only once
     * _gov - FL token contract
     * epochCount - how many epochs we will use
     */
    function initialize(address _gov, uint256 epochCount) public initializer {
        // only deployer can initialize
        require(deployer == msg.sender);

        gov = _gov;
        require(gov != address(0));
        require(epochCount > 0);

        EPOCHCOUNT = epochCount;
        EpochData memory data;
        for (uint256 i = 0; i < epochCount; i++) {
            epochs.push(data);
        }

        holder = new StakingRewardsDecayHolder(address(this));
    }

    /**
     * @dev setup aggregator contract (RewardDecayAggregator) which allow to claim FL
     * tokens from hirisk & lowrisk contracts in one tx
     */
    function setupAggregator(address _aggregator) public {
        require(deployer == msg.sender);
        require(_aggregator != address(0));
        require(aggregator == address(0)); //only one set allowed

        aggregator = _aggregator;
    }

    /**
     * @dev returns time when rewarding will start
     */
    function getStartTime() public view returns (uint256) {
        return epochs[0].starttime;
    }

    /**
     * @dev check is time allow to start rewarding
     */
    modifier checkStart() {
        require(block.timestamp >= getStartTime(), "not start");
        require(epochInited == EPOCHCOUNT, "not all epochs was inited");
        _;
    }

    /**
     * @dev init specific rewarding epoch
     * reward - how many Fl tokens we have to distribute in this epoch
     * starttime - time to start rewarding
     * duration - duration of each epoch
     * idx - id of epoch
     */
    function initRewardAmount(
        uint256 reward,
        uint256 starttime,
        uint256 duration,
        uint256 idx
    ) public {
        // only deployer can
        require(deployer == msg.sender);
        require(epochInited == 0, "not allowed after approve");
        initEpoch(reward, starttime, duration, idx);
    }

    /**
     * @dev setup checker contract which will be used to check
     * that LP pair used for FL rewarding contains only approved stables
     */
    function setupGemForRewardChecker(address a) public {
        require(deployer == msg.sender);
        gemForRewardChecker = IGemForRewardChecker(a);
    }

    /**
     * @dev core func to init specific rewarding epoch
     * reward - how many Fl tokens we have to distribute in this epoch
     * starttime - time to start rewarding
     * duration - duration of each epoch
     * idx - id of epoch
     */
    function initEpoch(
        uint256 reward,
        uint256 starttime,
        uint256 duration,
        uint256 idx
    ) internal {
        require(idx < EPOCHCOUNT, "idx < EPOCHCOUNT");
        require(duration > 0, "duration > 0");
        require(starttime >= block.timestamp, "starttime > block.timestamp");

        EpochData storage epoch = epochs[idx];

        epoch.rewardPerTokenStored = 0;
        epoch.starttime = starttime;
        epoch.duration = duration;
        epoch.rewardRate = reward.div(duration);
        require(epoch.rewardRate > 0, "zero rewardRate");

        epoch.initreward = reward;
        epoch.lastUpdateTime = starttime;
        epoch.periodFinish = starttime.add(duration);

        emit RewardAdded(reward, idx, duration, starttime);
    }

    /**
     * @dev init all reward epochs in one call
     * rewards - array of reward to distribute (one digit for one epoch)
     * starttime - time to start rewarding
     * duration - duration of each epoch
     */
    function initAllEpochs(
        uint256[] memory rewards,
        uint256 starttime,
        uint256 duration
    ) public {
        // only deployer can
        require(deployer == msg.sender);
        require(epochInited == 0, "not allowed after approve");

        require(duration > 0);
        require(starttime > 0);

        assert(rewards.length == EPOCHCOUNT);

        uint256 time = starttime;

        for (uint256 i = 0; i < EPOCHCOUNT; i++) {
            initEpoch(rewards[i], time, duration, i);
            time = time.add(duration);
        }
    }

    /**
     * @dev returns reward rate for specific epoch
     */
    function getEpochRewardRate(uint256 epochIdx) public view returns (uint256) {
        return epochs[epochIdx].rewardRate;
    }

    /**
     * @dev returns epoch start time for specific epoch
     */
    function getEpochStartTime(uint256 epochIdx) public view returns (uint256) {
        return epochs[epochIdx].starttime;
    }

    /**
     * @dev returns epoch finish time for specific epoch
     */
    function getEpochFinishTime(uint256 epochIdx) public view returns (uint256) {
        return epochs[epochIdx].periodFinish;
    }

    /**
     * @dev calculate total reward to distribute for all epochs
     */
    function getTotalRewards() public view returns (uint256 result) {
        require(epochInited == EPOCHCOUNT, "not inited");

        result = 0;

        for (uint256 i = 0; i < EPOCHCOUNT; i++) {
            result = result.add(epochs[i].initreward);
        }
    }

    /**
     * @dev calculate total time to reward for all epochs
     */
    function getTotalRewardTime() public view returns (uint256 result) {
        require(epochInited == EPOCHCOUNT, "not inited");

        result = 0;

        for (uint256 i = 0; i < EPOCHCOUNT; i++) {
            result = result.add(epochs[i].duration);
        }
    }

    /**
     * @dev we need to call this func after all epochs will finnally configured
     * only one call allowed
     */
    function approveEpochsConsistency() public {
        require(deployer == msg.sender);
        require(epochInited == 0, "double call not allowed");

        uint256 totalReward = epochs[0].initreward;
        require(getStartTime() > 0);

        for (uint256 i = 1; i < EPOCHCOUNT; i++) {
            EpochData storage epoch = epochs[i];
            require(epoch.starttime > 0);
            require(epoch.starttime == epochs[i - 1].periodFinish);
            totalReward = totalReward.add(epoch.initreward);
        }

        require(IERC20(gov).balanceOf(address(this)) >= totalReward, "GOV balance not enought");

        epochInited = EPOCHCOUNT;
    }

    /**
     * @dev set deployer prop to NULL to prevent further calling registerPairDesc by deployer(admin)
     * and prevent some other initialisation calls
     * needed for fair decentralization
     */
    function resetDeployer() public {
        // only deployer can do it
        require(deployer == msg.sender);
        require(epochInited == EPOCHCOUNT);
        deployer = address(0);
    }

    /**
     * @dev calculate and return current epoch index
     */
    function calcCurrentEpoch() public view returns (uint256 res) {
        res = 0;
        for (
            uint256 i = currentEpoch;
            i < EPOCHCOUNT && epochs[i].starttime <= block.timestamp;
            i++
        ) {
            res = i;
        }
    }

    /**
     * @dev calculate current epoch index and store it inside contract storage
     */
    modifier updateCurrentEpoch() {
        currentEpoch = calcCurrentEpoch();

        uint256 supply = totalSupply();
        epochs[currentEpoch].lastTotalSupply = supply;

        for (int256 i = int256(currentEpoch) - 1; i >= 0; i--) {
            EpochData storage epoch = epochs[uint256(i)];
            if (epoch.closed) {
                break;
            }

            epoch.lastTotalSupply = supply;
            epoch.closed = true;
        }

        _;
    }

    /**
     * @dev register LP pair which have to be rewarded when it will be locked
     * gem - address of LP token contract
     * adapter - address of adapter contract of LP token contract needed to
     *           calculate USD value of specific amount of LP tokens
     * factor -  multiplicator (actually eq 1)
     * name -    name of LP pair to indentificate in GUI. have to be unique
     */
    function registerPairDesc(
        address gem,
        address adapter,
        uint256 factor,
        bytes32 name
    ) public auth nonReentrant {
        require(gem != address(0x0), "gem is null");
        require(adapter != address(0x0), "adapter is null");

        require(checkGem(gem), "bad gem");

        require(pairNameToGem[name] == address(0) || pairNameToGem[name] == gem, "duplicate name");

        if (pairDescs[gem].name != "") {
            delete pairNameToGem[pairDescs[gem].name];
        }

        registerGem(gem);

        pairDescs[gem] = PairDesc({
            gem: gem,
            adapter: adapter,
            factor: factor,
            staker: address(0),
            name: name
        });

        pairNameToGem[name] = gem;
    }

    /**
     * @dev returns LP pair statistic for specific user account
     * return values:
     * gem - address of LP token
     * avail - amount of tokens on user wallet
     * locked - amount of tokens locked for rewarding by user
     * lockedValue - USD value of tokens locked for rewarding by user
     * availValue - USD value of tokens on user wallet
     */
    function getPairInfo(bytes32 name, address account)
        public
        view
        returns (
            address gem,
            uint256 avail,
            uint256 locked,
            uint256 lockedValue,
            uint256 availValue
        )
    {
        gem = pairNameToGem[name];
        if (gem == address(0)) {
            return (address(0), 0, 0, 0, 0);
        }

        PairDesc storage desc = pairDescs[gem];
        locked = holder.amounts(gem, account);
        lockedValue = IAdapter(desc.adapter).calc(gem, locked, desc.factor);
        avail = IERC20(gem).balanceOf(account);
        availValue = IAdapter(desc.adapter).calc(gem, avail, desc.factor);
    }

    /**
     * @dev returns USD value of 1 LP token with specific name
     */
    function getPrice(bytes32 name) public view returns (uint256) {
        address gem = pairNameToGem[name];
        if (gem == address(0)) {
            return 0;
        }

        PairDesc storage desc = pairDescs[gem];
        return IAdapter(desc.adapter).calc(gem, 1, desc.factor);
    }

    /**
     * @dev returns current rewarding speed. How many tokens distributed in one hour
     * at current epoch
     */
    function getRewardPerHour() public view returns (uint256) {
        EpochData storage epoch = epochs[calcCurrentEpoch()];
        return epoch.rewardRate * 3600;
    }

    /**
     * @dev returns current time with cutting by rewarding finish time
     * value calculated for specific epoch
     */
    function lastTimeRewardApplicable(EpochData storage epoch) internal view returns (uint256) {
        assert(block.timestamp >= epoch.starttime);
        return Math.min(block.timestamp, epoch.periodFinish);
    }

    /**
     * @dev returns current rewarding speed per one USD value of LP pair
     * value calculated for specific epoch
     * lastTotalSupply corresponded for current epoch have to be provided
     */
    function rewardPerToken(EpochData storage epoch, uint256 lastTotalSupply)
        internal
        view
        returns (uint256)
    {
        if (lastTotalSupply == 0) {
            return epoch.rewardPerTokenStored;
        }
        return
            epoch.rewardPerTokenStored.add(
                lastTimeRewardApplicable(epoch)
                    .sub(epoch.lastUpdateTime)
                    .mul(epoch.rewardRate)
                    .mul(1e18 * (10**decimals))
                    .div(lastTotalSupply)
            );
    }

    /**
     * @dev returns how many FL tokens specific user already earned for specific epoch
     * lastTotalSupply corresponded for current epoch have to be provided
     */
    function earnedEpoch(
        address account,
        EpochData storage epoch,
        uint256 lastTotalSupply
    ) internal view returns (uint256) {
        return
            balanceOf(account)
                .mul(
                rewardPerToken(epoch, lastTotalSupply).sub(epoch.userRewardPerTokenPaid[account])
            )
                .div(1e18 * (10**decimals))
                .add(epoch.rewards[account]);
    }

    /**
     * @dev returns how many FL tokens of specific user already earned remains unclaimed
     */
    function earned(address account) public view returns (uint256 acc) {
        uint256 currentSupply = totalSupply();
        int256 lastClaimedEpochIdx = int256(lastClaimedEpoch[account]);

        for (int256 i = int256(calcCurrentEpoch()); i >= lastClaimedEpochIdx; i--) {
            EpochData storage epoch = epochs[uint256(i)];

            uint256 epochTotalSupply = currentSupply;
            if (epoch.closed) {
                epochTotalSupply = epoch.lastTotalSupply;
            }
            acc = acc.add(earnedEpoch(account, epoch, epochTotalSupply));
        }

        acc = acc.add(yetNotClaimedOldEpochRewards[account]);
    }

    /**
     * @dev returns how many FL tokens specific user already earned for specified epoch
     * also it clear reward cache
     */
    function getRewardEpoch(address account, EpochData storage epoch) internal returns (uint256) {
        uint256 reward = earnedEpoch(account, epoch, epoch.lastTotalSupply);
        if (reward > 0) {
            epoch.rewards[account] = 0;
            return reward;
        }
        return 0;
    }

    /**
     * @dev returns how many FL tokens specific user already earned from moment of last claiming epoch
     * also this func update last claiming epoch
     */
    function takeStockReward(address account) internal returns (uint256 acc) {
        for (uint256 i = lastClaimedEpoch[account]; i <= currentEpoch; i++) {
            uint256 reward = getRewardEpoch(account, epochs[i]);
            acc = acc.add(reward);
            emit RewardTakeStock(account, reward, i);
        }
        lastClaimedEpoch[account] = currentEpoch;
    }

    /**
     * @dev recalculate and update yetNotClaimedOldEpochRewards cache
     */
    function gatherOldEpochReward(address account) internal {
        if (currentEpoch == 0) {
            return;
        }

        uint256 acc = takeStockReward(account);
        yetNotClaimedOldEpochRewards[account] = yetNotClaimedOldEpochRewards[account].add(acc);
    }

    /**
     * @dev called when we lock LP tokens for specific epoch (we expect current epoch here)
     */
    function stakeEpoch(
        uint256 amount,
        address gem,
        address usr,
        EpochData storage epoch
    ) internal updateReward(usr, epoch) {
        gatherOldEpochReward(usr);
        stakeLp(amount, gem, usr);
        emit Staked(usr, gem, amount);
    }

    /**
     * @dev called by LP token holder contract when we lock LP tokens
     * only LP token holder contract allow to call this func
     */
    function stake(
        address account,
        uint256 amount,
        address gem
    ) public nonReentrant checkStart updateCurrentEpoch {
        require(address(holder) == msg.sender);
        assert(amount > 0);
        stakeEpoch(amount, gem, account, epochs[currentEpoch]);
    }

    /**
     * @dev called when we unlock LP tokens for specific epoch (we expect current epoch here)
     */
    function withdrawEpoch(
        uint256 amount,
        address gem,
        address usr,
        EpochData storage epoch
    ) internal updateReward(usr, epoch) {
        gatherOldEpochReward(usr);
        withdrawLp(amount, gem, usr);
        emit Withdrawn(usr, gem, amount);
    }

    /**
     * @dev called by LP token holder contract when we unlock LP tokens
     * only LP token holder contract allow to call this func
     */
    function withdraw(
        address account,
        uint256 amount,
        address gem
    ) public nonReentrant checkStart updateCurrentEpoch {
        require(address(holder) == msg.sender);
        assert(amount > 0);
        withdrawEpoch(amount, gem, account, epochs[currentEpoch]);
    }

    /**
     * @dev core func to actual transferting rewarded FL tokens to user wallet
     */
    function getRewardCore(address account)
        internal
        checkStart
        updateCurrentEpoch
        updateReward(account, epochs[currentEpoch])
        returns (uint256 acc)
    {
        acc = takeStockReward(account);

        acc = acc.add(yetNotClaimedOldEpochRewards[account]);
        yetNotClaimedOldEpochRewards[account] = 0;

        if (acc > 0) {
            totalRewards = totalRewards.add(acc);
            IERC20(gov).safeTransfer(account, acc);
            emit RewardPaid(account, acc);
        }
    }

    /**
     * @dev func to actual transferting rewarded FL tokens to user wallet
     */
    function getReward() public nonReentrant returns (uint256) {
        return getRewardCore(msg.sender);
    }

    /**
     * @dev func to actual transferting rewarded FL tokens to user wallet
     * we call this func from aggregator contract (RewardDecayAggregator) to allow to claim FL
     * tokens from hirisk & lowrisk contracts in one tx
     */
    function getRewardEx(address account) public nonReentrant returns (uint256) {
        require(aggregator == msg.sender);
        return getRewardCore(account);
    }

    /**
     * @dev update some internal rewarding props
     */
    modifier updateReward(address account, EpochData storage epoch) {
        assert(account != address(0));

        epoch.rewardPerTokenStored = rewardPerToken(epoch, epoch.lastTotalSupply);
        epoch.lastUpdateTime = lastTimeRewardApplicable(epoch);
        epoch.rewards[account] = earnedEpoch(account, epoch, epoch.lastTotalSupply);
        epoch.userRewardPerTokenPaid[account] = epoch.rewardPerTokenStored;
        _;
    }
}


/**
 * @title class for combine reward claiming for hirisk & lowrisk contracts in one tx
*/
contract RewardDecayAggregator {
    using SafeMath for uint256;

    StakingRewardsDecay[2] public rewarders;

    constructor(address rewarder0, address rewarder1) public {
        rewarders[0] = StakingRewardsDecay(rewarder0);
        rewarders[1] = StakingRewardsDecay(rewarder1);
    }

    /**
     * @dev claim unclaimed reward
     */
    function claimReward() public {
        for (uint256 i = 0; i < rewarders.length; i++) {
            rewarders[i].getRewardEx(msg.sender);
        }
    }

    /**
     * @dev how many rewards remains unclaimed
     */
    function earned() public view returns (uint256 res) {
        for (uint256 i = 0; i < rewarders.length; i++) {
            res = res.add(rewarders[i].earned(msg.sender));
        }
    }
}
