// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BN254.sol";

library PVC3Params {
    using BN254 for *;

    // Replace these with the generated constants from the Python script.
    function H() internal pure returns (BN254.G1Point memory) {
        return BN254.G1Point(
            0x097ef6106c3c7b76ad182bdfa1398ac1b9e28e9f40928c01ada8a6cdc7cefdb3, // Hx
            0x1764bc1473279839ef4efbd63119dcdd7504227831fe45c097b106f31b1f03b7  // Hy
        );
    }

    function G0() internal pure returns (BN254.G1Point memory) {
        return BN254.G1Point(
            0x0327d017385db5b75f97616738ce8f3051719fedfc8d9d842236ffcf4078c2dc, // G0x
            0x0048deb6515532b1c585513df26aa937902383c4c10237de839530a871f6311f  // G0y
        );
    }

    function G1p() internal pure returns (BN254.G1Point memory) {
        return BN254.G1Point(
            0x22f9718115f8f822336c0d4af1890aa4deeb45b1fe0483f2f507aa79acd8f9f6, // G1x
            0x1cb49dceb15a19576c870b8b33287805e99a9d126dc27bdf4f6834d0da57fdad  // G1y
        );
    }

    function G2() internal pure returns (BN254.G1Point memory) {
        return BN254.G1Point(
            0x0c9fb58d522788cae68a3ef87e4b93338bab8027a91f85403ad85e6305b3cd5b, // G2x
            0x2dbd6c52cd768af225f42607ff8cb246fd551ec5b2e3bfac12046d9897ab7bc1  // G2y
        );
    }

    function Gi(uint256 i) internal pure returns (BN254.G1Point memory) {
        if (i == 0) return G0();
        if (i == 1) return G1p();
        if (i == 2) return G2();
        revert("out of range");
    }

    function N() internal pure returns (uint256) {
        return 3;
    }
}