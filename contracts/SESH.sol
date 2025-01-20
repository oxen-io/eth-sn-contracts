// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./libraries/Shared.sol";

/**
 * @title SESH contract
 * @notice The SESH utility token
 */
contract SESH is ERC20, ERC20Permit, Ownable2Step, Shared {
    // The maximum supply that can ever be in circulation
    // This is set to totalSupply_ (the initial minted amount) in the constructor.
    uint256 public immutable supplyCap;

    // The contract to which newly minted tokens will always be sent
    address public pool;

    constructor(
        uint256 totalSupply_,
        address receiverGenesisAddress
    )
        ERC20("Session", "SESH")
        ERC20Permit("Session")
        Ownable(msg.sender)
        nzAddr(receiverGenesisAddress)
        nzUint(totalSupply_)
    {
        supplyCap = totalSupply_;
        _mint(receiverGenesisAddress, totalSupply_);
    }

    /**
     * @notice Overrides the decimals to 9.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    /**
     * @notice Burn a specific amount of tokens from the caller's balance.
     * @dev Callable by anyone to reduce their own balance.
     * @param amount The number of tokens to burn.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Mint the maximum allowable amount (supplyCap - currentSupply) directly to the pool.
     * @dev Anyone can call this, but minting only succeeds if totalSupply() < cap.
     *      This means tokens must have been burned prior to calling this.
     */
    function mint() external nzAddr(pool) {
        uint256 currentSupply = totalSupply();
        require(currentSupply < supplyCap, "SESH: Cap already reached");

        uint256 amountToMint = supplyCap - currentSupply;
        _mint(pool, amountToMint);
    }

    /**
     * @notice Set or update the pool address.
     * @param newPool The new pool contract address.
     */
    function setPool(address newPool) external onlyOwner nzAddr(newPool) {
        pool = newPool;
    }
}

