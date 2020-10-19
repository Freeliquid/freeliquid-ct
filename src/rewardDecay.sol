pragma solidity ^0.5.12;

import "./reward.sol";


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

	uint constant EPOCHCOUNT = 52;
	uint epochInited = 0;
	EpochData[EPOCHCOUNT] public epochs;

	mapping(address => uint256) public lastClaimedEpoch;
	mapping(address => uint256) yetNotClaimedOldEpochRewards;
	uint256 public currentEpoch;


    event RewardAdded(uint256 reward, uint256 epoch, uint256 duration, uint256 starttime);
    event StopRewarding();
    event Staked(address indexed user, address indexed gem, uint256 amount);
    event Withdrawn(address indexed user, address indexed gem, uint256 amount);
    event RewardTakeStock(address indexed user, uint256 reward, uint256 epoch);
    event RewardPaid(address indexed user, uint256 reward);


    constructor () public {
        deployer = msg.sender;
    }

    function initialize(address _gov) public initializer {
        // only deployer can initialize
        require(deployer == msg.sender);

        gov = _gov;

    }

    modifier checkStart(){
        require(block.timestamp > epochs[0].starttime, "not start");
        require(epochInited == EPOCHCOUNT, "not all epochs was inited");
        _;
    }

    function initRewardAmount(uint256 reward, uint256 starttime, uint256 duration, uint256 idx) public
    {
    	require(deployer == msg.sender);
    	require(idx < EPOCHCOUNT);
    	require(duration > 0);
    	require(starttime > 0);

    	EpochData storage epoch = epochs[idx];

    	if (epoch.starttime == 0) {
        	epochInited = epochInited.add(1);
        }
        epoch.rewardPerTokenStored = 0;
    	epoch.starttime = starttime;
    	epoch.duration = duration;
        epoch.rewardRate = reward.div(duration);
        require(epoch.rewardRate > 0);


        epoch.initreward = reward;
        epoch.lastUpdateTime = starttime;
        epoch.periodFinish = starttime.add(duration);

        emit RewardAdded(reward, idx, duration, starttime);
    }

    modifier updateCurrentEpoch() {
    	for (uint i=currentEpoch; i < EPOCHCOUNT && epochs[i].periodFinish < block.timestamp; i++) {
    		currentEpoch = i;
    	}

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


    function registerPairDesc(address gem, address adapter, uint factor, address staker) public {
        // only deployer can do it
        require(deployer == msg.sender);

        require(gem != address(0x0));
        require(adapter != address(0x0));

        pairDescs[gem] = PairDesc({gem:gem, adapter:adapter, factor:factor, staker:staker});
    }


    function lastTimeRewardApplicable(EpochData storage epoch) internal view returns (uint256) {
    	assert(block.timestamp >= epoch.starttime);
        return Math.min(block.timestamp, epoch.periodFinish);
    }

    function rewardPerToken(EpochData storage epoch) internal view returns (uint256) {
        if (epoch.lastTotalSupply == 0) {
            return epoch.rewardPerTokenStored;
        }
        return
            epoch.rewardPerTokenStored.add(
                lastTimeRewardApplicable(epoch)
                    .sub(epoch.lastUpdateTime)
                    .mul(epoch.rewardRate)
                    .mul(1e18)
                    .div(epoch.lastTotalSupply)
            );
    }

    function earnedEpoch(address account, EpochData storage epoch) internal view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken(epoch).sub(epoch.userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(epoch.rewards[account]);
    }


    function earned(address account) public view returns (uint256 acc) {
    	for (uint i=lastClaimedEpoch[account]; i<=currentEpoch; i++) {
    		acc = acc.add(earnedEpoch(account, epochs[i]));
    	}
    	acc = acc.add(yetNotClaimedOldEpochRewards[account]);
    }

    function getRewardEpoch(address account, EpochData storage epoch) internal updateReward(account, epoch) returns (uint256) {
        uint256 reward = earnedEpoch(account, epoch);
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
        super.stake(amount, gem, usr);
        emit Staked(usr, gem, amount);
    }

    function stake(uint256 amount, address gem, address usr) public checkStart updateCurrentEpoch {
        require(amount > 0, "Cannot stake 0");
        stakeEpoch(amount, gem, usr, epochs[currentEpoch]);
    }


    function withdrawEpoch(uint256 amount, address gem, address usr, EpochData storage epoch) internal updateReward(usr, epoch) {
    	gatherOldEpochReward(usr);
        super.withdraw(amount, gem, usr);
        emit Withdrawn(usr, gem, amount);
    }

    function withdraw(uint256 amount, address gem, address usr) public checkStart updateCurrentEpoch {
        require(amount > 0, "Cannot withdraw 0");
        withdrawEpoch(amount, gem, usr, epochs[currentEpoch]);
    }


    function getReward() public
    	checkStart
    	updateCurrentEpoch
    	updateReward(msg.sender, epochs[currentEpoch])
    	returns (uint256 acc)
    {
    	acc = takeStockReward(msg.sender);

    	acc.add(yetNotClaimedOldEpochRewards[msg.sender]);
    	yetNotClaimedOldEpochRewards[msg.sender] = 0;

    	if (acc > 0) {
	        totalRewards = totalRewards.add(acc);
			IERC20(gov).safeTransfer(msg.sender, acc);
			emit RewardPaid(msg.sender, acc);
		}
    }


    modifier updateReward(address account, EpochData storage epoch) {
        assert (account != address(0));

        epoch.rewardPerTokenStored = rewardPerToken(epoch);
        epoch.lastUpdateTime = lastTimeRewardApplicable(epoch);
        epoch.rewards[account] = earnedEpoch(account, epoch);
        epoch.userRewardPerTokenPaid[account] = epoch.rewardPerTokenStored;
        _;
    }
}
