pragma solidity ^0.5.12;

import "./IERC20.sol";
import "./safeMath.sol";
import "./safeERC20.sol";



interface RegistryLike {
    function list() external view returns (bytes32[] memory);
    function info(bytes32 ilk) external view returns (
        string memory name,
        string memory symbol,
        uint256 dec,
        address gem,
        address pip,
        address join,
        address flip
    );
}

interface PipLike {
    function peek() external view returns (bytes32, bool);
}

interface RewardPoolLike {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getRewardPerHour() external view returns (uint256);
}

contract CollateralStat {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    RegistryLike public registry;
    RewardPoolLike public hiRiskPool;
    RewardPoolLike public lowRiskPool;
    uint256 constant HOURS_IN_YEAR = 8760;

    address deployer;


    constructor() public {
        deployer = msg.sender;
    }


    function setup(
        address _registry,
        address _hiRiskPool,
        address _lowRiskPool
    ) public {
        require(deployer == msg.sender, "auth");
        require(_registry != address(0), "registry is null");
        registry = RegistryLike(_registry);
        lowRiskPool = RewardPoolLike(_lowRiskPool);
        hiRiskPool = RewardPoolLike(_hiRiskPool);
    }

    function getHiRiskApy(uint256 amount, uint256 price) public view returns (uint256) {
        return getApy(amount, price, hiRiskPool);
    }

    function getLowRiskApy(uint256 amount, uint256 price) public view returns (uint256) {
        return getApy(amount, price, lowRiskPool);
    }

    function getHiRiskApyForBalance(address account, uint256 price) public view returns (uint256) {
        return getApyForBalance(account, price, hiRiskPool);
    }

    function getLowRiskApyForBalance(address account, uint256 price) public view returns (uint256) {
        return getApyForBalance(account, price, lowRiskPool);
    }

    function getApyForBalance(address account, uint256 price, RewardPoolLike pool) internal view returns (uint256) {
        return getApy(pool.balanceOf(account), price, pool);   
    }

    function getApy(uint256 amount, uint256 price, RewardPoolLike pool) internal view returns (uint256) {

        uint256 tokensInYear = amount.mul(pool.getRewardPerHour().mul(HOURS_IN_YEAR)).div(pool.totalSupply());
        return tokensInYear.mul(price).div(1e18);
    }

    function getStat(bytes32 ilk) public view returns (uint256) {

        (,,, address gem, address pip, address join,) = registry.info(ilk);
        uint256 amount = IERC20(gem).balanceOf(join);
        (bytes32 price, bool has) = PipLike(pip).peek();
        require(has, "PipLike-res-not-valid");

        return uint256(price).mul(amount).div(1e18);
    }

    function getTotalStat() public view returns (uint256 total) {
        bytes32[] memory ilks = registry.list();
        for (uint256 i = 0; i < ilks.length; i++) {
            uint256 value = getStat(ilks[i]); 
            total = total.add(value);
        }
    }
}
