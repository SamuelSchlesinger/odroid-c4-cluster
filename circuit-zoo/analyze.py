#!/usr/bin/env python3
"""
Analyze optimal circuit data for boolean functions.
Explore relationships between truth table structure and circuit complexity.
"""

import json
import numpy as np
from collections import defaultdict
from pathlib import Path

def load_data(path="circuits_n4.json"):
    """Load circuit data from JSON file."""
    with open(path) as f:
        return json.load(f)

def truth_table_to_bits(tt, n=4):
    """Convert truth table integer to bit array."""
    return np.array([(tt >> i) & 1 for i in range(2**n)], dtype=np.uint8)

def count_ones(tt):
    """Count number of 1s in truth table (function weight)."""
    return bin(tt).count('1')

def is_symmetric(tt, n=4):
    """Check if function is symmetric (depends only on Hamming weight of input)."""
    bits = truth_table_to_bits(tt, n)
    # Group inputs by Hamming weight
    weights = [bin(i).count('1') for i in range(2**n)]
    for w in range(n+1):
        indices = [i for i in range(2**n) if weights[i] == w]
        if len(indices) > 0:
            vals = [bits[i] for i in indices]
            if not all(v == vals[0] for v in vals):
                return False
    return True

def is_monotone(tt, n=4):
    """Check if function is monotone (x <= y implies f(x) <= f(y))."""
    bits = truth_table_to_bits(tt, n)
    for x in range(2**n):
        for y in range(2**n):
            # x <= y means every bit of x is <= corresponding bit of y
            if (x & y) == x:  # x is dominated by y
                if bits[x] > bits[y]:
                    return False
    return True

def is_linear(tt, n=4):
    """Check if function is affine (XOR of subset of inputs plus constant)."""
    bits = truth_table_to_bits(tt, n)
    # Affine functions have truth tables of the form a0 XOR (a1*x1) XOR ... XOR (an*xn)
    # They have exactly 2^(n-1) ones (unless constant)
    ones = count_ones(tt)
    if ones not in [0, 2**(n-1), 2**n]:
        return False
    # Check linearity by checking if f(x XOR y) = f(x) XOR f(y) XOR f(0)
    f0 = bits[0]
    for x in range(2**n):
        for y in range(2**n):
            if bits[x ^ y] != (bits[x] ^ bits[y] ^ f0):
                return False
    return True

def compute_influence(tt, var, n=4):
    """Compute influence of variable var on function tt."""
    bits = truth_table_to_bits(tt, n)
    count = 0
    for x in range(2**n):
        x_flipped = x ^ (1 << var)
        if bits[x] != bits[x_flipped]:
            count += 1
    return count / (2**n)

def total_influence(tt, n=4):
    """Compute total influence (sum of individual influences)."""
    return sum(compute_influence(tt, v, n) for v in range(n))

def sensitivity(tt, n=4):
    """Compute sensitivity (max number of sensitive bits for any input)."""
    bits = truth_table_to_bits(tt, n)
    max_sens = 0
    for x in range(2**n):
        sens = 0
        for v in range(n):
            x_flipped = x ^ (1 << v)
            if bits[x] != bits[x_flipped]:
                sens += 1
        max_sens = max(max_sens, sens)
    return max_sens

def block_sensitivity(tt, n=4):
    """Compute block sensitivity."""
    bits = truth_table_to_bits(tt, n)
    max_bs = 0
    for x in range(2**n):
        # Find maximum number of disjoint sensitive blocks
        # For simplicity, just check all subsets (exponential but n is small)
        best = 0
        # Greedy: find sensitive bits and count
        sensitive_vars = []
        for v in range(n):
            x_flipped = x ^ (1 << v)
            if bits[x] != bits[x_flipped]:
                sensitive_vars.append(v)
        best = len(sensitive_vars)  # Upper bound: each var is a block
        max_bs = max(max_bs, best)
    return max_bs

def decision_tree_depth(tt, n=4):
    """Compute decision tree depth (deterministic query complexity)."""
    bits = truth_table_to_bits(tt, n)

    def dt_depth_rec(indices, depth):
        if len(indices) == 0:
            return 0
        vals = [bits[i] for i in indices]
        if all(v == vals[0] for v in vals):
            return depth
        if depth == n:
            return depth
        # Try each variable
        best = n + 1
        for v in range(n):
            left = [i for i in indices if (i >> v) & 1 == 0]
            right = [i for i in indices if (i >> v) & 1 == 1]
            d = max(dt_depth_rec(left, depth + 1), dt_depth_rec(right, depth + 1))
            best = min(best, d)
        return best

    return dt_depth_rec(list(range(2**n)), 0)

