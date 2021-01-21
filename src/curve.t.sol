pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./testHelpers.sol";
import "./curvePoolMock.sol";
import "./IERC20.sol";
import "./safeMath.sol";

import "./curve.sol";

contract MinterMock {

    DSToken public crv;

    constructor() public {
        crv = new DSToken("CRV");
    }

    function mint(address gauge_addr) external {
        uint256 value = IERC20(CurveGauge(gauge_addr).lp_token()).balanceOf(msg.sender);
        crv.mint(msg.sender, value*2);
    }

    function testMintTo(address to, uint256 value) external {
        crv.mint(to, value);
    }

}


contract LastSender {
    address public lastSender;

    function popLastSender() external returns (address r) {
        r = lastSender;
        lastSender = address(0);
    }
}


contract VotingEscrowMock is LastSender {

    using SafeMath for uint256;


    IERC20 crv;

    mapping (address => uint256) public lockedAmount;
    mapping (address => uint256) public lockedTime;

    constructor(address _crv) public {
        crv = IERC20(_crv);
    }


    function create_lock(uint256 _value, uint256 _unlock_time) external {
        require(lockedAmount[msg.sender] == 0);
        require(lockedTime[msg.sender] == 0);

        crv.transferFrom(msg.sender, address(this), _value);

        lastSender = msg.sender;        lockedAmount[msg.sender] = _value;
        lockedTime[msg.sender] = _unlock_time;
    }

    function increase_amount(uint256 _value) external {
        crv.transferFrom(msg.sender, address(this), _value);
        lastSender = msg.sender;
        lockedAmount[msg.sender] += _value;
    }

    function increase_unlock_time(uint256 _unlock_time) external {
        lastSender = msg.sender;
        lockedTime[msg.sender] += _unlock_time;
    }

    function withdraw() external {
        crv.transfer(msg.sender, lockedAmount[msg.sender]);

        lockedTime[msg.sender] = 0;
        lockedAmount[msg.sender] = 0;

        lastSender = msg.sender;
    }
}

