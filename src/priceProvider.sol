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

    mapping(address => uint) public rewards;
    bytes32[] public ilks;
    SpotLike public spot;
    address public gov;
    address public owner;
    uint public nextUpdate;
    uint public updatePeriod;
    uint public rewardPerPeriod;
    uint public distributedReward;
    uint public rewardToDistribute;
    uint public rewardTime;

    event RewardPaid(address indexed user, uint256 reward);

    constructor () public {
        owner = msg.sender;
    }

    function setup(address _gov, address _spot, uint _updatePeriod, uint _rewardTime, bytes32[] memory _ilks) public {
        require(owner == msg.sender, "auth-error");

        require(_gov != address(0), "gov is null");
        require(_spot != address(0), "spot is null");
        require(_updatePeriod != 0, "updatePeriod is zero");
        require(_ilks.length < 16, "too big size of ilks");
        require(_rewardTime > _updatePeriod*10, "rewardTime vs updatePeriod inconsistence");

        rewardToDistribute = IERC20(_gov).balanceOf(address(this));
        require(rewardToDistribute > 0, "no reward to distribute");

        uint chunks = _rewardTime.div(_updatePeriod);

        spot = SpotLike(_spot);
        gov = _gov;
        rewardTime = _rewardTime;
        updatePeriod = _updatePeriod;
        ilks = _ilks;
        rewardPerPeriod = rewardToDistribute.div(chunks);
        require(rewardPerPeriod > 0, "rewardPerPeriod is zero");
    }


    function getReward() public returns (uint){
        uint acc = rewards[msg.sender];
        if (acc > 0) {
            distributedReward = distributedReward.add(acc);
            IERC20(gov).safeTransfer(msg.sender, acc);
            emit RewardPaid(msg.sender, acc);
            rewards[msg.sender] = 0;
        }
        return acc;
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