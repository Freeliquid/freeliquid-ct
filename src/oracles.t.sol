pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";

contract Hevm {
    function warp(uint256) public;
}


import "./oracles.sol";



contract AggregatorV3Stub {

  function decimals() public pure returns (uint8) { return 18; }
  function description() public pure returns (string memory) { return "TEST"; }
  function version() public pure returns (uint256) { return 1; }

  int256 public answer = 10**18;

  function setAnswer(int256 answer_) public {
    answer = answer_;
  }

  function latestRoundData()
    external
    view
    returns (uint80, int256, uint256, uint256, uint80)
  {
    return (1, answer, 1602594020, 1602594020, 1);
  }
}


contract UniswapToken is DSToken("UNIv2stub") {
    constructor(uint d) public {
      decimals = d;
    }

    DSToken t0;
    DSToken t1;

    function setupTokens(DSToken t0_, DSToken t1_) public {
      t0 = t0_;
      t1 = t1_;
    }

    function token0() public view returns (address) {
      return address(t0);
    }

    function token1() public view returns (address) {
      return address(t1);
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
      reserve0 = uint112(t0.balanceOf(address(this)));
      reserve1 = uint112(t1.balanceOf(address(this)));
      blockTimestampLast = 1;
    }

}


contract Token is DSToken {
    constructor(bytes32 symbol_, uint d) DSToken (symbol_) public {
      decimals = d;
    }
}

contract TokenWithSymbolUSDC {
  string public symbol = "USDC";
}

contract TokenWithSymbolUSDT {
  string public symbol = "USDT";
}

interface OracleLike {
  function peek() external view returns (bytes32, bool);
}

