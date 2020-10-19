pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./uni.sol";

contract Hevm {
    function warp(uint256) public;
}


import "./rewardDecay.sol";

contract UniswapV2Pair is DSToken("UNIv2") {

    constructor(address _t0, address _t1) public {
      decimals = 18;
      t0 = _t0;
      t1 = _t1;
    }

    address t0;
    address t1;
    uint112 reserve0;
    uint112 reserve1;

    function token0() external view returns (address) {
      return t0;
    }

    function token1() external view returns (address) {
      return t1;
    }

    function setReserve0(uint112 _reserve0) external {
      reserve0 = _reserve0;
    }

    function setReserve1(uint112 _reserve1) external {
      reserve1 = _reserve1;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 blockTimestampLast) {
      _reserve0 = reserve0;
      _reserve1 = reserve1;
      blockTimestampLast = 0;
    }
}

contract Token0 is DSToken("TOKEN0") {
    constructor(uint d) public {
      decimals = d;
    }
}

contract Token1 is DSToken("TOKEN1") {
    constructor(uint d) public {
      decimals = d;
    }
}

contract Token2 is DSToken("TOKEN2") {
    constructor(uint d) public {
      decimals = d;
    }
}

contract Token3 is DSToken("TOKEN3") {
    constructor(uint d) public {
      decimals = d;
    }
}

contract Token4 is DSToken("TOKEN4") {
    constructor(uint d) public {
      decimals = d;
    }
}


contract VatMock {
    function slip(bytes32,address,int) external {
    }
    function move(address,address,uint) external {
    }
}


contract User {
  bytes32 body;


  function getReward(StakingRewards rewards) public returns (uint256) {
    return rewards.getReward();
  }
}

contract RewardDecayTest is DSTest {

  DSToken token0;
  DSToken token1;
  DSToken token2;
  DSToken token3;
  DSToken token4;
  UniswapV2Pair uniPair;
  UniswapV2Pair uniPair2;
  UniswapV2Pair uniPair3;
  UniswapV2Pair uniPair4;
  DSToken gov;
  UniswapAdapterForStables sadapter;
  StakingRewardsDecay rewards;
  Hevm hevm;

  User user1;
  User user2;

  uint constant totalRewardsMul =  1e18;
  uint totalRewards =   100000*totalRewardsMul;
  uint rewardDuration = 1000000;

  function setUp() public {
    user1 = new User();
    user2 = new User();

    gov = new DSToken("GOV");
    token0 = new Token0(18);
    token1 = new Token1(8);
    token2 = new Token2(24);
    token3 = new Token3(6);
    token4 = new Token4(6);
    sadapter = new UniswapAdapterForStables();

    uniPair = new UniswapV2Pair(address(token0), address(token1));
    uniPair2 = new UniswapV2Pair(address(token1), address(token2));
    uniPair3 = new UniswapV2Pair(address(token0), address(token2));
    uniPair4 = new UniswapV2Pair(address(token3), address(token4));

    rewards = new StakingRewardsDecay();

    gov.mint(address(rewards), totalRewards);

    hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);//get hevm instance
  }

  function bucksToPair(uint v, DSToken t, UniswapV2Pair pair) internal returns (uint) {
    uint bal = v * (uint(10) ** t.decimals());
    t.mint(bal);
    t.transfer(address(pair), bal);

    (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

    if (address(t) == pair.token0()) {
      pair.setReserve0(uint112(bal)+reserve0);
    } else {
      pair.setReserve1(uint112(bal)+reserve1);
    }
    return bal;
  }

  function sqrt(uint y) internal pure returns (uint z) {
      if (y > 3) {
          z = y;
          uint x = y / 2 + 1;
          while (x < z) {
              z = x;
              x = (y / x + x) / 2;
          }
      } else if (y != 0) {
          z = 1;
      }
  }

  function assertEqM(uint a, uint b, bytes32 m) internal {
      if (a != b) {
          emit log_bytes32(m);
          emit log_named_uint("  Expected", b);
          emit log_named_uint("    Actual", a);
          fail();
      }
  }


  function addLiquidityCore(uint v, DSToken t0, DSToken t1, UniswapV2Pair pair) internal returns (uint) {
    uint b1 = bucksToPair(v, t0, pair);
    uint b2 = bucksToPair(v, t1, pair);
    uint l = sqrt(b1 * b2);
    pair.mint(l);
    return l;
  }


  function prepareRewarder3(uint256 starttime, uint skipEpoch) public {
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


  function testBase() public {
    uint starttime = 10;
    prepareRewarder3(starttime, 10);

  }


}