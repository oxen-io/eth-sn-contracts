// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "../ServiceNodeRewards.sol";

contract LocalDevnetServiceNodeRewards is ServiceNodeRewards {
    function minimumExitAge() internal override pure returns (uint64 result) { result = 0; }
}
