"""Capture one save + fresh-process replay per shipped evolved doctrine.

The host protocol is driven over stdin/stdout of `target/release/cas-sim.exe`.
Every match is a real headless World::advance run; the report records the save
hash and the replay result so the evidence is independently checkable.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "target" / "release" / ("cas-sim.exe" if sys.platform == "win32" else "cas-sim")
OUT = ROOT / "data" / "ai" / "evidence"

CASES = [
    ("cas-sim-evo-brawler-6106.json", 6106, "evo-brawler", "coord"),
    ("cas-sim-evo-kiter-6112.json", 6112, "evo-kiter", "gunnery"),
    ("cas-sim-evo-denial-6111.json", 6111, "evo-denial", "torpedo"),
]


def host():
    return subprocess.Popen(
        [str(EXE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )


def call(process, request):
    process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
    process.stdin.flush()
    reply = json.loads(process.stdout.readline())
    if reply.get("ok") is not True:
        raise RuntimeError(reply)
    return reply["data"]


def play(seed, candidate, opponent):
    process = host()
    try:
        call(process, {"op": "new", "seed": seed, "side": "allies", "enemy": opponent,
                       "variant": "", "profile": candidate})
        call(process, {"op": "ai", "fleet": 1, "profile": candidate, "mode": "auto",
                       "move": True, "gun": True, "torpedo": True})
        view = call(process, {"op": "step", "seconds": 2700})
        if view.get("settling") is True:
            view = call(process, {"op": "step", "seconds": 8})
        report = call(process, {"op": "report"})
        save = call(process, {"op": "save"})
        return view, report, save
    finally:
        process.stdin.close()
        process.terminate()


def replay(save):
    process = host()
    try:
        view = call(process, {"op": "replay", "save": save})
        return view
    finally:
        process.stdin.close()
        process.terminate()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, seed, candidate, opponent in CASES:
        view, report, save = play(seed, candidate, opponent)
        saved = json.dumps(save, ensure_ascii=False, sort_keys=True).encode("utf-8")
        replayed = replay(save)
        events = [event for event in report.get("events", [])]
        kinds = {}
        for event in events:
            kinds[event["kind"]] = kinds.get(event["kind"], 0) + 1
        sunk = [event["text"] for event in events if event.get("kind") == "sunk"]
        evidence = {
            "schema": "cas-ai-cas-sim-evidence-v1",
            "source": "cas-sim host protocol: new + ai + step + report + save, then replay(save) in a fresh process",
            "seed": seed,
            "side": "allies",
            "candidateProfile": candidate,
            "opponentProfile": opponent,
            "variant": "",
            "result": view.get("result"),
            "stepTick": view.get("tick"),
            "replayTick": replayed.get("tick"),
            "replayResult": replayed.get("result"),
            "replayMatches": (view.get("result") == replayed.get("result")
                              and view.get("tick") == replayed.get("tick")),
            "saveSha256": hashlib.sha256(saved).hexdigest(),
            "saveBytes": len(saved),
            "events": {key: kinds[key] for key in sorted(kinds)},
            "sunkShips": sunk,
        }
        (OUT / name).write_text(json.dumps(evidence, ensure_ascii=False, indent=4) + "\n",
                                encoding="utf-8", newline="\n")
        print(name, evidence["result"], evidence["replayMatches"], evidence["stepTick"])


if __name__ == "__main__":
    main()
