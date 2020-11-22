pragma solidity ^0.5.0;

import "./IERC20.sol";
import "./base.sol";
import "./safeMath.sol";

interface MooniPairLike {
    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function getTokens() external view returns (IERC20[] memory);
}

contract MooniAdapterForStables is IAdapter {
    using SafeMath for uint256;

    function calc(
        address gem,
        uint256 value,
        uint256 factor
    ) external view returns (uint256) {
        IERC20[] memory tokens = MooniPairLike(gem).getTokens();
        uint256 reserve0 = tokens[0].balanceOf(gem);
        uint256 reserve1 = tokens[1].balanceOf(gem);

        uint256 r0 = uint256(reserve0).div(uint256(10)**tokens[0].decimals());
        uint256 r1 = uint256(reserve1).div(uint256(10)**tokens[1].decimals());

        uint256 totalValue = r0.min(r1).mul(2); //total value in uni's reserves for stables only

        uint256 supply = MooniPairLike(gem).totalSupply();

        return value.mul(totalValue).mul(factor).div(supply);
    }
}
