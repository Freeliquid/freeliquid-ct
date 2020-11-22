pragma solidity >=0.5.12;

import {Flipper} from "dss/flip.sol";

contract FlipFabCompat {
    address public cat;
    address public deployer;

    // --- Init ---
    constructor() public {
        deployer = msg.sender;
    }

    function setCat(address cat_) public {
        require(deployer == msg.sender, "auth-error");
        cat = cat_;
        deployer = address(0);
    }

    function newFlip(address vat, bytes32 ilk) public returns (Flipper flip) {
        flip = new Flipper(vat, cat, ilk);
        flip.rely(msg.sender);
        flip.deny(address(this));
    }
}
