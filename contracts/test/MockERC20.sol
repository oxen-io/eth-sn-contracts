// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 d;
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        d = _decimals;
        _mint(msg.sender, 1000000 * (10 ** uint256(d))); // Mint 1 million tokens for testing
    }
    function decimals() public view override returns (uint8) {
        return d;
    }
}

