// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title BTCStyleMerkle
 * @dev show how to compute Merkle Root in Solidity
 *      Details: EVM native is keccak256, here we use sha256(...) to call precompile(0x02) to implement it.
 */
library BTCStyleMerkle {
    /**
     * @dev compute double-sha256(txA || txB)
     *      (where txA, txB are 32 bytes; after concatenation, it becomes 64 bytes; first sha256, then sha256)
     */
    function doubleSha256Pair(bytes32 txA, bytes32 txB) public pure returns (bytes32) {
        // concatenate and do sha256 once
        bytes memory first = abi.encodePacked(txA, txB);
        bytes32 hash1 = sha256(first);

        // do sha256 once again
        bytes memory second = abi.encodePacked(hash1);
        bytes32 hash2 = sha256(second);

        return hash2;
    }

    /**
     * @dev do double-sha256 for arbitrary bytes
     *      (in some scenarios, you need to concatenate arbitrary data before doing double SHA256, not just pair)
     */
    function doubleSha256Bytes(bytes memory data) public pure returns (bytes32) {
        bytes32 first = sha256(data);
        return sha256(abi.encodePacked(first));
    }

    /**
     * @dev compute Merkle Root for a set of "leaf hashes" (already in 32 bytes internal order)
     *      - when the number of hashes is odd, the last one will be hashed again (the "padding" method used in Bitcoin/Dogecoin)
     *      - note, here we assume each leaf is already in the 32 bytes internal order used in Bitcoin/Dogecoin,
     *        if you get txid from block explorer, you need to reverse it in advance.
     */
    function computeMerkleRoot(bytes32[] memory leaves) public pure returns (bytes32) {
        if (leaves.length == 0) {
            return bytes32(0);
        }
        if (leaves.length == 1) {
            return leaves[0];
        }

        // merge each level up until only 1 hash left
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            uint256 newLength = (currentLevel.length + 1) / 2; // calculate the size of the new array after merging (add 1 if odd)

            bytes32[] memory nextLevel = new bytes32[](newLength);

            uint256 j = 0;
            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 == currentLevel.length) {
                    // when odd number, duplicate the last one
                    nextLevel[j] = doubleSha256Pair(currentLevel[i], currentLevel[i]);
                } else {
                    nextLevel[j] = doubleSha256Pair(currentLevel[i], currentLevel[i + 1]);
                }
                j++;
            }
            currentLevel = nextLevel;
        }

        // only 1 hash left, which is the root
        return currentLevel[0];
    }

    /**
     * @dev reverse bytes32 (big endian <-> little endian)
     *      in Bitcoin/Dogecoin, if you want to convert "internal order 32 bytes hash" to "string displayed in block explorer",
     *      you need to do reverse; vice versa.
     */
    function reverseBytes32(bytes32 input) public pure returns (bytes32) {
        // convert to temporary bytes, reverse, then convert back to bytes32
        bytes memory buf = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            buf[i] = input[31 - i];
        }
        return bytes32(buf);
    }

    /**
     * @dev reverse bytes4 (big endian <-> little endian)
     * @param input uint32
     * @return bytes4
     */
    function reverseBytes4(uint32 input) public pure returns (bytes4) {
        return bytes4(
            ((input & 0xff000000) >> 24) | ((input & 0x00ff0000) >> 8) | ((input & 0x0000ff00) << 8)
                | ((input & 0x000000ff) << 24)
        );
    }

    /**
     * @dev Calculates the ceiling of log2 for a given number.
     * @param x The input number.
     * @return The ceiling of log2(x).
     */
    function log2Ceil(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        uint256 value = 1;

        while (value < x) {
            value *= 2;
            result++;
        }

        return result;
    }

    /**
     * @dev generate Merkle proof for a given index
     * @param leaves array of tx hashes (already in 32 bytes internal order)
     * @param index the index of the tx hash in the leaves array
     * @return proof the Merkle proof for the given index
     * @return root the Merkle root of the leaves array
     */
    function generateMerkleProof(bytes32[] memory leaves, uint256 index)
        public
        pure
        returns (bytes32[] memory proof, bytes32 root)
    {
        require(leaves.length > 0, "No tx hashes");
        require(index < leaves.length, "Invalid index");

        // calculate the maximum possible depth (log2Ceil)
        uint256 maxDepth = log2Ceil(leaves.length);
        proof = new bytes32[](maxDepth);
        uint256 proofPos = 0;

        bytes32[] memory currentLevel = leaves;
        // merge up until only 1 hash left
        while (currentLevel.length > 1) {
            uint256 levelLen = currentLevel.length;
            uint256 nextLen = (levelLen + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLen);

            for (uint256 i = 0; i < levelLen; i += 2) {
                // when right node is missing, duplicate left node
                bytes32 left = currentLevel[i];
                bytes32 right = (i + 1 < levelLen) ? currentLevel[i + 1] : currentLevel[i];

                uint256 parentIndex = i / 2;
                nextLevel[parentIndex] = doubleSha256Pair(left, right);

                // if index is in the (i, i+1) pair
                if (i == index) {
                    // sibling is on the right
                    proof[proofPos++] = right;
                    index = parentIndex; // parent index
                } else if (i + 1 == index) {
                    // sibling is on the left
                    proof[proofPos++] = left;
                    index = parentIndex;
                }
            }
            currentLevel = nextLevel;
        }

        // currentLevel[0] is the root
        root = currentLevel[0];

        // proof array may be shorter than maxDepth, no need to trim (or use dynamic array)
    }

    function verifyMerkleProof(bytes32 root, bytes32[] memory proof, bytes32 leaf, uint256 index)
        public
        pure
        returns (bool)
    {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                computedHash = doubleSha256Pair(computedHash, proof[i]);
            } else {
                computedHash = doubleSha256Pair(proof[i], computedHash);
            }
            index /= 2;
        }

        return computedHash == root;
    }
}
