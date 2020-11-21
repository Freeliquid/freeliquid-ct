/**
 *Submitted for verification at Etherscan.io on 2020-08-12
*/


/**
 *Submitted for verification at Etherscan.io on
*/

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Synthetix: YFIRewards.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
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
import "./lib.sol";


contract StakingRewards is LPTokenWrapper, Auth {
    // --- Auth ---

    address public gov;
    uint256 public duration;

    uint256 public initreward;
    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewards = 0;
    bool public fairDistribution = false;
    uint256 public fairDistributionMaxValue = 0;
    uint256 public fairDistributionTime = 0;


    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event StopRewarding();
    event Staked(address indexed user, address indexed gem, uint256 amount);
    event Withdrawn(address indexed user, address indexed gem, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor () public {
        deployer = msg.sender;
    }

    function initialize(address _gov, uint256 _duration, uint256 _initreward, uint256 _starttime) public initializer {
        // only deployer can initialize
        require(deployer == msg.sender);

        require(_starttime >= block.timestamp);

        gov = _gov;

        duration = _duration;
        starttime = _starttime;
        initRewardAmount(_initreward);
    }

    function setupFairDistribution(uint256 _fairDistributionMaxValue, uint256 _fairDistributionTime) public {
        // only deployer can initialize
        require(deployer == msg.sender);
        require(fairDistribution == false);

        fairDistribution = true;
        fairDistributionMaxValue = _fairDistributionMaxValue*(10**decimals);
        fairDistributionTime = _fairDistributionTime;
    }

    function registerPairDesc(address gem, address adapter, uint factor, address staker) public auth {
        require(gem != address(0x0));
        require(adapter != address(0x0));

        pairDescs[gem] = PairDesc({gem:gem, adapter:adapter, factor:factor, staker:staker, name:"dummy"});
    }

    function resetDeployer() public {
        // only deployer can do it
        require(deployer == msg.sender);
        deployer = address(0);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18 * (10**decimals))
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18 * (10**decimals))
                .add(rewards[account]);
    }

    function testFairDistribution(address usr, address gem, uint amount) public view returns (bool){
        return testFairDistributionByValue(usr, calcCheckValue(amount, gem));
    }

    function testFairDistributionByValue(address usr, uint value) public view returns (bool){
        if (fairDistribution) {
            return balanceOf(usr).add(value) <= fairDistributionMaxValue || block.timestamp >= starttime.add(fairDistributionTime);
        }
        return true;
    }


    function checkFairDistribution(address usr) public view checkStart {
        if (fairDistribution) {
            require(balanceOf(usr) <= fairDistributionMaxValue || block.timestamp >= starttime.add(fairDistributionTime),
                    "Fair-distribution-limit");
        }
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount, address gem, address usr) public updateReward(usr) checkFinish checkStart{
        require(amount > 0, "Cannot stake 0");
        require(pairDescs[gem].staker == msg.sender, "Stake from join only allowed");

        stakeLp(amount, gem, usr);
        emit Staked(usr, gem, amount);
    }

    function withdraw(uint256 amount, address gem, address usr) public updateReward(usr) checkFinish checkStart{
        require(amount > 0, "Cannot withdraw 0");
        require(pairDescs[gem].staker == msg.sender, "Stake from join only allowed");

        withdrawLp(amount, gem, usr);
        emit Withdrawn(usr, gem, amount);
    }


    function getReward() public updateReward(msg.sender) checkFinish checkStart returns (uint256) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(gov).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
            totalRewards = totalRewards.add(reward);
            return reward;
        }
        return 0;
    }

    modifier checkFinish(){
        if (block.timestamp > periodFinish) {
            initreward = 0;
            rewardRate = 0;
            periodFinish = uint256(-1);
            emit StopRewarding();
        }
        _;
    }

    modifier checkStart(){
        require(allowToStart(),"not start");
        _;
    }

    function allowToStart() view public returns (bool) {
        return block.timestamp > starttime;
    }

    function initRewardAmount(uint256 reward)
        internal
        updateReward(address(0))
    {
        require(starttime >= block.timestamp);
        rewardRate = reward.div(duration);
        initreward = reward;
        lastUpdateTime = starttime;
        periodFinish = starttime.add(duration);
        emit RewardAdded(reward);
    }
}


interface VatLike {
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;
}



contract GemJoinWithReward is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoinWithReward/not-authorized");
        _;
    }

    event stakeError(uint256 amount, address gem, address usr);
    event withdrawError(uint256 amount, address gem, address usr);

    StakingRewards public rewarder;
    VatLike public vat;   // CDP Engine
    bytes32 public ilk;   // Collateral Type
    IERC20  public gem;
    uint    public dec;
    uint    public live;  // Active Flag

    constructor(address vat_, bytes32 ilk_, address gem_, address rewarder_) public {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = IERC20(gem_);
        rewarder = StakingRewards(rewarder_);
        dec = gem.decimals();
        require(dec >= 18, "GemJoinWithReward/decimals-18-or-higher");
    }
    function cage() external note auth {
        live = 0;
    }
    function join(address urn, uint wad) external note {
        require(live == 1, "GemJoinWithReward/not-live");
        require(int(wad) >= 0, "GemJoinWithReward/overflow");
        vat.slip(ilk, urn, int(wad));

        // rewarder.stake(wad, address(gem), msg.sender);
        (bool ret, ) = address(rewarder).call(abi.encodeWithSelector(rewarder.stake.selector, wad, address(gem), msg.sender));
        if (!ret) {
          emit stakeError(wad, address(gem), msg.sender);
        }

        rewarder.checkFairDistribution(msg.sender);

        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoinWithReward/failed-transfer");
    }
    function exit(address usr, uint wad) external note {
        require(wad <= 2 ** 255, "GemJoinWithReward/overflow");
        vat.slip(ilk, msg.sender, -int(wad));

        require(rewarder.allowToStart(), "join-not-start");

        // rewarder.withdraw(wad, address(gem), msg.sender);
        (bool ret, ) = address(rewarder).call(abi.encodeWithSelector(rewarder.withdraw.selector, wad, address(gem), msg.sender));
        if (!ret) {
          emit withdrawError(wad, address(gem), msg.sender);
        }

        require(gem.transfer(usr, wad), "GemJoinWithReward/failed-transfer");
    }
}


contract RewardProxyActions {
    function claimReward(address rewarder) public {
        uint256 reward = StakingRewards(rewarder).getReward();
        IERC20(StakingRewards(rewarder).gov()).transfer(msg.sender, reward);
    }
}

