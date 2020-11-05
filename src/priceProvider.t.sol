pragma solidity ^0.5.12;


import "./IERC20.sol";
import "./safeMath.sol";
import "./safeERC20.sol";
import "./priceProvider.sol";
import "./testHelpers.sol";

contract User {
  bytes32 body;


  function getReward(PriceProvider provider) public returns (uint) {
    return provider.getReward();
  }

  function poke(PriceProvider provider) public {
    provider.poke();
  }

}

contract SpotMock {
  mapping(bytes32 => uint) public rewards;
  uint public code;

  function setCode(uint _code) public {
    code = _code;
  }

  function poke(bytes32 ilk) external {
    rewards[ilk] = code;
  }

  function check(bytes32 ilk) public view returns (bool) {
    return rewards[ilk] == code;
  }

  function checkAll(bytes32[] memory ilks) public view returns (bool) {
    for (uint i=0; i<ilks.length; i++) {
        if (!check(ilks[i])) {
          return false;
        }
    }
    return true;
  }
}

contract RegistryMock {
  bytes32[] public ilks;

  constructor () public {
    ilks.push("ilk0");
    ilks.push("ilk1");
  }


  function list() external view returns (bytes32[] memory) {
    return ilks;
  }
}

contract PriceProviderTest is TestBase {

  User user1;
  User user2;

  SpotMock spot;
  PriceProvider provider;
  RegistryMock registry;


  function setUp() public {
    super.setUp();

    user1 = new User();
    user2 = new User();
    spot = new SpotMock();
    provider = new PriceProvider();
    registry = new RegistryMock();
  }

  function testPriceProviderBase() public {
    uint updatePeriod = 3600;
    uint rewardTime = 72000;
    bytes32[] memory ilks = registry.list();

    uint chunks = rewardTime / updatePeriod;

    uint reward = 100000000;
    gov.mint(address(provider), reward);
    provider.setup(address(gov), address(spot), address(registry), updatePeriod, rewardTime);

    hevm.warp(1);

    spot.setCode(1);
    assertEqM(gov.balanceOf(address(user1)), 0, "u1 bal b");
    assertEqM(gov.balanceOf(address(user2)), 0, "u2 bal b");
    user1.getReward(provider);
    assertEqM(gov.balanceOf(address(user1)), 0, "u1 bal b");
    user1.poke(provider);
    user1.getReward(provider);
    assertEqM(gov.balanceOf(address(user1)), reward/chunks, "u1 bal a");
    assertTrue(spot.checkAll(ilks));

    uint smallStep = 10;
    hevm.warp(smallStep);
    spot.setCode(2);
    user2.poke(provider);
    assertTrue(spot.checkAll(ilks));
    spot.setCode(3);
    user1.poke(provider);
    assertTrue(spot.checkAll(ilks));
    user1.getReward(provider);
    user2.getReward(provider);

    assertEqM(gov.balanceOf(address(user1)), reward/chunks, "u1 bal aa");
    assertEqM(gov.balanceOf(address(user2)), 0, "u2 bal aa");

    hevm.warp(updatePeriod+smallStep-1);

    spot.setCode(4);
    user2.poke(provider);
    assertTrue(spot.checkAll(ilks));

    spot.setCode(5);
    user1.poke(provider);
    assertTrue(spot.checkAll(ilks));

    user1.getReward(provider);
    user2.getReward(provider);

    assertEqM(gov.balanceOf(address(user1)), reward/chunks, "u1 bal aaa");
    assertEqM(gov.balanceOf(address(user2)), 0, "u2 bal aaa");

    hevm.warp(updatePeriod+smallStep-1+updatePeriod);

    user2.poke(provider);
    user1.poke(provider);
    user1.getReward(provider);
    user2.getReward(provider);

    assertEqM(gov.balanceOf(address(user1)), reward/chunks, "u1 bal aaaa");
    assertEqM(gov.balanceOf(address(user2)), reward/chunks, "u2 bal aaaa");

    hevm.warp(updatePeriod+smallStep-1+2*updatePeriod);

    user2.poke(provider);
    user1.poke(provider);
    user1.getReward(provider);
    user2.getReward(provider);

    assertEqM(gov.balanceOf(address(user1)), reward/chunks, "u1 bal aaaaa");
    assertEqM(gov.balanceOf(address(user2)), 2*reward/chunks, "u2 bal aaaaa");
  }
}