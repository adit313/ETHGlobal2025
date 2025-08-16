// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library BN254 {
    uint256 internal constant FIELD_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct G1Point {
        uint256 x;
        uint256 y;
    }

    function P0() internal pure returns (G1Point memory) {
        return G1Point(0, 0);
    }

    function isInfinity(G1Point memory p) internal pure returns (bool) {
        return p.x == 0 && p.y == 0;
    }

    function eq(G1Point memory a, G1Point memory b) internal pure returns (bool) {
        return a.x == b.x && a.y == b.y;
    }

    function add(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint256[4] memory input = [p1.x, p1.y, p2.x, p2.y];
        uint256[2] memory output;
        assembly {
            if iszero(staticcall(gas(), 0x06, input, 0x80, output, 0x40)) {
                revert(0, 0)
            }
        }
        r.x = output[0];
        r.y = output[1];
    }

    function mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input = [p.x, p.y, s];
        uint256[2] memory output;
        assembly {
            if iszero(staticcall(gas(), 0x07, input, 0x60, output, 0x40)) {
                revert(0, 0)
            }
        }
        r.x = output[0];
        r.y = output[1];
    }

    function addAccum(G1Point memory acc, G1Point memory p) internal view returns (G1Point memory) {
        if (isInfinity(acc)) return p;
        if (isInfinity(p)) return acc;
        return add(acc, p);
    }

    // Map int -> Fr element as uint256
    function toField(int256 x) internal pure returns (uint256) {
        if (x >= 0) return uint256(x) % FIELD_MODULUS;
        uint256 ux = uint256(-x) % FIELD_MODULUS;
        if (ux == 0) return 0;
        return FIELD_MODULUS - ux;
    }
}