// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

contract HashToField {
    //The characteristic of a finite field F
    uint256 internal constant FIELD_MODULUS = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    uint256 private constant KECCAK256_BLOCKSIZE = 136;

    // The lenth that the extended hash needs to be
    // ceil((ceil(log2(p)) + k) / 8) = 48 bytes where k is the security paramter = 128
    uint256 L = 48;

    /**
     * Takes an arbitrary byte-string and a domain seperation tag (dst) and returns
     * two elements of the field used to create the secp256k1 curve.
     *
     * @dev DSTs longer than 255 bytes are considered unsound.
     *      see https://www.ietf.org/archive/id/draft-irtf-cfrg-hash-to-curve-16.html#name-domain-separation
     *
     * @param message the message to hash
     * @param dst domain separation tag, used to make protocol instantiations unique
     */
    function hash_to_field(bytes memory message, bytes memory dst) public view returns (uint256 u0, uint256 u1) {
        (bytes32 b1, bytes32 b2, bytes32 b3) = expand_message_xmd_keccak256(message, dst);

        // computes [...b1[..], ...b2[0..16]] ^ 1 mod n
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let p := mload(0x40) // next free memory slot
            mstore(p, 0x30) // Length of Base
            mstore(add(p, 0x20), 0x20) // Length of Exponent
            mstore(add(p, 0x40), 0x20) // Length of Modulus
            mstore(add(p, 0x60), b1) // Base
            mstore(add(p, 0x80), b2)
            mstore(add(p, 0x90), 1) // Exponent
            mstore(add(p, 0xb0), FIELD_MODULUS) // Modulus
            if iszero(staticcall(not(0), 0x05, p, 0xD0, p, 0x20)) { revert(0, 0) }

            u0 := mload(p)
        }

        // computes [...b2[16..32], ...b3[..]] ^ 1 mod n
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let p := mload(0x40)
            mstore(p, 0x30) // Length of Base
            mstore(add(p, 0x20), 0x20) // Length of Exponent
            mstore(add(p, 0x50), b2)
            mstore(add(p, 0x40), 0x20) // Length of Modulus
            mstore(add(p, 0x70), b3) // Base
            mstore(add(p, 0x90), 1) // Exponent
            mstore(add(p, 0xb0), FIELD_MODULUS) // Modulus
            if iszero(staticcall(not(0), 0x05, p, 0xD0, p, 0x20)) { revert(0, 0) }

            u1 := mload(p)
        }
    }

    /**
     * Expands an arbitrary byte-string to 96 bytes using the `expand_message_xmd` method described in
     * https://www.ietf.org/archive/id/draft-irtf-cfrg-hash-to-curve-16.html
     *
     * Used for hash_to_curve functionality.
     *
     * @dev This is not a general implementation as the output length fixed. It is tailor-made
     *      for secp256k1_XMD:KECCAK_256_SSWU_RO_ hash_to_curve implementation.
     *
     * @dev DSTs longer than 255 bytes are considered unsound.
     *      see https://www.ietf.org/archive/id/draft-irtf-cfrg-hash-to-curve-16.html#name-domain-separation
     *
     * @param message the message to hash
     * @param dst domain separation tag, used to make protocol instantiations unique
     */
    function expand_message_xmd_keccak256(
        bytes memory message,
        bytes memory dst
    )
        public
        pure
        returns (bytes32 b1, bytes32 b2, bytes32 b3)
    {
        // solhint-disable-next-line no-inline-assembly
        
        bytes32 b0;
        bytes memory bp = new bytes(140 + message.length + dst.length);
        assembly {
            if gt(mload(dst), 255) { revert(0, 0) }

            //let b0
            {
                // create payload for b0 hash
                let b0Payload := mload(0x40)

                // payload[0..KECCAK256_BLOCKSIZE] = 0

                let b0PayloadO := KECCAK256_BLOCKSIZE // leave first block empty
                let msg_o := 0x20 // skip length prefix

                // payload[KECCAK256_BLOCKSIZE..KECCAK256_BLOCKSIZE+message.len()] = message[0..message.len()]
                for { let i := 0 } lt(i, mload(message)) { i := add(i, 0x20) } {
                    mstore(add(b0Payload, b0PayloadO), mload(add(message, msg_o)))
                    b0PayloadO := add(b0PayloadO, 0x20)
                    msg_o := add(msg_o, 0x20)
                }

                // payload[KECCAK256_BLOCKSIZE+message.len()+1..KECCAK256_BLOCKSIZE+message.len()+2] = 96
                b0PayloadO := add(mload(message), 137)
                mstore8(add(b0Payload, b0PayloadO), 0x60) // only support for 96 bytes output length

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
                // Copy data from b0Payload to bp
                let length := add(140, add(mload(dst), mload(message)))
                mstore(bp, length)  // Store the length of the bytes
                for { let i := 0 } lt(i, length) { i := add(i, 32) } {
                    mstore(add(add(bp, 32), i), mload(add(b0Payload, i)))
                }
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
            // payload[32..33] = 2
            mstore8(add(bIPayload, 0x20), 3)

            b3 := keccak256(bIPayload, add(34, mload(dst)))
        }
    }
}
