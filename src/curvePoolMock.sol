pragma solidity ^0.5.10;


import "ds-token/token.sol";
import "./IERC20.sol";


contract Token is DSToken {
    constructor(bytes32 symbol_, uint256 d) public DSToken(symbol_) {
        decimals = d;
    }
}

contract CurvePoolMock {

    struct Coin {
        address coin;       
    }

    Coin[] public list;
    Token public token;

    constructor() public {
        token = new Token("CRV", 18);
    }

    function set(DSToken addr) public {
        require (address(addr) != address(0));

        for (uint256 i =0; i<list.length; i++) {
            if (list[i].coin == address(addr)) {
                return;
            }
        }

        list.push(Coin(address(addr)));
    }

    function setupTokens(DSToken t0_, DSToken t1_) public {
        set(t0_);
        set(t1_);
    }

    function balances(uint256 idx) external view returns (uint256) {
        return IERC20(list[idx].coin).balanceOf(address(this));
    }

    function coins(uint256 idx) external view returns (address) {
        return list[idx].coin;

    }


    function mint(address guy, uint wad) public  {
        token.mint(guy, wad);
    }

}