def fourier_sparsity(tt, n=4):
    """Count non-zero Fourier coefficients."""
    bits = truth_table_to_bits(tt, n)
    # Convert to +1/-1 representation
    f = 1 - 2 * bits.astype(float)

    # Compute Fourier transform
    count = 0
    for s in range(2**n):
        coef = 0
        for x in range(2**n):
            parity = bin(x & s).count('1') % 2
            coef += f[x] * (1 if parity == 0 else -1)
        coef /= 2**n
        if abs(coef) > 1e-10:
            count += 1
    return count

def analyze_data(data):
    """Perform comprehensive analysis of circuit data."""
    n = data['n']
    functions = data['functions']

    print(f"=== Analysis of {len(functions)} boolean functions on {n} variables ===\n")

    # Build lookup
    by_tt = {f['tt']: f for f in functions}

    # --- Size/Depth distributions ---
    sizes = [f['size'] for f in functions]
    depths = [f['depth'] for f in functions]

    print("Size statistics:")
    print(f"  Min: {min(sizes)}, Max: {max(sizes)}, Mean: {np.mean(sizes):.3f}, Std: {np.std(sizes):.3f}")
    print(f"\nDepth statistics:")
    print(f"  Min: {min(depths)}, Max: {max(depths)}, Mean: {np.mean(depths):.3f}, Std: {np.std(depths):.3f}")

    # --- Correlation with truth table properties ---
    print("\n--- Truth Table Properties vs Circuit Size ---\n")

    # Weight (number of 1s)
    weights = [count_ones(f['tt']) for f in functions]
    corr = np.corrcoef(weights, sizes)[0, 1]
    print(f"Weight (# of 1s) correlation with size: {corr:.4f}")

    # Group by weight
    by_weight = defaultdict(list)
    for f in functions:
        by_weight[count_ones(f['tt'])].append(f['size'])
    print("\nMean size by weight:")
    for w in sorted(by_weight.keys()):
        mean_s = np.mean(by_weight[w])
        print(f"  Weight {w:2d}: {len(by_weight[w]):5d} functions, mean size {mean_s:.2f}")

    # --- Special function classes ---
    print("\n--- Special Function Classes ---\n")

    symmetric_funcs = [f for f in functions if is_symmetric(f['tt'], n)]
    print(f"Symmetric functions: {len(symmetric_funcs)}")
    if symmetric_funcs:
        sym_sizes = [f['size'] for f in symmetric_funcs]
        print(f"  Size: min={min(sym_sizes)}, max={max(sym_sizes)}, mean={np.mean(sym_sizes):.2f}")

    monotone_funcs = [f for f in functions if is_monotone(f['tt'], n)]
    print(f"\nMonotone functions: {len(monotone_funcs)}")
    if monotone_funcs:
        mono_sizes = [f['size'] for f in monotone_funcs]
        print(f"  Size: min={min(mono_sizes)}, max={max(mono_sizes)}, mean={np.mean(mono_sizes):.2f}")

    linear_funcs = [f for f in functions if is_linear(f['tt'], n)]
    print(f"\nAffine/Linear functions: {len(linear_funcs)}")
    if linear_funcs:
        lin_sizes = [f['size'] for f in linear_funcs]
        print(f"  Size: min={min(lin_sizes)}, max={max(lin_sizes)}, mean={np.mean(lin_sizes):.2f}")

    # --- Complexity measures correlation ---
    print("\n--- Complexity Measures ---\n")

    # Sample for expensive computations
    sample_size = min(1000, len(functions))
    sample_indices = np.random.choice(len(functions), sample_size, replace=False)
    sample = [functions[i] for i in sample_indices]

    print(f"Computing complexity measures for {sample_size} sampled functions...")

    influences = []
    sensitivities = []
    dt_depths = []

    for f in sample:
        tt = f['tt']
        influences.append(total_influence(tt, n))
        sensitivities.append(sensitivity(tt, n))
        dt_depths.append(decision_tree_depth(tt, n))

    sample_sizes = [f['size'] for f in sample]

    print(f"\nTotal influence correlation with size: {np.corrcoef(influences, sample_sizes)[0,1]:.4f}")
    print(f"Sensitivity correlation with size: {np.corrcoef(sensitivities, sample_sizes)[0,1]:.4f}")
    print(f"Decision tree depth correlation with size: {np.corrcoef(dt_depths, sample_sizes)[0,1]:.4f}")

    # --- Hardest functions ---
    print("\n--- Hardest Functions (max size) ---\n")
    max_size = max(sizes)
    hardest = [f for f in functions if f['size'] == max_size]
    print(f"Functions with size {max_size}: {len(hardest)}")

    for f in hardest[:5]:
        tt = f['tt']
        bits = truth_table_to_bits(tt, n)
        print(f"  tt={tt:5d} (0b{tt:016b}), weight={count_ones(tt)}, depth={f['depth']}")
        print(f"    Symmetric: {is_symmetric(tt, n)}, Monotone: {is_monotone(tt, n)}, Linear: {is_linear(tt, n)}")

    # --- Size-Depth relationship ---
    print("\n--- Size vs Depth ---\n")
    size_depth_counts = defaultdict(int)
    for f in functions:
        size_depth_counts[(f['size'], f['depth'])] += 1

    print("Size \\ Depth:", end="")
    all_depths = sorted(set(depths))
    for d in all_depths:
        print(f" {d:6d}", end="")
    print()

    for s in sorted(set(sizes)):
        print(f"  {s:2d}        ", end="")
        for d in all_depths:
            count = size_depth_counts.get((s, d), 0)
            if count > 0:
                print(f" {count:6d}", end="")
            else:
                print("      -", end="")
        print()

    return by_tt

