/*
 * MIT License
 * ===========
 *
 * Copyright (c) 2020 Freeliquid
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 */

pragma solidity ^0.5.12;

import "./lib.sol";
import "./IERC20.sol";
import "./safeMath.sol";



interface VatLike {
    function slip(
        bytes32,
        address,
        int256
    ) external;

    function move(
        address,
        address,
        uint256
    ) external;
}



interface CurveGaugeWrapper {

    function deposit(uint256 _value, address addr) external;

    function withdraw(uint256 _value) external;

    function set_approve_deposit(address addr, bool can_deposit) external;

    function decimals() external view returns (uint8);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    function mint(address account, uint256 amount) external;

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}



interface CurveGauge {

    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;

    function lp_token() external returns (address);
    function minter() external returns (address);
    function crv_token() external returns (address);
    function voting_escrow() external returns (address);
}

interface CurveGaugeReward {
    function rewarded_token() external returns (address);
    function claim_rewards() external;
}

interface Minter {
    function mint(address gauge_addr) external;
}

interface VotingEscrow {

    function create_lock(uint256 _value, uint256 _unlock_time) external;

    function increase_amount(uint256 _value) external;

    function increase_unlock_time(uint256 _unlock_time) external;

    function withdraw() external;
}

contract Bag {

    using SafeMath for uint256;

    address public owner;
    uint256 amnt;

    constructor() public {
        owner = msg.sender;
    }

    function claim(CurveGauge curveGauge, CurveGaugeReward curveGaugeReward) internal {
        address minter = curveGauge.minter();
        Minter(minter).mint(address(curveGauge));

        if (address(curveGaugeReward) != address(0)) {
            curveGaugeReward.claim_rewards();
        }
    }

    function transferToken(uint256 wad, address token, address usr, uint256 total) internal {
        uint256 tokenToTransfer = IERC20(token).balanceOf(address(this)).mul(wad).div(total);
        require(IERC20(token).transfer(usr, tokenToTransfer), "GJFC/bag-failed-tkn-tran");
    }

    function exit(CurveGauge curveGauge, address gem, address usr, uint256 wad, 
                  CurveGaugeReward curveGaugeReward) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");

        uint256 amntBefore = amnt;
        amnt = amnt.sub(wad);

        claim(curveGauge, curveGaugeReward);

        transferToken(wad, curveGauge.crv_token(), usr, amntBefore);
        if (address(curveGaugeReward) != address(0)) {
            transferToken(wad, curveGaugeReward.rewarded_token(), usr, amntBefore);
        }
        curveGauge.withdraw(wad);

        require(IERC20(gem).transfer(usr, wad), "GJFC/bag-failed-transfer");
    }

    function join(CurveGauge curveGauge, address gem, uint256 wad, CurveGaugeReward curveGaugeReward) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");

        amnt = amnt.add(wad);
        claim(curveGauge, curveGaugeReward);


        IERC20(gem).approve(address(curveGauge), wad);
        curveGauge.deposit(wad);
    }

    function create_lock(CurveGauge curveGauge, uint256 _value, uint256 _unlock_time) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");
        VotingEscrow votingEscrow = VotingEscrow(curveGauge.voting_escrow());
        votingEscrow.create_lock(_value, _unlock_time);
    }

    function increase_amount(CurveGauge curveGauge, uint256 _value) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");
        VotingEscrow votingEscrow = VotingEscrow(curveGauge.voting_escrow());
        votingEscrow.increase_amount(_value);
    }

    function increase_unlock_time(CurveGauge curveGauge, uint256 _unlock_time) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");
        VotingEscrow votingEscrow = VotingEscrow(curveGauge.voting_escrow());
        votingEscrow.increase_unlock_time(_unlock_time);
    }

    function withdraw(CurveGauge curveGauge, address usr) external {
        require(owner == msg.sender, "GJFC/bag-exit-auth");
        VotingEscrow votingEscrow = VotingEscrow(curveGauge.voting_escrow());
        votingEscrow.withdraw();

        IERC20 crv = IERC20(curveGauge.crv_token());

        require(
            crv.transfer(usr, crv.balanceOf(address(this))),
            "GJFC/failed-transfer"
        );
    }
}

