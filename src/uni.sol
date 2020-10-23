pragma solidity ^0.5.0;

import "./base.sol";
import "./safeMath.sol";

interface UniswapV2PairLike {
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);

    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}


contract UniswapAdapterForStables is IAdapter {
    using SafeMath for uint;

    struct TokenPair {
        address t0;
        address t1;
    }


    function calc(address gem, uint value, uint factor) external view returns (uint) {

        (uint112 _reserve0, uint112 _reserve1,) = UniswapV2PairLike(gem).getReserves();

        TokenPair memory tokenPair;
        tokenPair.t0 = UniswapV2PairLike(gem).token0();
        tokenPair.t1 = UniswapV2PairLike(gem).token1();

        uint r0 = uint(_reserve0).div(uint(10) ** IERC20(tokenPair.t0).decimals());
        uint r1 = uint(_reserve1).div(uint(10) ** IERC20(tokenPair.t1).decimals());

        uint totalValue = r0.min(r1).mul(2); //total value in uni's reserves for stables only

        uint supply = UniswapV2PairLike(gem).totalSupply();

        return value.mul(totalValue).mul(factor).div(supply);
    }
}


contract SimpleAdapter is IAdapter {
    using SafeMath for uint;

    struct TokenPair {
        address t0;
        address t1;
    }

    function calc(address /*gem*/, uint value, uint factor) external view returns (uint) {
        return value.mul(factor);
    }
}
