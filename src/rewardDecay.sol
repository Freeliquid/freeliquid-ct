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


contract StakingRewardsDecay is LPTokenWrapper {
    address public gov;
    address public deployer;
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


    uint public EPOCHCOUNT = 0;
    uint public epochInited = 0;
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


    constructor () public {
        deployer = msg.sender;
    }

    function initialize(address _gov, uint epochCount) public initializer {
        // only deployer can initialize
        require(deployer == msg.sender);

        gov = _gov;
        require(gov != address(0));
        require(epochCount > 0);

        EPOCHCOUNT = epochCount;
        EpochData memory data;
        for (uint i =0; i<epochCount; i++) {
            epochs.push(data);
        }

        holder = new StakingRewardsDecayHolder(address(this));
    }

    modifier checkStart(){
        require(block.timestamp >= epochs[0].starttime, "not start");
        require(epochInited == EPOCHCOUNT, "not all epochs was inited");
        _;
    }

    function initRewardAmount(uint256 reward, uint256 starttime, uint256 duration, uint256 idx) public
    {
        // only deployer can
        require(deployer == msg.sender);
        require(epochInited == 0, "not allowed after approve");
        initEpoch(reward, starttime, duration, idx);
    }

    function initEpoch(uint256 reward, uint256 starttime, uint256 duration, uint256 idx) internal
    {
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

    function initAllEpochs(uint256[] memory rewards, uint256 starttime, uint256 duration) public
    {
        // only deployer can
        require(deployer == msg.sender);
        require(epochInited == 0, "not allowed after approve");

        require(duration > 0);
        require(starttime > 0);

        assert(rewards.length == EPOCHCOUNT);

        uint time = starttime;

        for (uint i=0; i < EPOCHCOUNT; i++) {
            initEpoch(rewards[i], time, duration, i);
            time = time.add(duration);
        }
    }

    function getEpochRewardRate(uint epochIdx) public view returns (uint) {
        return epochs[epochIdx].rewardRate;
    }

    function getEpochStartTime(uint epochIdx) public view returns (uint) {
        return epochs[epochIdx].starttime;
    }

    function getEpochFinishTime(uint epochIdx) public view returns (uint) {
        return epochs[epochIdx].periodFinish;
    }

    function getTotalRewards() public view returns (uint result) {
        require(epochInited == EPOCHCOUNT, "not inited");

        result = 0;

        for (uint i=0; i < EPOCHCOUNT; i++) {
            result = result.add(epochs[i].initreward);
        }
    }

    function getTotalRewardTime() public view returns (uint result) {
        require(epochInited == EPOCHCOUNT, "not inited");

        result = 0;

        for (uint i=0; i < EPOCHCOUNT; i++) {
            result = result.add(epochs[i].duration);
        }
    }


    function approveEpochsConsistency() public {
        require(deployer == msg.sender);
        require(epochInited == 0, "double call not allowed");

        uint totalReward = epochs[0].initreward;
        require(epochs[0].starttime > 0);

        for (uint i=1; i < EPOCHCOUNT; i++) {
            EpochData storage epoch = epochs[i];
            require(epoch.starttime > 0);
            require(epoch.starttime == epochs[i-1].periodFinish);
            totalReward = totalReward.add(epoch.initreward);
        }

        require(IERC20(gov).balanceOf(address(this)) >= totalReward, "GOV balance not enought");

        epochInited = EPOCHCOUNT;
    }

    function calcCurrentEpoch() public view returns (uint res){
        res = 0;
        for (uint i=currentEpoch; i < EPOCHCOUNT && epochs[i].starttime <= block.timestamp; i++) {
            res = i;
        }
    }


    modifier updateCurrentEpoch() {

        currentEpoch = calcCurrentEpoch();

        uint supply = totalSupply();
        epochs[currentEpoch].lastTotalSupply = supply;

        for (int i=int(currentEpoch)-1; i>=0; i--) {
            EpochData storage epoch = epochs[uint(i)];
            if (epoch.closed) {
                break;
            }

            epoch.lastTotalSupply = supply;
            epoch.closed = true;
        }

        _;
    }


    function registerPairDesc(address gem, address adapter, uint factor, bytes32 name) public {
        // only deployer can do it
        require(deployer == msg.sender);

        require(gem != address(0x0));
        require(adapter != address(0x0));

        require(pairNameToGem[name] == address(0) || pairNameToGem[name] == gem, "duplicate name");

        if (pairDescs[gem].name != "") {
            delete pairNameToGem[pairDescs[gem].name];
        }

        pairDescs[gem] = PairDesc({gem:gem, adapter:adapter, factor:factor, staker:address(0), name:name});

        pairNameToGem[name] = gem;
    }

    function getPairInfo(bytes32 name, address account) public view returns (
        address gem,
        uint avail,
        uint locked,
        uint lockedValue,
        uint rewardPerHour)
    {
        gem = pairNameToGem[name];
        if (gem == address(0)) {
            return (address(0), 0, 0, 0, 0);
        }

        PairDesc storage desc = pairDescs[gem];
        locked = holder.amounts(gem, account);
        lockedValue = IAdapter(desc.adapter).calc(gem, locked, desc.factor);
        avail = IERC20(gem).balanceOf(account);

        EpochData storage epoch = epochs[calcCurrentEpoch()];
        rewardPerHour = epoch.rewardRate * 3600;
    }


    function lastTimeRewardApplicable(EpochData storage epoch) internal view returns (uint256) {
        assert(block.timestamp >= epoch.starttime);
        return Math.min(block.timestamp, epoch.periodFinish);
    }

    function rewardPerToken(EpochData storage epoch, uint256 lastTotalSupply) internal view returns (uint256) {
        if (lastTotalSupply == 0) {
            return epoch.rewardPerTokenStored;
        }
        return
            epoch.rewardPerTokenStored.add(
                lastTimeRewardApplicable(epoch)
                    .sub(epoch.lastUpdateTime)
                    .mul(epoch.rewardRate)
                    .mul(1e18)
                    .div(lastTotalSupply)
            );
    }

    function earnedEpoch(address account,
                         EpochData storage epoch,
                         uint256 lastTotalSupply) internal view returns (uint256)
    {
        return
            balanceOf(account)
                .mul(rewardPerToken(epoch, lastTotalSupply).sub(epoch.userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(epoch.rewards[account]);
    }


    function earned(address account) public view returns (uint256 acc) {

        uint currentSupply = totalSupply();
        int lastClaimedEpochIdx = int(lastClaimedEpoch[account]);

        for (int i=int(calcCurrentEpoch()); i>=lastClaimedEpochIdx; i--) {
            EpochData storage epoch = epochs[uint(i)];

            uint epochTotalSupply = currentSupply;
            if (epoch.closed) {
                epochTotalSupply = epoch.lastTotalSupply;
            }
            acc = acc.add(earnedEpoch(account, epoch, epochTotalSupply));
        }

        acc = acc.add(yetNotClaimedOldEpochRewards[account]);
    }

    function getRewardEpoch(address account, EpochData storage epoch) internal updateReward(account, epoch) returns (uint256) {
        uint256 reward = earnedEpoch(account, epoch, epoch.lastTotalSupply);
        if (reward > 0) {
            epoch.rewards[account] = 0;
            return reward;
        }
        return 0;
    }

    function takeStockReward(address account) internal returns (uint256 acc) {
        for (uint i=lastClaimedEpoch[account]; i<=currentEpoch; i++) {
            uint256 reward = getRewardEpoch(account, epochs[i]);
            acc = acc.add(reward);
            emit RewardTakeStock(account, reward, i);
        }
        lastClaimedEpoch[account] = currentEpoch;
    }

    function gatherOldEpochReward(address account) internal {
        if (currentEpoch == 0) {
            return;
        }

        uint acc = takeStockReward(account);
        yetNotClaimedOldEpochRewards[account] = yetNotClaimedOldEpochRewards[account].add(acc);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stakeEpoch(uint256 amount, address gem, address usr, EpochData storage epoch) internal updateReward(usr, epoch) {
        gatherOldEpochReward(usr);
        stakeLp(amount, gem, usr);
        emit Staked(usr, gem, amount);
    }

    function stake(address account, uint256 amount, address gem) public checkStart updateCurrentEpoch {
        require (address(holder) == msg.sender);
        assert(amount > 0);
        stakeEpoch(amount, gem, account, epochs[currentEpoch]);
    }


    function withdrawEpoch(uint256 amount, address gem, address usr, EpochData storage epoch) internal updateReward(usr, epoch) {
        gatherOldEpochReward(usr);
        withdrawLp(amount, gem, usr);
        emit Withdrawn(usr, gem, amount);
    }

    function withdraw(address account, uint256 amount, address gem) public checkStart updateCurrentEpoch {
        require (address(holder) == msg.sender);
        assert(amount > 0);
        withdrawEpoch(amount, gem, account, epochs[currentEpoch]);
    }


    function getReward() public
        checkStart
        updateCurrentEpoch
        updateReward(msg.sender, epochs[currentEpoch])
        returns (uint256 acc)
    {
        acc = takeStockReward(msg.sender);

        acc = acc.add(yetNotClaimedOldEpochRewards[msg.sender]);
        yetNotClaimedOldEpochRewards[msg.sender] = 0;

        if (acc > 0) {
            totalRewards = totalRewards.add(acc);
            IERC20(gov).safeTransfer(msg.sender, acc);
            emit RewardPaid(msg.sender, acc);
        }
    }


    modifier updateReward(address account, EpochData storage epoch) {
        assert (account != address(0));

        epoch.rewardPerTokenStored = rewardPerToken(epoch, epoch.lastTotalSupply);
        epoch.lastUpdateTime = lastTimeRewardApplicable(epoch);
        epoch.rewards[account] = earnedEpoch(account, epoch, epoch.lastTotalSupply);
        epoch.userRewardPerTokenPaid[account] = epoch.rewardPerTokenStored;
        _;
    }
}

