pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./testHelpers.sol";
import "./curvePoolMock.sol";

import "./curve.sol";

contract MinterMock {

    DSToken public crv;

    constructor() public {
        crv = new DSToken("CRV");
    }

    function mint(address gauge_addr) external {
        crv.mint(gauge_addr, 10000);

    }
}


contract VotingEscrowMock {

    function create_lock(uint256 _value, uint256 _unlock_time) external {

    }

    function increase_amount(uint256 _value) external {

    }

    function increase_unlock_time(uint256 _unlock_time) external {

    }

    function withdraw() external {

    }
}

contract CurveGaugeMock {

    MinterMock theMinter;

    DSToken public rewardToken;
    VotingEscrowMock public votingEscrow;
    DSToken public lp;



    constructor(DSToken _lp) public {
        theMinter = new MinterMock();
        lp = _lp;
        rewardToken = new DSToken("REWARD");
        votingEscrow = new VotingEscrowMock();
    }

    function deposit(uint256 _value) external {
        lp.transferFrom(msg.sender, address(this), _value);
    }

    function withdraw(uint256 _value) external {
        lp.transfer(msg.sender, _value);
    }

    function lp_token() external view returns (address) {
        return address(lp);
    }

    function minter() external view returns (address) {
        return address(theMinter);
    }

    function crv_token() external view returns (address) {
        return address(theMinter.crv());
    }

    function voting_escrow() external view returns (address) {
        return address(votingEscrow);
    }

    function rewarded_token() external view returns (address) {
        return address(rewardToken);
    }

    function claim_rewards() external {

    }
}



contract User {
    bytes32 body;

    function joinHelper(
        GemJoinForCurve j,
        uint256 l
    ) public {
        j.gem().approve(address(j), l);
        j.join(address(this), l);
    }

    function exit(GemJoinForCurve j, uint256 l) public {
        j.exit(address(this), l);
    }

}

contract CurveJoinTest is TestBase {
    GemJoinForCurve join;

    CurveGaugeMock gauge;
    DSToken public lp1;


    User user1;
    User user2;

    uint256 constant totalRewardsMul = 1e18;
    uint256 totalRewards = 100000 * totalRewardsMul;
    uint256 rewardDuration = 1000000;

    function setUp() public {
        super.setUp();

        user1 = new User();
        user2 = new User();
        lp1 = new DSToken("LP");
        gauge = new CurveGaugeMock(lp1);

        address vat = address(new VatMock());

        join = new GemJoinForCurve(vat, "testilk", address(gauge), false);
    }

    function addLiquidity(uint256 v, User user) public returns (uint256) {
        uint256 l = v * 1e18;
        lp1.mint(address(user), l);
        return l;
    }

    function testCrvStakeUnstake() public {
        uint256 starttime = 10;

        uint256 v = 10000;
        uint256 l = addLiquidity(v, user1);

        assertEqM(lp1.balanceOf(address(user1)), l, "1");

        hevm.warp(starttime + 1);

        user1.joinHelper(join, l);

        hevm.warp(starttime + rewardDuration / 2 + 1);

        assertEqM(lp1.balanceOf(address(this)), 0, "2");
        address bag1 = join.bags(address(user1));
        assertTrue(bag1 != address(0));

        assertEqM(lp1.balanceOf(address(gauge)), l, "3");


        uint256 v2 = 110000;
        uint256 l2 = addLiquidity(v2, user1);

        assertEqM(lp1.balanceOf(address(user1)), l2, "4");
        assertEqM(lp1.balanceOf(address(gauge)), l, "5");

        user1.joinHelper(join, l2);
        assertEqM(lp1.balanceOf(address(this)), 0, "6");
        assertEqM(lp1.balanceOf(address(gauge)), l + l2, "7");


        hevm.warp(starttime + (rewardDuration * 400) / 500 + 1);

        uint256 w = (l2 * 30) / 100;
        user1.exit(join, w);
        assertEqM(lp1.balanceOf(address(user1)), w, "8");
        assertEqM(lp1.balanceOf(address(gauge)), l + l2 - w, "9");

        (bool ret, ) = address(user1).call(
            abi.encodeWithSelector(user1.exit.selector, join, l + l2 - w + 1)
        );
        if (ret) {
            emit log_bytes32("user1.exit fail expected");
            fail();
        }

        assertEqM(lp1.balanceOf(address(user1)), w, "10");
        assertEqM(lp1.balanceOf(address(gauge)), l + l2 - w, "11");

        uint256 v22 = 1000;
        uint256 l22 = addLiquidity(v22, user2);
        assertEqM(lp1.balanceOf(address(user2)), l22, "111");


        address bag2 = join.bags(address(user2));
        assertTrue(bag2 == address(0));

        user2.joinHelper(join, l22);
        assertEqM(lp1.balanceOf(address(user2)), 0, "112");


        bag2 = join.bags(address(user2));
        assertTrue(bag2 != address(0));
        assertTrue(bag1 != bag2);


        (ret, ) = address(user2).call(
            abi.encodeWithSelector(user2.exit.selector, join, l22+1)
        );
        if (ret) {
            emit log_bytes32("user2.exit fail expected");
            fail();
        }

        user1.exit(join, l + l2 - w);
        assertEqM(lp1.balanceOf(address(user1)), l + l2, "12");
        assertEqM(lp1.balanceOf(address(gauge)), l22, "13");

        user2.exit(join, l22);
        assertEqM(lp1.balanceOf(address(user2)), l22, "14");
    }


}
