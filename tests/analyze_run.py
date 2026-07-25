#!/usr/bin/env python3
"""Analyze a RunRecorder metrics CSV + events JSONL pair from a Freepeople turbo run.

Usage:
    python tests/analyze_run.py <path/to/run_..._metrics.csv> [path/to/run_..._events.jsonl]

If the JSONL path is omitted, it's derived from the CSV path by replacing
"_metrics.csv" with "_events.jsonl".

Prints a compact trajectory summary (population, crown gold, hunger, food stock,
gold spread, building health) sampled at regular intervals, plus a full dump of
JSONL events that are usually collapse-relevant (starved, derelict, build_aborted,
jobchange, game_over).
"""
import csv
import json
import sys
from pathlib import Path


def load_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    events = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def fnum(row: dict, key: str) -> float:
    return float(row.get(key, 0.0))


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    csv_path = Path(sys.argv[1])
    jsonl_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        str(csv_path).replace("_metrics.csv", "_events.jsonl")
    )

    rows = load_csv(csv_path)
    events = load_jsonl(jsonl_path)

    if not rows:
        print("No rows in metrics CSV.")
        sys.exit(1)

    print(f"=== {csv_path.name} ({len(rows)} samples) ===")
    last_day = int(fnum(rows[-1], "day"))
    print(f"Final day sampled: {last_day}")
    print(f"Final population: {rows[-1]['population']}  crown_gold: {rows[-1]['crown_gold']}")
    print()

    # Trajectory table, sampled every ~N rows to keep output short.
    step = max(1, len(rows) // 40)
    header = f"{'day':>5} {'pop':>3} {'crown_gold':>10} {'gold_min':>8} {'gold_max':>8} " \
             f"{'avg_hunger':>10} {'deaths':>6} {'food':>8} {'derelict':>8} {'repair':>6}"
    print(header)
    print("-" * len(header))
    for i in range(0, len(rows), step):
        r = rows[i]
        print(f"{fnum(r,'day'):5.0f} {fnum(r,'population'):3.0f} {fnum(r,'crown_gold'):10.1f} "
              f"{fnum(r,'gold_min'):8.1f} {fnum(r,'gold_max'):8.1f} {fnum(r,'avg_hunger'):10.3f} "
              f"{fnum(r,'cumulative_deaths'):6.0f} {fnum(r,'community_FOOD'):8.1f} "
              f"{fnum(r,'bld_derelict_total'):8.0f} {fnum(r,'bld_needs_repair_total'):6.0f}")
    if (len(rows) - 1) % step != 0:
        r = rows[-1]
        print(f"{fnum(r,'day'):5.0f} {fnum(r,'population'):3.0f} {fnum(r,'crown_gold'):10.1f} "
              f"{fnum(r,'gold_min'):8.1f} {fnum(r,'gold_max'):8.1f} {fnum(r,'avg_hunger'):10.3f} "
              f"{fnum(r,'cumulative_deaths'):6.0f} {fnum(r,'community_FOOD'):8.1f} "
              f"{fnum(r,'bld_derelict_total'):8.0f} {fnum(r,'bld_needs_repair_total'):6.0f}")

    print()
    interesting = {"starved", "derelict", "build_aborted", "jobchange", "game_over"}
    hits = [e for e in events if e.get("type") in interesting]
    print(f"=== Collapse-relevant events ({len(hits)} of {len(events)} total) ===")
    for e in hits:
        print(f"day={e.get('day'):>4} t={e.get('t'):>8.1f} {e.get('type'):14s} {e.get('data')}")


if __name__ == "__main__":
    main()
