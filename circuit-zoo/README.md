# Circuit Zoo

Distributed search for optimal boolean circuits. Finds minimum-size AND/OR circuits (with NOT pushed to inputs) for all boolean functions of n variables.

## Overview

This project exhaustively searches for optimal circuits for boolean functions:
- **n=4**: 65,536 functions - fully enumerable
- **n=5**: 4.3 billion functions - distributed search

Workers connect to a central PostgreSQL database and continuously discover optimal circuits.

## Key Findings (n=4)

- **Mean circuit size**: 7.91 gates
- **Max circuit size**: 15 gates (XOR-like functions)
- **Total influence** is the best predictor of circuit size (r=0.87)
- **Monotone functions** are easy (mean 3.3 gates)
- **Symmetric functions** are hard (mean 10 gates)

## Usage

The circuit-zoo service is configured in `../circuit-zoo.nix` and runs automatically on all cluster nodes.

```bash
# Check status
ssh admin@node1.local "systemctl status circuit-zoo"

# View logs
ssh admin@node1.local "journalctl -u circuit-zoo -f"
```

## Local Development

```bash
# Build
cargo build --release

# Run locally (no database)
./target/release/circuit_zoo -n 4 --local

# Run with database
./target/release/circuit_zoo -n 5 -s 14 -d "host=192.168.4.25 user=samuel dbname=samuel"
```

## CLI Options

```
-n, --n <N>           Number of input variables [default: 4]
-s, --max-size <N>    Maximum circuit size [default: 15]
-d, --database <URL>  Postgres connection string
-w, --worker-id <ID>  Worker identifier
-t, --threads <N>     Thread count [default: all cores]
--local               Run without database
```

## Circuit Representation

Circuits are AND/OR DAGs over literals (x_i or ¬x_i):
```json
{"type": "and", "left": 43690, "right": 52428}
{"type": "lit", "var": 0, "neg": false}
```

Truth tables are stored as integers (bit i = f(binary(i))).
