#!/usr/bin/env python3
"""Build cNFT Merkle tree matching CompressedNftCollection.tolk (TVM cell.hash()).

Leaf:  beginCell().storeUint(index, 64).storeAddress(owner).endCell().hash()
Pair:  beginCell().storeUint(left, 256).storeUint(right, 256).endCell().hash()
Depth: 8 (256 leaves). Empty slots use uint256(0).
Proof: 8 siblings packed 3-per-cell with ref chain (PlxAirdrop-style).

Usage:
  python3 scripts/cnft_merkle.py --owner EQ... --count 2
  python3 scripts/cnft_merkle.py --items-json '[{"owner":"EQ..."},{"owner":"EQ..."}]'
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from typing import Any


def _require_pytoniq():
    try:
        from pytoniq_core import Address, begin_cell  # type: ignore

        return Address, begin_cell
    except ImportError as exc:  # pragma: no cover
        raise SystemExit(
            "cnft_merkle requires pytoniq-core. "
            "Install: pip install pytoniq-core"
        ) from exc


TREE_DEPTH = 8
LEAF_COUNT = 1 << TREE_DEPTH
ZERO = b"\x00" * 32


def hash_pair(left: bytes, right: bytes, begin_cell) -> bytes:
    return (
        begin_cell()
        .store_uint(int.from_bytes(left, "big"), 256)
        .store_uint(int.from_bytes(right, "big"), 256)
        .end_cell()
        .hash
    )


def hash_leaf(index: int, owner: str, Address, begin_cell) -> bytes:
    return (
        begin_cell()
        .store_uint(index, 64)
        .store_address(Address(owner))
        .end_cell()
        .hash
    )


def pack_proof_cell(siblings: list[bytes], begin_cell):
    """Pack up to TREE_DEPTH uint256 siblings as 3-per-cell + refs."""
    chunks: list[list[bytes]] = []
    buf: list[bytes] = []
    for sib in siblings:
        buf.append(sib)
        if len(buf) == 3:
            chunks.append(buf)
            buf = []
    if buf:
        chunks.append(buf)

    cell = None
    for chunk in reversed(chunks):
        b = begin_cell()
        for sib in chunk:
            b.store_uint(int.from_bytes(sib, "big"), 256)
        if cell is not None:
            b.store_ref(cell)
        cell = b.end_cell()
    return cell


def build_tree(owners: list[str], Address, begin_cell) -> dict[str, Any]:
    if len(owners) > LEAF_COUNT:
        raise ValueError(f"too many items: {len(owners)} > {LEAF_COUNT}")

    leaves: list[bytes] = []
    for i in range(LEAF_COUNT):
        if i < len(owners):
            leaves.append(hash_leaf(i, owners[i], Address, begin_cell))
        else:
            leaves.append(ZERO)

    levels: list[list[bytes]] = [leaves]
    cur = leaves
    for _ in range(TREE_DEPTH):
        nxt: list[bytes] = []
        for i in range(0, len(cur), 2):
            nxt.append(hash_pair(cur[i], cur[i + 1], begin_cell))
        levels.append(nxt)
        cur = nxt

    root = levels[-1][0]
    proofs: dict[str, Any] = {}
    for idx in range(len(owners)):
        ix = idx
        sibs: list[bytes] = []
        for depth in range(TREE_DEPTH):
            sibs.append(levels[depth][ix ^ 1])
            ix //= 2
        proof_cell = pack_proof_cell(sibs, begin_cell)

        proofs[str(idx)] = {
            "owner": owners[idx],
            "siblings_hex": [s.hex() for s in sibs],
            "siblings_dec": [str(int.from_bytes(s, "big")) for s in sibs],
            "proof_boc_b64": base64.b64encode(proof_cell.to_boc()).decode(),
        }

    return {
        "tree_depth": TREE_DEPTH,
        "max_supply": LEAF_COUNT,
        "merkle_root_hex": root.hex(),
        "merkle_root": str(int.from_bytes(root, "big")),
        "item_count": len(owners),
        "owners": owners,
        "proofs": proofs,
        "hash_scheme": "tvm_cell_hash_v1",
    }


def _owners_from_args(args: argparse.Namespace) -> list[str]:
    if args.items_json:
        raw = json.loads(args.items_json)
        owners: list[str] = []
        for i, item in enumerate(raw):
            if isinstance(item, dict):
                owners.append(str(item.get("owner") or item.get("address") or args.owner))
            else:
                owners.append(str(args.owner))
        if args.owner and not owners:
            owners = [args.owner] * max(args.count, 0)
        return owners

    if not args.owner:
        raise SystemExit("--owner required when --items-json omitted")
    count = max(int(args.count), 0)
    return [args.owner] * count


def main() -> None:
    parser = argparse.ArgumentParser(description="Build TVM-compatible cNFT merkle tree")
    parser.add_argument("--owner", default="", help="Default owner address for leaves")
    parser.add_argument("--count", type=int, default=0, help="Leaf count when using --owner")
    parser.add_argument("--items-json", default="", help="JSON array of items with optional owner")
    parser.add_argument("--out", default="", help="Write JSON to file (also prints to stdout)")
    args = parser.parse_args()

    Address, begin_cell = _require_pytoniq()
    owners = _owners_from_args(args)
    if not owners:
        # Empty tree still has a defined root (all-zero leaves)
        owners = []

    result = build_tree(owners, Address, begin_cell)
    text = json.dumps(result, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
    print(text)


if __name__ == "__main__":
    main()