/**
 * @title MakerDAO like adapter for gem join
 *
 * see MakerDAO docs for details
*/
contract GemJoinForCurve is LibNote {
    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external note auth {
        wards[usr] = 1;
    }

    function deny(address usr) external note auth {
        wards[usr] = 0;
    }

    modifier auth {
        require(wards[msg.sender] == 1, "GJFC/not-authorized");
        _;
    }


    VatLike public vat; // CDP Engine
    bytes32 public ilk; // Collateral Type
    IERC20 public gem;
    CurveGauge public curveGauge;
    CurveGaugeReward public curveGaugeReward;
    uint256 public dec;
    uint256 public live; // Active Flag

    mapping(address => address) public bags;


    constructor(
        address vat_,
        bytes32 ilk_,
        address curveGauge_,
        bool withReward
    ) public {
        wards[msg.sender] = 1;
        live = 1;
        vat = VatLike(vat_);
        ilk = ilk_;
        curveGauge = CurveGauge(curveGauge_);
        if (withReward) {
            curveGaugeReward = CurveGaugeReward(curveGauge_);
        }
        gem = IERC20(curveGauge.lp_token());
        require(address(gem) != address(0));

        dec = gem.decimals();
        require(dec >= 18, "GJFC/decimals-18-or-higher");
    }

    function makeBag(address user) internal returns (address bag) {
        if (bags[user] != address(0)) {
            bag = bags[user];
        } else {
            bag = address(new Bag());
            bags[user] = bag;
        }
    }

    function cage() external note auth {
        live = 0;
    }

    function join(address urn, uint256 wad) external note {
        require(live == 1, "GJFC/not-live");
        require(int256(wad) >= 0, "GJFC/overflow");
        vat.slip(ilk, urn, int256(wad));

        address bag = makeBag(msg.sender);

        require(
            gem.transferFrom(msg.sender, bag, wad),
            "GJFC/failed-transfer"
        );

        Bag(bag).join(curveGauge, address(gem), wad, curveGaugeReward);
    }

    function exit(address usr, uint256 wad) external note {
        require(wad <= 2**255, "GJFC/overflow");
        vat.slip(ilk, msg.sender, -int256(wad));

        address bag = bags[msg.sender];
        require(bag != address(0), "GJFC/zero-bag");

        Bag(bag).exit(curveGauge, address(gem), usr, wad, curveGaugeReward);
    }

    function create_lock(uint256 _value, uint256 _unlock_time) external {
        address bag = bags[msg.sender];
        require(bag != address(0), "GJFC/zero-bag");

        require(
            IERC20(curveGauge.crv_token()).transferFrom(msg.sender, bag, _value),
            "GJFC/failed-transfer"
        );

        Bag(bag).create_lock(curveGauge, _value, _unlock_time);
    }

    function increase_amount(uint256 _value) external {
        address bag = bags[msg.sender];
        require(bag != address(0), "GJFC/zero-bag");

        require(
            IERC20(curveGauge.crv_token()).transferFrom(msg.sender, bag, _value),
            "GJFC/failed-transfer"
        );

        Bag(bag).increase_amount(curveGauge, _value);
    }

    function increase_unlock_time(uint256 _unlock_time) external {
        address bag = bags[msg.sender];
        require(bag != address(0), "GJFC/zero-bag");
        Bag(bag).increase_unlock_time(curveGauge, _unlock_time);
    }

    function withdraw() external {
        address bag = bags[msg.sender];
        require(bag != address(0), "GJFC/zero-bag");
        Bag(bag).withdraw(curveGauge, msg.sender);
    }
}
