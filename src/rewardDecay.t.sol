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
    gem.approve(address(rewards.holder()), amount);
    rewards.holder().stake(amount, address(gem));
  }

  function stakeNoHolder(StakingRewardsDecay rewards, UniswapV2Pair gem, uint amount) public {
    gem.approve(address(rewards), amount);
    rewards.stake(address(this), amount, address(gem));
  }


  function withdraw(StakingRewardsDecay rewards, UniswapV2Pair gem, uint amount) public {
    rewards.holder().withdraw(amount, address(gem));
  }

  function withdrawNoHolder(StakingRewardsDecay rewards, UniswapV2Pair gem, uint amount) public {
    rewards.withdraw(address(this), amount, address(gem));
  }


  function getReward(StakingRewardsDecay rewards) public returns (uint256) {
    return rewards.getReward();
  }

  function claimAllReward(RewardDecayAggregator rewards) public {
    return rewards.claimReward();
  }
}

contract RewardDecayTest is TestBase {

  StakingRewardsDecay rewards;

  User user1;
  User user2;

  uint constant totalRewardsMul =  1e18;
  uint totalRewards;
  bool vectorizedInit = false;

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

    if (vectorizedInit) {

      assertTrue(skipEpoch == uint(-1));

      uint256[] memory rewardsArr = new uint256[](n);

      for (uint i=0; i<n; i++) {

        rewardsArr[i] = reward;
        totalRewards += reward;

        allTime += timeStep;

        reward += rewardStep;
      }

      rewards.initAllEpochs(rewardsArr, starttime, timeStep);
    }
    else {
      for (uint i=0; i<n; i++) {

        if (i != skipEpoch) {
          rewards.initRewardAmount(reward, starttime, timeStep, i);
          allTime += timeStep;
          totalRewards += reward;

          reward += rewardStep;
          starttime += timeStep;
        }
      }
    }

    gov.mint(address(rewards), totalRewards);
    rewards.approveEpochsConsistency();

    assertEqM(rewards.getTotalRewardTime(), allTime, "getTotalRewardTime");
    assertEqM(rewards.getTotalRewards(), totalRewards, "getTotalRewards");

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

    rewards.registerPairDesc(address(uniPair), address(sadapter), 2, "1");

    assertFail(address(rewards), abi.encodeWithSelector(rewards.registerPairDesc.selector,
                                                        address(uniPair2), address(sadapter), 2, bytes32("1")),
               "reg..PairDesc fail dub");

    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, "2");

    (address gem, address adapter, address staker, uint factor, bytes32 name) =
          rewards.pairDescs(address(uniPair));
    assertEq(address(0), address(staker));
    assertEq(gem, address(uniPair));
    assertEq(adapter, address(sadapter));
    assertEq(factor, 2);
    assertEq(name, bytes32("1"));

    (address gem2, address adapter2, address staker2, uint factor2, bytes32 name2) =
          rewards.pairDescs(address(uniPair2));


    assertEq(address(0), address(staker2));
    assertEq(gem2, address(uniPair2));
    assertEq(adapter2, address(sadapter));
    assertEq(factor2, 1);
    assertEq(name2, bytes32("2"));

    assertEq(rewards.pairNameToGem("2"), gem2);
    assertEq(rewards.pairNameToGem("1"), gem);
    assertEq(rewards.pairNameToGem(""), address(0));
    assertEq(rewards.pairNameToGem("100"), address(0));
    assertEq(rewards.pairNameToGem("10000"), address(0));


    (gem, adapter, staker, factor, name) = rewards.pairDescs(address(0x0));
    assertEq(gem, address(0));
    assertEq(adapter, address(0));
    assertEq(staker, address(0));
    assertEq(factor, 0);
    assertEq(name, "");


    rewards.registerPairDesc(address(uniPair), address(sadapter), 2, "100");

    (gem, adapter, staker, factor, name) = rewards.pairDescs(address(uniPair));

    assertEq(address(0), address(staker));
    assertEq(gem, address(uniPair));
    assertEq(adapter, address(sadapter));
    assertEq(factor, 2);
    assertEq(name, bytes32("100"));

    (gem2, adapter2, staker2, factor2, name2) =rewards.pairDescs(address(uniPair2));

    assertEq(address(0), address(staker2));
    assertEq(gem2, address(uniPair2));
    assertEq(adapter2, address(sadapter));
    assertEq(factor2, 1);
    assertEq(name2, bytes32("2"));


    assertEq(rewards.pairNameToGem("2"), gem2);
    assertEq(rewards.pairNameToGem("1"), address(0));
    assertEq(rewards.pairNameToGem(""), address(0));
    assertEq(rewards.pairNameToGem("100"), gem);
    assertEq(rewards.pairNameToGem("10000"), address(0));


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


  struct LocalsBaseTest {
    address gem;
    uint avail;
    uint locked;
    uint lockedValue;
    uint rewardPerHour;
    uint starttime;
    uint allTime;
    uint uniAmnt2;
  }


  function baseImpl(bool getRewardOnHL2, bool user2Stake, bool user2x2) public {
    LocalsBaseTest memory locals;
    locals.starttime = 10;

    locals.allTime = prepareRewarder3(locals.starttime, 10);

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, "1");
    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, "2");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "this bal 1");

    hevm.warp(locals.starttime+1);

    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0 I");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 I");

    uint value1 = 10000;
    uint value2 = user2x2 ? 20000 : 10000;


    uint uniAmnt = addLiquidityToUser(value1, user1, uniPair3);

    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0 II");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 II");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal");

    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, uniAmnt),
               "user2.stake fail expected");

    assertFail(address(user1), abi.encodeWithSelector(user1.stakeNoHolder.selector, rewards, uniPair3, uniAmnt),
               "user1.stake fail expected NH");

    assertEq(rewards.earned(address(user1)), 0);

    (locals.gem, locals.avail, locals.locked, locals.lockedValue, locals.rewardPerHour) =
      rewards.getPairInfo("1", address(user1));

    assertEq(locals.gem, address(uniPair3));
    assertEqM(locals.avail, uniAmnt, "user1 avail I");
    assertEqM(locals.locked, 0, "user1 locked I");
    assertEqM(locals.lockedValue, 0, "user1 lockedValue I");
    assertEqM(locals.rewardPerHour, 3600, "user1 rewardPerHour I");


    assertEqM(rewards.balanceOf(address(user1)), 0, "rewards user1 bal");
    user1.stake(rewards, uniPair3, uniAmnt);
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), uniAmnt, "uniPair3 bal hld uniAmnt");

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "rewards user1 bal I");

    (locals.gem, locals.avail, locals.locked, locals.lockedValue, locals.rewardPerHour) =
      rewards.getPairInfo("1", address(user1));

    assertEq(locals.gem, address(uniPair3));
    assertEqM(locals.avail, 0, "user1 avail II");
    assertEqM(locals.locked, uniAmnt, "user1 locked II");
    assertEqM(locals.lockedValue, 2*value1, "user1 lockedValue II");
    assertEqM(locals.rewardPerHour, 3600, "user1 rewardPerHour II");


    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, uniAmnt),
              "user2.stake fail expected");


    locals.uniAmnt2 = addLiquidityToUser(value2, user2, uniPair2);
    assertEqM(locals.uniAmnt2, (user2x2 ? 2:1) * 100000000000000000000, "locals.uniAmnt2");

    assertFail(address(user2), abi.encodeWithSelector(user2.stake.selector, rewards, uniPair3, locals.uniAmnt2/2),
              "user2.stake fail II expected");

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "rewards user1 bal II");
    assertEqM(rewards.balanceOf(address(user2)), 0, "rewards user2 bal I");


    assertEqM(uniPair3.balanceOf(address(rewards.holder())), uniAmnt, "rewards.hld bal");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0");
    assertEqM(uniPair3.balanceOf(address(user1)), 0, "user1 bal 0");
    assertEqM(uniPair3.balanceOf(address(user2)), 0, "user2 bal2 0");
    assertEqM(uniPair2.balanceOf(address(user2)), locals.uniAmnt2, "user2 bal");

    assertFail(address(rewards), abi.encodeWithSelector(rewards.holder().withdraw.selector, uniAmnt, address(uniPair3)),
              "withdraw fail expected");

    assertEqM(uniPair3.balanceOf(address(rewards.holder())), uniAmnt, "rewards.hld bal III");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 III");


    hevm.warp(locals.starttime+locals.allTime/2);
    assertEqM(locals.allTime/2, 1500, "allTime/2==1500");

    assertEqM(rewards.balanceOf(address(user1)), 2*value1, "u1 rewards.balanceOf hl2");

    assertEqM(rewards.calcCurrentEpoch(), 1, "rewards.calcCurrentEpoch 1");
    uint rewardHL2 = 2000-1;
    assertEqM(rewards.earned(address(user1)), rewardHL2, "u1 earned on hl2");

    if (getRewardOnHL2)
      assertEqM(user1.getReward(rewards), rewardHL2, "u1 getReward hl2");

    if (user2Stake) {
      assertEqM(uniPair2.balanceOf(address(user2)), locals.uniAmnt2, "user2 bal II");
      assertEqM(uniPair2.balanceOf(address(rewards.holder())), 0, "rewards.hld bal uni2 0 III");
      assertEqM(uniPair2.balanceOf(address(rewards)), 0, "rewards bal uni2 0 III");
      user2.stake(rewards, uniPair2, locals.uniAmnt2);
      assertEqM(uniPair2.balanceOf(address(rewards.holder())), locals.uniAmnt2, "rewards.hld bal uni2 III");
      assertEqM(uniPair2.balanceOf(address(rewards)), 0, "rewards bal uni2 0 III");
      assertEqM(uniPair2.balanceOf(address(user2)), 0, "user2 bal II 0");
    }


    hevm.warp(locals.starttime+locals.allTime+1);

    assertFail(address(user1), abi.encodeWithSelector(user1.withdrawNoHolder.selector, rewards, uniPair3, uniAmnt),
               "user1.withdraw fail expected NH");

    user1.withdraw(rewards, uniPair3, uniAmnt);
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0 IV");
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

    if (user2Stake) {
      (locals.gem, locals.avail, locals.locked, locals.lockedValue, locals.rewardPerHour) =
        rewards.getPairInfo("2", address(user2));

      assertEq(locals.gem, address(uniPair2));
      assertEqM(locals.avail, 0, "user2 avail I");
      assertEqM(locals.locked, locals.uniAmnt2, "user2 locked I");
      assertEqM(locals.lockedValue, 2*value2, "user2 lockedValue I");
      assertEqM(locals.rewardPerHour, 3*3600, "user2 rewardPerHour I");

      user2.withdraw(rewards, uniPair2, locals.uniAmnt2/2);

      (locals.gem, locals.avail, locals.locked, locals.lockedValue, locals.rewardPerHour) =
        rewards.getPairInfo("2", address(user2));

      assertEq(locals.gem, address(uniPair2));
      assertEqM(locals.avail, locals.uniAmnt2/2, "user2 avail II");
      assertEqM(locals.locked, locals.uniAmnt2/2, "user2 locked II");
      assertEqM(locals.lockedValue, value2, "user2 lockedValue II");
      assertEqM(locals.rewardPerHour, 3*3600, "user2 rewardPerHour II");

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
    timeImpl(0);
  }

  function testTime1() public {
    timeImpl(1);
  }

  function testTime0Vec() public {
    vectorizedInit = true;
    timeImpl(0);
  }

  function timeImpl(uint shift) public {

    TestTimeVars memory vars;
    vars.n = 90;
    uint timeStep = 3600*24;
    uint rewardStep = 1000000000;
    uint starttime = 10;
    uint skipEpoch = uint(-1);
    uint allTime = prepareRewarder(vars.n, starttime, rewardStep, timeStep, skipEpoch);
    assertEqM(allTime, timeStep*vars.n, "allTime==timeStep*n");

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, "1");

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


  event withdrawError(uint256 amount, address gem);

  function testEventsHackInUniOrRewarder() public {
    uint starttime = 10;

    prepareRewarder3(starttime, 10);

    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, "1");

    uint value1 = 10000;
    uint uniAmnt = addLiquidityToUser(value1, user1, uniPair3);

    hevm.warp(starttime+1);

    uniPair3.setThrownExc();

    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal");
    assertEqM(rewards.balanceOf(address(user1)), 0, "rewards user1 bal");

    assertFail(address(user1), abi.encodeWithSelector(user1.stake.selector, rewards, uniPair3, uniAmnt),
               "user1.stake fail expected");

    assertEqM(rewards.balanceOf(address(user1)), 0, "rewards user1 bal II");
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0 II");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 II");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal II");

    uniPair3.resetThrownExc();
    user1.stake(rewards, uniPair3, uniAmnt);

    assertEqM(rewards.balanceOf(address(user1)), value1*2, "rewards user1 bal III");
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), uniAmnt, "rewards.hld bal 0 III");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 III");
    assertEqM(uniPair3.balanceOf(address(user1)), 0, "user1 bal III");


    assertFail(address(user1), abi.encodeWithSelector(user1.withdraw.selector, rewards, uniPair3, uniAmnt+1),
               "user1.withdraw fail expected");

    assertEqM(rewards.balanceOf(address(user1)), value1*2, "rewards user1 bal IIIb");
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), uniAmnt, "rewards.hld bal 0 IIIb");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 IIIb");
    assertEqM(uniPair3.balanceOf(address(user1)), 0, "user1 bal IIIb");

    uniPair3.setThrownExc();

    expectEventsExact(address(rewards.holder()));
    emit withdrawError(uniAmnt, address(uniPair3));
    //unfortunatelly event testing dosn't working now
    //https://github.com/dapphub/dapptools/issues/18

    user1.withdraw(rewards, uniPair3, uniAmnt);

    assertEqM(rewards.balanceOf(address(user1)), value1*2, "rewards user1 bal IV");
    assertEqM(uniPair3.balanceOf(address(rewards.holder())), 0, "rewards.hld bal 0 IV");
    assertEqM(uniPair3.balanceOf(address(rewards)), 0, "rewards bal 0 IV");
    assertEqM(uniPair3.balanceOf(address(user1)), uniAmnt, "user1 bal IV");

  }


  function testEpochStartTimeAfterCreate() public {
    hevm.warp(100);
    uint starttime = 90;
    rewards.initialize(address(gov), 10);

    assertFail(address(rewards), abi.encodeWithSelector(rewards.initRewardAmount.selector,
          1000, starttime, 10, 0), "init have to fail");

    starttime = 100;

    rewards.initRewardAmount(1000, starttime, 10, 0);
  }


  function testRewardDecayActions() public {
    uint starttime = 100;

    prepareRewarder3(starttime, 10);

    StakingRewardsDecay rewards2 = new StakingRewardsDecay();

    uint n = 3;
    rewards2.initialize(address(gov), n);
    rewards2.initRewardAmount(1000, starttime, 100, 0);
    rewards2.initRewardAmount(1000, 200, 100, 1);
    rewards2.initRewardAmount(1000, 300, 100, 2);
    gov.mint(address(rewards2), 3000);
    rewards2.approveEpochsConsistency();

    rewards.registerPairDesc(address(uniPair), address(sadapter), 1, "1");
    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, "2");
    rewards2.registerPairDesc(address(uniPair2), address(sadapter), 1, "3");


    hevm.warp(starttime+1);

    uint value1 = 10000;

    uint uniAmnt1 = addLiquidityToUser(value1, user1, uniPair3);
    uint uniAmnt2 = addLiquidityToUser(value1, user2, uniPair2);
    uint uniAmnt2_ = addLiquidityToUser(value1, user2, uniPair);

    user1.stake(rewards, uniPair3, uniAmnt1);
    user2.stake(rewards2, uniPair2, uniAmnt2);
    user2.stake(rewards, uniPair, uniAmnt2_);

    hevm.warp(starttime+1000);
    uint earned1 = rewards.earned(address(user1));
    uint earned2 = rewards2.earned(address(user2));
    uint earned2_ = rewards.earned(address(user2));
    assertEqM(earned1, 499, "earned1");
    assertEqM(earned2, 2990, "earned2");
    assertEqM(earned2_, 499, "earned2_");

    assertFail(address(rewards), abi.encodeWithSelector(rewards.getRewardEx.selector, address(user2)),
      "fail expected agg 2");

    assertFail(address(rewards2), abi.encodeWithSelector(rewards2.getRewardEx.selector, address(user1)),
      "fail expected agg 1");

    RewardDecayAggregator rewardsArr = new RewardDecayAggregator(address(rewards), address(rewards2));
    RewardDecayAggregator rewardsArrEnemy = new RewardDecayAggregator(address(rewards), address(rewards2));

    rewards2.setupAggregator(address(rewardsArr));
    rewards.setupAggregator(address(rewardsArr));

    assertEqM(gov.balanceOf(address(user1)), 0, "gov bal u1 0");
    assertEqM(gov.balanceOf(address(user2)), 0, "gov bal u2 0");

    assertFail(address(user1), abi.encodeWithSelector(user1.claimAllReward.selector, rewardsArrEnemy),
      "fail expected u1");
    assertFail(address(user2), abi.encodeWithSelector(user2.claimAllReward.selector, rewardsArrEnemy),
      "fail expected u2");

    assertEqM(gov.balanceOf(address(user1)), 0, "gov bal u1 0");
    assertEqM(gov.balanceOf(address(user2)), 0, "gov bal u2 0");

    user1.claimAllReward(rewardsArr);
    user2.claimAllReward(rewardsArr);

    assertEqM(gov.balanceOf(address(user1)), earned1, "gov bal u1");
    assertEqM(gov.balanceOf(address(user2)), earned2+earned2_, "gov bal u2");
  }

}