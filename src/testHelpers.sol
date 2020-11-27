pragma solidity ^0.5.10;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./uni.sol";
import "./gemForRewardChecker.sol";

contract Hevm {
    function warp(uint256) public;
}

contract UniswapV2Pair is DSToken("UNIv2") {
    constructor(address _t0, address _t1) public {
        decimals = 18;
        t0 = _t0;
        t1 = _t1;
    }

    address t0;
    address t1;
    uint112 reserve0;
    uint112 reserve1;

    bool thrownExc = false;

    function setThrownExc() public {
        thrownExc = true;
    }

    function resetThrownExc() public {
        thrownExc = false;
    }

    function token0() external view returns (address) {
        return t0;
    }

    function token1() external view returns (address) {
        return t1;
    }

    function setReserve0(uint112 _reserve0) external {
        reserve0 = _reserve0;
    }

    function setReserve1(uint112 _reserve1) external {
        reserve1 = _reserve1;
    }

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 blockTimestampLast
        )
    {
        require(!thrownExc);
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        blockTimestampLast = 0;
    }
}

contract Token0 is DSToken("TOKEN0") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract Token1 is DSToken("TOKEN1") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract Token2 is DSToken("TOKEN2") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract Token3 is DSToken("TOKEN3") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract Token4 is DSToken("TOKEN4") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract TokenVolatile is DSToken("VOLATILE") {
    constructor(uint256 d) public {
        decimals = d;
    }
}

contract VatMock {
    function slip(
        bytes32,
        address,
        int256
    ) external {}

    function move(
        address,
        address,
        uint256
    ) external {}
}

contract USDN is DSToken("USDN") {}
contract DAI is DSToken("DAI") {}

contract UniForRewardCheckerTest is UniForRewardCheckerBase {
    function add(DSToken token) public {
        tokens[address(token)] = true;
    }
}

contract TestBase is DSTest {
    DSToken token0;
    DSToken token1;
    DSToken token2;
    DSToken token3;
    DSToken token4;
    DSToken tokenVolatile;
    UniswapV2Pair uniPair;
    UniswapV2Pair uniPair2;
    UniswapV2Pair uniPair3;
    UniswapV2Pair uniPair4;
    UniswapV2Pair uniPairVolatile1;
    UniswapV2Pair uniPairVolatile2;
    DSToken gov;
    UniswapAdapterForStables sadapter;
    UniswapAdapterWithOneStable sadapterOne;
    GemForRewardChecker rewardCheckerTest;

    Hevm hevm;
    uint256 valueMult = 1e18;

    function setUp() public {
        gov = new DSToken("GOV");
        token0 = new Token0(18);
        token1 = new Token1(8);
        token2 = new Token2(24);
        token3 = new Token3(6);
        token4 = new Token4(6);
        tokenVolatile = new TokenVolatile(10);

        UniForRewardCheckerTest singleChecker = new UniForRewardCheckerTest();
        singleChecker.add(token0);
        singleChecker.add(token1);
        singleChecker.add(token2);
        singleChecker.add(token3);
        singleChecker.add(token4);
        singleChecker.add(tokenVolatile);
        singleChecker.add(gov);

        rewardCheckerTest = new GemForRewardChecker();
        rewardCheckerTest.addChecker(address(singleChecker));

        sadapter = new UniswapAdapterForStables();
        sadapterOne = new UniswapAdapterWithOneStable();

        uniPair = new UniswapV2Pair(address(token0), address(token1));
        uniPair2 = new UniswapV2Pair(address(token1), address(token2));
        uniPair3 = new UniswapV2Pair(address(token0), address(token2));
        uniPair4 = new UniswapV2Pair(address(token3), address(token4));

        uniPairVolatile1 = new UniswapV2Pair(address(tokenVolatile), address(token0));
        uniPairVolatile2 = new UniswapV2Pair(address(token0), address(tokenVolatile));

        sadapterOne.setup(address(token0));

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D); //get hevm instance
    }

    function bucksToPair(
        uint256 v,
        DSToken t,
        UniswapV2Pair pair
    ) internal returns (uint256) {
        uint256 bal = v * (uint256(10)**t.decimals());
        t.mint(bal);
        t.transfer(address(pair), bal);

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (address(t) == pair.token0()) {
            pair.setReserve0(uint112(bal) + reserve0);
        } else {
            pair.setReserve1(uint112(bal) + reserve1);
        }
        return bal;
    }

    function addLiquidityCore(uint256 v, UniswapV2Pair pair) internal returns (uint256) {
        uint256 b1 = bucksToPair(v, DSToken(pair.token0()), pair);
        uint256 b2 = bucksToPair(v, DSToken(pair.token1()), pair);
        uint256 l = sqrt(b1 * b2);
        pair.mint(l);
        return l;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

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

    function assertFail(
        address c,
        bytes memory call,
        bytes32 m
    ) internal {
        (bool ret, ) = c.call(call);
        if (m.length > 0 && m[0] == "!") {
            ret = !ret;
        }
        if (ret) {
            emit log_bytes32(m);
            fail();
        }
    }
}