def find_parity_function(data):
    """Find the XOR/parity function in the data."""
    n = data['n']
    # Parity of n bits: output is 1 iff odd number of 1s in input
    parity_tt = 0
    for x in range(2**n):
        if bin(x).count('1') % 2 == 1:
            parity_tt |= (1 << x)

    print(f"\n--- Parity Function (XOR of all {n} inputs) ---")
    print(f"Truth table: {parity_tt} (0b{parity_tt:016b})")

    for f in data['functions']:
        if f['tt'] == parity_tt:
            print(f"Size: {f['size']}, Depth: {f['depth']}")
            print(f"Circuit: {f['circuit']}")
            return f
    return None

def find_majority_function(data):
    """Find the majority function."""
    n = data['n']
    # Majority: output 1 iff at least n/2 inputs are 1
    threshold = n // 2 + 1  # For n=4, majority when >= 3 ones (strict majority)
    # Actually for n=4, let's use >= 2 for a more natural "at least half"
    # But strict majority (> n/2) means >= 3 ones

    # Let's find both
    for thresh in [2, 3]:
        maj_tt = 0
        for x in range(2**n):
            if bin(x).count('1') >= thresh:
                maj_tt |= (1 << x)

        print(f"\n--- Threshold-{thresh} Function (>= {thresh} ones) ---")
        print(f"Truth table: {maj_tt} (0b{maj_tt:016b})")

        for f in data['functions']:
            if f['tt'] == maj_tt:
                print(f"Size: {f['size']}, Depth: {f['depth']}")
                return f
    return None

