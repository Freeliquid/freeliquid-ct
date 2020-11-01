pragma solidity ^0.5.0;


import "./uni.sol";
import "./safeMath.sol";


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


contract UniswapAdapterPriceOracle_USDT_Buck {
    using SafeMath for uint;

    struct TokenPair {
        address buck;
        address usdt;
        uint buckReserve;
        uint usdtReserve;
    }

    AggregatorV3Interface public priceETHUSDT;
    AggregatorV3Interface public priceUSDETH;
    UniswapV2PairLike public gem;
    address public deployer;
    address public usdtAddress;



    constructor () public {
        deployer = msg.sender;
    }

    function setup(address _priceETHUSDT, address _priceUSDETH, address _gem, address _usdtAddress, bool usdtAsString) public {
        require(deployer == msg.sender);
        require(_usdtAddress != address(0));
        require(_priceETHUSDT != address(0));
        require(_priceUSDETH != address(0));
        require(_gem != address(0));

        (bool success, bytes memory returndata) = address(_usdtAddress).call(abi.encodeWithSignature("symbol()"));
        require(success, "USDT: low-level call failed");

        require(returndata.length > 0);
        if (usdtAsString) {
            bytes memory usdtSymbol = bytes(abi.decode(returndata, (string)));
            require(keccak256(bytes(usdtSymbol)) == keccak256("USDT"));
        } else {
            bytes32 usdtSymbol = abi.decode(returndata, (bytes32));
            require(usdtSymbol == "USDT");
        }


        priceETHUSDT = AggregatorV3Interface(_priceETHUSDT); //1/354 USD kovan:0x0bF499444525a23E7Bb61997539725cA2e928138
        priceUSDETH = AggregatorV3Interface(_priceUSDETH); //354 USD kovan:0x9326BFA02ADD2366b30bacB125260Af641031331
        gem = UniswapV2PairLike(_gem);
        usdtAddress = _usdtAddress;

        deployer = address(0);
    }

    function calc() internal view returns (bytes32, bool) {
        if (address(priceETHUSDT) == address(0x0) || address(priceUSDETH) == address(0x0) || address(gem) == address(0x0)) {
            return (0x0, false);
        }

        (, int256 answerUSDETH, , ,) = priceUSDETH.latestRoundData();
        (, int256 answerETHUSDT, , ,) = priceETHUSDT.latestRoundData();

        if (answerUSDETH <= 0 || answerETHUSDT <= 0) {
            return (0x0, false);
        }


        TokenPair memory tokenPair;
        {
            (uint112 _reserve0, uint112 _reserve1,) = gem.getReserves();

            if (gem.token1() == usdtAddress) {
                tokenPair.buck = gem.token0(); //buck
                tokenPair.buckReserve = uint(_reserve0);

                tokenPair.usdt = gem.token1(); //USDT
                tokenPair.usdtReserve = uint(_reserve1);
            } else {
                tokenPair.usdt = gem.token0(); //USDT
                tokenPair.usdtReserve = uint(_reserve0);

                tokenPair.buck = gem.token1(); //buck
                tokenPair.buckReserve = uint(_reserve1);
            }
        }

        uint usdPrec = 10**6;

        //assume buck == 1 USD
        uint r0 = tokenPair.buckReserve.mul(usdPrec).div(uint(10) ** uint(IERC20(tokenPair.buck).decimals()));

        uint price1Div = 10**(uint(priceETHUSDT.decimals())
                             .add(uint(priceUSDETH.decimals()))
                             .add(uint(IERC20(tokenPair.usdt).decimals())));

        uint usdtPrice = uint(answerUSDETH).mul(uint(answerETHUSDT));
        uint r1 = tokenPair.usdtReserve.mul(usdPrec).mul(usdtPrice).div(price1Div);

        uint totalValue = r0.add(r1); //total value in uni's reserves
        uint supply = gem.totalSupply();

        return (bytes32(totalValue.mul(10**(uint(gem.decimals()).add(18))).div(supply.mul(usdPrec))), true);
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


contract UniswapAdapterPriceOracle_Buck_Buck {
    using SafeMath for uint;

    struct TokenPair {
        address t0;
        address t1;
    }

    UniswapV2PairLike public gem;
    address public deployer;


    constructor () public {
        deployer = msg.sender;
    }

    function setup(address _gem) public {
        require(deployer == msg.sender);
        gem = UniswapV2PairLike(_gem);
        deployer = address(0);
    }

    function calc() internal view returns (bytes32, bool) {

        (uint112 _reserve0, uint112 _reserve1,) = gem.getReserves();

        TokenPair memory tokenPair;
        tokenPair.t0 = gem.token0();
        tokenPair.t1 = gem.token1();

        uint usdPrec = 10**6;

        uint r0 = uint(_reserve0).mul(usdPrec).div(uint(10) ** uint(IERC20(tokenPair.t0).decimals()));
        uint r1 = uint(_reserve1).mul(usdPrec).div(uint(10) ** uint(IERC20(tokenPair.t1).decimals()));

        uint totalValue = r0.add(r1); //total value in uni's reserves
        uint supply = gem.totalSupply();

        return (bytes32(totalValue.mul(10**(uint(gem.decimals()).add(18))).div(supply.mul(usdPrec))), true);
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


