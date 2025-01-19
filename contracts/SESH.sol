// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./libraries/Shared.sol";

/**
 * @title SESH contract
 * @notice The SESH utility token
 */
contract SESH is ERC20, ERC20Permit, Shared {
    constructor(
        uint256 totalSupply_,
        address receiverGenesisAddress
    ) ERC20("Session", "SESH") ERC20Permit("Session") nzAddr(receiverGenesisAddress) nzUint(totalSupply_) {
        _mint(receiverGenesisAddress, totalSupply_);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
