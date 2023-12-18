// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./BN256G1.sol";
import "./BN256G2.sol";
library Pairing {
    /// @return the result of computing the pairing check
    /// e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
    /// For example pairing([P1(), P1().negate()], [P2(), P2()]) should
    /// return true.
    function pairing(BN256G1.G1Point[] memory p1, BN256G2.G2Point[] memory p2) internal returns (bool) {
        require(p1.length == p2.length);
        uint elements = p1.length;
        uint inputSize = elements * 6;
        uint[] memory input = new uint[](inputSize);

        for (uint i = 0; i < elements; i++)
        {
            input[i * 6 + 0] = p1[i].X;
            input[i * 6 + 1] = p1[i].Y;
            input[i * 6 + 2] = p2[i].X[0];
            input[i * 6 + 3] = p2[i].X[1];
            input[i * 6 + 4] = p2[i].Y[0];
            input[i * 6 + 5] = p2[i].Y[1];
        }

        uint[1] memory out;
        bool success;

        assembly {
            success := call(sub(gas(), 2000), 8, 0, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
        }
        require(success, "Call to precompiled contract for pairing failed");
        return out[0] != 0;
    }

    /// Convenience method for a pairing check for two pairs.
    function pairing2(BN256G1.G1Point memory a1, BN256G2.G2Point memory a2, BN256G1.G1Point memory b1, BN256G2.G2Point memory b2) internal returns (bool) {
        BN256G1.G1Point[] memory p1 = new BN256G1.G1Point[](2);
        BN256G2.G2Point[] memory p2 = new BN256G2.G2Point[](2);
        p1[0] = a1;
        p1[1] = b1;
        p2[0] = a2;
        p2[1] = b2;
        return pairing(p1, p2);
    }
}