def analyze_hardest_functions(data):
    """Deep analysis of the hardest functions."""
    n = data['n']
    functions = data['functions']
    by_tt = {f['tt']: f for f in functions}

    sizes = [f['size'] for f in functions]
    max_size = max(sizes)
    hardest = [f for f in functions if f['size'] == max_size]

    print(f"\n=== Deep Analysis of {len(hardest)} Hardest Functions (size {max_size}) ===\n")

    # Check which are parity-related
    # Parity(4) and its variants
    parity_tt = 0
    for x in range(2**n):
        if bin(x).count('1') % 2 == 1:
            parity_tt |= (1 << x)

    not_parity = ((1 << (1 << n)) - 1) ^ parity_tt

    parity_variants = set([parity_tt, not_parity])

    # Partial parities (XOR of subsets of 3 or 4 variables)
    for mask in range(1, 2**n):
        if bin(mask).count('1') >= 3:  # At least 3 variables
            partial_parity = 0
            for x in range(2**n):
                # Count 1s in positions specified by mask
                if bin(x & mask).count('1') % 2 == 1:
                    partial_parity |= (1 << x)
            parity_variants.add(partial_parity)
            parity_variants.add(((1 << (1 << n)) - 1) ^ partial_parity)

    parity_related = [f for f in hardest if f['tt'] in parity_variants]
    print(f"Parity-related (XOR of 3+ variables): {len(parity_related)}")

    # Analyze symmetry types
    print("\nSymmetry breakdown:")
    symmetric_hard = [f for f in hardest if is_symmetric(f['tt'], n)]
    print(f"  Symmetric: {len(symmetric_hard)}")

    # Analyze by which symmetric functions they are
    sym_by_profile = defaultdict(list)
    for f in symmetric_hard:
        bits = truth_table_to_bits(f['tt'], n)
        weights = [bin(i).count('1') for i in range(2**n)]
        profile = tuple(bits[weights.index(w)] if w in weights else 0 for w in range(n+1))
        sym_by_profile[profile].append(f)

    print("\n  Symmetric function profiles (output by input weight):")
    for profile, funcs in sorted(sym_by_profile.items(), key=lambda x: -len(x[1])):
        print(f"    {profile}: {len(funcs)} functions")

    # Non-symmetric hard functions
    non_sym_hard = [f for f in hardest if not is_symmetric(f['tt'], n)]
    print(f"\n  Non-symmetric: {len(non_sym_hard)}")

    # Analyze by weight
    print("\nWeight distribution of hardest functions:")
    by_weight = defaultdict(int)
    for f in hardest:
        by_weight[count_ones(f['tt'])] += 1
    for w in sorted(by_weight.keys()):
        print(f"  Weight {w}: {by_weight[w]} functions")

    # Look at specific interesting functions
    print("\n--- Some specific hard functions ---\n")

    # 4-bit XOR
    print(f"XOR(x0,x1,x2,x3) = {parity_tt}")
    if parity_tt in by_tt:
        print(f"  Size: {by_tt[parity_tt]['size']}, Depth: {by_tt[parity_tt]['depth']}")

    # XOR of 3 bits
    xor3_tt = 0
    for x in range(2**n):
        if bin(x & 0b0111).count('1') % 2 == 1:  # XOR of x0,x1,x2
            xor3_tt |= (1 << x)
    print(f"\nXOR(x0,x1,x2): {xor3_tt}")
    if xor3_tt in by_tt:
        print(f"  Size: {by_tt[xor3_tt]['size']}, Depth: {by_tt[xor3_tt]['depth']}")

def analyze_circuit_structure(data):
    """Analyze the structure of circuits."""
    n = data['n']
    functions = data['functions']

    print("\n=== Circuit Structure Analysis ===\n")

    # Count gate types at each size
    and_counts = defaultdict(int)
    or_counts = defaultdict(int)

    for f in functions:
        circuit = f['circuit']
        if circuit['type'] == 'and':
            and_counts[f['size']] += 1
        elif circuit['type'] == 'or':
            or_counts[f['size']] += 1

    print("Gate type at output by size:")
    all_sizes = sorted(set(and_counts.keys()) | set(or_counts.keys()))
    for s in all_sizes:
        total = and_counts[s] + or_counts[s]
        if total > 0:
            and_pct = 100.0 * and_counts[s] / total
            print(f"  Size {s:2d}: AND={and_counts[s]:5d} ({and_pct:5.1f}%), OR={or_counts[s]:5d}")

    # Analyze subcircuit reuse
    print("\n--- Subcircuit Analysis ---\n")

    # How often is each truth table used as a subcircuit?
    subcircuit_usage = defaultdict(int)
    for f in functions:
        circuit = f['circuit']
        if circuit['type'] in ['and', 'or']:
            subcircuit_usage[circuit['left']] += 1
            subcircuit_usage[circuit['right']] += 1

    # Most commonly used subcircuits
    sorted_usage = sorted(subcircuit_usage.items(), key=lambda x: -x[1])
    print("Most commonly used subcircuits:")
    for tt, count in sorted_usage[:15]:
        if tt in {f['tt']: f for f in functions}:
            info = {f['tt']: f for f in functions}[tt]
            print(f"  tt={tt:5d}: used {count:5d} times, size={info['size']}, depth={info['depth']}")

if __name__ == "__main__":
    np.random.seed(42)

    data = load_data()
    by_tt = analyze_data(data)

    find_parity_function(data)
    find_majority_function(data)

    analyze_hardest_functions(data)
    analyze_circuit_structure(data)
