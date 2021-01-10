pragma solidity ^0.5.0;

import "./safeMath.sol";
import "./IERC20.sol";


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



interface CurvePoolLike {
    function balances(uint256 idx) external view returns (uint256);
    function coins(uint256 idx) external view returns (address);
}




/**
 * @title oracle for Uniswap LP tokens which contains stable coins
 * this contract assume USDT token may be part of pool
 * all stables except USDT assumed eq 1 USD
 *
*/
contract CurveAdapterPriceOracle_Buck_Buck {
    using SafeMath for uint256;

    IERC20 public gem;
    CurvePoolLike public pool;
    uint256 public numCoins;
    address public deployer;

    AggregatorV3Interface public priceETHUSDT;
    AggregatorV3Interface public priceUSDETH;
    address public usdtAddress;

    constructor() public {
        deployer = msg.sender;
    }

    /**
     * @dev initialize oracle
     * _gem - address of CRV pool token contract
     * _pool - address of CRV pool token contract
     * num - num of tokens in pools
     */
    function setup(address _gem, address _pool, uint256 num) public {
        require(deployer == msg.sender);
        gem = IERC20(_gem);
        pool = CurvePoolLike(_pool);
        numCoins = num;
    }

    function resetDeployer() public {
        require(deployer == msg.sender);
        deployer = address(0);
    }

    function setupUsdt(
        address _priceETHUSDT,
        address _priceUSDETH,
        address _usdtAddress,
        bool usdtAsString) public {

        require(address(pool) != address(0));

        require(deployer == msg.sender);
        require(_usdtAddress != address(0));
        require(_priceETHUSDT != address(0));
        require(_priceUSDETH != address(0));


        (bool success, bytes memory returndata) =
            address(_usdtAddress).call(abi.encodeWithSignature("symbol()"));
        require(success, "USDT: low-level call failed");

        require(returndata.length > 0);
        if (usdtAsString) {
            bytes memory usdtSymbol = bytes(abi.decode(returndata, (string)));
            require(keccak256(bytes(usdtSymbol)) == keccak256("USDT"));
        } else {
            bytes32 usdtSymbol = abi.decode(returndata, (bytes32));
            require(usdtSymbol == "USDT");
        }

        priceETHUSDT = AggregatorV3Interface(_priceETHUSDT);
        priceUSDETH  = AggregatorV3Interface(_priceUSDETH);
        usdtAddress = _usdtAddress;

        deployer = address(0);
    }

    function usdtCalcValue(uint256 value) internal view returns (uint256) {
        uint256 price1Div =
            10 **
                (
                    uint256(priceETHUSDT.decimals()).add(uint256(priceUSDETH.decimals())).add(
                        uint256(IERC20(usdtAddress).decimals())
                    )
                );

        (, int256 answerUSDETH, , , ) = priceUSDETH.latestRoundData();
        (, int256 answerETHUSDT, , , ) = priceETHUSDT.latestRoundData();

        uint256 usdtPrice = uint256(answerUSDETH).mul(uint256(answerETHUSDT));
        return value.mul(usdtPrice).div(price1Div);
    }


    /**
     * @dev calculate price
     */
    function calc() internal view returns (bytes32, bool) {

        uint256 totalSupply = gem.totalSupply();
        uint256 decimals = gem.decimals();

        uint256 totalValue = 0;
        for (uint256 i = 0; i<numCoins; i++) {
            uint256 value = pool.balances(i).mul(1e18).mul(uint256(10)**decimals).div(totalSupply);

            if (pool.coins(i) == usdtAddress) {

                totalValue = totalValue.add(usdtCalcValue(value));
            }
            else {
                uint256 tokenDecimalsF = uint256(10)**uint256(IERC20(pool.coins(i)).decimals());

                totalValue = totalValue.add(value.div(tokenDecimalsF));
            }
        }

        return (
            bytes32(
                totalValue
            ),
            true
        );

    }

    /**
     * @dev base oracle interface see OSM docs
     */
    function peek() public view returns (bytes32, bool) {
        return calc();
    }

    /**
     * @dev base oracle interface see OSM docs
     */
    function read() public view returns (bytes32) {
        bytes32 wut;
        bool haz;
        (wut, haz) = calc();
        require(haz, "haz-not");
        return wut;
    }
}
