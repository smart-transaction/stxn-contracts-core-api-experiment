// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "src/lamination/Laminator.sol";
import "src/timetravel/CallBreaker.sol";
import "src/timetravel/SmarterContract.sol";
import "test/examples/FlashPill.sol";

contract FlashPillLib {
    address payable public pusherLaminated;
    FlashPill public fp;
    Laminator public laminator;
    CallBreaker public callbreaker;
    uint256 _tipWei = 33;

    function deployerLand(address pusher) public {
        // Initializing contracts
        callbreaker = new CallBreaker();
        laminator = new Laminator(address(callbreaker));
        fp = new FlashPill(address(callbreaker));
        pusherLaminated = payable(laminator.computeProxyAddress(pusher));
    }

    function userLand() public returns (uint256) {
        // send proxy some eth
        pusherLaminated.transfer(1 ether);

        // Userland operations
        CallObject[] memory pusherCallObjs = new CallObject[](2);
        pusherCallObjs[0] = CallObject({amount: 0, addr: address(fp), gas: 1000000, callvalue: ""});

        pusherCallObjs[1] = CallObject({amount: _tipWei, addr: address(callbreaker), gas: 10000000, callvalue: ""});

        return laminator.pushToProxy(abi.encode(pusherCallObjs), 1, "0x00", "0x00");
    }

    function solverLand(uint256 laminatorSequenceNumber, address filler) public {
        CallObject[] memory callObjs = new CallObject[](1);
        ReturnObject[] memory returnObjs = new ReturnObject[](1);

        callObjs[0] = CallObject({
            amount: 0,
            addr: pusherLaminated,
            gas: 10000000,
            callvalue: abi.encodeWithSignature("pull(uint256)", laminatorSequenceNumber)
        });

        ReturnObject[] memory returnObjsFromPull = new ReturnObject[](2);
        returnObjsFromPull[0] = ReturnObject({returnvalue: abi.encode(4)});
        returnObjsFromPull[1] = ReturnObject({returnvalue: ""});

        returnObjs[0] = ReturnObject({returnvalue: abi.encode(abi.encode(returnObjsFromPull))});

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256(abi.encodePacked("tipYourBartender"));
        keys[1] = keccak256(abi.encodePacked("pullIndex"));
        // keys[2] = keccak256(abi.encodePacked("hintdex"));
        bytes[] memory values = new bytes[](2);
        values[0] = abi.encodePacked(filler);
        values[1] = abi.encode(laminatorSequenceNumber);
        // values[2] = abi.encode(4);
        bytes memory encodedData = abi.encode(keys, values);

        bytes32[] memory hintdicesKeys = new bytes32[](1);
        hintdicesKeys[0] = keccak256(abi.encode(callObjs[0]));
        uint256[] memory hintindicesVals = new uint256[](1);
        hintindicesVals[0] = 0;
        bytes memory hintdices = abi.encode(hintdicesKeys, hintindicesVals);
        callbreaker.verify(abi.encode(callObjs), abi.encode(returnObjs), encodedData, hintdices);
    }
}
