// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * Convert compressed or uncompressed Bitcoin public keys to:
 *   • P2PKH  (Base58Check) addresses
 *   • P2WPKH (Bech32 SegWit v0) addresses
 *
 * Usage:
 *   bytes  memory pubkey = hex"...";      // 33 or 65 bytes
 *   string memory mainPKH  = pubKeyToP2PKH(pubkey, true);   // Mainnet Base58
 *   string memory testPKH  = pubKeyToP2PKH(pubkey, false);  // Testnet Base58
 *   string memory mainWPKH = pubKeyToP2WPKH(pubkey, true);  // Mainnet bc1...
 *   string memory testWPKH = pubKeyToP2WPKH(pubkey, false); // Testnet tb1...
 */
library BtcParser {
    // ---------- Internal Tools ----------

    /* ===== Base58 ===== */
    bytes internal constant ALPHABET =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    function _base58Encode(
        bytes memory source
    ) internal pure returns (bytes memory out) {
        if (source.length == 0) return "";

        uint256 zeros = 0;
        while (zeros < source.length && source[zeros] == 0) zeros++;

        uint256 size = ((source.length * 138) / 100) + 1;
        uint256[] memory b58 = new uint256[](size);

        for (uint256 i = zeros; i < source.length; i++) {
            uint256 carry = uint8(source[i]);
            for (uint256 k = size; k > 0; k--) {
                carry += b58[k - 1] * 256;
                b58[k - 1] = carry % 58;
                carry /= 58;
            }
            require(carry == 0, "Base58: carry overflow");
        }

        uint256 skip = 0;
        while (skip < size && b58[skip] == 0) skip++;

        out = new bytes(zeros + size - skip);
        for (uint256 i = 0; i < zeros; i++) out[i] = ALPHABET[0];

        for (uint256 i = skip; i < size; i++) {
            out[zeros + i - skip] = ALPHABET[b58[i]];
        }
    }

    /* ===== Bech32 (BIP-173) ===== */
    uint32 internal constant GEN0 = 0x3b6a57b2;
    uint32 internal constant GEN1 = 0x26508e6d;
    uint32 internal constant GEN2 = 0x1ea119fa;
    uint32 internal constant GEN3 = 0x3d4233dd;
    uint32 internal constant GEN4 = 0x2a1462b3;
    bytes internal constant CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

    function _bech32Polymod(
        uint8[] memory values
    ) internal pure returns (uint32) {
        uint32 chk = 1;
        for (uint256 p = 0; p < values.length; p++) {
            uint8 top = uint8(chk >> 25);
            chk = ((chk & 0x1ffffff) << 5) ^ values[p];
            for (uint8 i = 0; i < 5; i++) {
                if ((top >> i) & 1 == 1) {
                    if (i == 0) chk ^= GEN0;
                    else if (i == 1) chk ^= GEN1;
                    else if (i == 2) chk ^= GEN2;
                    else if (i == 3) chk ^= GEN3;
                    else if (i == 4) chk ^= GEN4;
                }
            }
        }
        return chk;
    }

    function _bech32HrpExpand(
        string memory hrp
    ) internal pure returns (uint8[] memory) {
        bytes memory b = bytes(hrp);
        uint8[] memory ret = new uint8[](b.length * 2 + 1);

        for (uint256 i = 0; i < b.length; ++i) {
            ret[i] = uint8(b[i]) >> 5;
        }

        ret[b.length] = 0;

        for (uint256 i = 0; i < b.length; ++i) {
            ret[b.length + 1 + i] = uint8(b[i]) & 31;
        }

        return ret;
    }

    function _bech32CreateChecksum(
        string memory hrp,
        uint8[] memory data
    ) internal pure returns (uint8[] memory) {
        uint8[] memory values = new uint8[](
            _bech32HrpExpand(hrp).length + data.length + 6
        );
        uint256 p;
        uint8[] memory hrpEx = _bech32HrpExpand(hrp);
        for (p = 0; p < hrpEx.length; p++) values[p] = hrpEx[p];
        for (uint256 i = 0; i < data.length; i++) values[p++] = data[i];

        uint32 polymod = _bech32Polymod(values) ^ 1;
        uint8[] memory ret = new uint8[](6);
        for (uint8 i = 0; i < 6; i++) {
            ret[i] = uint8((polymod >> (5 * (5 - i))) & 31);
        }
        return ret;
    }

    function _bech32Encode(
        string memory hrp,
        uint8[] memory data
    ) internal pure returns (bytes memory ret) {
        uint8[] memory combined = new uint8[](data.length + 6);
        for (uint256 i = 0; i < data.length; i++) combined[i] = data[i];
        uint8[] memory checksum = _bech32CreateChecksum(hrp, data);
        for (uint256 i = 0; i < 6; i++) combined[data.length + i] = checksum[i];

        bytes memory b = bytes(hrp);
        ret = new bytes(b.length + 1 + combined.length);
        for (uint256 i = 0; i < b.length; i++) ret[i] = b[i];
        ret[b.length] = bytes1(uint8(49)); // '1'
        for (uint256 i = 0; i < combined.length; i++) {
            uint8 idx = combined[i];
            require(idx < 32, "Bech32: invalid character index");
            ret[b.length + 1 + i] = CHARSET[idx];
        }
    }

    /* ===== 辅助：8-bit → 5-bit ===== */
    function _convertBits(
        bytes memory data
    ) internal pure returns (uint8[] memory) {
        uint256 outputLength = (data.length * 8 + 4) / 5;
        uint256 acc = 0;
        uint256 bits = 0;
        uint256 maxv = 31; // 5 bits max value
        uint8[] memory out = new uint8[](outputLength);
        uint256 idx = 0;

        for (uint256 p = 0; p < data.length; p++) {
            acc = (acc << 8) | uint8(data[p]);
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                out[idx++] = uint8((acc >> bits) & maxv);
            }
        }

        // Add padding bit if needed
        if (bits > 0) {
            out[idx++] = uint8((acc << (5 - bits)) & maxv);
        }

        return out;
    }

    /* ===== Hash-160 ===== */
    function _hash160(bytes memory pubkey) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(pubkey)));
    }

    /* -------------------------------------------
     *    Public API
     * -----------------------------------------*/

    /** P2WPKH from h160 (Bech32 SegWit v0) */
    function h160ToP2WPKH(
        bytes20 h160,
        bool mainnet
    ) public pure returns (bytes memory) {
        // Calculate output size based on h160 (20 bytes)
        // We need 1 byte for version + enough space for converted bits + padding
        uint8[] memory prog = _convertBits(abi.encodePacked(h160));

        // Create data with correct size: 1 byte version + converted bits
        uint8[] memory data = new uint8[](1 + prog.length);
        data[0] = 0; // v0 segwit

        // Copy all bits
        for (uint256 i = 0; i < prog.length; i++) {
            data[i + 1] = prog[i];
        }

        return _bech32Encode(mainnet ? "bc" : "tb", data);
    }

    /** P2PKH Base58Check */
    function pubKeyToP2PKH(
        bytes memory pubkey,
        bool mainnet
    ) public pure returns (bytes memory) {
        require(
            pubkey.length == 33 || pubkey.length == 65,
            "Invalid pubkey length"
        );
        bytes20 h160 = _hash160(pubkey);

        bytes memory middle = abi.encodePacked(
            mainnet ? bytes1(0x00) : bytes1(0x6f),
            h160
        );

        bytes32 c1 = sha256(middle);
        bytes4 checksum = bytes4(sha256(abi.encodePacked(c1)));

        return _base58Encode(abi.encodePacked(middle, checksum));
    }

    /** P2WPKH from pubkey (Bech32 SegWit v0) */
    function pubKeyToP2WPKH(
        bytes memory pubkey,
        bool mainnet
    ) public pure returns (bytes memory) {
        require(
            pubkey.length == 33 || pubkey.length == 65,
            "Invalid pubkey length"
        );
        bytes20 h160 = _hash160(pubkey);

        return h160ToP2WPKH(h160, mainnet);
    }

    function bytesToBytes2(
        bytes memory input
    ) public pure returns (bytes32[2] memory compact) {
        require(input.length <= 64, "Too long");

        assembly {
            mstore(add(compact, 0), mload(add(input, 32))) // first 32 bytes
            mstore(add(compact, 32), mload(add(input, 64))) // next 32 bytes
        }
    }
}
