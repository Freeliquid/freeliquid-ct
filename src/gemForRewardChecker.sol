pragma solidity ^0.5.12;

contract GemForRewardChecker {

	address[] public checkers;
	address deployer;

	constructor () public {
		deployer = msg.sender;
	}

	function addChecker(address checker) public {
		require(deployer == msg.sender, "addChecker/auth-error");
		checkers.push(checker);
	}

    function check(address gem) external returns (bool) {
    	for (uint i=0; i<checkers.length; i++) {

	        (bool ret, ) = checkers[i].call(abi.encodeWithSignature("check(address)", gem));
	        if (ret) {
	        	return true;
	        }
    	}

    	return false;
    }
}
