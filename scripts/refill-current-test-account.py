"""Back up the explicitly approved primary and invoke its real Godot transaction.

This is a one-profile maintenance command, not a normal-profile initializer.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def raw_member(text: str, name: str) -> str:
    decoder = json.JSONDecoder()
    index = text.index("{") + 1
    while True:
        while text[index].isspace() or text[index] == ",":
            index += 1
        if text[index] == "}":
            raise KeyError(name)
        key, index = decoder.raw_decode(text, index)
        while text[index].isspace() or text[index] == ":":
            index += 1
        start = index
        _, index = decoder.raw_decode(text, index)
        if key == name:
            return text[start:index]


def changes(before, after, location="") -> list[str]:
    if isinstance(before, dict) and isinstance(after, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            path = f"{location}/{key}"
            if key not in before or key not in after:
                result.append(path)
            else:
                result.extend(changes(before[key], after[key], path))
        return result
    return [] if before == after else [location]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", required=True)
    parser.add_argument("--expected-sha", required=True)
    parser.add_argument("--verify-existing", action="store_true", help="verify the completed grant without replacing original backups")
    parser.add_argument("--godot", default="D:/downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    primary = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CAS · 归航/cas_port_v1.json"
    backup = Path(str(primary) + ".bak")
    target = root / "artifacts/test-account-refill-20261113"
    current_bytes = primary.read_bytes()
    before_bytes = (target / "cas_port_v1.before.json").read_bytes() if args.verify_existing else current_bytes
    backup_bytes = (target / "cas_port_v1.before.json.bak").read_bytes() if args.verify_existing else backup.read_bytes()
    if digest(current_bytes) != args.expected_sha:
        raise RuntimeError("Primary changed since account approval; no files written")
    probe = subprocess.run(
        ["powershell", "-NoProfile", "-Command", "@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^Godot'} | Select-Object ProcessId,Name,CommandLine) | ConvertTo-Json -Compress"],
        capture_output=True, text=True, check=True,
    )
    if probe.stdout.strip() not in ("", "[]"):
        raise RuntimeError("Godot process is active; do not overwrite an open account: " + probe.stdout)
    target.mkdir(parents=True, exist_ok=True)
    for name, data in (("cas_port_v1.before.json", before_bytes), ("cas_port_v1.before.json.bak", backup_bytes)):
        output = target / name
        if output.exists() and output.read_bytes() != data:
            raise RuntimeError("Existing exact backup differs; refusing to overwrite " + str(output))
        output.write_bytes(data)
    before = json.loads(before_bytes)
    active_raw = raw_member(before_bytes.decode("utf-8"), "active_run")
    snapshot = before.get("active_run", {}).get("snapshot")
    (target / "active-run.before.raw.json").write_bytes(active_raw.encode("utf-8"))
    if isinstance(snapshot, str):
        (target / "snapshot.before.exact.txt").write_bytes(snapshot.encode("utf-8"))
        (target / "snapshot.before.raw-json-token.txt").write_bytes(raw_member(active_raw, "snapshot").encode("utf-8"))
    metadata = {
        "path": str(primary), "primary_bytes": len(before_bytes),
        "primary_sha256": digest(before_bytes), "backup_bytes": len(backup_bytes),
        "backup_sha256": digest(backup_bytes), "test_account_before": before.get("test_account"),
        "active_run_id": before.get("active_run", {}).get("run_id"),
        "snapshot_utf8_sha256": digest(snapshot.encode("utf-8")) if isinstance(snapshot, str) else None,
        "live_godot_processes": [],
    }
    if not args.verify_existing:
        (target / "before-metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    scratch = target / "isolated-account-checks"
    scratch.mkdir(exist_ok=True)
    command = [args.godot, "--headless", "--path", str(root / "godot"), "--script", "res://tests/refill_current_test_resources.gd", "--",
               "--target=" + str(primary), "--expected-sha=" + args.expected_sha,
               "--receipt=" + str(target / "godot-transaction-receipt.json"), "--scratch=" + str(scratch)]
    run = subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace", timeout=120)
    log_name = "godot-reload-verification.log" if args.verify_existing else "godot-transaction.log"
    (target / log_name).write_text(run.stdout + run.stderr, encoding="utf-8")
    after_bytes = primary.read_bytes()
    after = json.loads(after_bytes)
    delta = changes(before, after)
    permitted = ("/wallet/", "/stamina/", "/test_account", "/test_resource_grant", "/inventory/scrap", "/inventory/alloy")
    unexpected = [path for path in delta if not any(path.startswith(prefix) for prefix in permitted)]
    active_after_raw = raw_member(after_bytes.decode("utf-8"), "active_run")
    snapshot_token_exact = raw_member(active_raw, "snapshot") == raw_member(active_after_raw, "snapshot")
    checks = {
        "godot_exit_zero": run.returncode == 0,
        "original_primary_backup_exact": (target / "cas_port_v1.before.json").read_bytes() == before_bytes,
        "original_bak_backup_exact": (target / "cas_port_v1.before.json.bak").read_bytes() == backup_bytes,
        "journal_rotated_bak_equals_original_primary": backup.read_bytes() == before_bytes,
        "all_unrelated_fields_equal": not unexpected,
        "complete_active_run_equal": before.get("active_run") == after.get("active_run"),
        "original_snapshot_string_utf8_exact": snapshot == after.get("active_run", {}).get("snapshot"),
        "original_snapshot_json_token_exact": snapshot_token_exact,
        "actual_instance_counts_equal": all(before["inventory"].get(key) == after["inventory"].get(key) for key in ("equipment", "command")),
    }
    receipt = {
        "ok": all(checks.values()), "checks": checks, "changed_paths": delta,
        "unexpected_changes": unexpected, "before": metadata, "after_sha256": digest(after_bytes),
        "wallet": after.get("wallet"), "inventory": after.get("inventory"),
        "stamina": after.get("stamina"), "test_account": after.get("test_account"),
    }
    (target / "preservation-receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=True, indent=2))
    if not receipt["ok"]:
        print(run.stdout[-3000:], run.stderr[-3000:])
        raise SystemExit(1)


if __name__ == "__main__":
    main()
