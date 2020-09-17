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

contract Hevm {
    function warp(uint256) public;
}


import "./reward.sol";

contract UniswapV2Pair is DSToken("UNIv2") {

    constructor(address _t0, address _t1) public {
      decimals = 8;
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


contract RewardTest is DSTest {

  DSToken token0;
  DSToken token1;
  DSToken token2;
  DSToken token3;
  UniswapV2Pair uniPair;
  UniswapV2Pair uniPair2;
  UniswapV2Pair uniPair3;
  DSToken gov;
  UniswapAdapterForStables sadapter;
  StakingRewards rewards;
  Hevm hevm;

  function setUp() public {
    gov = new DSToken("GOV");
    token0 = new Token0(18);
    token1 = new Token1(8);
    token2 = new Token2(24);
    token3 = new Token3(12);
    sadapter = new UniswapAdapterForStables();

    uniPair = new UniswapV2Pair(address(token0), address(token1));
    uniPair2 = new UniswapV2Pair(address(token1), address(token2));
    uniPair3 = new UniswapV2Pair(address(token0), address(token2));

    rewards = new StakingRewards();
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

  function testInitialize() public {
    rewards.initialize(address(gov), 100, 100, 10, false);
    assertTrue(address(rewards.gov()) == address(gov));

    rewards.registerPairDesc(address(uniPair), address(sadapter), 2);
    // rewards.pairDescs(address(uniPair));
    (address gem, address adapter, uint factor) = rewards.pairDescs(address(uniPair));
    assertEq(gem, address(uniPair));
    assertEq(adapter, address(sadapter));
    assertEq(factor, 2);

    (gem, adapter, factor) = rewards.pairDescs(address(0x0));
    assertEq(gem, address(0));
    assertEq(adapter, address(0));
    assertEq(factor, 0);
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


  function testStakeUnstacke() public {
    uint starttime = 10;
    rewards.initialize(address(gov), 100, 100, starttime, false);
    rewards.registerPairDesc(address(uniPair), address(sadapter), 1);

    uint v = 10000;
    uint l = addLiquidity(v);

    assertEq(uniPair.balanceOf(address(this)), l);
    assertEq(uniPair.balanceOf(address(rewards)), 0);
    uniPair.approve(address(rewards), l);

    assertEq(rewards.balanceOf(address(this)), 0);
    assertEq(rewards.totalSupply(), 0);

    (bool ret, ) = address(rewards).call(abi.encodeWithSelector(rewards.stake.selector, l, address(uniPair)));
    if (ret) {
      emit log_bytes32("rewards.stake fail expected");
      fail();
    }


    hevm.warp(starttime+1);
    rewards.stake(l, address(uniPair));
    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), l);

    assertEq(rewards.balanceOf(address(this)), v*2);
    assertEq(rewards.totalSupply(), v*2);


    uint v2 = 110000;
    uint l2 = addLiquidity(v2);

    assertEq(uniPair.balanceOf(address(this)), l2);
    assertEq(uniPair.balanceOf(address(rewards)), l);
    uniPair.approve(address(rewards), l2);

    rewards.stake(l2, address(uniPair));
    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), l+l2);

    assertEq(rewards.balanceOf(address(this)), v*2+v2*2);
    assertEq(rewards.totalSupply(), v*2+v2*2);


    uint w = l2*30/100;
    rewards.withdraw(w, address(uniPair));
    assertEq(uniPair.balanceOf(address(this)), w);
    assertEq(uniPair.balanceOf(address(rewards)), l+l2-w);

    uint rem = sadapter.calc(address(uniPair), l+l2-w, 1);

    assertEq(rewards.balanceOf(address(this)), rem);
    assertEq(rewards.totalSupply(), rem);


    (ret, ) = address(rewards).call(abi.encodeWithSelector(rewards.withdraw.selector, l+l2-w+1, address(uniPair)));
    if (ret) {
      emit log_bytes32("rewards.withdraw fail expected");
      fail();
    }

    assertEq(uniPair.balanceOf(address(this)), w);
    assertEq(uniPair.balanceOf(address(rewards)), l+l2-w);

    rewards.withdraw(l+l2-w, address(uniPair));
    assertEq(uniPair.balanceOf(address(this)), l+l2);
    assertEq(uniPair.balanceOf(address(rewards)), 0);

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
    rewards.initialize(address(gov), 100, 100, starttime, false);
    rewards.registerPairDesc(address(uniPair), address(sadapter), 1);
    rewards.registerPairDesc(address(uniPair2), address(sadapter), 1);
    rewards.registerPairDesc(address(uniPair3), address(sadapter), 1);

    uniPair.approve(address(rewards));
    uniPair2.approve(address(rewards));
    uniPair3.approve(address(rewards));

    StakeUnstacke3UniVars memory vars;

    vars.v = 10000;
    vars.l = addLiquidity(vars.v/2);

    hevm.warp(starttime+1);
    rewards.stake(vars.l, address(uniPair));

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l);

    assertEqM(rewards.balanceOf(address(this)), vars.v, "balanceOf vars.v");
    assertEqM(rewards.totalSupply(), vars.v, "totalSupply vars.v");


    vars.v2 = 20000;
    vars.l2 = addLiquidity2(vars.v2/2);
    rewards.stake(vars.l2, address(uniPair2));

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "1");
    assertEqM(uniPair2.balanceOf(address(rewards)), vars.l2, "2");

    assertEqM(rewards.balanceOf(address(this)), vars.v2+vars.v, "3");
    assertEqM(rewards.totalSupply(), vars.v2+vars.v, "4");

    vars.v22 = 1000;
    vars.l22 = addLiquidity2(vars.v22/2);
    rewards.stake(vars.l22, address(uniPair2));

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "21");
    assertEqM(uniPair2.balanceOf(address(rewards)), vars.l2+vars.l22, "22");

    assertEqM(rewards.balanceOf(address(this)), vars.v22+vars.v2+vars.v, "23");
    assertEqM(rewards.totalSupply(), vars.v22+vars.v2+vars.v, "24");


    vars.v3 = 200000;
    vars.l3 = addLiquidity3(vars.v3/2);
    rewards.stake(vars.l3, address(uniPair3));

    assertEq(uniPair.balanceOf(address(this)), 0);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "31");
    assertEqM(uniPair2.balanceOf(address(rewards)), vars.l2+vars.l22, "32");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "33");
    assertEqM(uniPair3.balanceOf(address(rewards)), vars.l3, "34");


    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v, "35");
    assertEqM(rewards.totalSupply(), vars.v3+vars.v22+vars.v2+vars.v, "36");

