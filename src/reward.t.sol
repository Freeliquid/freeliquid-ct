// Copyright (C) 2019 Maker Ecosystem Growth Holdings, INC.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./uni.sol";

contract Hevm {
    function warp(uint256) public;
}


import "./reward.sol";

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

  function joinHelper(GemJoinWithReward j, uint l, address urn) public {
    j.gem().approve(address(j), l);
    j.join(urn, l);
  }


  function exit(GemJoinWithReward j, uint l) public {
    j.exit(address(this), l);
  }

  function getReward(StakingRewards rewards) public returns (uint256) {
    return rewards.getReward();
  }
}

contract RewardTest is DSTest {

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
  StakingRewards rewards;
  GemJoinWithReward join;
  GemJoinWithReward join2;
  GemJoinWithReward join3;
  GemJoinWithReward join4;
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

    rewards = new StakingRewards();
    address vat = address(new VatMock());

    join = new GemJoinWithReward(vat, "testilk", address(uniPair), address(rewards));
    join2 = new GemJoinWithReward(vat, "testilk2", address(uniPair2), address(rewards));
    join3 = new GemJoinWithReward(vat, "testilk3", address(uniPair3), address(rewards));
    join4 = new GemJoinWithReward(vat, "testilk4", address(uniPair4), address(rewards));

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


  function addLiquidity(uint v) public returns (uint) {
    return addLiquidityCore(v, token0, token1, uniPair);
  }

  function addLiquidity2(uint v) public returns (uint) {
    return addLiquidityCore(v, token1, token2, uniPair2);
  }

  function addLiquidity3(uint v) public returns (uint) {
    return addLiquidityCore(v, token0, token2, uniPair3);
  }

  function testVerifyConstruction() public {
    assertTrue(rewards.deployer() == address(this));
  }

  function prepareRewarder(uint256 starttime) public {
    rewards.initialize(address(gov), rewardDuration, totalRewards, starttime, false);
  }

  function testInitialize() public {
    prepareRewarder(10);
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
  }

  function joinHelper(GemJoinWithReward j, uint l) public {
    j.gem().approve(address(j), l);
    j.join(address(this), l);
  }

  function joinHelperOwner(GemJoinWithReward j, uint l, address owner) public {
    j.gem().approve(address(j), l);
    j.join(owner, l);
  }


  function testUniAdapter() public {
    uint v = 10000;
    uint l = addLiquidity(v);
    assertEq(l, uniPair.totalSupply());


    (uint112 reserve0, uint112 reserve1, ) = uniPair.getReserves();

    assertEq(reserve0, v * uint(10)**18);
    assertEq(reserve1, v * uint(10)**8);

    assertEq(reserve0, token0.balanceOf(address(uniPair)));
    assertEq(reserve1, token1.balanceOf(address(uniPair)));

    uint r = sadapter.calc(address(uniPair), l, 1);
    assertEq(r, v * 2);

    uint v2 = 30000;
    uint l2 = addLiquidity(v2);

    r = sadapter.calc(address(uniPair), l2, 1);
    assertEq(r, v2 * 2);


    v = 171234;
    l = addLiquidity(v);

    r = sadapter.calc(address(uniPair), l, 1);
    assertEq(r, v * 2);

    r = sadapter.calc(address(uniPair), l2, 1);
    assertEq(r, v2 * 2);

    v = 3;
    l = addLiquidity(v);

    r = sadapter.calc(address(uniPair), l, 1);
    assertEq(r, v * 2);

    r = sadapter.calc(address(uniPair), l2, 1);
    assertEq(r, v2 * 2);
  }

  function testRightsForStake() public {
    uint starttime = 10;
    prepareRewarder(starttime);
    rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));
    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(this));

    uint v = 10000;
    uint l = addLiquidity(v);
    uint l2 = addLiquidity2(v);

    hevm.warp(starttime+1);


    (bool ret, ) = address(rewards).call(abi.encodeWithSelector(rewards.stake.selector, l, address(uniPair), address(this)));
    if (ret) {
      emit log_bytes32("stake must fail,no rights");
      fail();
    }

    rewards.stake(l2, address(uniPair2), address(this));
  }



  function testStakeUnstake() public {
    uint starttime = 10;
    prepareRewarder(starttime);
    rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));

    uint v = 10000;
    uint l = addLiquidity(v);

    assertEq(uniPair.balanceOf(address(this)), l);
    assertEq(uniPair.balanceOf(address(rewards)), 0);
    uniPair.approve(address(rewards), l);

    assertEq(rewards.balanceOf(address(this)), 0);
    assertEq(rewards.totalSupply(), 0);

    (bool ret, ) = address(this).call(abi.encodeWithSelector(this.joinHelper.selector, address(join), l));
    if (ret) {
      emit log_bytes32("join.join fail expected");
      fail();
    }




    hevm.warp(starttime+1);
    uint256 rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady, 0, "rewardReady 0");

    joinHelper(join, l);


    hevm.warp(starttime+rewardDuration/2+1);
    rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady, totalRewards/2, "rewardReady totalRewards/2");




    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(join)), l);

    assertEq(rewards.balanceOf(address(this)), v*2);
    assertEq(rewards.totalSupply(), v*2);


    uint v2 = 110000;
    uint l2 = addLiquidity(v2);

    assertEq(uniPair.balanceOf(address(this)), l2);
    assertEq(uniPair.balanceOf(address(join)), l);
    uniPair.approve(address(rewards), l2);

    joinHelper(join, l2);
    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(join)), l+l2);

    assertEq(rewards.balanceOf(address(this)), v*2+v2*2);
    assertEq(rewards.totalSupply(), v*2+v2*2);

    hevm.warp(starttime+rewardDuration*400/500+1);
    rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady, totalRewards*400/500, "rewardReady totalRewards 4/5 a");


    uint w = l2*30/100;
    join.exit(address(this), w);
    assertEq(uniPair.balanceOf(address(this)), w);
    assertEq(uniPair.balanceOf(address(join)), l+l2-w);

    rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady, totalRewards*400/500, "rewardReady totalRewards 4/5 b");


    uint rem = sadapter.calc(address(uniPair), l+l2-w, 1);

    assertEq(rewards.balanceOf(address(this)), rem);
    assertEq(rewards.totalSupply(), rem);

    hevm.warp(starttime+rewardDuration*90/100+1);
    rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady+1, totalRewards*90/100, "rewardReady totalRewards 9/10");

    hevm.warp(starttime+rewardDuration+2);
    rewardReady = rewards.earned(address(this));
    assertEqM(rewardReady+1*totalRewardsMul+1, totalRewards, "rewardReady totalRewards 100%");

    (ret, ) = address(join).call(abi.encodeWithSelector(join.exit.selector, address(this), l+l2-w+1));
    if (ret) {
      emit log_bytes32("rewards.withdraw fail expected");
      fail();
    }

    assertEq(uniPair.balanceOf(address(this)), w);
    assertEq(uniPair.balanceOf(address(join)), l+l2-w);

    join.exit(address(this), l+l2-w);
    assertEq(uniPair.balanceOf(address(this)), l+l2);
    assertEq(uniPair.balanceOf(address(join)), 0);

    assertEq(rewards.balanceOf(address(this)), 0);
    assertEq(rewards.totalSupply(), 0);

  }

  struct StakeUnstacke3UniVars {
    uint v;
    uint l;
    uint v2;
    uint l2;
    uint v22;
    uint l22;
    uint v3;
    uint l3;
    uint w;
    uint rem;
    uint w3;
    uint rem3;
    uint w12;
    uint rem12;
  }


  function testStakeUnstacke3Uni() public {
    uint starttime = 10;
    prepareRewarder(starttime);
    rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));
    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(join2));
    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));

    uniPair.approve(address(rewards));
    uniPair2.approve(address(rewards));
    uniPair3.approve(address(rewards));

    StakeUnstacke3UniVars memory vars;

    vars.v = 10000;
    vars.l = addLiquidity(vars.v/2);

    hevm.warp(starttime+1);
    joinHelper(join, vars.l);

    assertEqM(uniPair.balanceOf(address(this)), 0, "-4");
    assertEqM(uniPair.balanceOf(address(join)), vars.l, "-3");

    assertEqM(rewards.balanceOf(address(this)), vars.v, "balanceOf vars.v");
    assertEqM(rewards.totalSupply(), vars.v, "totalSupply vars.v");


    vars.v2 = 20000;
    vars.l2 = addLiquidity2(vars.v2/2);
    joinHelper(join2, vars.l2);

    assertEqM(uniPair.balanceOf(address(this)), 0, "-2");
    assertEqM(uniPair.balanceOf(address(join)), vars.l, "-1");

    assertEqM(uniPair2.balanceOf(address(this)), 0, "1");
    assertEqM(uniPair2.balanceOf(address(join2)), vars.l2, "2");

    assertEqM(rewards.balanceOf(address(this)), vars.v2+vars.v, "3");
    assertEqM(rewards.totalSupply(), vars.v2+vars.v, "4");

    vars.v22 = 1000;
    vars.l22 = addLiquidity2(vars.v22/2);
    joinHelper(join2, vars.l22);

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(join)), vars.l);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "21");
    assertEqM(uniPair2.balanceOf(address(join2)), vars.l2+vars.l22, "22");

    assertEqM(rewards.balanceOf(address(this)), vars.v22+vars.v2+vars.v, "23");
    assertEqM(rewards.totalSupply(), vars.v22+vars.v2+vars.v, "24");


    vars.v3 = 200000;
    vars.l3 = addLiquidity3(vars.v3/2);
    joinHelper(join3, vars.l3);

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(join)), vars.l);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "31");
    assertEqM(uniPair2.balanceOf(address(join2)), vars.l2+vars.l22, "32");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "33");
    assertEqM(uniPair3.balanceOf(address(join3)), vars.l3, "34");


    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v, "35");
    assertEqM(rewards.totalSupply(), vars.v3+vars.v22+vars.v2+vars.v, "36");

