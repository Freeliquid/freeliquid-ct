pragma solidity ^0.5.12;

import "./IERC20.sol";
import "./safeMath.sol";
import "./safeERC20.sol";

interface SpotLike {
    function poke(bytes32 ilk) external;
}

interface RegistryLike {
    function list() external view returns (bytes32[] memory);
}

contract PriceProvider {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => uint256) public rewards;
    RegistryLike public registry;
    SpotLike public spot;
    address public gov;
    address public owner;
    uint256 public nextUpdate;
    uint256 public updatePeriod;
    uint256 public rewardPerPeriod;
    uint256 public distributedReward;
    uint256 public rewardToDistribute;
    uint256 public rewardTime;

    event RewardPaid(address indexed user, uint256 reward);

    constructor() public {
        owner = msg.sender;
    }

    function setup(
        address _gov,
        address _spot,
        address _registry,
        uint256 _updatePeriod,
        uint256 _rewardTime
    ) public {
        require(owner == msg.sender, "auth-error");

        require(_gov != address(0), "gov is null");
        require(_spot != address(0), "spot is null");
        require(_updatePeriod != 0, "updatePeriod is zero");
        require(_registry != address(0), "registry is null");
        require(_rewardTime > _updatePeriod * 10, "rewardTime vs updatePeriod inconsistence");

        rewardToDistribute = IERC20(_gov).balanceOf(address(this));
        require(rewardToDistribute > 0, "no reward to distribute");

        uint256 chunks = _rewardTime.div(_updatePeriod);

        registry = RegistryLike(_registry);
        spot = SpotLike(_spot);
        gov = _gov;
        rewardTime = _rewardTime;
        updatePeriod = _updatePeriod;
        rewardPerPeriod = rewardToDistribute.div(chunks);
        require(rewardPerPeriod > 0, "rewardPerPeriod is zero");
    }

    function getReward() public returns (uint256) {
        uint256 acc = rewards[msg.sender];
        if (acc > 0) {
            distributedReward = distributedReward.add(acc);
            IERC20(gov).safeTransfer(msg.sender, acc);
            emit RewardPaid(msg.sender, acc);
            rewards[msg.sender] = 0;
        }
        return acc;
    }

    function poke() public {
        bytes32[] memory ilks = registry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            spot.poke(ilks[i]);
        }

        if (block.timestamp >= nextUpdate) {
            rewards[msg.sender] = rewards[msg.sender].add(rewardPerPeriod);
        }

        nextUpdate = updatePeriod.add(block.timestamp);
    }
}
