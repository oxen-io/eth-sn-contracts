// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Shared.sol";

/**
 * @title SENT contract
 * @notice The SENT utility token
 */
contract SENT is ERC20, Shared {
    constructor(
        uint256 totalSupply_,
        address receiverGenesisAddress
    ) ERC20("Session", "SENT") nzAddr(receiverGenesisAddress) nzUint(totalSupply_) {
        _mint(receiverGenesisAddress, totalSupply_);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
