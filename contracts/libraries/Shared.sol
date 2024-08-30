// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/**
 * @title    Shared contract
 * @notice   Holds constants and modifiers that are used in multiple contracts
 * @dev      It would be nice if this could be a library, but modifiers can't be exported :(
 */

abstract contract Shared {
    address internal constant _ZERO_ADDR = address(0);
    bytes32 internal constant _NULL = "";

    /// @dev    Checks that a uint isn't zero/empty
    modifier nzUint(uint256 u) {
        require(u != 0, "Shared: uint input is empty");
        _;
    }

    /// @dev    Checks that an address isn't zero/empty
    modifier nzAddr(address a) {
        require(a != _ZERO_ADDR, "Shared: address input is empty");
        _;
    }

    /// @dev    Checks that a bytes32 isn't zero/empty
    modifier nzBytes32(bytes32 b) {
        require(b != _NULL, "Shared: bytes32 input is empty");
        _;
    }
}
