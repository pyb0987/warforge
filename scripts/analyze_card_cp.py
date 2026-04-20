#!/usr/bin/env python3
"""
analyze_card_cp.py — Compute base CP (ATK/AS × HP sum) for all cards.

Usage:
    python3 scripts/analyze_card_cp.py              # full report
    python3 scripts/analyze_card_cp.py --sort cp    # sort by CP desc
    python3 scripts/analyze_card_cp.py --tier 4     # only tier 4

Formula per unit:  cp = n * (atk / attack_speed) * hp
Card base CP     = sum of per-unit cp over comp entries
This matches dr_cradle=1200, dr_lifebeat=1100, sp_furnace=393.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CARDS_DIR = ROOT / "data" / "cards"
UNIT_DB = ROOT / "godot" / "core" / "data" / "unit_db.gd"

_REG_RE = re.compile(
    r'_reg\("(\w+)",\s*"[^"]*",\s*(-?\d+),\s*(-?\d+),\s*([\d.]+),\s*(-?\d+),\s*(-?\d+),'
)


def load_units() -> dict[str, dict]:
    """Parse unit_db.gd _reg(...) calls → {id: {atk, hp, as, range, ms}}."""
    units: dict[str, dict] = {}
    text = UNIT_DB.read_text(encoding="utf-8")
    for m in _REG_RE.finditer(text):
        uid, atk, hp, as_, urange, ms = m.groups()
        units[uid] = {
            "atk": int(atk),
            "hp": int(hp),
            "as": float(as_),
            "range": int(urange),
            "ms": int(ms),
        }
    return units


def load_cards() -> list[dict]:
    """Load all YAML cards, attach theme from filename."""
    cards: list[dict] = []
    for yf in sorted(CARDS_DIR.glob("*.yaml")):
        data = yaml.safe_load(yf.read_text(encoding="utf-8"))
        if not data or "cards" not in data:
            continue
        for cid, cdata in data["cards"].items():
            entry = dict(cdata)
            entry["id"] = cid
            entry.setdefault("theme", yf.stem)
            cards.append(entry)
    return cards


def card_base_cp(card: dict, units: dict[str, dict]) -> tuple[float, int, str]:
    """Return (base_cp, unit_count, comp_desc)."""
    comp = card.get("comp") or []
    total_cp = 0.0
    total_units = 0
    parts: list[str] = []
    for entry in comp:
        uid = entry["unit"]
        n = int(entry.get("n", 1))
        u = units.get(uid)
        if not u:
            parts.append(f"{uid}×{n}(MISSING)")
            continue
        as_ = u["as"]
        if as_ <= 0:
            continue
        per = (u["atk"] / as_) * u["hp"]
        total_cp += n * per
        total_units += n
        parts.append(f"{uid}×{n}")
    return total_cp, total_units, " + ".join(parts)


def fmt_row(card: dict, cp: float, n_units: int, comp: str) -> str:
    return (
        f"  {card['id']:<22} T{card.get('tier', '?')} "
        f"{card.get('theme', '?'):<10} "
        f"CP={cp:7.1f} units={n_units:2d}  [{comp}]"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", type=int, default=None, help="filter by tier")
    ap.add_argument("--theme", type=str, default=None, help="filter by theme")
    ap.add_argument(
        "--sort",
        choices=["tier", "cp", "id", "theme"],
        default="tier",
        help="sort order (default: tier)",
    )
    ap.add_argument("--csv", action="store_true", help="output CSV")
    args = ap.parse_args()

    units = load_units()
    cards = load_cards()
    if args.tier is not None:
        cards = [c for c in cards if c.get("tier") == args.tier]
    if args.theme:
        cards = [c for c in cards if c.get("theme") == args.theme]

    rows = []
    for c in cards:
        cp, n, comp = card_base_cp(c, units)
        rows.append((c, cp, n, comp))

    sort_key = {
        "tier": lambda r: (r[0].get("tier", 99), -r[1]),
        "cp": lambda r: -r[1],
        "id": lambda r: r[0]["id"],
        "theme": lambda r: (r[0].get("theme", ""), r[0].get("tier", 99), -r[1]),
    }[args.sort]
    rows.sort(key=sort_key)

    if args.csv:
        print("id,tier,theme,base_cp,unit_count,comp")
        for c, cp, n, comp in rows:
            print(f"{c['id']},{c.get('tier','')},{c.get('theme','')},{cp:.1f},{n},{comp}")
        return 0

    # Grouped listing
    print(f"# Card base CP report — {len(rows)} cards (formula: sum(n × ATK/AS × HP))\n")
    by_tier_theme: dict[int, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    by_tier: dict[int, list[float]] = defaultdict(list)
    for c, cp, n, comp in rows:
        t = c.get("tier", 0)
        th = c.get("theme", "?")
        by_tier_theme[t][th].append((c, cp, n, comp))
        by_tier[t].append(cp)

    for tier in sorted(by_tier_theme.keys()):
        cps = by_tier[tier]
        avg = sum(cps) / len(cps)
        lo, hi = min(cps), max(cps)
        print(f"━━━ T{tier} — n={len(cps)}, avg={avg:.1f}, min={lo:.1f}, max={hi:.1f} ━━━")
        for th in sorted(by_tier_theme[tier].keys()):
            for c, cp, n, comp in by_tier_theme[tier][th]:
                print(fmt_row(c, cp, n, comp))
        print()

    # Summary table
    print("━━━ Tier summary ━━━")
    print(f"  {'Tier':<6} {'n':>3}  {'avg':>7}  {'min':>7}  {'max':>7}  {'median':>7}")
    for tier in sorted(by_tier.keys()):
        cps = sorted(by_tier[tier])
        avg = sum(cps) / len(cps)
        median = cps[len(cps) // 2] if len(cps) % 2 else (cps[len(cps)//2 - 1] + cps[len(cps)//2]) / 2
        print(f"  T{tier:<5} {len(cps):>3}  {avg:>7.1f}  {cps[0]:>7.1f}  {cps[-1]:>7.1f}  {median:>7.1f}")
    print()

    # Theme × Tier matrix
    print("━━━ Theme × Tier avg CP ━━━")
    themes = sorted({c.get("theme", "?") for c, *_ in rows})
    tiers = sorted(by_tier.keys())
    header = f"  {'theme':<10} " + " ".join(f"{'T'+str(t):>7}" for t in tiers)
    print(header)
    for th in themes:
        row_cells = []
        for t in tiers:
            entries = by_tier_theme[t].get(th, [])
            if entries:
                avg = sum(cp for _, cp, _, _ in entries) / len(entries)
                row_cells.append(f"{avg:>7.1f}")
            else:
                row_cells.append(f"{'·':>7}")
        print(f"  {th:<10} " + " ".join(row_cells))

    return 0


if __name__ == "__main__":
    sys.exit(main())
