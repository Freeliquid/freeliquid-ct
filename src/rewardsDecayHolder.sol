pragma solidity ^0.5.12;

import "./IERC20.sol";
import "./safeMath.sol";
import "./safeERC20.sol";

interface IRewarder {
    function stake(
        address account,
        uint256 amount,
        address gem
    ) external;

    function withdraw(
        address account,
        uint256 amount,
        address gem
    ) external;
}

contract StakingRewardsDecayHolder {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IRewarder public rewarder;

    uint256 public withdrawErrorCount;

    mapping(address => mapping(address => uint256)) public amounts;

    event withdrawError(uint256 amount, address gem);

    constructor(address _rewarder) public {
        rewarder = IRewarder(_rewarder);
    }

    function stake(uint256 amount, address gem) public {
        require(amount > 0, "Cannot stake 0");

        rewarder.stake(msg.sender, amount, gem);

        amounts[gem][msg.sender] = amounts[gem][msg.sender].add(amount);
        IERC20(gem).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount, address gem) public {
        require(amount > 0, "Cannot withdraw 0");

        (bool success, ) =
            address(rewarder).call(
                abi.encodeWithSelector(rewarder.withdraw.selector, msg.sender, amount, gem)
            );
        if (!success) {
            //don't interfere with user to withdraw his money regardless
            //of potential rewarder's bug or hacks
            //only amounts map matters
            emit withdrawError(amount, gem);
            withdrawErrorCount++;
        }

        amounts[gem][msg.sender] = amounts[gem][msg.sender].sub(amount);
        IERC20(gem).safeTransfer(msg.sender, amount);
    }
}
