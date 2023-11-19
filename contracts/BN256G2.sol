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
    uint256 constant FROBENIUS_COEFF_X_0 = 21575463638280843010398324269430826099269044274347216827212613867836435027261;
    uint256 constant FROBENIUS_COEFF_X_1 = 10307601595873709700152284273816112264069230130616436755625194854815875713954;

    // xiToPMinus1Over2 is ξ^((p-1)/2) where ξ = i+9.
    uint256 constant FROBENIUS_COEFF_Y_0 = 2821565182194536844548159561693502659359617185244120367078079554186484126554;
    uint256 constant FROBENIUS_COEFF_Y_1 = 3505843767911556378687030309984248845540243509899259641013678093033130930403;

    /**
     * @notice Add two twist points
     * @param pt1xx Coefficient 1 of x on point 1
     * @param pt1xy Coefficient 2 of x on point 1
     * @param pt1yx Coefficient 1 of y on point 1
     * @param pt1yy Coefficient 2 of y on point 1
     * @param pt2xx Coefficient 1 of x on point 2
     * @param pt2xy Coefficient 2 of x on point 2
     * @param pt2yx Coefficient 1 of y on point 2
     * @param pt2yy Coefficient 2 of y on point 2
     * @return (pt3xx, pt3xy, pt3yx, pt3yy)
     */
    function ECTwistAdd(
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy,
        uint256 pt2xx, uint256 pt2xy,
        uint256 pt2yx, uint256 pt2yy
    ) public view returns (
        uint256, uint256,
        uint256, uint256
    ) {
        if ( pt1xx == 0 && pt1xy == 0 &&
            pt1yx == 0 && pt1yy == 0
        ) {
            if (!(
                pt2xx == 0 && pt2xy == 0 &&
                pt2yx == 0 && pt2yy == 0
            )) {
                assert(_isOnCurve(
                    pt2xx, pt2xy,
                    pt2yx, pt2yy
                ));
            }
            return (
                pt2xx, pt2xy,
                pt2yx, pt2yy
            );
        } else if (
            pt2xx == 0 && pt2xy == 0 &&
            pt2yx == 0 && pt2yy == 0
        ) {
            assert(_isOnCurve(
                pt1xx, pt1xy,
                pt1yx, pt1yy
            ));
            return (
                pt1xx, pt1xy,
                pt1yx, pt1yy
            );
        }

        assert(_isOnCurve(
            pt1xx, pt1xy,
            pt1yx, pt1yy
        ));
        assert(_isOnCurve(
            pt2xx, pt2xy,
            pt2yx, pt2yy
        ));

        uint256[6] memory pt3 = _ECTwistAddJacobian(
            pt1xx, pt1xy,
            pt1yx, pt1yy,
            1,     0,
            pt2xx, pt2xy,
            pt2yx, pt2yy,
            1,     0
        );

        return _fromJacobian(
            pt3[PTXX], pt3[PTXY],
            pt3[PTYX], pt3[PTYY],
            pt3[PTZX], pt3[PTZY]
        );
    }

    /**
     * @notice Multiply a twist point by a scalar
     * @param s     Scalar to multiply by
     * @param pt1xx Coefficient 1 of x
     * @param pt1xy Coefficient 2 of x
     * @param pt1yx Coefficient 1 of y
     * @param pt1yy Coefficient 2 of y
     * @return (pt2xx, pt2xy, pt2yx, pt2yy)
     */
    function ECTwistMul(
        uint256 s,
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy
    ) public view returns (
        uint256, uint256,
        uint256, uint256
    ) {
        uint256 pt1zx = 1;
        if (
            pt1xx == 0 && pt1xy == 0 &&
            pt1yx == 0 && pt1yy == 0
        ) {
            pt1xx = 1;
            pt1yx = 1;
            pt1zx = 0;
        } else {
            assert(_isOnCurve(
                pt1xx, pt1xy,
                pt1yx, pt1yy
            ));
        }

        uint256[6] memory pt2 = _ECTwistMulJacobian(
            s,
            pt1xx, pt1xy,
            pt1yx, pt1yy,
            pt1zx, 0
        );

        return _fromJacobian(
            pt2[PTXX], pt2[PTXY],
            pt2[PTYX], pt2[PTYY],
            pt2[PTZX], pt2[PTZY]
        );
    }

    /**
     * @notice Get the field modulus
     * @return The field modulus
     */
    function GetFieldModulus() public pure returns (uint256) {
        return FIELD_MODULUS;
    }

    function submod(uint256 a, uint256 b, uint256 n) internal pure returns (uint256) {
        return addmod(a, n - b, n);
    }

    function _FQ2Mul(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal pure returns (uint256, uint256) {
        return (
            submod(mulmod(xx, yx, FIELD_MODULUS), mulmod(xy, yy, FIELD_MODULUS), FIELD_MODULUS),
            addmod(mulmod(xx, yy, FIELD_MODULUS), mulmod(xy, yx, FIELD_MODULUS), FIELD_MODULUS)
        );
    }

    function _FQ2Muc(
        uint256 xx, uint256 xy,
        uint256 c
    ) internal pure returns (uint256, uint256) {
        return (
            mulmod(xx, c, FIELD_MODULUS),
            mulmod(xy, c, FIELD_MODULUS)
        );
    }

    function _FQ2Add(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal pure returns (uint256, uint256) {
        return (
            addmod(xx, yx, FIELD_MODULUS),
            addmod(xy, yy, FIELD_MODULUS)
        );
    }

    function _FQ2Sub(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal pure returns (uint256 rx, uint256 ry) {
        return (
            submod(xx, yx, FIELD_MODULUS),
            submod(xy, yy, FIELD_MODULUS)
        );
    }

    function _FQ2Div(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal view returns (uint256, uint256) {
        (yx, yy) = _FQ2Inv(yx, yy);
        return _FQ2Mul(xx, xy, yx, yy);
    }

    function _FQ2Inv(uint256 x, uint256 y) internal view returns (uint256, uint256) {
        uint256 inv = _modInv(addmod(mulmod(y, y, FIELD_MODULUS), mulmod(x, x, FIELD_MODULUS), FIELD_MODULUS), FIELD_MODULUS);
        return (
            mulmod(x, inv, FIELD_MODULUS),
            FIELD_MODULUS - mulmod(y, inv, FIELD_MODULUS)
        );
    }

    function _FQ2Pow(uint256 basex, uint256 basey, uint256 exponent) internal pure returns (uint256, uint256) 
    {
        uint256 resultx = 1;
        uint256 resulty = 0; // Start with 1 + 0i in Fp2
        while (exponent > 0) {
            if (exponent % 2 != 0) {
                // Multiply result by base in Fp2
                (resultx, resulty) = _FQ2Mul(resultx, resulty, basex, basey);
            }
            // Square the base in Fp2
            (basex, basey) = _FQ2Mul(basex, basey, basex, basey);
            // Move to the next bit in the exponent
            exponent /= 2;
        }
        return (resultx, resulty);
    }

    function _isOnCurve(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) internal pure returns (bool) {
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

    function IsOnCurve(
        uint256 xx, uint256 xy,
        uint256 yx, uint256 yy
    ) public pure returns (bool) {
        return _isOnCurve(xx,xy,yx,yy);
    }
    

    function _modInv(uint256 a, uint256 n) internal view returns (uint256 result) {
        bool success;
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem,0x20), 0x20)
            mstore(add(freemem,0x40), 0x20)
            mstore(add(freemem,0x60), a)
            mstore(add(freemem,0x80), sub(n, 2))
            mstore(add(freemem,0xA0), n)
            success := staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            result := mload(freemem)
        }
        require(success);
    }

    function _fromJacobian(
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy,
        uint256 pt1zx, uint256 pt1zy
    ) internal view returns (
        uint256 pt2xx, uint256 pt2xy,
        uint256 pt2yx, uint256 pt2yy
    ) {
        uint256 invzx;
        uint256 invzy;
        (invzx, invzy) = _FQ2Inv(pt1zx, pt1zy);
        (pt2xx, pt2xy) = _FQ2Mul(pt1xx, pt1xy, invzx, invzy);
        (pt2yx, pt2yy) = _FQ2Mul(pt1yx, pt1yy, invzx, invzy);
    }

    function _ECTwistAddJacobian(
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy,
        uint256 pt1zx, uint256 pt1zy,
        uint256 pt2xx, uint256 pt2xy,
        uint256 pt2yx, uint256 pt2yy,
        uint256 pt2zx, uint256 pt2zy) internal pure returns (uint256[6] memory pt3) {
            if (pt1zx == 0 && pt1zy == 0) {
                (
                    pt3[PTXX], pt3[PTXY],
                    pt3[PTYX], pt3[PTYY],
                    pt3[PTZX], pt3[PTZY]
                ) = (
                    pt2xx, pt2xy,
                    pt2yx, pt2yy,
                    pt2zx, pt2zy
                );
                return pt3;
            } else if (pt2zx == 0 && pt2zy == 0) {
                (
                    pt3[PTXX], pt3[PTXY],
                    pt3[PTYX], pt3[PTYY],
                    pt3[PTZX], pt3[PTZY]
                ) = (
                    pt1xx, pt1xy,
                    pt1yx, pt1yy,
                    pt1zx, pt1zy
                );
                return pt3;
            }

            (pt2yx,     pt2yy)     = _FQ2Mul(pt2yx, pt2yy, pt1zx, pt1zy); // U1 = y2 * z1
            (pt3[PTYX], pt3[PTYY]) = _FQ2Mul(pt1yx, pt1yy, pt2zx, pt2zy); // U2 = y1 * z2
            (pt2xx,     pt2xy)     = _FQ2Mul(pt2xx, pt2xy, pt1zx, pt1zy); // V1 = x2 * z1
            (pt3[PTZX], pt3[PTZY]) = _FQ2Mul(pt1xx, pt1xy, pt2zx, pt2zy); // V2 = x1 * z2

            if (pt2xx == pt3[PTZX] && pt2xy == pt3[PTZY]) {
                if (pt2yx == pt3[PTYX] && pt2yy == pt3[PTYY]) {
                    (
                        pt3[PTXX], pt3[PTXY],
                        pt3[PTYX], pt3[PTYY],
                        pt3[PTZX], pt3[PTZY]
                    ) = _ECTwistDoubleJacobian(pt1xx, pt1xy, pt1yx, pt1yy, pt1zx, pt1zy);
                    return pt3;
                }
                (
                    pt3[PTXX], pt3[PTXY],
                    pt3[PTYX], pt3[PTYY],
                    pt3[PTZX], pt3[PTZY]
                ) = (
                    1, 0,
                    1, 0,
                    0, 0
                );
                return pt3;
            }

            (pt2zx,     pt2zy)     = _FQ2Mul(pt1zx, pt1zy, pt2zx,     pt2zy);     // W = z1 * z2
            (pt1xx,     pt1xy)     = _FQ2Sub(pt2yx, pt2yy, pt3[PTYX], pt3[PTYY]); // U = U1 - U2
            (pt1yx,     pt1yy)     = _FQ2Sub(pt2xx, pt2xy, pt3[PTZX], pt3[PTZY]); // V = V1 - V2
            (pt1zx,     pt1zy)     = _FQ2Mul(pt1yx, pt1yy, pt1yx,     pt1yy);     // V_squared = V * V
            (pt2yx,     pt2yy)     = _FQ2Mul(pt1zx, pt1zy, pt3[PTZX], pt3[PTZY]); // V_squared_times_V2 = V_squared * V2
            (pt1zx,     pt1zy)     = _FQ2Mul(pt1zx, pt1zy, pt1yx,     pt1yy);     // V_cubed = V * V_squared
            (pt3[PTZX], pt3[PTZY]) = _FQ2Mul(pt1zx, pt1zy, pt2zx,     pt2zy);     // newz = V_cubed * W
            (pt2xx,     pt2xy)     = _FQ2Mul(pt1xx, pt1xy, pt1xx,     pt1xy);     // U * U
            (pt2xx,     pt2xy)     = _FQ2Mul(pt2xx, pt2xy, pt2zx,     pt2zy);     // U * U * W
            (pt2xx,     pt2xy)     = _FQ2Sub(pt2xx, pt2xy, pt1zx,     pt1zy);     // U * U * W - V_cubed
            (pt2zx,     pt2zy)     = _FQ2Muc(pt2yx, pt2yy, 2);                    // 2 * V_squared_times_V2
            (pt2xx,     pt2xy)     = _FQ2Sub(pt2xx, pt2xy, pt2zx,     pt2zy);     // A = U * U * W - V_cubed - 2 * V_squared_times_V2
            (pt3[PTXX], pt3[PTXY]) = _FQ2Mul(pt1yx, pt1yy, pt2xx,     pt2xy);     // newx = V * A
            (pt1yx,     pt1yy)     = _FQ2Sub(pt2yx, pt2yy, pt2xx,     pt2xy);     // V_squared_times_V2 - A
            (pt1yx,     pt1yy)     = _FQ2Mul(pt1xx, pt1xy, pt1yx,     pt1yy);     // U * (V_squared_times_V2 - A)
            (pt1xx,     pt1xy)     = _FQ2Mul(pt1zx, pt1zy, pt3[PTYX], pt3[PTYY]); // V_cubed * U2
            (pt3[PTYX], pt3[PTYY]) = _FQ2Sub(pt1yx, pt1yy, pt1xx,     pt1xy);     // newy = U * (V_squared_times_V2 - A) - V_cubed * U2
    }

    function _ECTwistDoubleJacobian(
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy,
        uint256 pt1zx, uint256 pt1zy
    ) internal pure returns (
        uint256 pt2xx, uint256 pt2xy,
        uint256 pt2yx, uint256 pt2yy,
        uint256 pt2zx, uint256 pt2zy
    ) {
        (pt2xx, pt2xy) = _FQ2Muc(pt1xx, pt1xy, 3);            // 3 * x
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1xx, pt1xy); // W = 3 * x * x
        (pt1zx, pt1zy) = _FQ2Mul(pt1yx, pt1yy, pt1zx, pt1zy); // S = y * z
        (pt2yx, pt2yy) = _FQ2Mul(pt1xx, pt1xy, pt1yx, pt1yy); // x * y
        (pt2yx, pt2yy) = _FQ2Mul(pt2yx, pt2yy, pt1zx, pt1zy); // B = x * y * S
        (pt1xx, pt1xy) = _FQ2Mul(pt2xx, pt2xy, pt2xx, pt2xy); // W * W
        (pt2zx, pt2zy) = _FQ2Muc(pt2yx, pt2yy, 8);            // 8 * B
        (pt1xx, pt1xy) = _FQ2Sub(pt1xx, pt1xy, pt2zx, pt2zy); // H = W * W - 8 * B
        (pt2zx, pt2zy) = _FQ2Mul(pt1zx, pt1zy, pt1zx, pt1zy); // S_squared = S * S
        (pt2yx, pt2yy) = _FQ2Muc(pt2yx, pt2yy, 4);            // 4 * B
        (pt2yx, pt2yy) = _FQ2Sub(pt2yx, pt2yy, pt1xx, pt1xy); // 4 * B - H
        (pt2yx, pt2yy) = _FQ2Mul(pt2yx, pt2yy, pt2xx, pt2xy); // W * (4 * B - H)
        (pt2xx, pt2xy) = _FQ2Muc(pt1yx, pt1yy, 8);            // 8 * y
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1yx, pt1yy); // 8 * y * y
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt2zx, pt2zy); // 8 * y * y * S_squared
        (pt2yx, pt2yy) = _FQ2Sub(pt2yx, pt2yy, pt2xx, pt2xy); // newy = W * (4 * B - H) - 8 * y * y * S_squared
        (pt2xx, pt2xy) = _FQ2Muc(pt1xx, pt1xy, 2);            // 2 * H
        (pt2xx, pt2xy) = _FQ2Mul(pt2xx, pt2xy, pt1zx, pt1zy); // newx = 2 * H * S
        (pt2zx, pt2zy) = _FQ2Mul(pt1zx, pt1zy, pt2zx, pt2zy); // S * S_squared
        (pt2zx, pt2zy) = _FQ2Muc(pt2zx, pt2zy, 8);            // newz = 8 * S * S_squared
    }

    function _ECTwistMulJacobian(
        uint256 d,
        uint256 pt1xx, uint256 pt1xy,
        uint256 pt1yx, uint256 pt1yy,
        uint256 pt1zx, uint256 pt1zy
    ) internal pure returns (uint256[6] memory pt2) {
        while (d != 0) {
            if ((d & 1) != 0) {
                pt2 = _ECTwistAddJacobian(
                    pt2[PTXX], pt2[PTXY],
                    pt2[PTYX], pt2[PTYY],
                    pt2[PTZX], pt2[PTZY],
                    pt1xx, pt1xy,
                    pt1yx, pt1yy,
                    pt1zx, pt1zy);
            }
            (
                pt1xx, pt1xy,
                pt1yx, pt1yy,
                pt1zx, pt1zy
            ) = _ECTwistDoubleJacobian(
                pt1xx, pt1xy,
                pt1yx, pt1yy,
                pt1zx, pt1zy
            );

            d = d / 2;
        }
    }

    function Get_yy_coordinate(
        uint256 xx, uint256 xy
    ) public pure returns (uint256 yx, uint256 yy) {
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

    function divBy2(uint256 x) public pure returns (uint256 y) {
        bool odd = (x & 1) != 0;
        y = x / 2;
        if (odd) {
            y = addmod(y, HALF_FIELD_MODULUS, FIELD_MODULUS);
        }
    }


    function _sqrt(uint256 xx) public view returns (uint256 x, bool hasRoot) {
        bool callSuccess;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), xx)
            // (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(
                add(freemem, 0x80),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                FIELD_MODULUS
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            x := mload(freemem)
            hasRoot := eq(xx, mulmod(x, x, FIELD_MODULUS))
        }
        if (!callSuccess) {
            x = 0;
            hasRoot = false;
        }
    }

    function FQ2Sqrt(
        uint256 x1, uint256 x2
    ) public view returns (uint256, uint256) {
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
                return (t1, 0);  // y.a = t1, y.b = 0
            } else {
                // Fp::squareRoot(t1, -x.a)
                (t1, has_root) = _sqrt(FIELD_MODULUS - x1);  // -x.a under modulo FIELD_MODULUS
                assert(has_root);  // assert(b)
                return (0, t1);  // y.a = 0, y.b = t1
            }
        }

        // Fp::sqr(t1, x.a); Fp::sqr(t2, x.b);
        t1 = mulmod(x1, x1, FIELD_MODULUS);
        t2 = mulmod(x2, x2, FIELD_MODULUS);

        // t1 += t2; // c^2 + d^2
        t1 = addmod(t1, t2, FIELD_MODULUS);

        // if (!Fp::squareRoot(t1, t1)) return false;
        (t1, has_root) = _sqrt(t1);
        if (!has_root) return (0, 0);  // indicate failed sqrt

        // Fp::add(t2, x.a, t1); Fp::divBy2(t2, t2);
        t2 = addmod(x1, t1, FIELD_MODULUS);
        t2 = divBy2(t2);

        // if (!Fp::squareRoot(t2, t2))
        uint256 sqrt_t2;
        (sqrt_t2, has_root) = _sqrt(t2);
        if (!has_root) {
            // Fp::sub(t2, x.a, t1); Fp::divBy2(t2, t2);
            t2 = submod(x1, t1, FIELD_MODULUS);
            t2 = divBy2(t2);
            
            (sqrt_t2, has_root) = _sqrt(t2);
            if (!has_root) return (0, 0);  // indicate failed sqrt
        }

        // y.a = t2;
        uint256 y1 = sqrt_t2;

        // t2 += t2; Fp::inv(t2, t2);
        t2 = addmod(sqrt_t2, sqrt_t2, FIELD_MODULUS);
        t2 = _modInv(t2, FIELD_MODULUS);
        
        // Fp::mul(y.b, x.b, t2);
        uint256 y2;
        y2 = mulmod(x2, t2, FIELD_MODULUS);

        return (y1, y2);
    }

    function ECTwistMulByCofactor(
        uint256 Pxx, uint256 Pxy,
        uint256 Pyx, uint256 Pyy
    ) public view returns (
        uint256, uint256,
        uint256, uint256
    ) {
        assert(_isOnCurve(
            Pxx, Pxy,
            Pyx, Pyy
        ));
        uint256[6] memory Q = [Pxx, Pxy, Pyx, Pyy, 1, 0];
        
        Q = _ECTwistMulByCofactorJacobian(Q);

        return _fromJacobian(
            Q[PTXX], Q[PTXY],
            Q[PTYX], Q[PTYY],
            Q[PTZX], Q[PTZY]
        );
    }

    function _ECTwistMulByCofactorJacobian(
        uint256[6] memory P
    ) public pure returns (
        uint256[6] memory Q
    ) {
        uint256[6] memory T0;
        uint256[6] memory T1;
        uint256[6] memory T2;

        // T0 = CURVE_ORDER_FACTOR * P
        T0 = _ECTwistMulJacobian(CURVE_ORDER_FACTOR, P[PTXX], P[PTXY], P[PTYX], P[PTYY], P[PTZX], P[PTZY]);

        // T1 = 2 * T0
        T1 = _ECTwistMulJacobian(2, T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY]);


        // T1 = T1 + T0
        T1 = _ECTwistAddJacobian(T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY], T1[PTXX], T1[PTXY], T1[PTYX], T1[PTYY], T1[PTZX], T1[PTZY]);

        // T1 = Frobenius(T1)
        T1 = _ECTwistFrobeniusJacobian(T1);

        // T2 = Frobenius^2(T0)
        T2 = _ECTwistFrobeniusJacobian(T0);
        T2 = _ECTwistFrobeniusJacobian(T2);

        // T0 = T0 + T1 + T2
        T0 = _ECTwistAddJacobian(T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY], T1[PTXX], T1[PTXY], T1[PTYX], T1[PTYY], T1[PTZX], T1[PTZY]);
        T0 = _ECTwistAddJacobian(T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY], T2[PTXX], T2[PTXY], T2[PTYX], T2[PTYY], T2[PTZX], T2[PTZY]);

        // T2 = Frobenius^3(P)
        T2 = _ECTwistFrobeniusJacobian(P);
        T2 = _ECTwistFrobeniusJacobian(T2);
        T2 = _ECTwistFrobeniusJacobian(T2);

        // Q = T0 + T2
        return _ECTwistAddJacobian(T0[PTXX], T0[PTXY], T0[PTYX], T0[PTYY], T0[PTZX], T0[PTZY], T2[PTXX], T2[PTXY], T2[PTYX], T2[PTYY], T2[PTZX], T2[PTZY]);
    }

    function _ECTwistFrobeniusJacobian(uint256[6] memory pt1) public pure returns (uint256[6] memory pt2) {
        // Apply Frobenius map to each component
        (pt2[PTXX], pt2[PTXY]) = _FQ2Frobenius(pt1[PTXX], pt1[PTXY]);
        (pt2[PTYX], pt2[PTYY]) = _FQ2Frobenius(pt1[PTYX], pt1[PTYY]);
        (pt2[PTZX], pt2[PTZY]) = _FQ2Frobenius(pt1[PTZX], pt1[PTZY]);

        // Multiply x and y coordinates by appropriate constants to bring it back onto the curve
        (pt2[PTXX], pt2[PTXY]) = _FQ2Mul(pt2[PTXX], pt2[PTXY], FROBENIUS_COEFF_X_0, FROBENIUS_COEFF_X_1);
        (pt2[PTYX], pt2[PTYY]) = _FQ2Mul(pt2[PTYX], pt2[PTYY], FROBENIUS_COEFF_Y_0, FROBENIUS_COEFF_Y_1);

        return pt2;
    }


    function _FQ2Frobenius(
        uint256 x1, uint256 x2
    ) public pure returns (uint256, uint256) {
        return (x1, FIELD_MODULUS - x2);
    }

    // hashes to G2 using the try and increment method
    function mapToG2(uint256 h) public view returns (G2Point memory) {
        // Define the G2Point coordinates
        uint256 x1 = h;
        uint256 x2 = 0;
        uint256 y1;
        uint256 y2;

        bool foundValidPoint = false;

        // Iterate until we find a valid G2 point
        while (!foundValidPoint) {
            // Try to get y^2
            (uint256 yx, uint256 yy) = Get_yy_coordinate(x1, x2);

            // Calculate square root
            (uint256 sqrt_x, uint256 sqrt_y) = FQ2Sqrt(yx, yy);


            // Check if this is a point
            if (sqrt_x != 0 && sqrt_y != 0) {
                y1 = sqrt_x;
                y2 = sqrt_y;
                if (IsOnCurve(x1, x2, y1, y2)) {
                    foundValidPoint = true;
                } else {
                    x1 += 1;
                }
            } else {
                // Increment x coordinate and try again.
                x1 += 1;
            }
        }

        return (G2Point([x2,x1],[y2,y1]));
    }

    function hashToG2(uint256 h) public view returns (G2Point memory) {
        G2Point memory map = mapToG2(h);
        (uint256 x1, uint256 x2, uint256 y1, uint256 y2) = ECTwistMulByCofactor(map.X[1], map.X[0], map.Y[1], map.Y[0]);
        return (G2Point([x2,x1],[y2,y1]));
    }

    function getWeierstrass(uint256 x, uint256 y) public pure returns (uint256, uint256) {
        return Get_yy_coordinate(x,y);
    }

    function convertArrayAsLE(bytes32 src) public pure returns (bytes32) {
        bytes32 dst;
        for (uint256 i = 0; i < 32; i++) {
            // Considering each byte of bytes32
            bytes1 s = src[i];
            // Assuming the role of D is just to cast or store our byte in this context
            dst |= bytes32(s) >> (i * 8);
        }
        return dst;
    }

    // This matches mcl maskN, this only takes the 254 bits for the field, if it is still greater than the field then take the 253 bits
    function maskBits(uint256 input) public pure returns (uint256) {
        uint256 mask = ~uint256(0) - 0xC0;
        if (byteSwap(input & mask) >= FIELD_MODULUS) {
            mask = ~uint256(0) - 0xE0;
        }
        return input & mask;
    }

    function byteSwap(uint256 value) public pure returns (uint256) {
        uint256 swapped = 0;
        for (uint256 i = 0; i < 32; i++) {
            uint256 byteValue = (value >> (i * 8)) & 0xFF; 
            swapped |= byteValue << (256 - 8 - (i * 8));
        }
        return swapped;
    }

    function calcField(uint256 pkX, uint256 pkY) public pure returns (uint256) {
        return hashToField(string(abi.encodePacked(pkX, pkY)));
    }

    function hashToField(string memory message) public pure returns (uint256) {
        return byteSwap(maskBits(uint256(convertArrayAsLE(keccak256(bytes(message))))));
    }

    /// @return the generator of G2
    function P2() public pure returns (G2Point memory) {
        return G2Point(
            [11559732032986387107991004021392285783925812861821192530917403151452391805634,
            10857046999023057135944570762232829481370756359578518086990519993285655852781],

            [4082367875863433681332203403145435568316851327593401208105741076214120093531,
            8495653923123431417604973247489272438418190587263600148770280649306958101930]
        );
    }

}
