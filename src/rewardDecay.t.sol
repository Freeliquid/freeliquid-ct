pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./uni.sol";
import "./testHelpers.sol";

import "./rewardDecay.sol";



contract User {
  bytes32 body;

  function approve(UniswapV2Pair gem, address other, uint amount) public {
    gem.approve(other, amount);
  }

  function stake(StakingRewardsDecay rewards, UniswapV2Pair gem, uint amount) public {
    gem.approve(address(rewards), amount);
    rewards.stake(amount, address(gem));
  }

  function withdraw(StakingRewardsDecay rewards, UniswapV2Pair gem, uint amount) public {
    rewards.withdraw(amount, address(gem));
  }

  function getReward(StakingRewards rewards) public returns (uint256) {
    return rewards.getReward();
  }
}

contract RewardDecayTest is TestBase {

  StakingRewardsDecay rewards;

  User user1;
  User user2;

  uint constant totalRewardsMul =  1e18;
  uint totalRewards =   100000*totalRewardsMul;
  uint rewardDuration = 1000000;

  function setUp() public {
    super.setUp();

    user1 = new User();
    user2 = new User();

    rewards = new StakingRewardsDecay();

    gov.mint(address(rewards), totalRewards);
  }


  function prepareRewarder3(uint256 starttime, uint skipEpoch) public returns (uint){
    uint n = 3;
    rewards.initialize(address(gov), n);
    uint rewardStep = 1000;
    uint timeStep = 1000;
    uint reward = rewardStep;
    for (uint i=0; i<n; i++) {
      if (i != skipEpoch) {
        rewards.initRewardAmount(reward, starttime, timeStep, i);

        reward += rewardStep;
        starttime += timeStep;
      }
    }

    rewards.approveEpochsConsistency();

    return starttime + timeStep;
  }

  function testSkipEpochInitialize() public {
    uint starttime = 10;

    (bool ret, ) = address(this).call(abi.encodeWithSelector(this.prepareRewarder3.selector, starttime, 0));
    if (ret) {
      emit log_bytes32("prepareRewarder3 fail expected");
      fail();
    }

    hevm.warp(starttime+1);

    (ret, ) = address(rewards).call(abi.encodeWithSelector(rewards.getReward.selector));
    if (ret) {
      emit log_bytes32("getReward fail expected");
      fail();
    }
  }

  function badEpochInitialize(bool crossover) public {
    uint n = 3;
    rewards.initialize(address(gov), n);
    rewards.initRewardAmount(1000, 100, 100, 0);
    rewards.initRewardAmount(1000, 200, crossover ? 101 : 99, 1);
    rewards.initRewardAmount(1000, 300, 100, 2);

    rewards.approveEpochsConsistency();
  }

  function testFailCrossoverEpochInitialize() public {
    badEpochInitialize(true);
  }

  function testFailGapEpochInitializeFail() public {
    badEpochInitialize(false);
  }

  function testInitialize() public {
    uint starttime = 10;
    prepareRewarder3(starttime, 10);
    assertTrue(address(rewards.gov()) == address(gov));

    rewards.registerPairDesc(address(uniPair), address(sadapter), 2, address(this));

    (address gem, address adapter, address staker, uint factor) = rewards.pairDescs(address(uniPair));
    assertEq(address(this), address(staker));
    assertEq(gem, address(uniPair));
    assertEq(adapter, address(sadapter));
    assertEq(factor, 2);

    (gem, adapter, staker, factor) = rewards.pairDescs(address(0x0));
    assertEq(gem, address(0));
    assertEq(adapter, address(0));
    assertEq(staker, address(0));
    assertEq(factor, 0);

    hevm.warp(starttime+1);
    assertEq(rewards.getReward(), 0 );
  }



  function addLiquidityToUser(uint value, User user, UniswapV2Pair pair) public returns (uint) {

    uint myBal = pair.balanceOf(address(this));

    uint uniAmnt = addLiquidityCore(value, pair);
    assertTrue(uniAmnt > 0);
    uint bal = pair.balanceOf(address(user));
    pair.transfer(address(user), uniAmnt);

    assertEqM(uniAmnt+bal, pair.balanceOf(address(user)), "addLtu uniAmnt");
    assertEqM(myBal, pair.balanceOf(address(this)), "addLtu this uniAmnt");

    return uniAmnt;
  }

  function addLiquidityUni3ToUser(uint value, User user) public returns (uint) {
    return addLiquidityToUser(value, user, uniPair3);
  }



  function testBase() public {
    uint starttime = 10;
    uint finishTime = prepareRewarder3(starttime, 10);

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(this));

    assertEqM(uniPair3.balanceOf(address(this)), 0, "this bal 1");

    hevm.warp(starttime+1);

    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 I");

    uint uniAmnt = addLiquidityUni3ToUser(10000, user1);

    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 II");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal");

    user1.stake(rewards, uniPair3, uniAmnt);

    assertEqM(uniPair3.balanceOf(address(rewards)), uniAmnt, "rewards bal");
    assertEqM(uniPair3.balanceOf(address(user1)), 0, "user1 bal 0");

    (bool ret, ) = address(rewards).call(abi.encodeWithSelector(rewards.withdraw.selector, uniAmnt, address(uniPair3)));
    if (ret) {
      emit log_bytes32("withdraw fail expected");
      fail();
    }

    assertEqM(uniPair3.balanceOf(address(rewards)), uniAmnt, "rewards bal III");

    hevm.warp(starttime+finishTime+1);

    user1.withdraw(rewards, uniPair3, uniAmnt);
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 IV");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user bal uniAmnt");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "this bal 2");
  }


}