/////////////////////
    vars.w = vars.l*30/100;
    join.exit(address(this), vars.w);
    assertEq(uniPair.balanceOf(address(this)), vars.w);
    assertEq(uniPair.balanceOf(address(join)), vars.l-vars.w);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "41");
    assertEqM(uniPair2.balanceOf(address(join2)), vars.l2+vars.l22, "42");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "43");
    assertEqM(uniPair3.balanceOf(address(join3)), vars.l3, "44");


    vars.rem = sadapter.calc(address(uniPair), vars.w, 1);

    assertEq(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem);

/////////////////////
    vars.w3 = vars.l3*50/100;
    join3.exit(address(this), vars.w3);
    assertEq(uniPair.balanceOf(address(this)), vars.w);
    assertEq(uniPair.balanceOf(address(join)), vars.l-vars.w);

    assertEq(uniPair3.balanceOf(address(this)), vars.w3);
    assertEq(uniPair3.balanceOf(address(join3)), vars.l3-vars.w3);


    vars.rem3 = sadapter.calc(address(uniPair3), vars.w3, 1);

    assertEq(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem-vars.rem3);


/////////////////////
    vars.w12 = vars.l-vars.w;
    join.exit(address(this), vars.w12);
    assertEqM(uniPair.balanceOf(address(this)), vars.w+vars.w12, "511");
    assertEqM(uniPair.balanceOf(address(this)), vars.l, "512");
    assertEqM(uniPair.balanceOf(address(join)), 0, "513");

    assertEqM(uniPair2.balanceOf(address(this)), 0, "51");
    assertEqM(uniPair2.balanceOf(address(join2)), vars.l2+vars.l22, "52");

    assertEq(uniPair3.balanceOf(address(this)), vars.w3);
    assertEq(uniPair3.balanceOf(address(join3)), vars.l3-vars.w3);


    vars.rem12 = sadapter.calc(address(uniPair), vars.w12, 1);

    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem-vars.rem3-vars.rem12, "55");
    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2-vars.rem3, "56");
    assertEqM(rewards.totalSupply(), vars.v3+vars.v22+vars.v2-vars.rem3, "57");

  }

  function rewardForTwoUsers(uint value1, uint value2,
                             uint amntMult,
                             uint expectEarned1,
                             uint expectEarned2,
                             int err,
                             bool claimTimeInvariant1) public {

    uint starttime = 10;
    prepareRewarder(starttime);
    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));
    rewards.registerPairDesc(address(uniPair4), address(sadapter), 1, address(join4));

    uniPair3.approve(address(rewards));
    uniPair4.approve(address(rewards));



    uint uniPair3Amnt = addLiquidityCore(value1, token0, token2, uniPair3);
    uint uniPair4Amnt = addLiquidityCore(value2, token3, token4, uniPair4);
    uniPair3.transfer(address(user1), uniPair3Amnt);
    uniPair4.transfer(address(user2), uniPair4Amnt);

    assertEqM(uniPair3Amnt/uniPair4Amnt, amntMult, "uniPair3Amnt/uniPair4Amnt");
    assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt");
    assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt");

    hevm.warp(starttime+1);

    user1.joinHelper(join3, uniPair3Amnt, address(this));
    user2.joinHelper(join4, uniPair4Amnt, address(this));

    assertEqM(0, uniPair3.balanceOf(address(user1)), "uniPair3Amnt 0");
    assertEqM(0, uniPair4.balanceOf(address(user2)), "uniPair4Amnt 0");

    assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3");
    assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4");


    assertEqM(2*value1, rewards.calcCheckValue(uniPair3Amnt, address(uniPair3), false), "uniPair3Amnt value");
    assertEqM(2*value2, rewards.calcCheckValue(uniPair4Amnt, address(uniPair4), false), "uniPair4Amnt value");

    assertEqM(rewards.earned(address(user1)), 0, "rewardReadyOnStart1 is 0");
    assertEqM(rewards.earned(address(user2)), 0, "rewardReadyOnStart2 is 0");

    hevm.warp(starttime+rewardDuration/2+1);

    uint earned1 = rewards.earned(address(user1));
    uint earned2 = rewards.earned(address(user2));
    assertEqM(earned1, expectEarned1, "rewardReadyOnHL1 is 1/4");
    assertEqM(earned2, expectEarned2, "rewardReadyOnHL2 is 1/4");
    assertEqM(uint(int256(earned1+earned2)+err), totalRewards/2, "tot rewardReadyOnHL2 is 1/2");

    assertEqM(0, gov.balanceOf(address(user1)), "gov1 bal zero");
    assertEqM(0, gov.balanceOf(address(user2)), "gov2 bal zero");

    assertEqM(totalRewards, gov.balanceOf(address(rewards)), "gov rewards bal full");

    if (!claimTimeInvariant1) {
      assertEqM(earned1, user1.getReward(rewards), "getReward1");
    }
    assertEqM(earned2, user2.getReward(rewards), "getReward2");

    if (!claimTimeInvariant1) {
      assertEqM(rewards.earned(address(user1)), 0, "earned1 0 after claim");
    } else {
      assertEqM(rewards.earned(address(user1)), expectEarned1, "earned1 as expected after claim");
    }
    assertEqM(rewards.earned(address(user2)), 0, "earned2 0 after claim");

    if (!claimTimeInvariant1) {
      assertEqM(earned1, gov.balanceOf(address(user1)), "gov1 bal");
    } else {
      assertEqM(0, gov.balanceOf(address(user1)), "gov1 bal zero after claim");
    }
    assertEqM(earned2, gov.balanceOf(address(user2)), "gov2 bal");

    if (!claimTimeInvariant1) {
      assertEqM(totalRewards-(earned1+earned2), gov.balanceOf(address(rewards)), "gov rewards bal was spent inv");
    } else {
      assertEqM(totalRewards-(earned2), gov.balanceOf(address(rewards)), "gov rewards bal was spent");
    }

    user1.exit(join3, uniPair3Amnt);

    assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt user1 exit");
    assertEqM(0, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3 exit");

    hevm.warp(starttime+rewardDuration*2); //to the future

    uint earned1f = rewards.earned(address(user1));
    uint earned2f = rewards.earned(address(user2));
    if (!claimTimeInvariant1) {
      assertEqM(earned1f, 0, "rewardReadyInFuture1 is 0");
    } else {
      assertEqM(earned1f, expectEarned1, "rewardReadyInFuture1 is 0");
    }
    assertEqM(earned2f/totalRewardsMul+1, (totalRewards-(earned1+earned2))/totalRewardsMul, "rewardReadyInFuture2 is remain");

    if (!claimTimeInvariant1) {
      assertEqM(0, user1.getReward(rewards), "getReward1f is 0");
    } else {
      assertEqM(earned1f, user1.getReward(rewards), "getReward1f is 0");
    }
    assertEqM(earned2f, user2.getReward(rewards), "getReward2 is remain");

    assertEqM(earned1, gov.balanceOf(address(user1)), "gov1f bal");
    assertEqM(earned2+earned2f, gov.balanceOf(address(user2)), "gov2f bal");

    assertEqM(totalRewards-(earned1+earned2+earned2f), gov.balanceOf(address(rewards)), "gov rewards bal near 0");
    assertEqM(gov.balanceOf(address(rewards))/totalRewardsMul, 1, "gov rewards bal is 1");

    assertEqM(0, user1.getReward(rewards), "getReward1ff is 0");
    assertEqM(0, user2.getReward(rewards), "getReward2ff is 0");

    assertEqM(rewards.earned(address(user1)), 0, "earned1f 0 after claim");
    assertEqM(rewards.earned(address(user1)), 0, "earned2f 0 after claim");

    assertEqM(earned1, gov.balanceOf(address(user1)), "gov1f bal");
    assertEqM(earned2+earned2f, gov.balanceOf(address(user2)), "gov2f bal");

    hevm.warp(starttime+rewardDuration*3); //to the future x3

    assertEqM(rewards.earned(address(user1)), 0, "earned1fff 0");
    assertEqM(rewards.earned(address(user1)), 0, "earned2fff 0");

    assertEqM(0, user1.getReward(rewards), "getReward1fff is 0");
    assertEqM(0, user2.getReward(rewards), "getReward2fff is 0");

    assertEqM(earned1, gov.balanceOf(address(user1)), "gov1fff bal");
    assertEqM(earned2+earned2f, gov.balanceOf(address(user2)), "gov2fff bal");

    user2.exit(join4, uniPair4Amnt);

    assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt user1 exit");
    assertEqM(0, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join3 exit");

    assertEqM(rewards.earned(address(user1)), 0, "earned1fff 0");
    assertEqM(rewards.earned(address(user1)), 0, "earned2fff 0");

    assertEqM(0, user1.getReward(rewards), "getReward1fff is 0");
    assertEqM(0, user2.getReward(rewards), "getReward2fff is 0");
  }

  function testRewardIsBasedOnUSDEquityNotTokenAmnt() public {
    rewardForTwoUsers(10000, 10000, 1000000000000000, totalRewards/4, totalRewards/4, 0, false);
  }

  function testRewardIsBasedOnUSDEquityDifferentUsers() public {
    rewardForTwoUsers(10000, 20000, 500000000000000, 16666666666666666666666, 33333333333333333333333, 1, false);
  }

  function testRewardIsBasedOnUSDEquityNotTokenAmntClaimInvariant() public {
    rewardForTwoUsers(10000, 10000, 1000000000000000, totalRewards/4, totalRewards/4, 0, true);
  }

  function testRewardIsBasedOnUSDEquityDifferentUsersClaimInvariant() public {
    rewardForTwoUsers(10000, 20000, 500000000000000, 16666666666666666666666, 33333333333333333333333, 1, true);
  }
}
