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

  function getReward(StakingRewardsDecay rewards) public returns (uint256) {
    return rewards.getReward();
  }
}

contract RewardDecayTest is TestBase {

  StakingRewardsDecay rewards;

  User user1;
  User user2;

  uint constant totalRewardsMul =  1e18;
  uint totalRewards;

  function setUp() public {
    super.setUp();

    user1 = new User();
    user2 = new User();

    rewards = new StakingRewardsDecay();
  }


  function prepareRewarder(uint n, uint starttime, uint rewardStep, uint timeStep, uint skipEpoch) public returns (uint) {
    rewards.initialize(address(gov), n);
    totalRewards = 0;
    uint reward = rewardStep;
    uint allTime = 0;
    for (uint i=0; i<n; i++) {
      if (i != skipEpoch) {
        rewards.initRewardAmount(reward, starttime, timeStep, i);
        allTime += timeStep;
        totalRewards += reward;

        reward += rewardStep;
        starttime += timeStep;
      }
    }

    rewards.approveEpochsConsistency();

    gov.mint(address(rewards), totalRewards);

    return allTime;
  }

  function prepareRewarder3(uint256 starttime, uint skipEpoch) public returns (uint) {
    uint n = 3;
    uint rewardStep = 1000;
    uint timeStep = 1000;
    return prepareRewarder(n, starttime, rewardStep, timeStep, skipEpoch);
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
    assertEq(rewards.earned(address(this)), 0);
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


  function testBase1() public {
    baseImpl(true, false, false);
  }

  function testBase2() public {
    baseImpl(false, false, false);
  }

  function testBase1User2() public {
    baseImpl(true, true, false);
  }

  function testBase2User2() public {
    baseImpl(false, true, false);
  }

  function testBase1_u2x2() public {
    baseImpl(true, false, true);
  }

  function testBase2_u2x2() public {
    baseImpl(false, false, true);
  }

  function testBase1User2_u2x2() public {
    baseImpl(true, true, true);
  }

  function testBase2User2_u2x2() public {
    baseImpl(false, true, true);
  }


  function baseImpl(bool getRewardOnHL2, bool user2Stake, bool user2x2) public {
    uint starttime = 10;

    uint allTime = prepareRewarder3(starttime, 10);

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(this));
    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(this));

    assertEqM(uniPair3.balanceOf(address(this)), 0, "this bal 1");

    hevm.warp(starttime+1);

    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 I");

    uint value1 = 10000;
    uint value2 = user2x2 ? 20000 : 10000;

    uint uniAmnt = addLiquidityToUser(value1, user1, uniPair3);

    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 II");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal");

    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, uniAmnt),
               "user2.stake fail expected");

    assertEq(rewards.earned(address(user1)), 0);


    assertEqM(rewards.balanceOf(address(user1)), 0, "rewards user1 bal");
    user1.stake(rewards, uniPair3, uniAmnt);

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "rewards user1 bal I");


    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, uniAmnt),
              "user2.stake fail expected");


    uint uniAmnt2 = addLiquidityToUser(value2, user2, uniPair2);
    assertEqM(uniAmnt2, (user2x2 ? 2:1) * 100000000000000000000, "uniAmnt2");

    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, uniAmnt2/2),
              "user2.stake fail II expected");

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "rewards user1 bal II");
    assertEqM(rewards.balanceOf(address(user2)), 0, "rewards user2 bal I");


    assertEqM(uniPair3.balanceOf(address(rewards)), uniAmnt, "rewards bal");
    assertEqM(uniPair3.balanceOf(address(user1)), 0, "user1 bal 0");
    assertEqM(uniPair3.balanceOf(address(user2)), 0, "user2 bal2 0");
    assertEqM(uniPair2.balanceOf(address(user2)), uniAmnt2, "user2 bal");

    assertFail(address(rewards), abi.encodeWithSelector(rewards.withdraw.selector, uniAmnt, address(uniPair3)),
              "withdraw fail expected");

    assertEqM(uniPair3.balanceOf(address(rewards)), uniAmnt, "rewards bal III");


    hevm.warp(starttime+allTime/2);
    assertEqM(allTime/2, 1500, "allTime/2==1500");

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "u1 rewards.balanceOf hl2");

    assertEqM(rewards.calcCurrentEpoch(), 1, "rewards.calcCurrentEpoch 1");
    uint rewardHL2 = 2000-1;
    assertEqM(rewards.earned(address(user1)), rewardHL2, "u1 earned on hl2");

    if (getRewardOnHL2)
      assertEqM(user1.getReward(rewards), rewardHL2, "u1 getReward hl2");

    if (user2Stake)
      user2.stake(rewards, uniPair2, uniAmnt2);


    hevm.warp(starttime+allTime+1);


    user1.withdraw(rewards, uniPair3, uniAmnt);
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 IV");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user bal uniAmnt");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "this bal 2");

    uint user2Reward = user2Stake ? (user2x2 ? 2666 : 2000) : 0;

    uint err = (user2x2 && user2Stake) ? 1 : 0;

    assertEqM(rewards.earned(address(user1)), totalRewards-1 - (getRewardOnHL2 ? rewardHL2 : 0)-user2Reward-err,
              "earned user1 fn");
    assertEqM(rewards.earned(address(user2)), user2Reward, "earned user2 0 fn");

    assertEqM(gov.balanceOf(address(user1)), getRewardOnHL2 ? rewardHL2 : 0, "gov bal u1 b");
    assertEqM(gov.balanceOf(address(user2)), 0, "gov bal u2 b");
    assertEqM(gov.balanceOf(address(rewards)), totalRewards - (getRewardOnHL2 ? rewardHL2 : 0), "gov bal r b");

    assertEqM(user1.getReward(rewards), totalRewards-1-(getRewardOnHL2 ? rewardHL2 : 0)-user2Reward-err, "getReward u1");

    assertEqM(gov.balanceOf(address(user1)), totalRewards-1-user2Reward-err, "gov bal u1 a");
    assertEqM(gov.balanceOf(address(user2)), 0, "gov bal u2 0 a");
    assertEqM(gov.balanceOf(address(rewards)), 1+user2Reward+err, "gov bal r a");

    if (user2Stake) {
      assertEqM(user2.getReward(rewards), user2Reward, "getReward u2");
      assertEqM(gov.balanceOf(address(user2)), user2Reward, "gov bal u2 a");
      assertEqM(gov.balanceOf(address(rewards)), 1+err, "gov bal r aa");
      assertEqM(gov.balanceOf(address(user1)), totalRewards-1-user2Reward-err, "gov bal u1 aa");

    } else {

      assertEqM(user2.getReward(rewards), 0, "getReward u2 0 aaa");

      assertEqM(gov.balanceOf(address(user1)), totalRewards-1-user2Reward, "gov bal u1 aaa");
      assertEqM(gov.balanceOf(address(user2)), 0, "gov bal u2 0 aaa");
      assertEqM(gov.balanceOf(address(rewards)), 1+user2Reward, "gov bal r aaa");
    }
  }

  struct TestTimeVars {
    uint e;
    uint n;
    uint i;
    uint epochCenter;
  }

  function checkCurrentEpoch(TestTimeVars memory vars) internal {

    uint currentEpoch = rewards.currentEpoch();

    if (vars.e >= vars.n) {
      assertEqM(currentEpoch, vars.n-1, "currentEpoch n-1");
    } else if (vars.e > 0) {

      if (vars.i >= vars.epochCenter) {
        assertEqM(currentEpoch, vars.e, "currentEpoch");
      } else {
        assertEqM(currentEpoch, vars.e-1, "currentEpoch-1");
      }
    } else {
        assertEqM(currentEpoch, 0, "currentEpoch-1 e0");
    }
  }

  function testTime0() public {
    time1Impl(0);
  }

  function testTime1() public {
    time1Impl(1);
  }


  function time1Impl(uint shift) public {

    TestTimeVars memory vars;
    vars.n = 90;
    uint timeStep = 3600*24;
    uint rewardStep = 1000000000;
    uint starttime = 10;
    uint skipEpoch = uint(-1);
    uint allTime = prepareRewarder(vars.n, starttime, rewardStep, timeStep, skipEpoch);
    assertEqM(allTime, timeStep*vars.n, "allTime==timeStep*n");

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(this));

    uint border=2;

    uint value1 = 10000;
    uint uniAmnt = addLiquidityToUser(value1, user1, uniPair3);

    bool needStake = true;

    uint accReward = 0;
    uint lastStakeTime = 0;
    uint rewardRate;

    for (vars.e = 0; vars.e<vars.n+2; vars.e++) {

      vars.epochCenter = timeStep*vars.e+starttime;

      uint start = vars.epochCenter-border;
      if (start < starttime)
        start = starttime;

      for (vars.i=start; vars.i<vars.epochCenter+border; vars.i++) {
        hevm.warp(vars.i);

        // emit log_named_uint("  e", vars.e);
        // emit log_named_uint("  t", vars.i);
        // emit log_named_uint("  needStake", needStake?1:0);
        // emit log_named_uint("  shift", shift);

        if (shift == 0) {
          if (needStake) {
            user1.stake(rewards, uniPair3, uniAmnt);
            lastStakeTime = vars.i;
            rewardRate = vars.i < allTime+starttime ? rewards.getEpochRewardRate(rewards.calcCurrentEpoch()) : 0;

          } else {
            user1.withdraw(rewards, uniPair3, uniAmnt);
            assertTrue(vars.i > lastStakeTime);
            accReward += rewardRate * (vars.i - lastStakeTime);
          }
          needStake = !needStake;

          checkCurrentEpoch(vars);
        }

        if (shift > 0)
          shift--;
      }
    }

    assertEqM(user1.getReward(rewards), accReward, "getRewards");
  }

}