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
    for seed in range(6106, 6112):
        row = {"seed": seed}
        for seat in seats:
            data = json.loads(
                subprocess.check_output(
                    [str(args.exe.resolve()), "demo", str(seed), seat], encoding="utf-8"
                )
            )
            if seat == "allies":
                row.update(result=data["report"]["result"], tick=data["save"]["tick"])
            assert data["report"]["result"] == row["result"] == data["replay_result"]
            assert data["save"]["tick"] == row["tick"]
            counts = Counter(e["kind"] for e in data["report"]["events"])
            row[seat] = {
                name: counts[name]
                for name in ("route", "gun", "hit", "damage", "torpedo", "torpedo_hit", "critical", "ai_state")
            }
            assert all(counts[k] > 0 for k in ("gun", "damage", "hit"))
            if seed == 6106:
                (args.out / f"cas-duel-{seed}-{seat}.json").write_text(
                    json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
                )
        summary.append(row)
    assert sum(summary[0][side]["torpedo_hit"] for side in seats) > 0
    (args.out / "ai-exchange-20261106.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("6 seeds, 12 seat projections; both sides hit, same outcomes on replay; seed 6106 included a torpedo hit")


if __name__ == "__main__":
    main()
