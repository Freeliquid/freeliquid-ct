pragma solidity >=0.5.12;

import {Flipper} from "dss/flip.sol";


contract FlipFabCompat {
	address public cat;

    // --- Init ---
    constructor(address cat_) public {
        cat = cat_;
    }

    function newFlip(address vat, bytes32 ilk) public returns (Flipper flip) {
        flip = new Flipper(vat, cat, ilk);
        flip.rely(msg.sender);
        flip.deny(address(this));
    }
}
