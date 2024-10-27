// contracts/BN256G1Test.sol
pragma solidity ^0.8.26;

import "../libraries/BN256G1.sol";

contract BN256G1Test {
    using BN256G1 for BN256G1.G1Point;

    function addPoints(BN256G1.G1Point memory p1, BN256G1.G1Point memory p2) public view returns (BN256G1.G1Point memory) {
        return p1.add(p2);
    }

    function negatePoint(BN256G1.G1Point memory p) public pure returns (BN256G1.G1Point memory) {
        return p.negate();
    }

    function getGenerator() public pure returns (BN256G1.G1Point memory) {
        return BN256G1.P1();
    }

    function getKey(BN256G1.G1Point memory point) public pure returns (bytes memory) {
        return BN256G1.getKeyForG1Point(point);
    }
}
