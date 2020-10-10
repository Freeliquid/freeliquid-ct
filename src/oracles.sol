pragma solidity ^0.5.0;


import "./uni.sol";
import "./safeMath.sol";

interface IERC20 {
    function decimals() external view returns(uint8);
}

interface AggregatorV3Interface {

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}


contract UniswapAdapterPriceOracle_USDT_USDC {
    using SafeMath for uint;

    struct TokenPair {
        address t0;
        address t1;
    }

    AggregatorV3Interface public priceETHUSDT;
    AggregatorV3Interface public priceUSDETH;
    UniswapV2PairLike public gem;
    address public deployer;


    constructor () public {
        deployer = msg.sender;
    }

    function setup(address _priceETHUSDT, address _priceUSDETH, address _gem) public {
        require(deployer == msg.sender);

        priceETHUSDT = AggregatorV3Interface(_priceETHUSDT); //1/354 USD kovan:0x0bF499444525a23E7Bb61997539725cA2e928138
        priceUSDETH = AggregatorV3Interface(_priceUSDETH); //354 USD kovan:0x9326BFA02ADD2366b30bacB125260Af641031331
        gem = UniswapV2PairLike(_gem);
    }

    function calc() internal view returns (bytes32, bool) {
        if (address(priceETHUSDT) == address(0x0) || address(priceUSDETH) == address(0x0) || address(gem) == address(0x0)) {
            return (0x0, false);
        }

        (, int256 answerUSDETH, , ,) = priceUSDETH.latestRoundData();
        (, int256 answerETHUSDT, , ,) = priceETHUSDT.latestRoundData();

        if (answerUSDETH <= 0 || answerETHUSDT <= 0)
            return (0x0, false);

        uint usdtPrice = uint(answerUSDETH).mul(uint(answerETHUSDT));

        (uint112 _reserve0, uint112 _reserve1,) = gem.getReserves();

        TokenPair memory tokenPair;
        tokenPair.t0 = gem.token0(); //USDC
        tokenPair.t1 = gem.token1(); //USDT

        uint r0 = uint(_reserve0).div(uint(10) ** IERC20(tokenPair.t0).decimals()); //assume USDC == 1 USD

        uint price1Div = 10**(uint(priceETHUSDT.decimals())
                             .add(uint(priceUSDETH.decimals()))
                             .add(uint(IERC20(tokenPair.t1).decimals())));

        uint r1 = uint(_reserve1).mul(usdtPrice).div(price1Div);

        uint totalValue = r0.add(r1); //total value in uni's reserves
        uint supply = gem.totalSupply();

        return (bytes32(totalValue.mul(10**18).mul(gem.decimals()).div(supply)), true);
    }


    function peek() public view returns (bytes32, bool) {
        return calc();
    }
    function read() public view returns (bytes32) {
        bytes32 wut; bool haz;
        (wut, haz) = calc();
        require(haz, "haz-not");
        return wut;
    }
}


