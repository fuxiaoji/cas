extends SceneTree
## Explicitly invoked maintenance tool; never loaded by a game scene.
const Economy = preload("res://scripts/economy.gd")
const Resources = preload("res://scripts/test_account_resources.gd")
var checks: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func _check(label: String, passed: bool) -> void:
	checks.append({"label": label, "ok": passed})
	if not passed:
		push_error(label)

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _equal_json(first: Dictionary, second: Dictionary) -> bool:
	# Godot JSON loads numbers as float; compare both through that same boundary.
	return JSON.parse_string(JSON.stringify(first)) == JSON.parse_string(JSON.stringify(second))

func _unchanged_fields(value: Dictionary) -> Dictionary:
	var copy: Dictionary = value.duplicate(true)
	for key in ["wallet", "stamina", "test_account", "test_resource_grant"]:
		copy.erase(key)
	for key in Resources.INVENTORY_FLOORS:
		copy.get("inventory", {}).erase(key)
	return copy

func _load_exact(path: String):
	var account = Economy.new(path)
	var raw: Dictionary = account._read_dictionary(path)
	if not account._valid_state(raw):
		return null
	account.state = raw
	account._sync_formation()
	return account

func run() -> void:
	var args: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		var split: PackedStringArray = argument.split("=", true, 1)
		if split.size() == 2:
			args[split[0]] = split[1]
	var path: String = str(args.get("--target", ""))
	var expected: String = str(args.get("--expected-sha", ""))
	var receipt_path: String = str(args.get("--receipt", ""))
	var scratch: String = str(args.get("--scratch", ""))
	var approved: String = ProjectSettings.globalize_path("user://cas_port_v1.json")
	if path.replace("\\", "/") != approved.replace("\\", "/") or expected.length() != 64 or receipt_path.is_empty() or scratch.is_empty():
		push_error("Explicit actual-profile path, fingerprint, receipt and isolated scratch path required")
		quit(1)
		return
	_check("approved primary save fingerprint before maintenance", _hash(path) == expected)
	if not checks[-1].ok:
		quit(1)
		return
	var account = _load_exact(path)
	if account == null:
		push_error("Current account is invalid; original files retained")
		quit(1)
		return
	var original: Dictionary = account.state.duplicate(true)
	# Use the actual current profile as an isolated preservation/rollback fixture.
	var fixture = Economy.new(scratch + "/preservation-fixture.json")
	fixture.state = original.duplicate(true)
	fixture._sync_formation()
	fixture.state.erase("test_account")
	var fixture_before: Dictionary = fixture.state.duplicate(true)
	var skipped: Dictionary = Resources.apply(fixture)
	_check("unmarked existing account receives no automatic grant", bool(skipped.get("skipped", false)) and fixture.state == fixture_before)
	var granted: Dictionary = Resources.apply(fixture, true)
	_check("explicit grant uses journaled account commit", bool(granted.get("ok", false)) and FileAccess.file_exists(fixture.save_path))
	_check("actual fixture ownership progress items and active_run unchanged", _unchanged_fields(fixture.state) == _unchanged_fields(fixture_before))
	_check("actual fixture original snapshot string unchanged", fixture.state.get("active_run", {}).get("snapshot") == original.get("active_run", {}).get("snapshot"))
	var fixture_hash: String = _hash(fixture.save_path)
	var full: Dictionary = Resources.apply(fixture)
	_check("already full test account does not write again", bool(full.get("unchanged", false)) and _hash(fixture.save_path) == fixture_hash)
	var fresh = Economy.new(scratch + "/ordinary-new-profile.json")
	var fresh_result: Dictionary = fresh.new_profile()
	var normal_before: Dictionary = fresh.state.duplicate(true)
	var normal_skip: Dictionary = Resources.apply(fresh)
	_check("ordinary new profile retains configured initial resources", bool(fresh_result.ok) and bool(normal_skip.get("skipped", false)) and fresh.state == normal_before and not fresh.state.has("test_account") and int(fresh.state.wallet.credits) == int(fresh.config.initial.credits))
	var failure = Economy.new(scratch + "/write-blocker/save.json")
	var blocker := FileAccess.open(scratch + "/write-blocker", FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("isolated commit failure fixture")
		blocker.close()
	failure.state = original.duplicate(true)
	failure.state.wallet.credits = 0
	failure._sync_formation()
	var failed_before: Dictionary = failure.state.duplicate(true)
	var rejected: Dictionary = Resources.apply(failure, true)
	_check("failed commit restores all state including marker and active_run", not bool(rejected.get("ok", false)) and failure.state == failed_before)
	var failed: bool = checks.any(func(row: Dictionary) -> bool: return not bool(row.ok))
	if failed or _hash(path) != expected:
		push_error("Maintenance preflight failed or primary changed; original account not written")
		quit(1)
		return
	# The only primary-file mutation is the same account transaction used by the game.
	var result: Dictionary = Resources.apply(account, true)
	_check("actual test account resource transaction committed", bool(result.get("ok", false)))
	_check("actual nonresource state completely retained", _unchanged_fields(account.state) == _unchanged_fields(original))
	_check("actual active_run and original snapshot retained", account.state.get("active_run") == original.get("active_run"))
	var after_commit_hash: String = _hash(path)
	var restored = Economy.new(path)
	var loaded: Dictionary = restored.load_state()
	_check("actual load_state succeeds with same full state", bool(loaded.get("ok", false)) and _equal_json(restored.state, account.state))
	_check("actual reload does not rewrite full account", _hash(path) == after_commit_hash)
	var wallet: Dictionary = restored.wallet()
	_check("actual wallet read preserves assets and active_run", _equal_json(restored.state, account.state))
	_check("actual stamina full at configured maximum", int(wallet.stamina) == int(wallet.stamina_max))
	for key in Resources.WALLET_FLOORS:
		_check("wallet floor " + str(key), int(restored.state.wallet.get(key, 0)) >= int(Resources.WALLET_FLOORS[key]))
	for key in Resources.INVENTORY_FLOORS:
		_check("fungible salvage floor " + str(key), int(restored.state.inventory.get(key, 0)) >= int(Resources.INVENTORY_FLOORS[key]))
	var receipt: Dictionary = {
		"ok": checks.all(func(row: Dictionary) -> bool: return bool(row.ok)),
		"checks": checks, "path": path, "before_sha256": expected,
		"after_sha256": _hash(path), "test_account": restored.state.get("test_account"),
		"grant": result, "wallet": wallet, "inventory": restored.state.inventory,
		"active_run_id": restored.state.get("active_run", {}).get("run_id"),
		"owned_count": restored.state.owned.size(),
	}
	var stream := FileAccess.open(receipt_path, FileAccess.WRITE)
	if stream != null:
		stream.store_string(JSON.stringify(receipt, "\t"))
		stream.close()
	print("TEST_RESOURCE_REFILL ", JSON.stringify(receipt))
	quit(0 if bool(receipt.ok) else 1)
