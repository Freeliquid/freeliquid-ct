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

	int256 public answer;

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


contract Token0 is DSToken("TOKEN0") {
    constructor(uint d) public {
      decimals = d;
    }
}



contract OracleTest is DSTest {

  AggregatorV3Stub public priceETHUSDT;
  AggregatorV3Stub public priceUSDETH;
  DSToken gem;
  UniswapAdapterPriceOracle_USDT_USDC oracle;

  Hevm hevm;

  function setUp() public {
    priceETHUSDT = new AggregatorV3Stub();
    priceUSDETH = new AggregatorV3Stub();
    gem = new Token0(18);

    oracle = new UniswapAdapterPriceOracle_USDT_USDC();
    oracle.setup(address(priceETHUSDT), address(priceUSDETH), address(gem));
	}

	function test1() public {
		(bytes32 val, bool has) = oracle.peek();
	}

}