contract OracleTest is DSTest {

  AggregatorV3Stub public priceETHUSDT;
  AggregatorV3Stub public priceUSDETH;
  UniswapToken uni;
  UniswapToken uni2;
  UniswapToken uni2i;
  UniswapAdapterPriceOracle_USDT_Buck oracle;
  UniswapAdapterPriceOracle_USDT_Buck oracle2;
  UniswapAdapterPriceOracle_USDT_Buck oracle2i;
  UniswapAdapterPriceOracle_Buck_Buck oracleBb;
  DSToken t0;
  DSToken t1;
  DSToken t2;

  TokenWithSymbolUSDT ttUSDT;
  TokenWithSymbolUSDC ttUSDC;


  Hevm hevm;

  function setUp() public {
    priceETHUSDT = new AggregatorV3Stub();
    priceUSDETH = new AggregatorV3Stub();

    t0 = new Token("USDC", 6);
    t1 = new Token("USDT", 6);
    t2 = new Token("DAI", 18);

    uni = new UniswapToken(18);
    uni.setupTokens(t0, t1);

    uni2 = new UniswapToken(18);
    uni2.setupTokens(t1, t2);

    uni2i = new UniswapToken(18);
    uni2i.setupTokens(t2, t1);


    ttUSDT = new TokenWithSymbolUSDT();
    ttUSDC = new TokenWithSymbolUSDC();


    oracle = new UniswapAdapterPriceOracle_USDT_Buck();
    oracle.setup(address(priceETHUSDT), address(priceUSDETH), address(uni), address(t1), false);

    oracle2 = new UniswapAdapterPriceOracle_USDT_Buck();
    oracle2.setup(address(priceETHUSDT), address(priceUSDETH), address(uni2), address(t1), false);

    oracle2i = new UniswapAdapterPriceOracle_USDT_Buck();
    oracle2i.setup(address(priceETHUSDT), address(priceUSDETH), address(uni2i), address(t1), false);

    oracleBb = new UniswapAdapterPriceOracle_Buck_Buck();
    oracleBb.setup(address(uni));
  }


  function testSetup() public {
    UniswapAdapterPriceOracle_USDT_Buck oracleEx = new UniswapAdapterPriceOracle_USDT_Buck();
    oracleEx.setup(address(priceETHUSDT), address(priceUSDETH), address(uni), address(ttUSDT), true);
  }

  function testFailSetup() public {
    UniswapAdapterPriceOracle_USDT_Buck oracleEx = new UniswapAdapterPriceOracle_USDT_Buck();
    oracleEx.setup(address(priceETHUSDT), address(priceUSDETH), address(uni), address(ttUSDC), true);
  }

  function testFailSetupEx() public {
    UniswapAdapterPriceOracle_USDT_Buck oracleEx = new UniswapAdapterPriceOracle_USDT_Buck();
    oracleEx.setup(address(priceETHUSDT), address(priceUSDETH), address(uni), address(t1), true);
  }

  function mintToUni(uint amnt0, uint amnt1) public {
    (uint112 reserve0b, uint112 reserve1b,) = uni.getReserves();
    t0.mint(address(uni), amnt0);
    t1.mint(address(uni), amnt1);
    (uint112 reserve0, uint112 reserve1,) = uni.getReserves();

    assertEq(reserve0-reserve0b, amnt0);
    assertEq(reserve1-reserve1b, amnt1);
  }


  function mintToUni2(uint amnt2, uint amnt1, UniswapToken uniRef, bool inv) public {
    (uint112 reserve0b, uint112 reserve1b,) = uniRef.getReserves();
    t2.mint(address(uniRef), amnt2);
    t1.mint(address(uniRef), amnt1);
    (uint112 reserve0, uint112 reserve1,) = uniRef.getReserves();

    assertEq(reserve0-reserve0b, inv ? amnt2 : amnt1);
    assertEq(reserve1-reserve1b, inv ? amnt1 : amnt2);
  }


  function mintToUni(uint amnt) public {
    mintToUni(amnt, amnt);
  }

  function readOracle() public returns (uint) {
    (bytes32 val, bool has) = oracle.peek();
    assertEq(uint(has?1:0), uint(1));
    return uint(val);
  }

  function test1() public {
    uni.mint(address(this), 1000*(10**18));
    mintToUni(1000*(10**6));
    uint val = readOracle();
    assertEq(uni.totalSupply(), 1000*(10**18));
    assertEq(t0.totalSupply(), 1000*(10**6));
    assertEq(t1.totalSupply(), 1000*(10**6));
    assertEq(val, uint(2 * 10**18));
  }

  function testBb() public {
    uni.mint(address(this), 1000*(10**18));
    mintToUni(1000*(10**6));


    (bytes32 val, bool has) = oracleBb.peek();
    assertEq(uint(has?1:0), uint(1));

    assertEq(uni.totalSupply(), 1000*(10**18));
    assertEq(t0.totalSupply(), 1000*(10**6));
    assertEq(t1.totalSupply(), 1000*(10**6));
    assertEq(uint(val), uint(2 * 10**18));
  }

  function testBbDis() public {
    uni.mint(address(this), 1000*(10**18));
    mintToUni(1000*(10**6), 2000*(10**6));


    (bytes32 val, bool has) = oracleBb.peek();
    assertEq(uint(has?1:0), uint(1));

    assertEq(uni.totalSupply(), 1000*(10**18));
    assertEq(t0.totalSupply(), 1000*(10**6));
    assertEq(t1.totalSupply(), 2000*(10**6));
    assertEq(uint(val), uint(3 * 10**18));
  }

  function implDAI_USDT(UniswapToken uniRef, OracleLike o, bool inv) public {
    uniRef.mint(address(this), 1000*(10**18));
    mintToUni2(1000*(10**18), 1000*(10**6), uniRef, inv);


    (bytes32 val, bool has) = o.peek();
    assertEq(uint(has?1:0), uint(1));

    assertEq(uniRef.totalSupply(), 1000*(10**18));
    assertEq(t2.totalSupply(), 1000*(10**18));
    assertEq(t1.totalSupply(), 1000*(10**6));

    assertEq(uint(val), uint(2 * 10**18));
  }

  function testDAI_USDT() public {
    implDAI_USDT(uni2, OracleLike(address(oracle2)), false);
  }

  function testDAI_USDTinv() public {
    implDAI_USDT(uni2i, OracleLike(address(oracle2i)), true);
  }


  function test2() public {
    uni.mint(address(this), 1000*(10**18));
    mintToUni(1000*(10**6));

    priceETHUSDT.setAnswer(2500000000000000);
    priceUSDETH.setAnswer(200000000000000000000);

    uint val = readOracle();
    assertEq(uni.totalSupply(), 1000*(10**18));
    assertEq(t0.totalSupply(), 1000*(10**6));
    assertEq(t1.totalSupply(), 1000*(10**6));
    assertEq(val, uint(15 * 10**17));
  }

  function test3() public {
    uni.mint(address(this), 1000*(10**18));
    mintToUni(1000*(10**6), 2000*(10**6));

    priceETHUSDT.setAnswer(2500000000000000);
    priceUSDETH.setAnswer(200000000000000000000);

    uint val = readOracle();
    assertEq(uni.totalSupply(), 1000*(10**18));
    assertEq(t0.totalSupply(), 1000*(10**6));
    assertEq(t1.totalSupply(), 2000*(10**6));
    assertEq(val, uint(2 * 10**18));
  }

}


