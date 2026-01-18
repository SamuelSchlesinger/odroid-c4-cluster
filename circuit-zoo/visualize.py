#!/usr/bin/env python3
"""
Visualize circuit complexity data.
Creates ASCII histograms and charts for terminal viewing.
"""

import json
from collections import defaultdict

def load_data(path="circuits_n4.json"):
    with open(path) as f:
        return json.load(f)

def ascii_histogram(values, title, bins=None, width=60):
    """Create an ASCII histogram."""
    if bins is None:
        bins = sorted(set(values))

    counts = defaultdict(int)
    for v in values:
        counts[v] += 1

    max_count = max(counts.values()) if counts else 0
    total = len(values)

    print(f"\n{title}")
    print("=" * (width + 20))

    for b in bins:
        count = counts.get(b, 0)
        bar_len = int(width * count / max_count) if max_count > 0 else 0
        pct = 100.0 * count / total if total > 0 else 0
        bar = "█" * bar_len
        print(f"{b:3d} │ {bar:<{width}} │ {count:6d} ({pct:5.1f}%)")

    print("=" * (width + 20))

def ascii_scatter(x_values, y_values, title, x_label, y_label, width=60, height=20):
    """Create an ASCII scatter plot (density-based)."""
    if not x_values or not y_values:
        return

    x_min, x_max = min(x_values), max(x_values)
    y_min, y_max = min(y_values), max(y_values)

    # Create density grid
    grid = [[0] * width for _ in range(height)]

    for x, y in zip(x_values, y_values):
        xi = int((width - 1) * (x - x_min) / (x_max - x_min)) if x_max > x_min else 0
        yi = int((height - 1) * (y - y_min) / (y_max - y_min)) if y_max > y_min else 0
        yi = height - 1 - yi  # Flip y axis
        grid[yi][xi] += 1

    max_density = max(max(row) for row in grid) if grid else 1

    # Density characters
    chars = " ·:+*#@"

    print(f"\n{title}")
    print(f"Y: {y_label}")
    print("┌" + "─" * width + "┐")

    for row in grid:
        line = "│"
        for cell in row:
            idx = int(len(chars) - 1) * cell / max_density if max_density > 0 else 0
            line += chars[int(idx)]
        line += "│"
        print(line)

    print("└" + "─" * width + "┘")
    print(f"  {x_label}: {x_min} to {x_max}")

def size_depth_heatmap(data):
    """Create a heatmap of size vs depth."""
    functions = data['functions']

    size_depth = defaultdict(int)
    for f in functions:
        size_depth[(f['size'], f['depth'])] += 1

    sizes = sorted(set(f['size'] for f in functions))
    depths = sorted(set(f['depth'] for f in functions))

    max_count = max(size_depth.values()) if size_depth else 1

    # Intensity characters
    chars = " ░▒▓█"

    print("\n=== Size vs Depth Heatmap ===")
    print()

    # Header
    print("     ", end="")
    for d in depths:
        print(f"  {d}  ", end="")
    print(" ← Depth")

    print("    ┌" + "─────" * len(depths) + "┐")

    for s in sizes:
        print(f" {s:2d} │", end="")
        for d in depths:
            count = size_depth.get((s, d), 0)
            if count == 0:
                print("  ·  ", end="")
            else:
                idx = min(len(chars) - 1, int((len(chars) - 1) * count / max_count * 2))
                print(f" {chars[idx]}{count:3d}", end="")
        print("│")

    print("    └" + "─────" * len(depths) + "┘")
    print(" ↑ Size")
    print(f"\n  Legend: · = 0, ░ = 1-{max_count//4}, ▒ = {max_count//4+1}-{max_count//2}, ▓ = {max_count//2+1}-{3*max_count//4}, █ = {3*max_count//4+1}+")

def weight_size_chart(data):
    """Show how size varies with truth table weight."""
    functions = data['functions']

    def count_ones(tt):
        return bin(tt).count('1')

    by_weight = defaultdict(list)
    for f in functions:
        by_weight[count_ones(f['tt'])].append(f['size'])

    print("\n=== Circuit Size by Truth Table Weight ===")
    print()
    print("Weight │ Count │ Mean Size │ Distribution")
    print("───────┼───────┼───────────┼" + "─" * 40)

    for w in sorted(by_weight.keys()):
        sizes = by_weight[w]
        mean = sum(sizes) / len(sizes)

        # Mini histogram
        size_counts = defaultdict(int)
        for s in sizes:
            size_counts[s] += 1

        max_s = max(size_counts.keys())
        min_s = min(size_counts.keys())
        max_count = max(size_counts.values())

        hist = ""
        for s in range(min_s, max_s + 1):
            c = size_counts.get(s, 0)
            if c > 0:
                level = int(8 * c / max_count) if max_count > 0 else 0
                hist += "▁▂▃▄▅▆▇█"[min(level, 7)]
            else:
                hist += " "

        print(f"  {w:2d}   │ {len(sizes):5d} │   {mean:5.2f}   │ [{min_s:2d}-{max_s:2d}] {hist}")

def main():
    data = load_data()
    functions = data['functions']

    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║     CIRCUIT COMPLEXITY VISUALIZATION - n=4 Boolean Functions    ║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    # Size distribution
    sizes = [f['size'] for f in functions]
    ascii_histogram(sizes, "Circuit Size Distribution")

    # Depth distribution
    depths = [f['depth'] for f in functions]
    ascii_histogram(depths, "Circuit Depth Distribution")

    # Size vs Depth heatmap
    size_depth_heatmap(data)

    # Weight vs Size
    weight_size_chart(data)

    # Summary statistics
    print("\n=== Summary Statistics ===")
    print(f"Total functions: {len(functions)}")
    print(f"Size:  min={min(sizes)}, max={max(sizes)}, mean={sum(sizes)/len(sizes):.2f}")
    print(f"Depth: min={min(depths)}, max={max(depths)}, mean={sum(depths)/len(depths):.2f}")

    # Functions at each extreme
    print(f"\nFunctions at size 15 (hardest): {sum(1 for f in functions if f['size'] == 15)}")
    print(f"Functions at size 0 (literals): {sum(1 for f in functions if f['size'] == 0)}")

if __name__ == "__main__":
    main()