/////////////////////
    vars.w = vars.l*30/100;
    rewards.withdraw(vars.w, address(uniPair));
    assertEq(uniPair.balanceOf(address(this)), vars.w);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l-vars.w);

    assertEqM(uniPair2.balanceOf(address(this)), 0, "41");
    assertEqM(uniPair2.balanceOf(address(rewards)), vars.l2+vars.l22, "42");

    assertEqM(uniPair3.balanceOf(address(this)), 0, "43");
    assertEqM(uniPair3.balanceOf(address(rewards)), vars.l3, "44");


    vars.rem = sadapter.calc(address(uniPair), vars.w, 1);

    assertEq(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem);

/////////////////////
    vars.w3 = vars.l3*50/100;
    rewards.withdraw(vars.w3, address(uniPair3));
    assertEq(uniPair.balanceOf(address(this)), vars.w);
    assertEq(uniPair.balanceOf(address(rewards)), vars.l-vars.w);

    assertEq(uniPair3.balanceOf(address(this)), vars.w3);
    assertEq(uniPair3.balanceOf(address(rewards)), vars.l3-vars.w3);


    vars.rem3 = sadapter.calc(address(uniPair3), vars.w3, 1);

    assertEq(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem-vars.rem3);


/////////////////////
    vars.w12 = vars.l-vars.w;
    rewards.withdraw(vars.w12, address(uniPair));
    assertEqM(uniPair.balanceOf(address(this)), vars.w+vars.w12, "511");
    assertEqM(uniPair.balanceOf(address(this)), vars.l, "512");
    assertEqM(uniPair.balanceOf(address(rewards)), 0, "513");

    assertEqM(uniPair2.balanceOf(address(this)), 0, "51");
    assertEqM(uniPair2.balanceOf(address(rewards)), vars.l2+vars.l22, "52");

    assertEq(uniPair3.balanceOf(address(this)), vars.w3);
    assertEq(uniPair3.balanceOf(address(rewards)), vars.l3-vars.w3);


    vars.rem12 = sadapter.calc(address(uniPair), vars.w12, 1);

    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2+vars.v-vars.rem-vars.rem3-vars.rem12, "55");
    assertEqM(rewards.balanceOf(address(this)), vars.v3+vars.v22+vars.v2-vars.rem3, "56");
    assertEqM(rewards.totalSupply(), vars.v3+vars.v22+vars.v2-vars.rem3, "57");

  }


}
