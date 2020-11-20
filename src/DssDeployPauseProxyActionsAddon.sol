
pragma solidity >=0.5.12;

interface PauseLike {
    function plot(address, bytes32, bytes calldata, uint) external;
    function exec(address, bytes32, bytes calldata, uint) external;
}

contract DssDeployPauseProxyActionsAddon {

    function deny(address pause, address actions, address who, address to) external {
        bytes32 tag;
        assembly { tag := extcodehash(actions) }
        PauseLike(pause).plot(
            address(actions),
            tag,
            abi.encodeWithSignature("deny(address,address)", who, to),
            now
        );
        PauseLike(pause).exec(
            address(actions),
            tag,
            abi.encodeWithSignature("deny(address,address)", who, to),
            now
        );
    }
}
