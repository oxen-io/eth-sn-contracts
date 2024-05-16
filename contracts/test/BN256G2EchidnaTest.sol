// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/BN256G2.sol";

contract BN256G2EchidnaTest {
    // Test the ECTwistAdd function
    /*function checkECTwistAdd(*/
    /*uint256 pt1xx, uint256 pt1xy,*/
    /*uint256 pt1yx, uint256 pt1yy,*/
    /*uint256 pt2xx, uint256 pt2xy,*/
    /*uint256 pt2yx, uint256 pt2yy*/
    /*) public {*/
    /*(uint256 sumXx, uint256 sumXy, uint256 sumYx, uint256 sumYy) = BN256G2.ECTwistAdd(*/
    /*pt1xx, pt1xy, pt1yx, pt1yy,*/
    /*pt2xx, pt2xy, pt2yx, pt2yy*/
    /*);*/
    /*assert(BN256G2.IsOnCurve(sumXx, sumXy, sumYx, sumYy));*/
    /*}*/

    // Test the ECTwistMul function
    /*function checkECTwistMul(*/
    /*uint256 s,*/
    /*uint256 pt1xx, uint256 pt1xy,*/
    /*uint256 pt1yx, uint256 pt1yy*/
    /*) public {*/
    /*(uint256 mulXx, uint256 mulXy, uint256 mulYx, uint256 mulYy) = BN256G2.ECTwistMul(*/
    /*s, pt1xx, pt1xy, pt1yx, pt1yy*/
    /*);*/
    /*assert(BN256G2.IsOnCurve(mulXx, mulXy, mulYx, mulYy));*/
    /*}*/

    bytes private message;
    BN256G2.G2Point Hm;

    constructor() {
        message = bytes("1");
        Hm = BN256G2.hashToG2(BN256G2.hashToField(string(message)));
    }

    function setMessage(bytes calldata _message) public {
        message = _message;
        Hm = BN256G2.hashToG2(BN256G2.hashToField(string(message)));
    }

    function echidna_always_hashable() public returns (bool) {
        return BN256G2.IsOnCurve(Hm.X[1], Hm.X[0], Hm.Y[1], Hm.Y[0]);
    }
}
