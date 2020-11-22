pragma solidity >=0.5.12;

import "./testHelpers.sol";
import {Flipper} from "dss/flip.sol";

contract VatStub {
    function move(
        address,
        address,
        uint256
    ) external {}

    function flux(
        bytes32,
        address,
        address,
        uint256
    ) external {}
}

contract CatStub {
    function claw(uint256) external {}
}

contract LiquidationTest is TestBase {
    VatStub vat;
    Flipper flip;
    CatStub cat;

    function setUp() public {
        super.setUp();
        vat = new VatStub();
        cat = new CatStub();
        flip = new Flipper(address(vat), address(cat), "TEST");
    }

    function testFlipperOk() public {
        flip.kick(address(this), address(this), 1, 1, 1);
    }

    function testFlipperOK2() public {
        flip.file("tau", 2**48 - 2);
        flip.kick(address(this), address(this), 1, 1, 1);
    }

    function testFlipperFailKick() public {
        flip.file("tau", 2**48 - 1);
        assertFail(
            address(flip),
            abi.encodeWithSelector(flip.kick.selector, address(this), address(this), 1, 1, 1),
            "kick must fail"
        );
    }
}
