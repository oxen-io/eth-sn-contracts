// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title Elliptic curve operations on twist points for alt_bn128
 * @author Mustafa Al-Bassam (mus@musalbas.com)
 * @dev Homepage: https://github.com/musalbas/solidity-BN256G2
 */

library BN256G2 {
    uint256 internal constant CURVE_ORDER_FACTOR = 4965661367192848881; // this is also knows as z, generates prime definine base field (FIELD MODULUS) and order of the curve for BN curves
    uint256 internal constant FIELD_MODULUS = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    uint256 constant HALF_FIELD_MODULUS = (FIELD_MODULUS + 1) / 2;
    uint256 internal constant TWISTBX = 0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5;
    uint256 internal constant TWISTBY = 0x9713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d2;
    uint internal constant PTXX = 0;
    uint internal constant PTXY = 1;
    uint internal constant PTYX = 2;
    uint internal constant PTYY = 3;
    uint internal constant PTZX = 4;
    uint internal constant PTZY = 5;

    // Encoding of field elements is: X[0] * z + X[1]
    struct G2Point {
        uint[2] X;
        uint[2] Y;
    }

    /*
    These constants represent the coefficients used to adjust the x and y coordinates
    of a point on an elliptic curve when applying the Frobenius Endomorphism. The 
    Frobenius Endomorphism is a function that can be applied to a point on an elliptic 
    curve, resulting in another valid point on the curve. It is an efficient operation
    that is especially useful in cryptographic protocols implemented on elliptic curves. 

    The coefficients are specific to the curve and the field in which the curve is defined. 
    In this case, they are calculated as follows:

    1. We start with a base element xi, which in our case is (9, 1) in the field F_p^2.
    2. We then raise this base element to the power of ((p - 1) / 6) to obtain g. 
    3. The x-coefficient (FROBENIUS_COEFF_X) is then calculated as the square of g.
    4. The y-coefficient (FROBENIUS_COEFF_Y) is calculated as the cube of g.
    */

    // xiToPMinus1Over3 is ξ^((p-1)/3) where ξ = i+9.
    uint256 constant FROBENIUS_COEFF_X_0 =
        21575463638280843010398324269430826099269044274347216827212613867836435027261;
    uint256 constant FROBENIUS_COEFF_X_1 =
        10307601595873709700152284273816112264069230130616436755625194854815875713954;

    // xiToPMinus1Over2 is ξ^((p-1)/2) where ξ = i+9.
    uint256 constant FROBENIUS_COEFF_Y_0 = 2821565182194536844548159561693502659359617185244120367078079554186484126554;
    uint256 constant FROBENIUS_COEFF_Y_1 = 3505843767911556378687030309984248845540243509899259641013678093033130930403;

    function submod(uint256 a, uint256 b, uint256 n) internal pure returns (uint256) {
        return addmod(a, n - b, n);
    }

    function _FQ2Mul(uint256 xx, uint256 xy, uint256 yx, uint256 yy) internal pure returns (uint256, uint256) {
        return (
            submod(mulmod(xx, yx, FIELD_MODULUS), mulmod(xy, yy, FIELD_MODULUS), FIELD_MODULUS),
            addmod(mulmod(xx, yy, FIELD_MODULUS), mulmod(xy, yx, FIELD_MODULUS), FIELD_MODULUS)
        );
    }

    function _FQ2Muc(uint256 xx, uint256 xy, uint256 c) internal pure returns (uint256, uint256) {
        return (mulmod(xx, c, FIELD_MODULUS), mulmod(xy, c, FIELD_MODULUS));
    }

    function _FQ2Add(uint256 xx, uint256 xy, uint256 yx, uint256 yy) internal pure returns (uint256, uint256) {
        return (addmod(xx, yx, FIELD_MODULUS), addmod(xy, yy, FIELD_MODULUS));
    }

    function _FQ2Sub(uint256 xx, uint256 xy, uint256 yx, uint256 yy) internal pure returns (uint256 rx, uint256 ry) {
        return (submod(xx, yx, FIELD_MODULUS), submod(xy, yy, FIELD_MODULUS));
    }

    function _FQ2Inv(uint256 x, uint256 y) internal view returns (uint256, uint256) {
        uint256 inv = _modInv(
            addmod(mulmod(y, y, FIELD_MODULUS), mulmod(x, x, FIELD_MODULUS), FIELD_MODULUS),
            FIELD_MODULUS
        );
        return (mulmod(x, inv, FIELD_MODULUS), FIELD_MODULUS - mulmod(y, inv, FIELD_MODULUS));
    }

    function _isOnCurve(uint256 xx, uint256 xy, uint256 yx, uint256 yy) internal pure returns (bool) {
        uint256 yyx;
        uint256 yyy;
        uint256 xxxx;
        uint256 xxxy;
        (yyx, yyy) = _FQ2Mul(yx, yy, yx, yy);
        (xxxx, xxxy) = _FQ2Mul(xx, xy, xx, xy);
        (xxxx, xxxy) = _FQ2Mul(xxxx, xxxy, xx, xy);
        (yyx, yyy) = _FQ2Sub(yyx, yyy, xxxx, xxxy);
        (yyx, yyy) = _FQ2Sub(yyx, yyy, TWISTBX, TWISTBY);
        return yyx == 0 && yyy == 0;
    }

    function IsOnCurve(uint256 xx, uint256 xy, uint256 yx, uint256 yy) internal pure returns (bool) {
        return _isOnCurve(xx, xy, yx, yy);
    }

    function _modInv(uint256 a, uint256 n) internal view returns (uint256 result) {
        bool success;
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), a)
            mstore(add(freemem, 0x80), sub(n, 2))
            mstore(add(freemem, 0xA0), n)
            success := staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            result := mload(freemem)
        }
        require(success);
    }

    function _fromProjective(
        uint256 pt1xx,
        uint256 pt1xy,
        uint256 pt1yx,
        uint256 pt1yy,
        uint256 pt1zx,
        uint256 pt1zy
    ) internal view returns (uint256 pt2xx, uint256 pt2xy, uint256 pt2yx, uint256 pt2yy) {
        uint256 invzx;
        uint256 invzy;
        (invzx, invzy) = _FQ2Inv(pt1zx, pt1zy);
        (pt2xx, pt2xy) = _FQ2Mul(pt1xx, pt1xy, invzx, invzy);
        (pt2yx, pt2yy) = _FQ2Mul(pt1yx, pt1yy, invzx, invzy);
    }

     /**
     * @notice Adds two points on a twisted elliptic curve in projective coordinates.
     * @dev This function implements the addition formula for elliptic curves in projective coordinates
     * based on formula (3) in section 2.2 from the paper
     * Cohen, H., Miyaji, A., Ono, T. (1998). Efficient Elliptic Curve Exponentiation Using Mixed Coordinates.
     * In: Ohta, K., Pei, D. (eds) Advances in Cryptology — ASIACRYPT’98. ASIACRYPT 1998.
     * Lecture Notes in Computer Science, vol 1514. Springer, Berlin, Heidelberg. https://doi.org/10.1007/3-540-49649-1_6
     * also available at: https://link.springer.com/chapter/10.1007/3-540-49649-1_6.
     * This elliptic curve is twisted and each coordinate has both real and imaginary parts.
     * 
     * @param pt1xx The real part of the x-coordinate of the first point.
     * @param pt1xy The imaginary part of the x-coordinate of the first point.
     * @param pt1yx The real part of the y-coordinate of the first point.
     * @param pt1yy The imaginary part of the y-coordinate of the first point.
     * @param pt1zx The real part of the z-coordinate of the first point.
     * @param pt1zy The imaginary part of the z-coordinate of the first point.
     * @param pt2xx The real part of the x-coordinate of the second point.
     * @param pt2xy The imaginary part of the x-coordinate of the second point.
     * @param pt2yx The real part of the y-coordinate of the second point.
     * @param pt2yy The imaginary part of the y-coordinate of the second point.
     * @param pt2zx The real part of the z-coordinate of the second point.
     * @param pt2zy The imaginary part of the z-coordinate of the second point.
     * @return pt3 The resulting point of the addition in projective coordinates, including both real and imaginary parts for x, y, and z coordinates.
     */
    function _ECTwistAddProjective(
        uint256 pt1xx,
        uint256 pt1xy,
        uint256 pt1yx,
        uint256 pt1yy,
        uint256 pt1zx,
        uint256 pt1zy,
        uint256 pt2xx,
        uint256 pt2xy,
        uint256 pt2yx,
        uint256 pt2yy,
        uint256 pt2zx,
        uint256 pt2zy
    ) internal pure returns (uint256[6] memory pt3) {
        if (pt1zx == 0 && pt1zy == 0) {
            (pt3[PTXX], pt3[PTXY], pt3[PTYX], pt3[PTYY], pt3[PTZX], pt3[PTZY]) = (
                pt2xx,
                pt2xy,
                pt2yx,
                pt2yy,
                pt2zx,
                pt2zy
            );
            return pt3;
        } else if (pt2zx == 0 && pt2zy == 0) {
            (pt3[PTXX], pt3[PTXY], pt3[PTYX], pt3[PTYY], pt3[PTZX], pt3[PTZY]) = (
                pt1xx,
                pt1xy,
                pt1yx,
                pt1yy,
                pt1zx,
                pt1zy
            );
            return pt3;
        }

        (pt2yx,     pt2yy)     = _FQ2Mul(pt2yx, pt2yy, pt1zx, pt1zy); // Y₂Z₁ = Y₂ * Z₁
        (pt3[PTYX], pt3[PTYY]) = _FQ2Mul(pt1yx, pt1yy, pt2zx, pt2zy); // Y₁Z₂ = Y₁ * Z₂
        (pt2xx,     pt2xy)     = _FQ2Mul(pt2xx, pt2xy, pt1zx, pt1zy); // X₂Z₁ = X₂ * Z₁
        (pt3[PTZX], pt3[PTZY]) = _FQ2Mul(pt1xx, pt1xy, pt2zx, pt2zy); // X₁Z₂ = X₁ * Z₂

        if (pt2xx == pt3[PTZX] && pt2xy == pt3[PTZY]) {
            if (pt2yx == pt3[PTYX] && pt2yy == pt3[PTYY]) {
                (pt3[PTXX], pt3[PTXY], pt3[PTYX], pt3[PTYY], pt3[PTZX], pt3[PTZY]) = _ECTwistDoubleProjective(
                    pt1xx,
                    pt1xy,
                    pt1yx,
                    pt1yy,
                    pt1zx,
                    pt1zy
                );
                return pt3;
            }
            (pt3[PTXX], pt3[PTXY], pt3[PTYX], pt3[PTYY], pt3[PTZX], pt3[PTZY]) = (1, 0, 1, 0, 0, 0);
            return pt3;
        }

        (pt2zx,     pt2zy)     = _FQ2Mul(pt1zx, pt1zy, pt2zx,     pt2zy);     // Z₁Z₂        = Z₁ * Z₂
        (pt1xx,     pt1xy)     = _FQ2Sub(pt2yx, pt2yy, pt3[PTYX], pt3[PTYY]); // u           = Y₂Z₁ - Y₁Z₂
        (pt1yx,     pt1yy)     = _FQ2Sub(pt2xx, pt2xy, pt3[PTZX], pt3[PTZY]); // v           = X₂Z₁ - X₁Z₂
        (pt1zx,     pt1zy)     = _FQ2Mul(pt1yx, pt1yy, pt1yx,     pt1yy);     // v²          = v * v
        (pt2yx,     pt2yy)     = _FQ2Mul(pt1zx, pt1zy, pt3[PTZX], pt3[PTZY]); // v²X₁Z₂      = v² * X₁Z₂
        (pt1zx,     pt1zy)     = _FQ2Mul(pt1zx, pt1zy, pt1yx,     pt1yy);     // v³          = v² * v
        (pt3[PTZX], pt3[PTZY]) = _FQ2Mul(pt1zx, pt1zy, pt2zx,     pt2zy);     // Z₃          = v³ * Z₁Z₂
        (pt2xx,     pt2xy)     = _FQ2Mul(pt1xx, pt1xy, pt1xx,     pt1xy);     // u²          = u * u
        (pt2xx,     pt2xy)     = _FQ2Mul(pt2xx, pt2xy, pt2zx,     pt2zy);     // u²Z₁Z₂      = u² * Z₁Z₂
        (pt2xx,     pt2xy)     = _FQ2Sub(pt2xx, pt2xy, pt1zx,     pt1zy);     //             = u²Z₁Z₂ - v³
        (pt2zx,     pt2zy)     = _FQ2Muc(pt2yx, pt2yy, 2);                    // 2v²X₁Z₂     = v²X₁Z₂ * 2
        (pt2xx,     pt2xy)     = _FQ2Sub(pt2xx, pt2xy, pt2zx,     pt2zy);     // A           = (u²Z₁Z₂ - v³) - 2v²X₁Z₂
        (pt3[PTXX], pt3[PTXY]) = _FQ2Mul(pt1yx, pt1yy, pt2xx,     pt2xy);     // X₃          = v * A
        (pt1yx,     pt1yy)     = _FQ2Sub(pt2yx, pt2yy, pt2xx,     pt2xy);     //             = v²X₁Z₂ - A
        (pt1yx,     pt1yy)     = _FQ2Mul(pt1xx, pt1xy, pt1yx,     pt1yy);     // uv²X₁Z₂ - A = u * (v²X₁Z₂ - A)
        (pt1xx,     pt1xy)     = _FQ2Mul(pt1zx, pt1zy, pt3[PTYX], pt3[PTYY]); // v³Y₁Z₂      = v³ * Y₁Z₂
        (pt3[PTYX], pt3[PTYY]) = _FQ2Sub(pt1yx, pt1yy, pt1xx,     pt1xy);     // Y₃          = (u * (v²X₁Z₂ - A)) - v³Y₁Z₂
    }

    /**
     * @notice Doubles a point on a twisted elliptic curve in projective coordinates.
     * @dev This function implements the doubling formula for elliptic curves in projective coordinates
     * based on formula (4) in section 2.2 from the paper
     * Cohen, H., Miyaji, A., Ono, T. (1998). Efficient Elliptic Curve Exponentiation Using Mixed Coordinates.
     * In: Ohta, K., Pei, D. (eds) Advances in Cryptology — ASIACRYPT’98. ASIACRYPT 1998.
     * Lecture Notes in Computer Science, vol 1514. Springer, Berlin, Heidelberg. https://doi.org/10.1007/3-540-49649-1_6
     * also available at: https://link.springer.com/chapter/10.1007/3-540-49649-1_6.
     * This elliptic curve is twisted and each coordinate has both real and imaginary parts.
     *
     * @param pt1xx The real part of the x-coordinate of the point.
     * @param pt1xy The imaginary part of the x-coordinate of the point.
     * @param pt1yx The real part of the y-coordinate of the point.
     * @param pt1yy The imaginary part of the y-coordinate of the point.
     * @param pt1zx The real part of the z-coordinate of the point.
     * @param pt1zy The imaginary part of the z-coordinate of the point.
     * @return pt2xx The real part of the x-coordinate of the resulting point.
     * @return pt2xy The imaginary part of the x-coordinate of the resulting point.
     * @return pt2yx The real part of the y-coordinate of the resulting point.
     * @return pt2yy The imaginary part of the y-coordinate of the resulting point.
     * @return pt2zx The real part of the z-coordinate of the resulting point.
     * @return pt2zy The imaginary part of the z-coordinate of the resulting point.
     */
    function _ECTwistDoubleProjective(
        uint256 pt1xx,
        uint256 pt1xy,
        uint256 pt1yx,
        uint256 pt1yy,
        uint256 pt1zx,
        uint256 pt1zy
    ) internal pure returns (uint256 pt2xx, uint256 pt2xy, uint256 pt2yx, uint256 pt2yy, uint256 pt2zx, uint256 pt2zy) {
        (pt2xx, pt2xy) = _FQ2Muc(pt1xx, pt1xy, 3);            // 3X₁          = 3 * X₁
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1xx, pt1xy); // 3X₁²         = 3X₁ * X₁ = w
        (pt1zx, pt1zy) = _FQ2Mul(pt1yx, pt1yy, pt1zx, pt1zy); // s            = Y₁Z₁
        (pt2yx, pt2yy) = _FQ2Mul(pt1xx, pt1xy, pt1yx, pt1yy); // X₁Y₁         = X₁ * Y₁
        (pt2yx, pt2yy) = _FQ2Mul(pt2yx, pt2yy, pt1zx, pt1zy); // B            = X₁Y₁ * s
        (pt1xx, pt1xy) = _FQ2Mul(pt2xx, pt2xy, pt2xx, pt2xy); // w²           = w * w [^Computes (3X₁²)² instead of (aZ₁² + 3X₁²)²]
        (pt2zx, pt2zy) = _FQ2Muc(pt2yx, pt2yy, 8);            // 8B           = B * 8
        (pt1xx, pt1xy) = _FQ2Sub(pt1xx, pt1xy, pt2zx, pt2zy); // h            = w² - 8B
        (pt2zx, pt2zy) = _FQ2Mul(pt1zx, pt1zy, pt1zx, pt1zy); // s²           = s * s
        (pt2yx, pt2yy) = _FQ2Muc(pt2yx, pt2yy, 4);            // 4B           = B * 4
        (pt2yx, pt2yy) = _FQ2Sub(pt2yx, pt2yy, pt1xx, pt1xy); //              = 4B - h
        (pt2yx, pt2yy) = _FQ2Mul(pt2yx, pt2yy, pt2xx, pt2xy); // w * (4B - H) = (4B - H) * w
        (pt2xx, pt2xy) = _FQ2Muc(pt1yx, pt1yy, 8);            // 8Y₁          = Y₁ * 8
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1yx, pt1yy); // 8Y₁²         = 8Y₁ * Y₁
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt2zx, pt2zy); // 8Y₁²s²       = 8Y₁² * s²
        (pt2yx, pt2yy) = _FQ2Sub(pt2yx, pt2yy, pt2xx, pt2xy); // Y₃           = (w * (4B - H)) - 8Y₁²s²
        (pt2xx, pt2xy) = _FQ2Muc(pt1xx, pt1xy, 2);            // 2h           = h * 2
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1zx, pt1zy); // X₃           = 2h * s
        (pt2zx, pt2zy) = _FQ2Mul(pt1zx, pt1zy, pt2zx, pt2zy); // s³           = s * s²
        (pt2zx, pt2zy) = _FQ2Muc(pt2zx, pt2zy, 8);            // Z₃           = s³ * 8

        // ^In Section 2.2 formula (4) it is assumed that `a` is 0 which cancels
        //  out the LHS term of (aZ₁² + 3X₁²)² to (3X₁²)² for BN128/256 which is
        //  defined by `Y² = X³ + 3` where `a = 0` and `b = 3`.
    }

    function _ECTwistMulProjective(
        uint256 d,
        uint256 pt1xx,
        uint256 pt1xy,
        uint256 pt1yx,
        uint256 pt1yy,
        uint256 pt1zx,
        uint256 pt1zy
    ) internal pure returns (uint256[6] memory pt2) {
        while (d != 0) {
            if ((d & 1) != 0) {
                pt2 = _ECTwistAddProjective(
                    pt2[PTXX],
                    pt2[PTXY],
                    pt2[PTYX],
                    pt2[PTYY],
                    pt2[PTZX],
                    pt2[PTZY],
                    pt1xx,
                    pt1xy,
                    pt1yx,
                    pt1yy,
                    pt1zx,
                    pt1zy
                );
            }
            (pt1xx, pt1xy, pt1yx, pt1yy, pt1zx, pt1zy) = _ECTwistDoubleProjective(
                pt1xx,
                pt1xy,
                pt1yx,
                pt1yy,
                pt1zx,
                pt1zy
            );

            d = d / 2;
        }
    }

    function Get_yy_coordinate(uint256 xx, uint256 xy) internal pure returns (uint256 yx, uint256 yy) {
        uint256 y_squared_x;
        uint256 y_squared_y;
        uint256 xxxx;
        uint256 xxxy;

        // Calculate y^2 = x^3 + 3 using curve equation
        // y^2 = x^3 + ax + b with a=0 and b=3
        (xxxx, xxxy) = _FQ2Mul(xx, xy, xx, xy); // x^2
        (xxxx, xxxy) = _FQ2Mul(xxxx, xxxy, xx, xy); // x^3
        (y_squared_x, y_squared_y) = _FQ2Add(xxxx, xxxy, TWISTBX, TWISTBY); // x^3 + b

        // The y coordinate would be sqrt(y_squared) but calculating square root in finite fields is complex
        // We return y_squared instead. You may want to use a library or a precompiled contract to get the square root
        return (y_squared_x, y_squared_y);
    }

    function divBy2(uint256 x) internal pure returns (uint256 y) {
        bool odd = (x & 1) != 0;
        y = x / 2;
        if (odd) {
            y = addmod(y, HALF_FIELD_MODULUS, FIELD_MODULUS);
        }
    }

    function _sqrt(uint256 xx) internal view returns (uint256 x, bool hasRoot) {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), xx)
            // (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(add(freemem, 0x80), 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52)
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(add(freemem, 0xA0), FIELD_MODULUS)
            callSuccess := staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            x := mload(freemem)
            hasRoot := eq(xx, mulmod(x, x, FIELD_MODULUS))
        }
        if (!callSuccess) {
            x = 0;
            hasRoot = false;
        }
    }

    /**
     * @dev Square root function implemented as a translation from herumi's
     * bls/mcl/include/mcl/fp_tower.hpp Fp::squareRoot, see:
     *
     * github.com/herumi/mcl/blob/0ede57b846f02298bd80995533fb789f9067d86e/include/mcl/fp_tower.hpp#L364
     *
     *   (a + bi)^2 = (a^2 - b^2) + 2ab i = c + di
     *   A = a^2
     *   B = b^2
     *   A = (c +/- sqrt(c^2 + d^2))/2
     *   b = d / 2a
     */
    function FQ2Sqrt(uint256 x1, uint256 x2) public view returns (uint256, uint256) {
        // t1 and t2 for Fp types
        uint256 t1;
        uint256 t2;
        bool has_root;

        // if x.b is zero
        if (x2 == 0) {
            // Fp::squareRoot(t1, x.a)
            (t1, has_root) = _sqrt(x1);

            // if sqrt exists
            if (has_root) {
                return (t1, 0); // y.a = t1, y.b = 0
            } else {
                return (0, t1); // y.a = 0, y.b = t1
            }
        }

        t1 = mulmod(x1, x1, FIELD_MODULUS);           // c^2                          => Fp::sqr(t1, x.a);
        t2 = mulmod(x2, x2, FIELD_MODULUS);           // d^2                          => Fp::sqr(t2, x.b);
        t1 = addmod(t1, t2, FIELD_MODULUS);           // t1 = c^2 + d^2               => t1 += t2;

        (t1, has_root) = _sqrt(t1);                   // sqrt(c^2 + d^2)              => if (!Fp::squareRoot(t1, t1)) return false;
        if (!has_root) return (0, 0);                 // Return failed sqrt value

        t2 = addmod(x1, t1, FIELD_MODULUS);           // t2 = c + sqrt(c^2 + d^2)     => Fp::add(t2, x.a, t1);
        t2 = divBy2(t2);                              // t2 = (c + sqrt(c^2 + d^2))/2 => Fp::divBy2(t2, t2);

        uint256 sqrt_t2;
        (sqrt_t2, has_root) = _sqrt(t2);
        if (!has_root) {                              //                              => if (!Fp::squareRoot(t2, t2))
            t2 = submod(x1, t1, FIELD_MODULUS);       // t2 = c - sqrt(c^2 + d^2)     => Fp::sub(t2, x.a, t1);
            t2 = divBy2(t2);                          // t2 = (c - sqrt(c^2 + d^2))/2 => Fp::divBy2(t2, t2);

            (sqrt_t2, has_root) = _sqrt(t2);
            if (!has_root) return (0, 0);             // Return failed sqrt value
        }

        uint256 y1 = sqrt_t2;                         // y1 = t2;

        t2 = addmod(sqrt_t2, sqrt_t2, FIELD_MODULUS); // t2 += t2;
        t2 = _modInv(t2, FIELD_MODULUS);              // Fp::inv(t2, t2);

        uint256 y2;
        y2 = mulmod(x2, t2, FIELD_MODULUS);           // y2 = b / (2 * t2)            => Fp::mul(y.b, x.b, t2);

        return (y1, y2);
    }

    function NegateFQ2Sqrt(uint256 x1, uint256 x2) public pure returns (uint256, uint256) {
        uint256 neg_x1 = FIELD_MODULUS - x1;
        uint256 neg_x2 = FIELD_MODULUS - x2;
        return (neg_x1, neg_x2);
    }

    function ECTwistMulByCofactor(
        uint256 Pxx,
        uint256 Pxy,
        uint256 Pyx,
        uint256 Pyy
    ) internal view returns (uint256, uint256, uint256, uint256) {
        assert(_isOnCurve(Pxx, Pxy, Pyx, Pyy));
        uint256[6] memory Q = [Pxx, Pxy, Pyx, Pyy, 1, 0];

        Q = _ECTwistMulByCofactorProjective(Q);

        return _fromProjective(Q[PTXX], Q[PTXY], Q[PTYX], Q[PTYY], Q[PTZX], Q[PTZY]);
    }

    /**
     * @notice Multiplies a point on a twisted elliptic curve by the cofactor in projective coordinates.
     * @dev This function implements the algorithm described in the paper "Faster Hashing to G2" by 
     * Laura Fuentes-Castaneda, Edward Knapp, and Francisco Rodriguez-Henriquez, available at: 
     * https://cacr.uwaterloo.ca/techreports/2011/cacr2011-26.pdf. The elliptic curve is twisted and 
     * each coordinate has both real and imaginary parts.
     * 
     * @param P The input point in projective coordinates as an array of six uint256 values:
     * - P[0] (PTXX): The real part of the x-coordinate of the point.
     * - P[1] (PTXY): The imaginary part of the x-coordinate of the point.
     * - P[2] (PTYX): The real part of the y-coordinate of the point.
     * - P[3] (PTYY): The imaginary part of the y-coordinate of the point.
     * - P[4] (PTZX): The real part of the z-coordinate of the point.
     * - P[5] (PTZY): The imaginary part of the z-coordinate of the point.
     * @return Q The resulting point in projective coordinates as an array of six uint256 values:
     * - Q[0] (PTXX): The real part of the x-coordinate of the resulting point.
     * - Q[1] (PTXY): The imaginary part of the x-coordinate of the resulting point.
     * - Q[2] (PTYX): The real part of the y-coordinate of the resulting point.
     * - Q[3] (PTYY): The imaginary part of the y-coordinate of the resulting point.
     * - Q[4] (PTZX): The real part of the z-coordinate of the resulting point.
     * - Q[5] (PTZY): The imaginary part of the z-coordinate of the resulting point.
     */
    function _ECTwistMulByCofactorProjective(uint256[6] memory P) internal pure returns (uint256[6] memory Q) {
        uint256[6] memory T0;
        uint256[6] memory T1;
        uint256[6] memory T2;

        // T0 = CURVE_ORDER_FACTOR * P
        T0 = _ECTwistMulProjective(CURVE_ORDER_FACTOR, P[PTXX], P[PTXY], P[PTYX], P[PTYY], P[PTZX], P[PTZY]);

        // T1 = 2 * T0
        T1 = _ECTwistMulProjective(2, T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY]);

        // T1 = T1 + T0
        T1 = _ECTwistAddProjective(
            T0[PTXX],
            T0[PTXY],
            T0[PTYX],
            T0[PTYY],
            T0[PTZX],
            T0[PTZY],
            T1[PTXX],
            T1[PTXY],
            T1[PTYX],
            T1[PTYY],
            T1[PTZX],
            T1[PTZY]
        );

        // T1 = Frobenius(T1)
        T1 = _ECTwistFrobeniusProjective(T1);

        // T2 = Frobenius^2(T0)
        T2 = _ECTwistFrobeniusProjective(T0);
        T2 = _ECTwistFrobeniusProjective(T2);

        // T0 = T0 + T1 + T2
        T0 = _ECTwistAddProjective(
            T0[PTXX],
            T0[PTXY],
            T0[PTYX],
            T0[PTYY],
            T0[PTZX],
            T0[PTZY],
            T1[PTXX],
            T1[PTXY],
            T1[PTYX],
            T1[PTYY],
            T1[PTZX],
            T1[PTZY]
        );
        T0 = _ECTwistAddProjective(
            T0[PTXX],
            T0[PTXY],
            T0[PTYX],
            T0[PTYY],
            T0[PTZX],
            T0[PTZY],
            T2[PTXX],
            T2[PTXY],
            T2[PTYX],
            T2[PTYY],
            T2[PTZX],
            T2[PTZY]
        );

        // T2 = Frobenius^3(P)
        T2 = _ECTwistFrobeniusProjective(P);
        T2 = _ECTwistFrobeniusProjective(T2);
        T2 = _ECTwistFrobeniusProjective(T2);

        // Q = T0 + T2
        return
            _ECTwistAddProjective(
                T0[PTXX],
                T0[PTXY],
                T0[PTYX],
                T0[PTYY],
                T0[PTZX],
                T0[PTZY],
                T2[PTXX],
                T2[PTXY],
                T2[PTYX],
                T2[PTYY],
                T2[PTZX],
                T2[PTZY]
            );
    }

    function _ECTwistFrobeniusProjective(uint256[6] memory pt1) internal pure returns (uint256[6] memory pt2) {
        // Apply Frobenius map to each component
        (pt2[PTXX], pt2[PTXY]) = _FQ2Frobenius(pt1[PTXX], pt1[PTXY]);
        (pt2[PTYX], pt2[PTYY]) = _FQ2Frobenius(pt1[PTYX], pt1[PTYY]);
        (pt2[PTZX], pt2[PTZY]) = _FQ2Frobenius(pt1[PTZX], pt1[PTZY]);

        // Multiply x and y coordinates by appropriate constants to bring it back onto the curve
        (pt2[PTXX], pt2[PTXY]) = _FQ2Mul(pt2[PTXX], pt2[PTXY], FROBENIUS_COEFF_X_0, FROBENIUS_COEFF_X_1);
        (pt2[PTYX], pt2[PTYY]) = _FQ2Mul(pt2[PTYX], pt2[PTYY], FROBENIUS_COEFF_Y_0, FROBENIUS_COEFF_Y_1);

        return pt2;
    }

    function _FQ2Frobenius(uint256 x1, uint256 x2) internal pure returns (uint256, uint256) {
        return (x1, FIELD_MODULUS - x2);
    }

    // Hashes to G2 using the try and increment method
    function mapToG2(bytes memory message, bytes32 hashToG2Tag) internal view returns (G2Point memory) {

        // Define the G2Point coordinates
        uint256 x1;
        uint256 x2;
        uint256 y1 = 0;
        uint256 y2 = 0;

        bytes memory message_with_i = new bytes(message.length + 1 /*bytes*/);
        for (uint index = 0; index < message.length; index++) {
            message_with_i[index] = message[index];
        }

        for (uint8 increment = 0;; increment++) { // Iterate until we find a valid G2 point
            message_with_i[message_with_i.length - 1] = bytes1(increment);

            bool b;
            (x1, x2, b)                      = hashToField(message_with_i, hashToG2Tag);
            (uint256 yx,     uint256 yy)     = Get_yy_coordinate(x1, x2); // Try to get y^2
            (uint256 sqrt_x, uint256 sqrt_y) = FQ2Sqrt(yx, yy);           // Calculate square root

            if (sqrt_x != 0 && sqrt_y != 0) { // Check if this is a point
                if (b) { // Let b => {0, 1} to choose between the two roots.
                    (sqrt_x, sqrt_y) = NegateFQ2Sqrt(sqrt_x, sqrt_y);
                }
                (y1, y2) = (sqrt_x, sqrt_y);
                if (IsOnCurve(x1, x2, y1, y2)) {
                    break;
                }
            }
        }

        return (G2Point([x2, x1], [y2, y1]));
    }

    function hashToG2(bytes memory message, bytes32 hashToG2Tag) internal view returns (G2Point memory) {
        G2Point memory map = mapToG2(message, hashToG2Tag);
        (uint256 x1, uint256 x2, uint256 y1, uint256 y2) = ECTwistMulByCofactor(map.X[1], map.X[0], map.Y[1], map.Y[0]);
        return (G2Point([x2, x1], [y2, y1]));
    }

    uint256 private constant KECCAK256_BLOCKSIZE = 136;

    /**
     * Takes an arbitrary byte-string and a domain seperation tag (dst) and
     * returns two elements of the field with prime `FIELD_MODULUS`. This
     * implementation is taken from Hopr's crypto implementation and repurposed
     * for a BN256 curve:
     *
     * github.com/hoprnet/hoprnet/blob/53e3f49855775af8e92b465306be144038167b63/ethereum/contracts/src/Crypto.sol
     *
     * @dev DSTs longer than 255 bytes are considered unsound.
     *      see https://www.ietf.org/archive/id/draft-irtf-cfrg-hash-to-curve-16.html#name-domain-separation
     *
     * @param message the message to hash
     * @param dst domain separation tag, used to make protocol instantiations unique
     */
    function hashToField(bytes memory message, bytes32 dst) public view returns (uint256 u0, uint256 u1, bool b) {
        (bytes32 b1, bytes32 b2, bytes32 b3, bytes32 b4) = expandMessageXMDKeccak256(message, abi.encodePacked(dst));

        // computes ([...b1[..], ...b2[0..16]] ^ 1) mod n
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let p := mload(0x40)                // next free memory slot
            mstore(p, 0x30)                     // Length of Base
            mstore(add(p, 0x20), 0x20)          // Length of Exponent
            mstore(add(p, 0x40), 0x20)          // Length of Modulus
            mstore(add(p, 0x60), b1)            // Base
            mstore(add(p, 0x80), b2)
            mstore(add(p, 0x90), 1)             // Exponent
            mstore(add(p, 0xb0), FIELD_MODULUS) // Modulus
            if iszero(staticcall(not(0), 0x05, p, 0xD0, p, 0x20)) { revert(0, 0) }

            u0 := mload(p)
        }

        // computes ([...b2[16..32], ...b3[..]] ^ 1) mod n
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let p := mload(0x40)
            mstore(p, 0x30)                     // Length of Base
            mstore(add(p, 0x20), 0x20)          // Length of Exponent
            mstore(add(p, 0x50), b2)
            mstore(add(p, 0x40), 0x20)          // Length of Modulus
            mstore(add(p, 0x70), b3)            // Base
            mstore(add(p, 0x90), 1)             // Exponent
            mstore(add(p, 0xb0), FIELD_MODULUS) // Modulus
            if iszero(staticcall(not(0), 0x05, p, 0xD0, p, 0x20)) { revert(0, 0) }

            u1 := mload(p)
        }

        b = (uint8(uint256(b4)) & 1) == 1;
    }

    /**
     * Expands an arbitrary byte-string to 128 bytes using the
     * `expand_message_xmd` method described in
     *
     * https://www.rfc-editor.org/rfc/rfc9380.html#name-expand_message_xmd
     *
     * This implementation is taken from Hopr's crypto implementation:
     *
     * github.com/hoprnet/hoprnet/blob/53e3f49855775af8e92b465306be144038167b63/ethereum/contracts/src/Crypto.sol
     *
     * Used for hashToField functionality to generate points within
     * FIELD_MODULUS such that bias of selecting such numbers is beneath 2^-128
     * as recommended by RFC9380.
     *
     * @dev DSTs longer than 255 bytes are considered unsound.
     *      see https://www.ietf.org/archive/id/draft-irtf-cfrg-hash-to-curve-16.html#name-domain-separation
     *
     * @param message the message to hash
     * @param dst domain separation tag, used to make protocol instantiations unique
     */
    function expandMessageXMDKeccak256(
        bytes memory message,
        bytes memory dst
    )
        public
        pure
        returns (bytes32 b1, bytes32 b2, bytes32 b3, bytes32 b4)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            if gt(mload(dst), 255) { revert(0, 0) }

            let b0
            {
                // create payload for b0 hash
                let b0Payload := mload(0x40)

                // payload[0..KECCAK256_BLOCKSIZE] = 0
                for { let i := 0 } lt(i, KECCAK256_BLOCKSIZE) { i := add(i, 0x20) } {
                    mstore(add(b0Payload, i), 0)
                }

                let b0PayloadO := KECCAK256_BLOCKSIZE // leave first block empty
                let msg_o := 0x20 // skip length prefix

                // payload[KECCAK256_BLOCKSIZE..KECCAK256_BLOCKSIZE+message.len()] = message[0..message.len()]
                for { let i := 0 } lt(i, mload(message)) { i := add(i, 0x20) } {
                    mstore(add(b0Payload, b0PayloadO), mload(add(message, msg_o)))
                    b0PayloadO := add(b0PayloadO, 0x20)
                    msg_o := add(msg_o, 0x20)
                }

                // payload[KECCAK256_BLOCKSIZE+message.len()+1..KECCAK256_BLOCKSIZE+message.len()+2] = 128
                b0PayloadO := add(mload(message), 137)
                mstore8(add(b0Payload, b0PayloadO), 0x80) // only support for 128 bytes output length

                let dstO := 0x20
                b0PayloadO := add(b0PayloadO, 2)

                // payload[KECCAK256_BLOCKSIZE+message.len()+3..KECCAK256_BLOCKSIZE+message.len()+dst.len()]
                // = dst[0..dst.len()]
                for { let i := 0 } lt(i, mload(dst)) { i := add(i, 0x20) } {
                    mstore(add(b0Payload, b0PayloadO), mload(add(dst, dstO)))
                    b0PayloadO := add(b0PayloadO, 0x20)
                    dstO := add(dstO, 0x20)
                }

                // payload[KECCAK256_BLOCKSIZE+message.len()+dst.len()..KECCAK256_BLOCKSIZE+message.len()+dst.len()+1]
                // = dst.len()
                b0PayloadO := add(add(mload(message), mload(dst)), 139)
                mstore8(add(b0Payload, b0PayloadO), mload(dst))

                b0 := keccak256(b0Payload, add(140, add(mload(dst), mload(message))))
            }

            // create payload for b1, b2 ... hashes
            let bIPayload := mload(0x40)
            mstore(bIPayload, b0)
            // payload[32..33] = 1
            mstore8(add(bIPayload, 0x20), 1)

            let payloadO := 0x21
            let dstO := 0x20

            // payload[33..33+dst.len()] = dst[0..dst.len()]
            for { let i := 0 } lt(i, mload(dst)) { i := add(i, 0x20) } {
                mstore(add(bIPayload, payloadO), mload(add(dst, dstO)))
                payloadO := add(payloadO, 0x20)
                dstO := add(dstO, 0x20)
            }

            // payload[65+dst.len()..66+dst.len()] = dst.len()
            mstore8(add(bIPayload, add(0x21, mload(dst))), mload(dst))

            b1 := keccak256(bIPayload, add(34, mload(dst)))

            // payload[0..32] = b0 XOR b1
            mstore(bIPayload, xor(b0, b1))
            // payload[32..33] = 2
            mstore8(add(bIPayload, 0x20), 2)

            b2 := keccak256(bIPayload, add(34, mload(dst)))

            // payload[0..32] = b0 XOR b2
            mstore(bIPayload, xor(b0, b2))
            // payload[32..33] = 3
            mstore8(add(bIPayload, 0x20), 3)

            b3 := keccak256(bIPayload, add(34, mload(dst)))

            // payload[0..32] = b0 XOR b3
            mstore(bIPayload, xor(b0, b3))
            // payload[32..33] = 4
            mstore8(add(bIPayload, 0x20), 4)

            b4 := keccak256(bIPayload, add(34, mload(dst)))
        }
    }
}
