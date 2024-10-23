// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../libraries/Shared.sol";

contract MockWOXEN is ERC20, Shared {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_
    ) ERC20(name_, symbol_) nzUint(totalSupply_) {
        _mint(msg.sender, totalSupply_);
    }
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
