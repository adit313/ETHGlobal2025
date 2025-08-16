// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BN254.sol";
import "./PVC3Params.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract PVCContest3 {
    using BN254 for *;

    // Immutable contest configuration
    IERC20 public immutable token;
    address public immutable organizer;
    uint256 public immutable poolAmount;
    uint32  public immutable epsBps;      // epsilon to avoid division by zero (in basis points)
    uint256 public constant WEIGHT_BASE = 1e12; // scale for integer weight numerators

    // Submission data
    struct Submission {
        address submitter;
        int256[3] w;         // vector
        uint256 r;           // randomness
        uint32  errorBps;    // error in basis points
        BN254.G1Point C;     // commitment
        string  uri;         // optional metadata
        bool    exists;
    }

    uint256 public submissionCount;
    mapping(uint256 => Submission) public submissions;

    bool public finalized;

    event Submitted(uint256 indexed id, address indexed user, uint32 errorBps, uint256 Cx, uint256 Cy);
    event Aggregated(bytes32 proofHash, uint256 sumWeights);
    event Paid(address indexed user, uint256 amount);

    constructor(
        address _token,
        uint256 _fundAmount,
        uint32 _epsBps
    ) {
        require(_token != address(0), "bad token");
        token = IERC20(_token);
        organizer = msg.sender;
        epsBps = _epsBps;

        // Pull stablecoins into the pool
        require(token.allowance(organizer, address(this)) >= _fundAmount, "approve first");
        bool ok = token.transferFrom(organizer, address(this), _fundAmount);
        require(ok, "transferFrom failed");
        poolAmount = _fundAmount;
    }

    // Commitment for a 3-vector
    function commit3(int256[3] memory w, uint256 r) internal view returns (BN254.G1Point memory acc) {
        acc = BN254.P0();
        BN254.G1Point memory term;

        uint256 w0 = BN254.toField(w[0]);
        term = BN254.mul(PVC3Params.Gi(0), w0);
        acc = BN254.addAccum(acc, term);

        uint256 w1 = BN254.toField(w[1]);
        term = BN254.mul(PVC3Params.Gi(1), w1);
        acc = BN254.addAccum(acc, term);

        uint256 w2 = BN254.toField(w[2]);
        term = BN254.mul(PVC3Params.Gi(2), w2);
        acc = BN254.addAccum(acc, term);

        BN254.G1Point memory rH = BN254.mul(PVC3Params.H(), r);
        acc = BN254.addAccum(acc, rH);
    }

    // Deterministic integer weight numerator from error
    function weightNumerator(uint32 errorBps) public pure returns (uint256) {
        // denominator = errorBps + epsBps (eps handled by caller with contest epsBps)
        // To keep function pure we let caller pass epsBps; but here epsBps is immutable, so:
        // Note: implement as a view wrapper below to use epsBps.
        return 0;
    }

    function weightNumeratorFor(uint32 errorBps_) public view returns (uint256) {
        uint256 denom = uint256(errorBps_) + uint256(epsBps);
        // avoid division by zero (epsBps >= 1 recommended)
        if (denom == 0) denom = 1;
        return WEIGHT_BASE / denom; // integer division
    }

    function submit(int256[3] calldata w, uint256 r, uint32 errorBps, string calldata uri) external returns (uint256 id) {
        // For hackathon simplicity: immediate reveal with PVC check
        BN254.G1Point memory C = commit3(w, r);

        id = ++submissionCount;
        submissions[id] = Submission({
            submitter: msg.sender,
            w: w,
            r: r,
            errorBps: errorBps,
            C: C,
            uri: uri,
            exists: true
        });
        emit Submitted(id, msg.sender, errorBps, C.x, C.y);
    }

    // View: top K by lowest error (naive O(n^2))
    function getTop(uint256 k) external view returns (uint256[] memory ids) {
        if (k > submissionCount) k = submissionCount;
        ids = new uint256[](k);

        // Simple selection
        bool[] memory picked = new bool[](submissionCount + 1);
        for (uint256 t = 0; t < k; t++) {
            uint32 bestErr = type(uint32).max;
            uint256 bestId = 0;
            for (uint256 i = 1; i <= submissionCount; i++) {
                if (picked[i]) continue;
                Submission storage S = submissions[i];
                if (!S.exists) continue;
                if (S.errorBps < bestErr) {
                    bestErr = S.errorBps;
                    bestId = i;
                }
            }
            picked[bestId] = true;
            ids[t] = bestId;
        }
    }

    // Off-chain aggregator computes Wsum,Rsum using the same integer weight numerators num_i.
    // This function verifies: Commit(Wsum,Rsum) == sum_i num_i * C_i
    // If valid, pays each submitter poolAmount * num_i / sum(num_i)
    function verifyAggregationAndPayout(int256[3] calldata Wsum, uint256 Rsum, string calldata aggregatedModelUri) external {
        require(!finalized, "already finalized");
        require(submissionCount > 0, "no submissions");

        // Recompute right-hand side: Σ num_i * C_i
        BN254.G1Point memory rhs = BN254.P0();
        uint256 sumNum = 0;

        for (uint256 i = 1; i <= submissionCount; i++) {
            Submission storage S = submissions[i];
            if (!S.exists) continue;
            uint256 num_i = weightNumeratorFor(S.errorBps);
            sumNum += num_i;
            BN254.G1Point memory term = BN254.mul(S.C, num_i);
            rhs = BN254.addAccum(rhs, term);
        }
        require(sumNum > 0, "sumNum=0");

        // Compute left-hand side: Commit(Wsum, Rsum)
        BN254.G1Point memory lhs = commit3(Wsum, Rsum);

        // Check equality
        require(BN254.eq(lhs, rhs), "aggregation PVC mismatch");

        // Payout proportionally
        uint256 remaining = poolAmount;
        for (uint256 i = 1; i <= submissionCount; i++) {
            Submission storage S = submissions[i];
            if (!S.exists) continue;
            uint256 num_i = weightNumeratorFor(S.errorBps);
            if (num_i == 0) continue;

            // amount = poolAmount * num_i / sumNum
            uint256 amt = (poolAmount * num_i) / sumNum;
            if (amt > 0) {
                remaining -= amt;
                require(token.transfer(S.submitter, amt), "transfer failed");
                emit Paid(S.submitter, amt);
            }
        }

        // Any dust stays in contract (or could be sent back to organizer)
        finalized = true;

        // Log a hash pointer to your off-chain artifact (include aggregatedModelUri for convenience)
        bytes32 proofHash = keccak256(abi.encodePacked(aggregatedModelUri, Wsum, Rsum, sumNum));
        emit Aggregated(proofHash, sumNum);
    }

    // Helper to expose all submissions for off-chain aggregator
    function getSubmission(uint256 id) external view returns (
        address submitter,
        int256[3] memory w,
        uint256 r,
        uint32 errorBps,
        uint256 Cx,
        uint256 Cy,
        string memory uri
    ) {
        Submission storage S = submissions[id];
        require(S.exists, "bad id");
        submitter = S.submitter;
        w = S.w;
        r = S.r;
        errorBps = S.errorBps;
        Cx = S.C.x;
        Cy = S.C.y;
        uri = S.uri;
    }

    function totalSubmissions() external view returns (uint256) {
        return submissionCount;
    }
}