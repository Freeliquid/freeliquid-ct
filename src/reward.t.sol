pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./uni.sol";
import "./testHelpers.sol";

import "./reward.sol";

contract User {
    bytes32 body;

    function joinHelper(
        GemJoinWithReward j,
        uint256 l,
        address urn
    ) public {
        j.gem().approve(address(j), l);
        j.join(urn, l);
    }

    function exit(GemJoinWithReward j, uint256 l) public {
        j.exit(address(this), l);
    }

    function getReward(StakingRewards rewards) public returns (uint256) {
        return rewards.getReward();
    }

    function registerPairDesc(
        StakingRewards rewards,
        address gem,
        address adapter,
        uint256 factor,
        address staker
    ) public {
        rewards.registerPairDesc(gem, adapter, factor, staker);
    }

    function relyReward(StakingRewards rewards, address usr) public returns (uint256) {
        rewards.rely(usr);
    }
}

contract RewardTest is TestBase {
    StakingRewards rewards;
    GemJoinWithReward join;
    GemJoinWithReward join2;
    GemJoinWithReward join3;
    GemJoinWithReward join4;

    User user1;
    User user2;

    uint256 constant totalRewardsMul = 1e18;
    uint256 totalRewards = 100000 * totalRewardsMul;
    uint256 rewardDuration = 1000000;

    function setUp() public {
        super.setUp();

        user1 = new User();
        user2 = new User();

        rewards = new StakingRewards();
        rewards.setupGemForRewardChecker(address(rewardCheckerTest));

        address vat = address(new VatMock());

        join = new GemJoinWithReward(vat, "testilk", address(uniPair), address(rewards));
        join2 = new GemJoinWithReward(vat, "testilk2", address(uniPair2), address(rewards));
        join3 = new GemJoinWithReward(vat, "testilk3", address(uniPair3), address(rewards));
        join4 = new GemJoinWithReward(vat, "testilk4", address(uniPair4), address(rewards));

        gov.mint(address(rewards), totalRewards);
    }

    function addLiquidity(uint256 v) public returns (uint256) {
        return addLiquidityCore(v, uniPair);
    }

    function addLiquidity2(uint256 v) public returns (uint256) {
        return addLiquidityCore(v, uniPair2);
    }

    function addLiquidity3(uint256 v) public returns (uint256) {
        return addLiquidityCore(v, uniPair3);
    }

    function testVerifyConstruction() public {
        assertTrue(rewards.deployer() == address(this));
    }

    function prepareRewarder(uint256 starttime) public {
        rewards.initialize(address(gov), rewardDuration, totalRewards, starttime);
    }

    function testInitialize() public {
        prepareRewarder(10);
        assertTrue(address(rewards.gov()) == address(gov));

        rewards.registerPairDesc(address(uniPair), address(sadapter), 2, address(this));

        (address gem, address adapter, address staker, uint256 factor, ) =
            rewards.pairDescs(address(uniPair));
        assertEq(address(this), address(staker));
        assertEq(gem, address(uniPair));
        assertEq(adapter, address(sadapter));
        assertEq(factor, 2);

        (gem, adapter, staker, factor, ) = rewards.pairDescs(address(0x0));
        assertEq(gem, address(0));
        assertEq(adapter, address(0));
        assertEq(staker, address(0));
        assertEq(factor, 0);
    }

    function joinHelper(GemJoinWithReward j, uint256 l) public {
        j.gem().approve(address(j), l);
        j.join(address(this), l);
    }

    function joinHelperOwner(
        GemJoinWithReward j,
        uint256 l,
        address owner
    ) public {
        j.gem().approve(address(j), l);
        j.join(owner, l);
    }

    function testGovLaterRegisterPreStakeMode0() public {
        implGovLaterRegister(0);
    }

    function testGovLaterRegisterPreStakeMode1() public {
        implGovLaterRegister(1);
    }

    function testGovLaterRegisterPreStakeMode2() public {
        implGovLaterRegister(2);
    }

    function implGovLaterRegister(uint256 preStakeMode) public {
        uint256 starttime = 10;
        prepareRewarder(starttime);

        uniPair.approve(address(rewards));
        uniPair2.approve(address(rewards));

        uint256 alltime = rewardDuration;
        assertTrue(address(rewards.gov()) == address(gov));

        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));

        hevm.warp(starttime + 1);

        assertFail(
            address(user1),
            abi.encodeWithSelector(
                user1.registerPairDesc.selector,
                rewards,
                address(uniPair2),
                address(sadapter),
                1,
                address(join2)
            ),
            "no auth u1"
        );

        rewards.rely(address(user1));

        assertFail(
            address(user2),
            abi.encodeWithSelector(
                user2.registerPairDesc.selector,
                rewards,
                address(uniPair2),
                address(sadapter),
                1,
                address(join2)
            ),
            "no auth u2"
        );

        rewards.resetDeployer();

        assertFail(
            address(rewards),
            abi.encodeWithSelector(rewards.rely.selector, address(user2)),
            "rely after resetDeployer"
        );

        user1.relyReward(rewards, address(user2));

        uint256 value = 1000000;

        uint256 uniPairAmnt = addLiquidityCore(value, uniPair);
        uint256 uniPair2Amnt = addLiquidityCore(value, uniPair2);
        uniPair.transfer(address(user1), uniPairAmnt);
        uniPair2.transfer(address(user2), uniPair2Amnt);

        assertEqM(rewards.balanceOf(address(user1)), 0, "rewards user1 bal");
        user1.joinHelper(join, uniPairAmnt, address(this));
        assertEqM(uniPair.balanceOf(address(join)), uniPairAmnt, "uniPair bal uniAmnt");

        assertEqM(rewards.balanceOf(address(user1)), value * 2 * 1e18, "rewards bal u1");

        if (preStakeMode > 0) {
            user2.joinHelper(join2, uniPair2Amnt, address(this));
            //zero b/c pair is not registered
            assertEqM(rewards.balanceOf(address(user2)), 0, "rewards bal u2 zero");
            assertEqM(uniPair2.balanceOf(address(join2)), uniPair2Amnt, "uniPair2 bal uniAmnt2");
        }

        hevm.warp(starttime + 1 + alltime / 2);
        assertEqM(rewards.earned(address(user1)), totalRewards / 2, "earned 1 hl2");

        if (preStakeMode == 1) user2.exit(join2, uniPair2Amnt);

        user2.registerPairDesc(rewards, address(uniPair2), address(sadapter), 1, address(join2));

        if (preStakeMode == 2) user2.exit(join2, uniPair2Amnt);

        assertEqM(uniPair2.balanceOf(address(join2)), 0, "uniPair2 bal uniAmnt2 zero");
        assertEqM(rewards.balanceOf(address(user2)), 0, "rewards bal u2 zero");
        user2.joinHelper(join2, uniPair2Amnt, address(this));
        assertEqM(rewards.balanceOf(address(user2)), value * 2 * 1e18, "rewards bal u2 II");
        assertEqM(uniPair2.balanceOf(address(join2)), uniPair2Amnt, "uniPair2 bal uniAmnt2 II");

        hevm.warp(starttime + alltime + 100);

        assertEqM(
            rewards.earned(address(user1)) / 1e18 + 1,
            (totalRewards * 3) / 4 / 1e18,
            "earned 1"
        );
        assertEqM(rewards.earned(address(user2)) / 1e18 + 1, totalRewards / 4 / 1e18, "earned 2");
    }

    function testUniAdapter() public {
        uint256 v = 10000;
        uint256 l = addLiquidity(v);
        assertEq(l, uniPair.totalSupply());

        (uint112 reserve0, uint112 reserve1, ) = uniPair.getReserves();

        assertEq(reserve0, v * uint256(10)**18);
        assertEq(reserve1, v * uint256(10)**8);

        assertEq(reserve0, token0.balanceOf(address(uniPair)));
        assertEq(reserve1, token1.balanceOf(address(uniPair)));

        uint256 r = sadapter.calc(address(uniPair), l, 1);
        assertEq(r, v * 2 * valueMult);

        uint256 v2 = 30000;
        uint256 l2 = addLiquidity(v2);

        r = sadapter.calc(address(uniPair), l2, 1);
        assertEq(r, v2 * 2 * valueMult);

        v = 171234;
        l = addLiquidity(v);

        r = sadapter.calc(address(uniPair), l, 1);
        assertEq(r, v * 2 * valueMult);

        r = sadapter.calc(address(uniPair), l2, 1);
        assertEq(r, v2 * 2 * valueMult);

        v = 3;
        l = addLiquidity(v);

        r = sadapter.calc(address(uniPair), l, 1);
        assertEq(r, v * 2 * valueMult);

        r = sadapter.calc(address(uniPair), l2, 1);
        assertEq(r, v2 * 2 * valueMult);
    }

    function testRightsForStake() public {
        uint256 starttime = 10;
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));
        rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(this));

        uint256 v = 10000;
        uint256 l = addLiquidity(v);
        uint256 l2 = addLiquidity2(v);

        hevm.warp(starttime + 1);

        (bool ret, ) =
            address(rewards).call(
                abi.encodeWithSelector(
                    rewards.stake.selector,
                    l2,
                    address(uniPair3),
                    address(this)
                )
            );
        if (ret) {
            emit log_bytes32("stake must fail,wrong pair");
            fail();
        }

        (ret, ) = address(rewards).call(
            abi.encodeWithSelector(rewards.stake.selector, l, address(uniPair), address(this))
        );
        if (ret) {
            emit log_bytes32("stake must fail,no rights");
            fail();
        }

        rewards.stake(l2, address(uniPair2), address(this));
    }

    function testFlashLoans() public {
        uint256 starttime = 10;
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));

        uint256 v = 10000;
        uint256 l = addLiquidity(v);

        assertEq(uniPair.balanceOf(address(this)), l);
        assertEq(uniPair.balanceOf(address(rewards)), 0);
        uniPair.approve(address(rewards), l);

        assertEq(rewards.balanceOf(address(this)), 0);
        assertEq(rewards.totalSupply(), 0);

        hevm.warp(starttime + 1);
        uint256 rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, 0, "rewardReady 0");

        joinHelper(join, l);

        assertEqM(rewards.balanceOf(address(this)), 2 * v * valueMult, "rewards.balanceOf(this)");
        assertEqM(rewards.totalSupply(), 2 * v * valueMult, "rewards.totalSupply");

        join.exit(address(this), l);

        rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, 0, "rewardReady 0 a");

        hevm.warp(starttime + 10);

        uint256 uniPairAmnt = addLiquidityCore(v, uniPair);
        uniPair.transfer(address(user1), uniPairAmnt);

        user1.joinHelper(join, uniPairAmnt, address(this));

        hevm.warp(starttime + 50);

        joinHelper(join, l);
        join.exit(address(this), l);

        hevm.warp(starttime + 100);

        assertEqM(rewards.earned(address(user1)), 9000000000000000000, "reward u1 0 a");
    }

    function testStakeUnstake() public {
        uint256 starttime = 10;
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));

        uint256 v = 10000;
        uint256 l = addLiquidity(v);

        assertEq(uniPair.balanceOf(address(this)), l);
        assertEq(uniPair.balanceOf(address(rewards)), 0);
        uniPair.approve(address(rewards), l);

        assertEq(rewards.balanceOf(address(this)), 0);
        assertEq(rewards.totalSupply(), 0);

        (bool ret, ) =
            address(this).call(abi.encodeWithSelector(this.joinHelper.selector, address(join), l));
        if (ret) {
            emit log_bytes32("join.join fail expected");
            fail();
        }

        hevm.warp(starttime + 1);
        uint256 rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, 0, "rewardReady 0");

        joinHelper(join, l);

        hevm.warp(starttime + rewardDuration / 2 + 1);
        rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, totalRewards / 2, "rewardReady totalRewards/2");

        assertEq(uniPair.balanceOf(address(this)), 0);
        assertEq(uniPair.balanceOf(address(join)), l);

        assertEq(rewards.balanceOf(address(this)), v * 2 * valueMult);
        assertEq(rewards.totalSupply(), v * 2 * valueMult);

        uint256 v2 = 110000;
        uint256 l2 = addLiquidity(v2);

        assertEq(uniPair.balanceOf(address(this)), l2);
        assertEq(uniPair.balanceOf(address(join)), l);
        uniPair.approve(address(rewards), l2);

        joinHelper(join, l2);
        assertEq(uniPair.balanceOf(address(this)), 0);
        assertEq(uniPair.balanceOf(address(join)), l + l2);

        assertEq(rewards.balanceOf(address(this)), (v * 2 + v2 * 2) * valueMult);
        assertEq(rewards.totalSupply(), (v * 2 + v2 * 2) * valueMult);

        hevm.warp(starttime + (rewardDuration * 400) / 500 + 1);
        rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, (totalRewards * 400) / 500, "rewardReady totalRewards 4/5 a");

        uint256 w = (l2 * 30) / 100;
        join.exit(address(this), w);
        assertEq(uniPair.balanceOf(address(this)), w);
        assertEq(uniPair.balanceOf(address(join)), l + l2 - w);

        rewardReady = rewards.earned(address(this));
        assertEqM(rewardReady, (totalRewards * 400) / 500, "rewardReady totalRewards 4/5 b");

        uint256 rem = sadapter.calc(address(uniPair), l + l2 - w, 1);

        assertEq(rewards.balanceOf(address(this)), rem);
        assertEq(rewards.totalSupply(), rem);

        hevm.warp(starttime + (rewardDuration * 90) / 100 + 1);
        rewardReady = rewards.earned(address(this));
        assertEqM(
            rewardReady / 1e8 + 1,
            (totalRewards * 90) / 100 / 1e8,
            "rewardReady totalRewards 9/10"
        );

        hevm.warp(starttime + rewardDuration + 2);
        rewardReady = rewards.earned(address(this));
        assertEqM(
            rewardReady / totalRewardsMul + 1,
            totalRewards / totalRewardsMul,
            "rewardReady totalRewards 100%"
        );

        (ret, ) = address(join).call(
            abi.encodeWithSelector(join.exit.selector, address(this), l + l2 - w + 1)
        );
        if (ret) {
            emit log_bytes32("rewards.withdraw fail expected");
            fail();
        }

        assertEq(uniPair.balanceOf(address(this)), w);
        assertEq(uniPair.balanceOf(address(join)), l + l2 - w);

        join.exit(address(this), l + l2 - w);
        assertEq(uniPair.balanceOf(address(this)), l + l2);
        assertEq(uniPair.balanceOf(address(join)), 0);

        assertEq(rewards.balanceOf(address(this)), 0);
        assertEq(rewards.totalSupply(), 0);
    }

    struct StakeUnstacke3UniVars {
        uint256 v;
        uint256 l;
        uint256 v2;
        uint256 l2;
        uint256 v22;
        uint256 l22;
        uint256 v3;
        uint256 l3;
        uint256 w;
        uint256 rem;
        uint256 w3;
        uint256 rem3;
        uint256 w12;
        uint256 rem12;
    }

    function testStakeUnstacke3Uni() public {
        uint256 starttime = 10;
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));
        rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(join2));
        rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));

        rewards.resetDeployer();

        assertFail(
            address(rewards),
            abi.encodeWithSelector(
                rewards.registerPairDesc.selector,
                address(uniPair),
                address(sadapter),
                1,
                address(join)
            ),
            "resetDeployer fail expected"
        );

        uniPair.approve(address(rewards));
        uniPair2.approve(address(rewards));
        uniPair3.approve(address(rewards));

        StakeUnstacke3UniVars memory vars;

        vars.v = 10000;
        vars.l = addLiquidity(vars.v / 2);

        hevm.warp(starttime + 1);
        joinHelper(join, vars.l);

        assertEqM(uniPair.balanceOf(address(this)), 0, "-4");
        assertEqM(uniPair.balanceOf(address(join)), vars.l, "-3");

        assertEqM(rewards.balanceOf(address(this)), vars.v * valueMult, "balanceOf vars.v");
        assertEqM(rewards.totalSupply(), vars.v * valueMult, "totalSupply vars.v");

        vars.v2 = 20000;
        vars.l2 = addLiquidity2(vars.v2 / 2);
        joinHelper(join2, vars.l2);

        assertEqM(uniPair.balanceOf(address(this)), 0, "-2");
        assertEqM(uniPair.balanceOf(address(join)), vars.l, "-1");

        assertEqM(uniPair2.balanceOf(address(this)), 0, "1");
        assertEqM(uniPair2.balanceOf(address(join2)), vars.l2, "2");

        assertEqM(rewards.balanceOf(address(this)), (vars.v2 + vars.v) * valueMult, "3");
        assertEqM(rewards.totalSupply(), (vars.v2 + vars.v) * valueMult, "4");

        vars.v22 = 1000;
        vars.l22 = addLiquidity2(vars.v22 / 2);
        joinHelper(join2, vars.l22);

        assertEq(uniPair.balanceOf(address(this)), 0);
        assertEq(uniPair.balanceOf(address(join)), vars.l);

        assertEqM(uniPair2.balanceOf(address(this)), 0, "21");
        assertEqM(uniPair2.balanceOf(address(join2)), vars.l2 + vars.l22, "22");

        assertEqM(
            rewards.balanceOf(address(this)),
            (vars.v22 + vars.v2 + vars.v) * valueMult,
            "23"
        );
        assertEqM(rewards.totalSupply(), (vars.v22 + vars.v2 + vars.v) * valueMult, "24");

        vars.v3 = 200000;
        vars.l3 = addLiquidity3(vars.v3 / 2);
        joinHelper(join3, vars.l3);

        assertEq(uniPair.balanceOf(address(this)), 0);
        assertEq(uniPair.balanceOf(address(join)), vars.l);

        assertEqM(uniPair2.balanceOf(address(this)), 0, "31");
        assertEqM(uniPair2.balanceOf(address(join2)), vars.l2 + vars.l22, "32");

        assertEqM(uniPair3.balanceOf(address(this)), 0, "33");
        assertEqM(uniPair3.balanceOf(address(join3)), vars.l3, "34");

        assertEqM(
            rewards.balanceOf(address(this)),
            (vars.v3 + vars.v22 + vars.v2 + vars.v) * valueMult,
            "35"
        );
        assertEqM(
            rewards.totalSupply(),
            (vars.v3 + vars.v22 + vars.v2 + vars.v) * valueMult,
            "36"
        );

        /////////////////////
        vars.w = (vars.l * 30) / 100;
        join.exit(address(this), vars.w);
        assertEq(uniPair.balanceOf(address(this)), vars.w);
        assertEq(uniPair.balanceOf(address(join)), vars.l - vars.w);

        assertEqM(uniPair2.balanceOf(address(this)), 0, "41");
        assertEqM(uniPair2.balanceOf(address(join2)), vars.l2 + vars.l22, "42");

        assertEqM(uniPair3.balanceOf(address(this)), 0, "43");
        assertEqM(uniPair3.balanceOf(address(join3)), vars.l3, "44");

        vars.rem = sadapter.calc(address(uniPair), vars.w, 1);

        assertEq(
            rewards.balanceOf(address(this)),
            (vars.v3 + vars.v22 + vars.v2 + vars.v) * valueMult - vars.rem
        );

        /////////////////////
        vars.w3 = (vars.l3 * 50) / 100;
        join3.exit(address(this), vars.w3);
        assertEq(uniPair.balanceOf(address(this)), vars.w);
        assertEq(uniPair.balanceOf(address(join)), vars.l - vars.w);

        assertEq(uniPair3.balanceOf(address(this)), vars.w3);
        assertEq(uniPair3.balanceOf(address(join3)), vars.l3 - vars.w3);

        vars.rem3 = sadapter.calc(address(uniPair3), vars.w3, 1);

        assertEq(
            rewards.balanceOf(address(this)),
            (vars.v3 + vars.v22 + vars.v2 + vars.v) * valueMult - vars.rem - vars.rem3
        );

        /////////////////////
        vars.w12 = vars.l - vars.w;
        join.exit(address(this), vars.w12);
        assertEqM(uniPair.balanceOf(address(this)), vars.w + vars.w12, "511");
        assertEqM(uniPair.balanceOf(address(this)), vars.l, "512");
        assertEqM(uniPair.balanceOf(address(join)), 0, "513");

        assertEqM(uniPair2.balanceOf(address(this)), 0, "51");
        assertEqM(uniPair2.balanceOf(address(join2)), vars.l2 + vars.l22, "52");

        assertEq(uniPair3.balanceOf(address(this)), vars.w3);
        assertEq(uniPair3.balanceOf(address(join3)), vars.l3 - vars.w3);

        vars.rem12 = sadapter.calc(address(uniPair), vars.w12, 1);

        assertEqM(
            rewards.balanceOf(address(this)),
            (vars.v3 + vars.v22 + vars.v2 + vars.v) *
                valueMult -
                vars.rem -
                vars.rem3 -
                vars.rem12,
            "55"
        );
        assertEqM(
            rewards.balanceOf(address(this)),
            (vars.v3 + vars.v22 + vars.v2) * valueMult - vars.rem3,
            "56"
        );
        assertEqM(
            rewards.totalSupply(),
            (vars.v3 + vars.v22 + vars.v2) * valueMult - vars.rem3,
            "57"
        );
    }

    function rewardForTwoUsers(
        uint256 value1,
        uint256 value2,
        uint256 amntMult,
        uint256 expectEarned1,
        uint256 expectEarned2,
        int256 err,
        bool claimTimeInvariant1
    ) public {
        uint256 starttime = 10;
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));
        rewards.registerPairDesc(address(uniPair4), address(sadapter), 1, address(join4));

        uniPair3.approve(address(rewards));
        uniPair4.approve(address(rewards));

        uint256 errPrec = 1e5;

        uint256 uniPair3Amnt = addLiquidityCore(value1, uniPair3);
        uint256 uniPair4Amnt = addLiquidityCore(value2, uniPair4);
        uniPair3.transfer(address(user1), uniPair3Amnt);
        uniPair4.transfer(address(user2), uniPair4Amnt);

        assertEqM(uniPair3Amnt / uniPair4Amnt, amntMult, "uniPair3Amnt/uniPair4Amnt");
        assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt");
        assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt");

        hevm.warp(starttime + 1);

        user1.joinHelper(join3, uniPair3Amnt, address(this));
        user2.joinHelper(join4, uniPair4Amnt, address(this));

        assertEqM(0, uniPair3.balanceOf(address(user1)), "uniPair3Amnt 0");
        assertEqM(0, uniPair4.balanceOf(address(user2)), "uniPair4Amnt 0");

        assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3");
        assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4");

        assertEqM(
            2 * value1 * valueMult,
            rewards.calcCheckValue(uniPair3Amnt, address(uniPair3)),
            "uniPair3Amnt value"
        );
        assertEqM(
            2 * value2 * valueMult,
            rewards.calcCheckValue(uniPair4Amnt, address(uniPair4)),
            "uniPair4Amnt value"
        );

        assertEqM(rewards.earned(address(user1)), 0, "rewardReadyOnStart1 is 0");
        assertEqM(rewards.earned(address(user2)), 0, "rewardReadyOnStart2 is 0");

        hevm.warp(starttime + rewardDuration / 2 + 1);

        uint256 earned1 = rewards.earned(address(user1));
        uint256 earned2 = rewards.earned(address(user2));
        assertEqM(earned1 / errPrec, expectEarned1 / errPrec, "rewardReadyOnHL1 is 1/4");
        assertEqM(earned2 / errPrec, expectEarned2 / errPrec, "rewardReadyOnHL2 is 1/4");
        assertEqM(
            uint256(int256((earned1 + earned2) / errPrec) + err),
            totalRewards / 2 / errPrec,
            "tot rewardReadyOnHL2 is 1/2"
        );

        assertEqM(0, gov.balanceOf(address(user1)), "gov1 bal zero");
        assertEqM(0, gov.balanceOf(address(user2)), "gov2 bal zero");

        assertEqM(totalRewards, gov.balanceOf(address(rewards)), "gov rewards bal full");

        if (!claimTimeInvariant1) {
            assertEqM(earned1, user1.getReward(rewards), "getReward1");
        }
        assertEqM(earned2, user2.getReward(rewards), "getReward2");

        if (!claimTimeInvariant1) {
            assertEqM(rewards.earned(address(user1)), 0, "earned1 0 after claim");
        } else {
            assertEqM(
                rewards.earned(address(user1)) / errPrec,
                expectEarned1 / errPrec,
                "earned1 as expected after claim"
            );
        }
        assertEqM(rewards.earned(address(user2)), 0, "earned2 0 after claim");

        if (!claimTimeInvariant1) {
            assertEqM(earned1, gov.balanceOf(address(user1)), "gov1 bal");
        } else {
            assertEqM(0, gov.balanceOf(address(user1)), "gov1 bal zero after claim");
        }
        assertEqM(earned2, gov.balanceOf(address(user2)), "gov2 bal");

        if (!claimTimeInvariant1) {
            assertEqM(
                totalRewards - (earned1 + earned2),
                gov.balanceOf(address(rewards)),
                "gov rewards bal was spent inv"
            );
        } else {
            assertEqM(
                totalRewards - (earned2),
                gov.balanceOf(address(rewards)),
                "gov rewards bal was spent"
            );
        }

        user1.exit(join3, uniPair3Amnt);

        assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt user1 exit");
        assertEqM(0, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3 exit");

        hevm.warp(starttime + rewardDuration * 2); //to the future

        uint256 earned1f = rewards.earned(address(user1));
        uint256 earned2f = rewards.earned(address(user2));
        if (!claimTimeInvariant1) {
            assertEqM(earned1f, 0, "rewardReadyInFuture1 is 0");
        } else {
            assertEqM(
                earned1f / errPrec,
                expectEarned1 / errPrec,
                "rewardReadyInFuture1 is not 0"
            );
        }
        assertEqM(
            earned2f / totalRewardsMul + 1,
            (totalRewards - (earned1 + earned2)) / totalRewardsMul,
            "rewardReadyInFuture2 is remain"
        );

        if (!claimTimeInvariant1) {
            assertEqM(0, user1.getReward(rewards), "getReward1f is 0");
        } else {
            assertEqM(earned1f, user1.getReward(rewards), "getReward1f is 0");
        }
        assertEqM(earned2f, user2.getReward(rewards), "getReward2 is remain");

        assertEqM(earned1, gov.balanceOf(address(user1)), "gov1f bal");
        assertEqM(earned2 + earned2f, gov.balanceOf(address(user2)), "gov2f bal");

        assertEqM(
            totalRewards - (earned1 + earned2 + earned2f),
            gov.balanceOf(address(rewards)),
            "gov rewards bal near 0"
        );
        assertEqM(gov.balanceOf(address(rewards)) / totalRewardsMul, 0, "gov rewards bal is 1");

        assertEqM(0, user1.getReward(rewards), "getReward1ff is 0");
        assertEqM(0, user2.getReward(rewards), "getReward2ff is 0");

        assertEqM(rewards.earned(address(user1)), 0, "earned1f 0 after claim");
        assertEqM(rewards.earned(address(user1)), 0, "earned2f 0 after claim");

        assertEqM(earned1, gov.balanceOf(address(user1)), "gov1f bal");
        assertEqM(earned2 + earned2f, gov.balanceOf(address(user2)), "gov2f bal");

        hevm.warp(starttime + rewardDuration * 3); //to the future x3

        assertEqM(rewards.earned(address(user1)), 0, "earned1fff 0");
        assertEqM(rewards.earned(address(user1)), 0, "earned2fff 0");

        assertEqM(0, user1.getReward(rewards), "getReward1fff is 0");
        assertEqM(0, user2.getReward(rewards), "getReward2fff is 0");

        assertEqM(earned1, gov.balanceOf(address(user1)), "gov1fff bal");
        assertEqM(earned2 + earned2f, gov.balanceOf(address(user2)), "gov2fff bal");

        user2.exit(join4, uniPair4Amnt);

        assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt user1 exit");
        assertEqM(0, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join3 exit");

        assertEqM(rewards.earned(address(user1)), 0, "earned1fff 0");
        assertEqM(rewards.earned(address(user1)), 0, "earned2fff 0");

        assertEqM(0, user1.getReward(rewards), "getReward1fff is 0");
        assertEqM(0, user2.getReward(rewards), "getReward2fff is 0");
    }

    function testRewardIsBasedOnUSDEquityNotTokenAmnt() public {
        rewardForTwoUsers(
            10000,
            10000,
            1000000000000000,
            totalRewards / 4,
            totalRewards / 4,
            0,
            false
        );
    }

    function testRewardIsBasedOnUSDEquityDifferentUsers() public {
        rewardForTwoUsers(
            10000,
            20000,
            500000000000000,
            16666666666666666666666,
            33333333333333333333333,
            1,
            false
        );
    }

    function testRewardIsBasedOnUSDEquityNotTokenAmntClaimInvariant() public {
        rewardForTwoUsers(
            10000,
            10000,
            1000000000000000,
            totalRewards / 4,
            totalRewards / 4,
            0,
            true
        );
    }

    function testRewardIsBasedOnUSDEquityDifferentUsersClaimInvariant() public {
        rewardForTwoUsers(
            10000,
            20000,
            500000000000000,
            16666666666666666666666,
            33333333333333333333333,
            1,
            true
        );
    }

    function checkFairDistribution(uint256 mode, bool fairDistributionEnabled) public {
        uint256 starttime = 10;
        uint256 value1 = 50000;
        uint256 value2 = 50000;

        if (mode == 1) {
            value1 = 50001;
        } else if (mode == 2) {
            value2 = 50001;
        }

        if (!fairDistributionEnabled) {
            value1 = 160001;
            value2 = 160001;
        }

        uint256 fairDistributionTime = 60;
        prepareRewarder(starttime);

        if (fairDistributionEnabled) {
            rewards.setupFairDistribution(100000, fairDistributionTime);
        }

        rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));
        rewards.registerPairDesc(address(uniPair4), address(sadapter), 1, address(join4));

        uniPair3.approve(address(rewards));
        uniPair4.approve(address(rewards));

        uint256 uniPair3Amnt = addLiquidityCore(value1, uniPair3);
        uint256 uniPair4Amnt = addLiquidityCore(value2, uniPair4);
        uniPair3.transfer(address(user1), uniPair3Amnt);
        uniPair4.transfer(address(user2), uniPair4Amnt);

        assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt");
        assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt");

        hevm.warp(starttime + 1);

        assertEqM(
            2 * value1 * valueMult,
            rewards.calcCheckValue(uniPair3Amnt, address(uniPair3)),
            "uniPair3Amnt value"
        );
        assertEqM(
            2 * value2 * valueMult,
            rewards.calcCheckValue(uniPair4Amnt, address(uniPair4)),
            "uniPair4Amnt value"
        );

        if (mode == 1) {
            assertTrue(
                !rewards.testFairDistribution(address(user1), address(uniPair3), uniPair3Amnt)
            );

            (bool ret, ) =
                address(user1).call(
                    abi.encodeWithSelector(
                        user1.joinHelper.selector,
                        join3,
                        uniPair3Amnt,
                        address(this)
                    )
                );
            if (ret) {
                emit log_bytes32("user1.joinHelper fail expected");
                fail();
            }

            assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt");
            assertEqM(0, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3 0");
        } else {
            assertTrue(
                rewards.testFairDistribution(address(user1), address(uniPair3), uniPair3Amnt)
            );
            user1.joinHelper(join3, uniPair3Amnt, address(this));

            assertEqM(0, uniPair3.balanceOf(address(user1)), "uniPair3Amnt 0");
            assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3");
        }

        if (mode == 2) {
            assertTrue(
                !rewards.testFairDistribution(address(user2), address(uniPair4), uniPair4Amnt)
            );
            (bool ret, ) =
                address(user2).call(
                    abi.encodeWithSelector(
                        user2.joinHelper.selector,
                        join4,
                        uniPair4Amnt,
                        address(this)
                    )
                );
            if (ret) {
                emit log_bytes32("user2.joinHelper fail expected");
                fail();
            }

            assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt");
            assertEqM(0, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4 0");
        } else {
            assertTrue(
                rewards.testFairDistribution(address(user2), address(uniPair4), uniPair4Amnt)
            );
            user2.joinHelper(join4, uniPair4Amnt, address(this));

            assertEqM(0, uniPair4.balanceOf(address(user2)), "uniPair4Amnt 0");
            assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4");
        }

        hevm.warp(starttime + fairDistributionTime + 1);

        if (mode == 1) {
            assertTrue(
                rewards.testFairDistribution(address(user1), address(uniPair3), uniPair3Amnt)
            );
            user1.joinHelper(join3, uniPair3Amnt, address(this));
            assertEqM(0, uniPair3.balanceOf(address(user1)), "uniPair3Amnt 0");
            assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3");
        }

        if (mode == 2) {
            assertTrue(
                rewards.testFairDistribution(address(user2), address(uniPair4), uniPair4Amnt)
            );
            user2.joinHelper(join4, uniPair4Amnt, address(this));
            assertEqM(0, uniPair4.balanceOf(address(user2)), "uniPair4Amnt 0");
            assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4");
        }

        user1.exit(join3, uniPair3Amnt);
        assertEqM(uniPair3Amnt, uniPair3.balanceOf(address(user1)), "uniPair3Amnt");
        assertEqM(0, uniPair3.balanceOf(address(join3)), "uniPair3Amnt join3 0");

        user2.exit(join4, uniPair4Amnt);
        assertEqM(uniPair4Amnt, uniPair4.balanceOf(address(user2)), "uniPair4Amnt");
        assertEqM(0, uniPair4.balanceOf(address(join4)), "uniPair4Amnt join4 0");
    }

    function testFairDistribution0() public {
        checkFairDistribution(0, true);
    }

    function testFairDistribution1() public {
        checkFairDistribution(1, true);
    }

    function testFairDistribution2() public {
        checkFairDistribution(2, true);
    }

    function testFairDistributionDisabled() public {
        checkFairDistribution(0, false);
    }

    function testPartialTimes() public {
        uint256 starttime = 10;
        rewardDuration = 259200;
        totalRewards = 100000 * (10**18);
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));
        rewards.registerPairDesc(address(uniPair2), address(sadapter), 1, address(join2));
        rewards.registerPairDesc(address(uniPair3), address(sadapter), 1, address(join3));

        uniPair.approve(address(rewards));
        uniPair2.approve(address(rewards));
        uniPair3.approve(address(rewards));

        uint256 v1 = 10000;
        uint256 l1 = addLiquidity(v1 / 2);

        uint256 v2 = 14000;
        uint256 l2 = addLiquidity2(v2 / 2);

        uint256 v3 = 5000;
        uint256 l3 = addLiquidity3(v3 / 2);

        hevm.warp(starttime + rewardDuration / 3);
        joinHelper(join, l1);

        hevm.warp(starttime + rewardDuration / 3 + rewardDuration / 10);
        joinHelper(join2, l2);

        hevm.warp(starttime + rewardDuration / 3 + rewardDuration / 10 + 100);
        uint256 reward = rewards.getReward();

        hevm.warp(starttime + rewardDuration / 3 + rewardDuration / 8);
        joinHelper(join3, l3);

        hevm.warp(starttime + rewardDuration - rewardDuration / 8);
        join.exit(address(this), l1);

        hevm.warp(starttime + rewardDuration + 1);
        join2.exit(address(this), l2);
        join3.exit(address(this), l3);

        uint256 rewardReady = rewards.earned(address(this)) + reward;
        assertEqM(
            rewardReady / (10**18),
            (2 * totalRewards) / 3 / (10**18),
            "rewardReady totalRewards/3"
        );
    }

    function testStartTimeAfterCreate() public {
        rewardDuration = 259200;
        totalRewards = 100000 * (10**18);
        hevm.warp(100);
        uint256 starttime = 90;

        assertFail(
            address(rewards),
            abi.encodeWithSelector(
                rewards.initialize.selector,
                address(gov),
                rewardDuration,
                totalRewards,
                starttime
            ),
            "init have to fail"
        );

        starttime = 100;
        rewards.initialize(address(gov), rewardDuration, totalRewards, starttime);
    }

    function testRepeat() public {
        uint256 starttime = 1603497774;
        rewardDuration = 259200;
        totalRewards = 100000 * (10**18);
        hevm.warp(1603497774 - 3600);
        prepareRewarder(starttime);
        rewards.registerPairDesc(address(uniPair), address(sadapter), 1, address(join));

        //1603673652 create time

        uniPair.approve(address(rewards));

        uint256 v1 = 10000;
        uint256 l1 = addLiquidity(v1 / 2);

        uint256 v2 = 14000;
        uint256 l2 = addLiquidity(v2 / 2);

        hevm.warp(1603743120);
        joinHelper(join, l1);

        hevm.warp(1603749400);
        uint256 reward1 = rewards.getReward();

        //end at 1603756974

        hevm.warp(1603803448);
        uint256 reward2 = rewards.getReward();

        hevm.warp(1603824204);
        uint256 reward3 = rewards.getReward();

        hevm.warp(1603824252);
        joinHelper(join, l2);

        hevm.warp(1603998768);
        uint256 reward4 = rewards.getReward();

        assertEqM(reward1 / (10**18), 2422, "reward1");
        assertEqM(reward2 / (10**18), 2922, "reward2");
        assertEqM(reward3 / (10**18), 0, "reward3");
        assertEqM(reward4 / (10**18), 0, "reward4");
    }
}
