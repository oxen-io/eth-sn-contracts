// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 immutable d;
    constructor(string memory name_, string memory symbol_, uint8 _decimals) ERC20(name_, symbol_) {
        d = _decimals;
        _mint(msg.sender, 100000000 * (10 ** uint256(d))); // Mint 100 million tokens for testing
    }
    function decimals() public view override returns (uint8) {
        return d;
    }
}

