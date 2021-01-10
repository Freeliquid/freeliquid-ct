pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./curvePoolMock.sol";
import "./oraclesCurve.sol";

contract Hevm {
    function warp(uint256) public;
}


contract AggregatorV3Stub {
    function decimals() public pure returns (uint8) {
        return 18;
    }

    function description() public pure returns (string memory) {
        return "TEST";
    }

    function version() public pure returns (uint256) {
        return 1;
    }

    int256 public answer = 10**18;

    function setAnswer(int256 answer_) public {
        answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (1, answer, 1602594020, 1602594020, 1);
    }
}


contract TokenWithSymbolUSDC {
    string public symbol = "USDC";
}

contract TokenWithSymbolUSDT {
    string public symbol = "USDT";
}

interface OracleLike {
    function peek() external view returns (bytes32, bool);
}

contract OracleTest is DSTest {
    AggregatorV3Stub public priceETHUSDT;
    AggregatorV3Stub public priceUSDETH;
    CurvePoolMock crvPool;
    CurvePoolMock crvPool2;
    CurvePoolMock crvPool2i;
    CurveAdapterPriceOracle_Buck_Buck oracle;
    CurveAdapterPriceOracle_Buck_Buck oracle2;
    CurveAdapterPriceOracle_Buck_Buck oracle2i;
    CurveAdapterPriceOracle_Buck_Buck oracleBb;
    Token t0;
    Token t1;
    Token t2;

    TokenWithSymbolUSDT ttUSDT;
    TokenWithSymbolUSDC ttUSDC;

    Hevm hevm;

    function assertEqM(
        uint256 a,
        uint256 b,
        bytes32 m
    ) internal {
        if (a != b) {
            emit log_bytes32(m);
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            fail();
        }
    }

    function setUp() public {
        priceETHUSDT = new AggregatorV3Stub();
        priceUSDETH = new AggregatorV3Stub();

        t0 = new Token("USDC", 6);
        t1 = new Token("USDT", 6);
        t2 = new Token("DAI", 18);

        crvPool = new CurvePoolMock();
        crvPool.setupTokens(t0, t1);

        crvPool2 = new CurvePoolMock();
        crvPool2.setupTokens(t1, t2);

        crvPool2i = new CurvePoolMock();
        crvPool2i.setupTokens(t2, t1);

        ttUSDT = new TokenWithSymbolUSDT();
        ttUSDC = new TokenWithSymbolUSDC();

        oracle = new CurveAdapterPriceOracle_Buck_Buck();
        oracle.setup(address(crvPool.token()), address(crvPool), 2);
        oracle.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(t1),
            false
        );

        oracle2 = new CurveAdapterPriceOracle_Buck_Buck();
        oracle2.setup(address(crvPool2.token()), address(crvPool2), 2);
        oracle2.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(t1),
            false
        );

        oracle2i = new CurveAdapterPriceOracle_Buck_Buck();
        oracle2i.setup(address(crvPool2i.token()), address(crvPool2i), 2);
        oracle2i.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(t1),
            false
        );

        oracleBb = new CurveAdapterPriceOracle_Buck_Buck();
        oracleBb.setup(address(crvPool.token()), address(crvPool), 2);
        oracleBb.resetDeployer();
    }

    function testSetup() public {
        CurveAdapterPriceOracle_Buck_Buck oracleEx = new CurveAdapterPriceOracle_Buck_Buck();
        oracleEx.setup(address(crvPool.token()), address(crvPool), 2);
        oracleEx.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(ttUSDT),
            true
        );
    }

    function testFailSetup() public {
        CurveAdapterPriceOracle_Buck_Buck oracleEx = new CurveAdapterPriceOracle_Buck_Buck();
        oracleEx.setup(address(crvPool.token()), address(crvPool), 2);
        oracleEx.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(ttUSDC),
            true
        );
    }

    function testFailSetupEx() public {
        CurveAdapterPriceOracle_Buck_Buck oracleEx = new CurveAdapterPriceOracle_Buck_Buck();
        oracleEx.setup(address(crvPool.token()), address(crvPool), 2);
        oracleEx.setupUsdt(
            address(priceETHUSDT),
            address(priceUSDETH),
            address(t1),
            true
        );
    }



    function mintToCurve2(
        uint256 amnt2,
        uint256 amnt1,
        CurvePoolMock curvePoolRef,
        bool inv
    ) public {
        uint256 reserve0b = curvePoolRef.balances(0);
        uint256 reserve1b = curvePoolRef.balances(1);

        t2.mint(address(curvePoolRef), amnt2);
        t1.mint(address(curvePoolRef), amnt1);

        uint256 reserve0 = curvePoolRef.balances(0);
        uint256 reserve1 = curvePoolRef.balances(1);

        assertEq(reserve0 - reserve0b, inv ? amnt2 : amnt1);
        assertEq(reserve1 - reserve1b, inv ? amnt1 : amnt2);
    }

    function mintToCurve(uint256 amnt0, uint256 amnt1) public {


        uint256 reserve0b = crvPool.balances(0);
        uint256 reserve1b = crvPool.balances(1);

        t0.mint(address(crvPool), amnt0);
        t1.mint(address(crvPool), amnt1);

        uint256 reserve0 = crvPool.balances(0);
        uint256 reserve1 = crvPool.balances(1);

        assertEq(reserve0 - reserve0b, amnt0);
        assertEq(reserve1 - reserve1b, amnt1);
    }

    function mintToCurve(uint256 amnt) public {
        mintToCurve(amnt, amnt);
    }

    function readOracle() public returns (uint256) {
        (bytes32 val, bool has) = oracle.peek();
        assertEq(uint256(has ? 1 : 0), uint256(1));
        return uint256(val);
    }

    function test1() public {
        crvPool.mint(address(this), 1000 * (10**18));
        mintToCurve(1000 * (10**6));
        uint256 val = readOracle();
        assertEq(crvPool.token().totalSupply(), 1000 * (10**18));
        assertEq(t0.totalSupply(), 1000 * (10**6));
        assertEq(t1.totalSupply(), 1000 * (10**6));
        assertEq(val, uint256(2 * 10**18));
    }

    function testBb() public {
        crvPool.mint(address(this), 1000 * (10**18));
        mintToCurve(1000 * (10**6));

        (bytes32 val, bool has) = oracleBb.peek();
        assertEq(uint256(has ? 1 : 0), uint256(1));

        assertEq(crvPool.token().totalSupply(), 1000 * (10**18));
        assertEq(t0.totalSupply(), 1000 * (10**6));
        assertEq(t1.totalSupply(), 1000 * (10**6));
        assertEq(uint256(val), uint256(2 * 10**18));
    }

    function testBbDis() public {
        crvPool.mint(address(this), 1000 * (10**18));
        mintToCurve(1000 * (10**6), 2000 * (10**6));

        (bytes32 val, bool has) = oracleBb.peek();
        assertEq(uint256(has ? 1 : 0), uint256(1));

        assertEq(crvPool.token().totalSupply(), 1000 * (10**18));
        assertEq(t0.totalSupply(), 1000 * (10**6));
        assertEq(t1.totalSupply(), 2000 * (10**6));
        assertEq(uint256(val), uint256(3 * 10**18));
    }

    function implDAI_USDT(
        CurvePoolMock curvePoolRef,
        OracleLike o,
        bool inv
    ) public {
        curvePoolRef.mint(address(this), 1000 * (10**18));
        mintToCurve2(1000 * (10**18), 1000 * (10**6), curvePoolRef, inv);

        (bytes32 val, bool has) = o.peek();
        assertEqM(uint256(has ? 1 : 0), uint256(1), "1");

        assertEqM(curvePoolRef.token().totalSupply(), 1000 * (10**18), "2");
        assertEqM(t2.totalSupply(), 1000 * (10**18), "3");
        assertEqM(t1.totalSupply(), 1000 * (10**6), "4");

        assertEqM(uint256(val), uint256(2 * 10**18), "5");
    }

    function testCrvDAI_USDT() public {
        implDAI_USDT(crvPool2, OracleLike(address(oracle2)), false);
    }

    function testCrvDAI_USDTinv() public {
        implDAI_USDT(crvPool2i, OracleLike(address(oracle2i)), true);
    }

    function test2() public {
        crvPool.mint(address(this), 1000 * (10**18));
        mintToCurve(1000 * (10**6));

        priceETHUSDT.setAnswer(2500000000000000);
        priceUSDETH.setAnswer(200000000000000000000);
        // 1 USDT == 0.5 USD

        uint256 val = readOracle();
        assertEq(crvPool.token().totalSupply(), 1000 * (10**18));
        assertEq(t0.totalSupply(), 1000 * (10**6));
        assertEq(t1.totalSupply(), 1000 * (10**6));
        assertEq(val, uint256(15 * 10**17));
    }

    function test3() public {
        crvPool.mint(address(this), 1000 * (10**18));
        mintToCurve(1000 * (10**6), 2000 * (10**6));

        priceETHUSDT.setAnswer(2500000000000000);
        priceUSDETH.setAnswer(200000000000000000000);
        // 1 USDT == 0.5 USD

        uint256 val = readOracle();
        assertEq(crvPool.token().totalSupply(), 1000 * (10**18));
        assertEq(t0.totalSupply(), 1000 * (10**6));
        assertEq(t1.totalSupply(), 2000 * (10**6));
        assertEq(val, uint256(2 * 10**18));
    }
}
