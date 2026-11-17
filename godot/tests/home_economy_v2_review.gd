extends SceneTree
## Meaningful account transactions against an isolated ordinary profile and a synthetic clock.
const OUTPUT: String = "res://../artifacts/home-economy-v2-20261116/"
var checks: int = 0
var failures: Array[String] = []
var account
var home
var processing
var formal_hash: String
var backup_hash: String
const T: int = 1800000000

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func same(before: Dictionary, message: String) -> void:
	check(home._same(before, account.state), message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	formal_hash = FileAccess.get_sha256("user://cas_port_v1.json")
	backup_hash = FileAccess.get_sha256("user://cas_port_v1.json.bak")
	OS.set_environment("CAS_WORLD3D", "1")
	account = load("res://scripts/economy.gd").new(OUTPUT + "account-%d.json" % OS.get_process_id())
	check(account.new_profile().get("ok", false), "isolated ordinary account persisted")
	check(account.load_state().get("ok", false), "ordinary save migrations complete before the isolated order fixture")
	home = load("res://scripts/home_service.gd").new(account)
	home.state().unlocked = true
	for kind: String in ["recycler", "dock", "forge", "medical"]:
		home.state().buildings.append({"id": "qa-" + kind, "kind": kind, "level": 1, "hp": 100, "cell": {"x": 4, "y": 4}})
	for key: String in home.RESOURCE_NAMES: home.state().resources[key] = 4000
	account.state.wallet.credits = 8000
	processing = load("res://scripts/home_economy_v2.gd").new(home)
	var before: Dictionary = account.state.duplicate(true)
	load("res://scripts/home_economy_v2.gd").checkpoint_account_transition(account, before, T)
	same(before, "generic transition hook is a pure no-op when no order ledger exists")
	var overview: Dictionary = processing.overview(T)
	check(overview.recipes.size() == 5, "five existing-facility recipes validate against real material catalog")
	check(not home.state().has("economy_v2"), "constructor and overview do not migrate a legacy account")
	same(before, "overview and production quotes are pure")
	OS.set_environment("CAS_WORLD3D", "0")
	check(not processing.start("qa-recycler", "civilian_order", 1, "blocked", {}, T).get("ok", false), "normal game cannot invoke candidate orders")
	same(before, "normal entry opt-out preserves full state")
	OS.set_environment("CAS_WORLD3D", "1")
	for args: Array in [["qa-recycler", "port_trade", 1], ["absent", "civilian_order", 1], ["qa-recycler", "civilian_order", 0], ["qa-recycler", "civilian_order", 49]]:
		check(not processing.start(str(args[0]), str(args[1]), int(args[2]), "invalid-" + str(checks), {}, T).get("ok", false), "invalid facility/recipe/quantity rejected")
		same(before, "invalid order never charges or opens a ledger")
	var quote: Dictionary = processing.preview("qa-recycler", "civilian_order", 3, T)
	check(quote.get("ready", false) and int(quote.total_seconds) == 1800, "three-batch quote has exact frozen duration")
	var wrong: Dictionary = {"home": {"scrap": 1}, "wallet": {}}
	check(not processing.start("qa-recycler", "civilian_order", 3, "wrong-price", wrong, T).ok, "changed confirmed price is rejected")
	same(before, "changed price is atomic")
	var result: Dictionary = processing.start("qa-recycler", "civilian_order", 3, "civilian-start", {"home": quote.home_cost, "wallet": quote.wallet_cost}, T)
	check(result.ok, "prepaid order starts")
	check(int(home.state().resources.scrap) == 3988 and int(home.state().resources.energy) == 3994, "all batches deducted exactly once")
	check(int(account.state.wallet.credits) == 8000, "home costs never spend wallet silver")
	before = account.state.duplicate(true)
	check(processing.start("qa-recycler", "civilian_order", 3, "civilian-start", {}, T + 1).get("duplicate", false), "start retry returns original receipt")
	same(before, "start retry has no duplicate cost")
	check(not processing.start("qa-recycler", "civilian_order", 1, "occupied", {}, T + 1).ok, "one real facility has one slot")
	same(before, "busy slot leaves complete state unchanged")
	check(not processing.claim("qa-recycler", "too-early", T + 599).ok, "unfinished batch cannot be claimed")
	same(before, "early claim does not materialize clock or rewards")
	check(processing.claim("qa-recycler", "civilian-first", T + 600).ok, "one matured batch can be claimed")
	check(int(home.state().resources.credits) == 4020 and int(account.state.wallet.credits) == 8000, "civilian output goes exclusively to island supplies")
	before = account.state.duplicate(true)
	check(processing.claim("qa-recycler", "civilian-first", T + 700).get("duplicate", false), "same claim request returns receipt")
	same(before, "claim replay never grants twice")
	check(not processing.claim("qa-recycler", "civilian-again", T + 700).ok, "new request cannot re-claim old batches")
	same(before, "claimed count is authoritative")
	var cancellation: Dictionary = processing.cancel_preview("qa-recycler", T + 700)
	check(int(cancellation.refund_batches) == 1 and int(cancellation.lost_batches) == 1, "cancel distinguishes completed, in-progress and unstarted work")
	same(before, "cancel preview is pure")
	var stale_cancel: Dictionary = processing.cancel_preview("qa-recycler", T + 600)
	var stale_result: Dictionary = processing.cancel("qa-recycler", "stale-cancel", T + 700, stale_cancel)
	check(not stale_result.ok and stale_result.get("quote_changed", false), "crossed batch boundary rejects stale refund approval atomically")
	same(before, "stale refund guard neither cancels work nor issues a smaller unapproved refund")
	check(processing.cancel("qa-recycler", "civilian-cancel", T + 700, cancellation).ok, "fresh approved cancellation refunds only unstarted batch")
	check(int(home.state().resources.scrap) == 3992 and not home.state().economy_v2.jobs.has("qa-recycler"), "exact refund and slot released after claimed output")
	before = account.state.duplicate(true)
	check(processing.cancel("qa-recycler", "civilian-cancel", T + 800).get("duplicate", false), "cancel retry is idempotent")
	same(before, "cancel does not refund twice")
	# Completed products survive cancellation and full warehouses.
	check(processing.start("qa-recycler", "civilian_order", 3, "cap-start", {}, T + 1000).ok, "new finite order accepted")
	home.state().resources.credits = home.RESOURCE_CAP
	before = account.state.duplicate(true)
	check(not processing.claim("qa-recycler", "full-cap", T + 1600).ok, "full output store blocks claiming without destroying product")
	same(before, "full warehouse preserves all work and inputs")
	check(processing.cancel("qa-recycler", "cap-cancel", T + 1700).ok, "partly complete order cancels remaining work")
	check(home.state().economy_v2.jobs.has("qa-recycler"), "completed unclaimed product retains slot")
	home.state().resources.credits -= 20
	check(processing.claim("qa-recycler", "cap-reclaim", T + 3000).ok and int(home.state().resources.credits) == home.RESOURCE_CAP, "matured product remains exactly one batch after cancellation")
	check(not home.state().economy_v2.jobs.has("qa-recycler"), "claimed cancelled order closes")
	# Silver trade uses another ledger, and an explicit eight-hour order cannot grow indefinitely.
	var home_supply: int = int(home.state().resources.credits)
	var silver: int = int(account.state.wallet.credits)
	check(processing.start("qa-dock", "port_trade", 1, "trade-start", {}, T).ok, "real dock trade starts")
	check(processing.claim("qa-dock", "trade-claim", T + 600).ok and int(account.state.wallet.credits) == silver + 120, "trade output uses existing wallet silver")
	check(int(home.state().resources.credits) == home_supply, "trade does not rename or overwrite island supplies")
	check(processing.start("qa-forge", "alloy_refining", 32, "eight-hour", {}, T).ok, "maximum eight-hour explicit batch accepted")
	var progress: Dictionary = processing.overview(T + 999999).jobs.filter(func(row): return row.facility_id == "qa-forge")[0]
	check(int(progress.completed_batches) == 32 and int(progress.work_seconds) == 28800, "offline time never creates more batches than paid eight-hour order")
	# Pause clocks on both sides of an actual run flag; no offline combat-time catch-up.
	check(processing.start("home-hq", "navigation_record", 2, "training-start", {}, T).ok, "HQ produces legal growth material")
	processing.checkpoint(T + 300)
	account.state.active_run = {"mode": "qa-only-pause-fixture"}
	processing.checkpoint(T + 5000)
	account.state.active_run = {}
	progress = processing.overview(T + 5600).jobs.filter(func(row): return row.facility_id == "home-hq")[0]
	check(int(progress.work_seconds) == 900, "battle time is excluded when checkpointed before both run transitions")
	var materials: int = int(account.state.wallet.materials)
	check(processing.claim("home-hq", "training-claim", T + 5600).ok and int(account.state.wallet.materials) == materials + 2, "training grants existing materials identifier")
	var identity: String = str(account.state.owned.keys()[0])
	account.state.owned[identity].level = 1
	account.state.owned[identity].xp = 0
	account.state.owned[identity].ascension = 0
	check(account.train_material(identity, 1, 1, "consume-record").get("ok", false), "newly produced material is consumed by real existing ship training")
	check(int(account.state.wallet.materials) == materials + 1, "real material consumer reduces the same wallet item")
	var cores: int = int(account.state.wallet.get("core_t1", 0))
	check(processing.start("qa-medical", "core_restoration", 2, "core-start", {}, T).ok, "medical facility processes rare exploration ingredient")
	check(processing.claim("qa-medical", "core-claim", T + 3600).ok and int(account.state.wallet.core_t1) == cores + 2, "research output is legal existing breakthrough core")
	account.state.owned[identity].level = 10
	account.state.commander.level = 6
	var ascent: Dictionary = account.ascend_preview(identity)
	check(ascent.get("ready", false), "restored core participates in real ascension affordability")
	check(account.ascend_ship(identity, "consume-core").get("ok", false), "existing ascension consumes restored resource")
	check(int(account.state.wallet.core_t1) == cores + 2 - int(ascent.materials.core_t1), "ascension debits same core field")
	# Damaged facility pauses the work clock; repair does not backfill disabled hours.
	check(processing.start("qa-recycler", "civilian_order", 3, "pause-start", {}, T + 6000).ok, "real paid order prepared for damage pause")
	processing.checkpoint(T + 6300)
	home.state().buildings[1].hp = 0
	processing.checkpoint(T + 10000)
	home.state().buildings[1].hp = 100
	progress = processing.overview(T + 10300).jobs.filter(func(row): return row.facility_id == "qa-recycler")[0]
	check(int(progress.work_seconds) == 600, "destroyed facility interval is excluded rather than backfilled after repair")
	# Persistence failure rolls every queue/cost field back.
	var old_path: String = account.save_path
	var blocker: String = OUTPUT + "not-a-directory-%d" % OS.get_process_id()
	FileAccess.open(blocker, FileAccess.WRITE).store_string("intentional failure fixture")
	account.save_path = blocker + "/account.json"
	before = account.state.duplicate(true)
	check(not processing.claim("qa-recycler", "claim-disk-failure", T + 10300).ok, "failed durable output commit reports failure")
	same(before, "failed claim rolls output, claimed count, clocks and request receipt back")
	check(not processing.cancel("qa-recycler", "cancel-disk-failure", T + 10400).ok, "failed durable cancellation commit reports failure")
	same(before, "failed cancellation restores refunds and paid order")
	check(not processing.start("qa-dock", "port_trade", 1, "disk-failure", {}, T + 11000).ok, "failed durable start commit reports failure")
	same(before, "failed persistence restores all debited resources, clock, slot and transaction receipt")
	account.save_path = old_path
	check(account.save_state().ok, "final isolated ledger is valid and durable")
	var reloaded = load("res://scripts/economy.gd").new(old_path)
	check(reloaded.load_state().ok and home._same(account.state, reloaded.state), "save/load roundtrip preserves paid queue and receipts")
	transition_checks()
	check(FileAccess.get_sha256("user://cas_port_v1.json") == formal_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak") == backup_hash, "formal account and backup remain unchanged")
	var report: Dictionary = {"checks": checks, "failures": failures, "formal_sha256": formal_hash, "backup_sha256": backup_hash, "scope": "real isolated account transactions; deliberately synthetic facility/clock fixtures; no UI or Android claim", "version": processing.VERSION}
	FileAccess.open(OUTPUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("HOME_ECONOMY_V2 ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func transition_checks() -> void:
	account = load("res://scripts/economy.gd").new(OUTPUT + "transitions-%d.json" % OS.get_process_id())
	check(account.new_profile().ok and account.load_state().ok, "second isolated account validates generic commit transitions")
	home = load("res://scripts/home_service.gd").new(account)
	home.state().unlocked = true
	home.state().buildings.append({"id": "clock-facility", "kind": "recycler", "level": 1, "hp": 100, "cell": {"x": 3, "y": 4}})
	for key: String in home.RESOURCE_NAMES: home.state().resources[key] = 2000
	processing = load("res://scripts/home_economy_v2.gd").new(home)
	check(processing.start("clock-facility", "civilian_order", 10, "transition-start", {}, T).ok, "transition fixture has one real prepaid queue")
	var before: Dictionary = account.state.duplicate(true)
	account.state.active_run = {"mode": "transition-test"}
	load("res://scripts/home_economy_v2.gd").checkpoint_account_transition(account, before, T + 300)
	check(int(home.state().economy_v2.jobs["clock-facility"].work_seconds) == 300, "departure accrues old idle interval before pausing")
	processing.checkpoint_transition(before, T + 300)
	check(int(home.state().economy_v2.jobs["clock-facility"].work_seconds) == 300, "same transition cannot advance a clock twice")
	check(account._commit(before, "test departure").ok, "transition clock persists in enclosing account transaction")
	before = account.state.duplicate(true)
	account.state.active_run = {}
	load("res://scripts/home_economy_v2.gd").checkpoint_account_transition(account, before, T + 5000)
	var job: Dictionary = home.state().economy_v2.jobs["clock-facility"]
	check(int(job.work_seconds) == 300 and int(job.checkpoint_at) == T + 5000, "return transition drops battle interval and resumes from now")
	before = account.state.duplicate(true)
	home.state().buildings[1].hp = 0
	load("res://scripts/home_economy_v2.gd").checkpoint_account_transition(account, before, T + 5300)
	job = home.state().economy_v2.jobs["clock-facility"]
	check(int(job.work_seconds) == 600, "damage transition settles work before facility became disabled")
	before = account.state.duplicate(true)
	home.state().buildings[1].hp = 100
	processing.checkpoint_transition(before, T + 10000)
	check(int(job.work_seconds) == 600 and int(job.checkpoint_at) == T + 10000, "repair cannot backfill destroyed facility interval")
	before = account.state.duplicate(true)
	home.state().buildings[1].kind = "dock"
	processing.checkpoint_transition(before, T + 10300)
	check(int(job.work_seconds) == 900 and bool(processing.overview(T + 20000).jobs[0].paused), "changing facility kind pauses incompatible recipe")
	before = account.state.duplicate(true)
	home.state().buildings[1].kind = "recycler"
	processing.checkpoint_transition(before, T + 20000)
	check(int(job.work_seconds) == 900, "restoring compatible kind cannot retrospectively complete work")
	before = account.state.duplicate(true)
	processing.checkpoint(T + 20100)
	var settled: int = int(job.work_seconds)
	account.state.active_run = {"mode": "explicit-checkpoint-test"}
	processing.checkpoint_transition(before, T + 20100)
	check(int(job.work_seconds) == settled, "generic hook respects an already advanced explicit checkpoint")
	before = account.state.duplicate(true)
	account.state.active_run = {}
	processing.checkpoint_transition(before, T + 20200)
	before = account.state.duplicate(true)
	home.state().buildings.remove_at(1)
	processing.checkpoint_transition(before, T + 20300)
	check(int(job.work_seconds) == settled + 100 and bool(processing.overview(T + 30000).jobs[0].paused), "deleting facility checkpoints old operation then retains a paused paid order")
	var old_path: String = account.save_path
	var blocker: String = OUTPUT + "transition-blocker-%d" % OS.get_process_id()
	FileAccess.open(blocker, FileAccess.WRITE).store_string("intentional failure fixture")
	account.save_path = blocker + "/account.json"
	before = account.state.duplicate(true)
	account.state.active_run = {"mode": "failed-transition"}
	processing.checkpoint_transition(before, T + 40000)
	check(not account._commit(before, "expected failure").ok, "transition cannot report success before durable save")
	same(before, "failed enclosing commit restores clock, active run and every other account field")
	account.save_path = old_path
	var valid: Dictionary = account.state.duplicate(true)
	home.state().economy_v2.jobs["clock-facility"].wallet_output = {"origins": 1}
	var malformed: Dictionary = account.state.duplicate(true)
	check(not processing.overview(T).get("ok", true) and not processing.claim("clock-facility", "bad-schema", T).ok, "invalid saved output cannot issue recruitment currency or crash rendering")
	same(malformed, "invalid ledger is preserved for repair, never silently rewritten")
	account.state = valid
