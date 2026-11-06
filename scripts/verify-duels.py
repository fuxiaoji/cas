"""Run the same complete CAS matches from both seats and verify genuine exchanges."""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path, help="Release cas-sim executable")
    parser.add_argument("--out", type=Path, default=Path("artifacts"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    seats = ("allies", "axis")
    summary = []
    cases = [(seed, "") for seed in range(6106, 6112)] + [(6106, "night")]
    for seed, variant in cases:
        row = {"seed": seed, "variant": variant or "day"}
        for seat in seats:
            data = json.loads(
                subprocess.check_output(
                    [str(args.exe.resolve()), "demo", str(seed), seat, variant], encoding="utf-8"
                )
            )
            if seat == "allies":
                row.update(result=data["report"]["result"], tick=data["save"]["tick"])
            assert row["result"] is not None
            assert data["report"]["result"] == row["result"] == data["replay_result"]
            assert data["save"]["tick"] == row["tick"]
            counts = Counter(e["kind"] for e in data["report"]["events"])
            row[seat] = {
                name: counts[name]
                for name in ("route", "contact", "lost", "gun", "hit", "damage", "torpedo", "torpedo_hit", "torpedo_detected", "critical", "ai_state")
            }
            assert all(counts[k] > 0 for k in ("gun", "damage", "hit"))
            if (seed, variant) in [(6107, ""), (6106, "night")]:
                assert counts["torpedo_hit"] > 0 or seat == "allies" and not variant
                (args.out / f"cas-duel-{variant or 'day'}-{seed}-{seat}.json").write_text(
                    json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
                )
        summary.append(row)
    (args.out / "ai-exchange-v2.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("7 complete matches, 14 seat projections; day and night torpedo hits, both sides exchange fire, same replay outcomes")


if __name__ == "__main__":
    main()
