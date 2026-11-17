extends SceneTree
## Component checks only. This does not claim boot or GPU loading coverage.
const LoadingScene = preload("res://scenes/ui/loading_screen.tscn")
var checks: int = 0
var failures: Array[String] = []
var retry_count: int = 0
var quit_count: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func frames(count: int = 3) -> void:
	for index in range(count): await process_frame

func run() -> void:
	var loading = LoadingScene.instantiate()
	loading.set_stage("正在读取舰队档案", 0.25)
	root.add_child(loading)
	await frames()
	check(loading.stage_text == "正在读取舰队档案", "stage set before tree survives readiness")
	check(loading.progress_value == 0.25, "only supplied progress is displayed")
	check(loading.mouse_filter == Control.MOUSE_FILTER_STOP, "visible loading blocks input")
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await frames()
		var content: Control = loading.get_node("Center/Content")
		check(loading.size == Vector2(root.get_visible_rect().size), "loading fills viewport at " + str(dimensions))
		check(loading.get_global_rect().encloses(content.get_global_rect()), "text stays inside loading at " + str(dimensions))
	loading.set_stage("正在准备海域")
	var clock_before: float = loading.animation_clock
	await frames(12)
	check(loading.progress_value < 0.0, "unknown loading never invents progress")
	check(loading.animation_clock > clock_before, "unknown loading has live motion")
	loading.set_stage("正在准备页面", 0.73)
	await frames(12)
	check(is_equal_approx(loading.progress_value, 0.73), "waiting never walks progress to completion")
	loading.set_reduced_motion(true)
	clock_before = loading.animation_clock
	await frames(12)
	check(loading.animation_clock == clock_before, "reduced motion stops decorative animation")
	check(loading.get_node("Center/Content/Stage").text == "正在准备页面", "reduced motion preserves readable status")
	loading.show_failure("舰队档案无法读取。原文件已保留，请检查可用备份。")
	await frames()
	check(loading.failed and loading.get_node("Center/Content/Actions").visible, "failed loading exposes actions")
	check(loading.get_node("Center/Content/Message").text.contains("原文件已保留"), "failure explains preserved archive")
	loading.set_stage("晚到的旧任务", 1.0)
	check(loading.get_node("Center/Content/Stage").text == "暂时无法启航", "late progress cannot mask a failure")
	loading.retry_requested.connect(func() -> void: retry_count += 1)
	loading.quit_requested.connect(func() -> void: quit_count += 1)
	loading.get_node("Center/Content/Actions/Retry").pressed.emit()
	loading.get_node("Center/Content/Actions/Quit").pressed.emit()
	check(retry_count == 1 and quit_count == 1, "failure actions emit once without mutating an account")
	loading.hide()
	await frames()
	check(loading.mouse_filter == Control.MOUSE_FILTER_IGNORE and not loading.is_processing(), "hidden loading releases pointer blocking and processing")
	loading.clear_failure()
	loading.set_stage("重新读取舰队档案", -1.0)
	loading.show()
	await frames()
	check(not loading.failed and not loading.get_node("Center/Content/Actions").visible, "clear failure restores loading without stale actions")
	check(loading.get_node("Center/Content/Stage").text == "重新读取舰队档案", "retry has its own current stage")
	loading.queue_free()
	await frames()
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "headless loading control state and layout only; no GPU or boot proof"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/loading-startup"))
	FileAccess.open("res://../artifacts/loading-startup/loading-component.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("LOADING_SCREEN ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
