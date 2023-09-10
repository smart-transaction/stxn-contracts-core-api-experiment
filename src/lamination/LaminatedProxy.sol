// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// identical to the one from callbreaker
struct CallObject {
    uint256 amount;
    address addr;
    uint256 gas;
    /// should be abi encoded
    bytes callvalue;
}

struct CallObjectHolder {
    bool initialized;
    uint256 firstCallableBlock;
    CallObject callObj;
}

contract LaminatedProxy {
    address public owner;
    address public laminator;
    uint256 public sequenceNumber = 0;

    mapping(uint256 => CallObjectHolder) public deferredCalls;

    /// @dev Emitted when a function call is deferred and added to the queue.
    /// @param callObj The CallObject containing details of the deferred function call.
    /// @param sequenceNumber The sequence number assigned to the deferred function call.
    event CallPushed(CallObject callObj, uint256 sequenceNumber);

    /// @dev Emitted when a deferred function call is executed from the queue.
    /// @param callObj The CallObject containing details of the executed function call.
    /// @param sequenceNumber The sequence number of the executed function call.
    event CallPulled(CallObject callObj, uint256 sequenceNumber);

    /// @dev Emitted when a function call is executed immediately, without being deferred.
    /// @param callObj The CallObject containing details of the executed function call.
    event CallExecuted(CallObject callObj);

    /// @dev Modifier to make a function callable only by the owner.
    ///      Reverts the transaction if the sender is not the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Proxy: Not the owner");
        _;
    }

    /// @notice Constructs a new contract instance - usually called by the Laminator contract
    /// @dev Initializes the contract, setting the owner and laminator addresses.
    /// @param _laminator The address of the laminator contract.
    /// @param _owner The address of the contract's owner.
    constructor(address _owner, address _laminator) {
        owner = _owner;
        laminator = _laminator;
    }


    /// @notice Allows the contract to receive Ether.
    /// @dev The received Ether can be spent via the `execute`, `push`, and `pull` functions.
    receive() external payable {}

    /// @notice Pushes a deferred function call to be executed after a certain delay.
    /// @dev Adds a new CallObject to the `deferredCalls` mapping and emits a CallPushed event.
    ///      The function can only be called by the contract owner.
    /// @param input The encoded CallObject containing information about the function call to defer.
    /// @param delay The number of blocks to delay before the function call can be executed.
    ///      Use 0 for no delay.
    /// @return currentSequenceNumber The sequence number assigned to this deferred call.

    function push(bytes calldata input, uint32 delay) external onlyOwner returns (uint256) {
        CallObject memory callObj = abi.decode(input, (CallObject));
        uint256 currentSequenceNumber = sequenceNumber++;
        deferredCalls[currentSequenceNumber] =
            CallObjectHolder({initialized: true, firstCallableBlock: block.number + delay, callObj: callObj});

        emit CallPushed(callObj, currentSequenceNumber);
        return currentSequenceNumber;
    }

    /// @notice Executes a deferred function call that has been pushed to the contract.
    /// @dev Executes the deferred call specified by the sequence number `seqNumber`.
    ///      This function performs a series of checks before calling `_execute` to
    ///      execute the deferred call. It emits a `CallPulled` event and deletes
    ///      the deferred call object from the `deferredCalls` mapping.
    /// @param seqNumber The sequence number of the deferred call to be executed.
    /// @return returnValue The return value of the executed deferred call.
    function pull(uint256 seqNumber) external onlyOwner returns (bytes memory returnValue) {
        CallObjectHolder memory coh = deferredCalls[seqNumber];
        require(coh.initialized, "Proxy: Invalid sequence number");
        require(block.number >= coh.firstCallableBlock, "Proxy: Too early to pull this sequence number");

        returnValue = _execute(coh.callObj);

        emit CallPulled(coh.callObj, seqNumber);
        delete deferredCalls[seqNumber];
    }

    /// @notice Executes a function call immediately.
    /// @dev Decodes the provided `input` into a CallObject and then calls `_execute`.
    ///      Can only be invoked by the owner of the contract.
    /// @param input The encoded CallObject containing information about the function call to execute.
    /// @return returnValue The return value from the executed function call.
    function execute(bytes calldata input) external onlyOwner returns (bytes memory) {
        CallObject memory callToMake = abi.decode(input, (CallObject));
        return _execute(callToMake);
    }

    /// @dev Executes the function call specified by the CallObject `callToMake`.
    ///      Emits a `CallExecuted` event upon successful execution.
    /// @param callToMake The CallObject containing information about the function call to execute.
    /// @return returnValue The return value from the executed function call.
    function _execute(CallObject memory callToMake) internal returns (bytes memory) {
        (bool success, bytes memory returnvalue) =
            callToMake.addr.call{gas: callToMake.gas, value: callToMake.amount}(callToMake.callvalue);
        require(success, "Proxy: Immediate call failed");
        emit CallExecuted(callToMake);
        return returnvalue;
    }
}
