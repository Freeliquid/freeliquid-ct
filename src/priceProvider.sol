pragma solidity ^0.5.12;


import "./IERC20.sol";
import "./safeMath.sol";
import "./safeERC20.sol";

interface SpotLike {
    function poke(bytes32 ilk) external;
}

contract PriceProvider {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public gov;
    bytes32[] public ilks;
    uint public nextUpdate;
    uint public updatePeriod;
    uint public rewardPerPeriod;
    uint public totalRewards;
    mapping(address => uint) public rewards;
    SpotLike public spot;

    event RewardPaid(address indexed user, uint256 reward);

    function getRewards() public {
        uint acc = rewards[msg.sender];
        if (acc > 0) {
            totalRewards = totalRewards.add(acc);
            IERC20(gov).safeTransfer(msg.sender, acc);
            emit RewardPaid(msg.sender, acc);
            rewards[msg.sender] = 0;
        }
    }

    function poke() public {

        for (uint i=0; i<ilks.length; i++) {
            spot.poke(ilks[i]);
        }

        if (block.timestamp >= nextUpdate) {
            rewards[msg.sender] = rewards[msg.sender].add(rewardPerPeriod);
        }

        nextUpdate = updatePeriod.add(block.timestamp);
    }
}