contract CurveGaugeMock is CurveGauge, LastSender {

    MinterMock public theMinter;

    DSToken public rewardToken;
    VotingEscrowMock public votingEscrow;
    DSToken public lp;


    constructor(DSToken _lp) public {
        theMinter = new MinterMock();
        lp = _lp;
        rewardToken = new DSToken("REWARD");
        votingEscrow = new VotingEscrowMock(address(theMinter.crv()));
    }

    function deposit(uint256 _value) external {
        lp.transferFrom(msg.sender, address(this), _value);
        lastSender = msg.sender;
    }

    function withdraw(uint256 _value) external {
        lp.transfer(msg.sender, _value);
        lastSender = msg.sender;
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

    function claim_rewards(address addr) external {
        uint256 value = lp.balanceOf(addr);
        rewardToken.mint(address(this), value);
        rewardToken.transfer(addr, value);
    }
}



contract User {
    bytes32 body;

    TestBase test;

    constructor(TestBase _test) public {
        test = _test;
    }

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

    event log_bytes32            (bytes32);
    event log_named_address      (bytes32 key, address val);
    event log_named_bytes32      (bytes32 key, bytes32 val);


    function transfer(address token, address to, uint256 amount, bytes32 tag) public {

        (bool ret, ) = token.call(
            abi.encodeWithSelector(IERC20(token).transfer.selector, to, amount)
        );
        if (!ret) {
            emit log_bytes32("transfer failed");
            emit log_named_address("    token", token);
            emit log_named_bytes32("    token name", DSToken(token).symbol());
            emit log_named_bytes32("    tag", tag);

            test.callFail();
        }
    }

}

contract CurveJoinTest is TestBase {
    GemJoinForCurve join;
    GemJoinForCurve joinWithRewards;

    CurveGaugeMock gauge;
    CurveGaugeMock gaugeWithRewards;

    DSToken public lp1;
    DSToken public lp2;


    User user1;
    User user2;

    uint256 constant totalRewardsMul = 1e18;
    uint256 totalRewards = 100000 * totalRewardsMul;
    uint256 rewardDuration = 1000000;

    function setUp() public {
        super.setUp();

        user1 = new User(this);
        user2 = new User(this);
        lp1 = new DSToken("LP1");
        lp2 = new DSToken("LP2");

        gauge = new CurveGaugeMock(lp1);
        gaugeWithRewards = new CurveGaugeMock(lp2);

        address vat = address(new VatMock());

        join = new GemJoinForCurve(vat, "testilk", address(gauge), false);
        joinWithRewards = new GemJoinForCurve(vat, "testilk2", address(gaugeWithRewards), true);
    }


    function addCrvTo(address to, uint256 value) public {
        DSToken crv = gauge.theMinter().crv();
        uint256 b = crv.balanceOf(to);

        gauge.theMinter().testMintTo(to, value);

        assertEqM(crv.balanceOf(to) - b, value, "crv-mint");
    }

    function addLiquidityCore(DSToken _lp, uint256 v, User user) public returns (uint256) {
        return addLiquidityCoreEx(_lp, v, address(user));
    }

    function addLiquidityCoreEx(DSToken _lp, uint256 v, address to) public returns (uint256) {
        uint256 l = v * 1e18;
        _lp.mint(to, l);
        return l;
    }

    function addLiquidity1(uint256 v, User user) public returns (uint256) {
        return addLiquidityCore(lp1, v, user);
    }

    function testCrvStakeUnstake() public {
        uint256 starttime = 10;

        uint256 v = 10000;
        uint256 l = addLiquidity1(v, user1);

        assertEqM(lp1.balanceOf(address(user1)), l, "1");

        hevm.warp(starttime + 1);

        user1.joinHelper(join, l);
        address bag1 = join.bags(address(user1));
        assertTrue(bag1 != address(0));

        assertTrue(gauge.popLastSender() == address(bag1));
        assertTrue(gauge.popLastSender() == address(0));

        hevm.warp(starttime + rewardDuration / 2 + 1);

        assertEqM(lp1.balanceOf(address(this)), 0, "2");

        assertEqM(lp1.balanceOf(address(gauge)), l, "3");


        uint256 v2 = 110000;
        uint256 l2 = addLiquidity1(v2, user1);

        assertEqM(lp1.balanceOf(address(user1)), l2, "4");
        assertEqM(lp1.balanceOf(address(gauge)), l, "5");

        user1.joinHelper(join, l2);
        assertTrue(gauge.popLastSender() == address(bag1));

        assertEqM(lp1.balanceOf(address(this)), 0, "6");
        assertEqM(lp1.balanceOf(address(gauge)), l + l2, "7");


        hevm.warp(starttime + (rewardDuration * 400) / 500 + 1);

        uint256 w = (l2 * 30) / 100;
        user1.exit(join, w);
        assertTrue(gauge.popLastSender() == address(bag1));

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
        uint256 l22 = addLiquidity1(v22, user2);
        assertEqM(lp1.balanceOf(address(user2)), l22, "111");


        address bag2 = join.bags(address(user2));
        assertTrue(bag2 == address(0));

        user2.joinHelper(join, l22);

        assertEqM(lp1.balanceOf(address(user2)), 0, "112");


        bag2 = join.bags(address(user2));
        assertTrue(bag2 != address(0));
        assertTrue(bag1 != bag2);
        assertTrue(gauge.popLastSender() == address(bag2));


        (ret, ) = address(user2).call(
            abi.encodeWithSelector(user2.exit.selector, join, l22+1)
        );
        if (ret) {
            emit log_bytes32("user2.exit fail expected");
            fail();
        }

        user1.exit(join, l + l2 - w);
        assertTrue(gauge.popLastSender() == address(bag1));

        assertEqM(lp1.balanceOf(address(user1)), l + l2, "12");
        assertEqM(lp1.balanceOf(address(gauge)), l22, "13");

        user2.exit(join, l22);
        assertTrue(gauge.popLastSender() == address(bag2));

        assertEqM(lp1.balanceOf(address(user2)), l22, "14");
    }

    function implCrvRewards(GemJoinForCurve _join, CurveGaugeMock _gauge, DSToken _lp,
                            bool rewardValueZero) public {
        uint256 starttime = 10;

        uint256 v = 10000;
        uint256 l = addLiquidityCore(_lp, v, user1);

        uint256 v2 = 30000;
        uint256 l2 = addLiquidityCore(_lp, v2, user2);

        IERC20 crv = IERC20(_gauge.crv_token());
        IERC20 rewardedToken = IERC20(_gauge.rewarded_token());


        assertEqM(_lp.balanceOf(address(user1)), l, "1");
        assertEqM(_lp.balanceOf(address(user2)), l2, "11");

        hevm.warp(starttime + 1);

        assertEqM(_lp.balanceOf(address(_gauge)), 0, "12");


        user1.joinHelper(_join, l);
        address bag1 = _join.bags(address(user1));

        assertTrue(_gauge.popLastSender() == address(bag1));

        assertEqM(_lp.balanceOf(address(user1)), 0, "2");
        assertEqM(_lp.balanceOf(address(_gauge)), l, "21");

        user2.joinHelper(_join, l2);
        address bag2 = _join.bags(address(user2));
        assertTrue(_gauge.popLastSender() == address(bag2));


        assertEqM(_lp.balanceOf(address(user2)), 0, "31");
        assertEqM(_lp.balanceOf(address(_gauge)), l+l2, "31");


        assertEqM(crv.balanceOf(address(user1)), 0, "4");
        assertEqM(rewardedToken.balanceOf(address(user1)), 0, "41");
        assertEqM(crv.balanceOf(address(user2)), 0, "42");
        assertEqM(rewardedToken.balanceOf(address(user2)), 0, "43");
        
        user2.exit(_join, l2);
        assertTrue(_gauge.popLastSender() == address(bag2));

        user1.exit(_join, l);
        assertTrue(_gauge.popLastSender() == address(bag1));




        assertEqM(crv.balanceOf(address(user1)), l*2, "5");
        assertEqM(rewardedToken.balanceOf(address(user1)), rewardValueZero ? 0 : l, "51");

        assertEqM(_lp.balanceOf(address(user1)), l, "52");
        assertEqM(_lp.balanceOf(address(user2)), l2, "53");

        assertEqM(crv.balanceOf(address(user2)), l2*2, "6");
        assertEqM(rewardedToken.balanceOf(address(user2)), rewardValueZero ? 0 : l2, "61");

        assertEqM(_lp.balanceOf(address(_gauge)), 0, "7");

        user1.transfer(address(crv), address(this), l*2, "71");
        user2.transfer(address(crv), address(this), l2*2, "72");

        if (!rewardValueZero) {
            user1.transfer(address(rewardedToken), address(this), l, "73");
            user2.transfer(address(rewardedToken), address(this), l2, "74");
        }

        assertEqM(rewardedToken.balanceOf(address(user1)), 0, "75");
        assertEqM(rewardedToken.balanceOf(address(user2)), 0, "76");
        assertEqM(crv.balanceOf(address(user1)), 0, "77");
        assertEqM(crv.balanceOf(address(user2)), 0, "78");
    }

    function implCrvRewardsPartialExit(GemJoinForCurve _join, CurveGaugeMock _gauge, DSToken _lp,
                                       bool rewardValueZero) public {

        IERC20 crv = IERC20(_gauge.crv_token());
        IERC20 rewardedToken = IERC20(_gauge.rewarded_token());

        hevm.warp(11);

        // uint256 v = 10000;
        uint256 l = addLiquidityCore(_lp, 10000, user1);
        assertEqM(_lp.balanceOf(address(user1)), l, "1");

        user1.joinHelper(_join, l);

        assertEqM(_lp.balanceOf(address(user1)), 0, "8");
        assertEqM(_lp.balanceOf(address(_gauge)), l, "81");

        user1.exit(_join, l/2);

        assertEqM(_lp.balanceOf(address(user1)), l/2, "9");
        assertEqM(_lp.balanceOf(address(_gauge)), l/2, "91");

        assertEqM(crv.balanceOf(address(user1)), l*2/2, "10");
        assertEqM(rewardedToken.balanceOf(address(user1)), rewardValueZero ? 0 : l/2, "11");

        address bag1 = _join.bags(address(user1));

        assertEqM(crv.balanceOf(bag1), l*2/2, "111");
        assertEqM(rewardedToken.balanceOf(bag1), rewardValueZero ? 0 : l/2, "112");

        user1.transfer(address(crv), address(this), crv.balanceOf(address(user1)), "113");

        if (!rewardValueZero) {
            user1.transfer(address(rewardedToken), address(this), rewardedToken.balanceOf(address(user1)), "114");
        }

        assertEqM(rewardedToken.balanceOf(address(user1)), 0, "115");
        assertEqM(crv.balanceOf(address(user1)), 0, "116");

        uint256 crvEarnedExpected = crv.balanceOf(bag1) + _lp.balanceOf(address(bag1)) * 2;
        uint256 rewardEarnedExpected = rewardedToken.balanceOf(bag1) + _lp.balanceOf(address(bag1));

        user1.exit(_join, l/3);


        uint256 remainAmount = l*5/6;
        assertEqM(_lp.balanceOf(address(user1)), remainAmount, "12");
        assertEqM(_lp.balanceOf(address(_gauge)), l/6+1, "121");

        uint256 crvUserBal = crvEarnedExpected * (l/3) / (l/2);
        uint256 rewardUserBal = rewardValueZero ? 0 : rewardEarnedExpected * (l/3) / (l/2);

        assertEqM(crv.balanceOf(address(user1)), crvUserBal, "13");
        assertEqM(rewardedToken.balanceOf(address(user1)), rewardUserBal, "131");

        assertEqM(crv.balanceOf(address(bag1)), crvEarnedExpected-crvUserBal, "132");
        assertEqM(rewardedToken.balanceOf(address(bag1)), rewardEarnedExpected-rewardUserBal, "133");

        user1.transfer(address(crv), address(this), crv.balanceOf(address(user1)), "113");
        if (!rewardValueZero) {
            user1.transfer(address(rewardedToken), address(this), rewardedToken.balanceOf(address(user1)), "114");
        }
        assertEqM(rewardedToken.balanceOf(address(user1)), 0, "1141");
        assertEqM(crv.balanceOf(address(user1)), 0, "1142");


        crvEarnedExpected = crv.balanceOf(bag1) + _lp.balanceOf(address(bag1)) * 2;
        rewardEarnedExpected = rewardedToken.balanceOf(bag1) + _lp.balanceOf(address(bag1));

        user1.exit(_join, l/6+1);

        assertEqM(_lp.balanceOf(address(user1)), l, "14");
        assertEqM(_lp.balanceOf(address(_gauge)), 0, "141");

        assertEqM(rewardedToken.balanceOf(address(user1)), rewardEarnedExpected, "15");
        assertEqM(crv.balanceOf(address(user1)), crvEarnedExpected, "151");

        assertEqM(crv.balanceOf(address(bag1)), 0, "16");
        assertEqM(rewardedToken.balanceOf(address(bag1)), 0, "161");
    }

    function testCrvRewards() public {
        implCrvRewards(join, gauge, lp1, true);
    }

    function testCrvAdditionalRewards() public {
        implCrvRewards(joinWithRewards, gaugeWithRewards, lp2, false);
    }

    function testCrvRewardsPartialExit() public {
        implCrvRewardsPartialExit(join, gauge, lp1, true);
    }

    function testCrvAdditionalRewardsPartialExit() public {
        implCrvRewardsPartialExit(joinWithRewards, gaugeWithRewards, lp2, false);
    }


    function testCrvVotingEscrow() public {

        bool ret;

        uint256 v = 10000;
        uint256 l = addLiquidityCoreEx(lp1, v, address(this));

        assertEqM(lp1.balanceOf(address(this)), l, "1");

        VotingEscrowMock votingEscrow = gauge.votingEscrow();
        DSToken crv = gauge.theMinter().crv();

        hevm.warp(1);
        uint256 crvValue = 1000;
        uint256 crvValue2 = 2000;

        addCrvTo(address(this), crvValue);
        crv.approve(address(join), crvValue);

        (ret, ) = address(join).call(
            abi.encodeWithSelector(join.create_lock.selector, crvValue, 100)
        );
        if (ret) {
            emit log_bytes32("join crt must fail");
            fail();
        }


        join.gem().approve(address(join), l);
        join.join(address(this), l);

        address bag = join.bags(address(this));
        assertTrue(bag != address(0));

        assertTrue(gauge.popLastSender() == address(bag));

        uint256 time1 = 100;
        uint256 time2 = 200;

        assertEqM(crv.balanceOf(gauge.voting_escrow()), 0, "1");
        join.create_lock(crvValue, time1);
        assertTrue(votingEscrow.popLastSender() == address(bag));
        assertTrue(votingEscrow.popLastSender() == address(0));


        assertEqM(crv.balanceOf(gauge.voting_escrow()), crvValue, "2");
        assertEqM(crv.balanceOf(address(this)), 0, "3");



        (ret, ) = address(join).call(
            abi.encodeWithSelector(join.increase_amount.selector, crvValue2)
        );
        if (ret) {
            emit log_bytes32("join inc amnt must fail");
            fail();
        }

        assertTrue(votingEscrow.popLastSender() == address(0));


        addCrvTo(address(this), crvValue2);
        crv.approve(address(join), crvValue2);
        join.increase_amount(crvValue2);
        assertTrue(votingEscrow.popLastSender() == address(bag));


        assertEqM(crv.balanceOf(gauge.voting_escrow()), crvValue+crvValue2, "4");
        assertEqM(crv.balanceOf(address(this)), 0, "5");
        assertEqM(votingEscrow.lockedAmount(bag), crvValue+crvValue2, "6");
        assertEqM(votingEscrow.lockedTime(bag), time1, "7");

        join.increase_unlock_time(time2);
        assertTrue(votingEscrow.popLastSender() == address(bag));

        assertEqM(crv.balanceOf(gauge.voting_escrow()), crvValue+crvValue2, "8");
        assertEqM(crv.balanceOf(address(this)), 0, "9");
        assertEqM(votingEscrow.lockedAmount(bag), crvValue+crvValue2, "10");
        assertEqM(votingEscrow.lockedTime(bag), time1+time2, "11");


    }
}
