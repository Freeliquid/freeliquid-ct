pragma solidity ^0.5.0;

import "./IERC20.sol";


interface IAdapter {
    function calc(address gem, uint acc, uint factor) external view returns (uint);
}

interface IGemForRewardChecker {
    function check(address gem) external view returns (bool);
}


