pragma solidity ^0.5.0;

import "./IERC20.sol";
import "./base.sol";
import "./safeMath.sol";

interface MooniPairLike {
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);

    function getTokens() external view returns(IERC20[] memory);
}


contract MooniAdapterForStables is IAdapter {
    using SafeMath for uint;


    function calc(address gem, uint value, uint factor) external view returns (uint) {

        IERC20[] memory tokens = MooniPairLike(gem).getTokens();
        uint reserve0 = tokens[0].balanceOf(gem);
        uint reserve1 = tokens[1].balanceOf(gem);

        uint r0 = uint(reserve0).div(uint(10) ** tokens[0].decimals());
        uint r1 = uint(reserve1).div(uint(10) ** tokens[1].decimals());

        uint totalValue = r0.min(r1).mul(2); //total value in uni's reserves for stables only

        uint supply = MooniPairLike(gem).totalSupply();

        return value.mul(totalValue).mul(factor).div(supply);
    }
}


