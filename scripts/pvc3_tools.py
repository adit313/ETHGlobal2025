# pip install py-ecc==6.0.0
from py_ecc.bn128.bn128_curve import curve_order, field_modulus, add, multiply
from py_ecc.bn128.bn128_field_elements import FQ
from hashlib import sha256
from typing import Tuple, List

Fr = curve_order
Fp = field_modulus

def hash_to_int(b: bytes) -> int:
    return int.from_bytes(sha256(b).digest(), 'big') % Fp

def map_to_curve(seed: bytes) -> Tuple[int, int]:
    x = hash_to_int(seed)
    while True:
        rhs = (pow(x, 3, Fp) + 3) % Fp
        # BN254: p % 4 == 3, sqrt via exponent
        y = pow(rhs, (Fp + 1) // 4, Fp)
        if (y * y) % Fp == rhs:
            return x, y
        x = (x + 1) % Fp

def gen_params(seed: str):
    Hx, Hy = map_to_curve(b"H|" + seed.encode())
    G0x, G0y = map_to_curve(b"G|0|" + seed.encode())
    G1x, G1y = map_to_curve(b"G|1|" + seed.encode())
    G2x, G2y = map_to_curve(b"G|2|" + seed.encode())
    return (Hx, Hy), (G0x, G0y), (G1x, G1y), (G2x, G2y)

def to_fr(x: int) -> int:
    return x % Fr

def to_fr_int(x: int) -> int:
    # map signed to field
    if x >= 0: return x % Fr
    ux = (-x) % Fr
    return 0 if ux == 0 else (Fr - ux)

def point_mul(P, s: int):
    return multiply((FQ(P[0]), FQ(P[1])), to_fr(s))

def point_add(A, B):
    if A is None: return B
    if B is None: return A
    return add(A, B)

def pedersen_commit(H, Gs, w: List[int], r: int):
    acc = None
    for wi, Gi in zip(w, Gs):
        acc = point_add(acc, point_mul(Gi, to_fr_int(wi)))
    acc = point_add(acc, point_mul(H, to_fr(r)))
    return acc

def print_sol_constants(H, G0, G1, G2):
    def hx(x): return f"0x{int(x):064x}"
    print("Paste these into PVC3Params.sol:")
    print(f"H: ({hx(H[0])}, {hx(H[1])})")
    print(f"G0: ({hx(G0[0])}, {hx(G0[1])})")
    print(f"G1: ({hx(G1[0])}, {hx(G1[1])})")
    print(f"G2: ({hx(G2[0])}, {hx(G2[1])})")

def weight_numerator(error_bps: int, eps_bps: int, WEIGHT_BASE: int = 10**12) -> int:
    denom = error_bps + eps_bps
    if denom == 0: denom = 1
    return WEIGHT_BASE // denom

def aggregate_wsum_rsum(H, Gs, submissions, eps_bps: int):
    # submissions: list of dicts {w: [int,int,int], r: int, error_bps: int}
    nums = [weight_numerator(s["error_bps"], eps_bps) for s in submissions]
    Wsum = [0, 0, 0]
    Rsum = 0
    for num, s in zip(nums, submissions):
        Rsum = (Rsum + (num * (s["r"] % Fr)) % Fr) % Fr
        for j in range(3):
            Wsum[j] = (Wsum[j] + (num * (to_fr_int(s["w"][j]))) % Fr) % Fr
    # Also compute Csum = Σ num_i * C_i for local check
    Cs = [pedersen_commit(H, Gs, s["w"], s["r"]) for s in submissions]
    Csum = None
    for num, C in zip(nums, Cs):
        Csum = point_add(Csum, point_mul(C, num))
    CfromWs = pedersen_commit(H, Gs, Wsum, Rsum)
    assert Csum == CfromWs, "PVC aggregation mismatch (off-chain)"
    return Wsum, Rsum, nums, sum(nums)

if __name__ == "__main__":
    seed = "PVC-3-v1"
    H, G0, G1, G2 = gen_params(seed)
    print_sol_constants(H, G0, G1, G2)

    # Example usage
    subs = [
        {"w": [12, -7, 3], "r": 123456789, "error_bps": 1500},
        {"w": [-4, 5, 9],  "r": 222222222, "error_bps": 800},
        {"w": [1, 2, -3],  "r": 999999999, "error_bps": 5000},
    ]
    Wsum, Rsum, nums, sumNum = aggregate_wsum_rsum(H, [G0,G1,G2], subs, eps_bps=1)
    print("Wsum:", Wsum)
    print("Rsum:", Rsum)
    print("nums:", nums, "sumNum:", sumNum)
    # Call verifyAggregationAndPayout(Wsum, Rsum, aggregatedModelUri) on-chain after deploying.