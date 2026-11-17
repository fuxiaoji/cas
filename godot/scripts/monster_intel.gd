@tool
extends Control
## Reads visible contacts and public telegraphs only; no enemy authority or commands.
const Design = preload("res://scripts/ui_design.gd")
var observed_id := ""
var signature := ""
var details_open:bool=false

func _ready() -> void:
	theme = Design.theme()
	$Card.add_theme_stylebox_override("panel", Design.box(Color(.035,.105,.15,.94), 8, Color(.39,.62,.65,.65)))
	$Card/Margin/Rows/Health.add_theme_stylebox_override("background", Design.box(Color(.15,.26,.29), 2))
	$Card/Margin/Rows/Health.add_theme_stylebox_override("fill", Design.box(Color("eead88"), 2))
	$DetailPanel.add_theme_stylebox_override("panel",Design.box(Color(.965,.98,.98,.99),9,Color(.5,.7,.72)))
	for label in $DetailPanel.find_children("*","Label",true,false):label.add_theme_color_override("font_color",Design.INK)
	Design.apply_button($Card/Margin/Rows/Header/Details,false,true)
	$Card/Margin/Rows/Header/Details.add_theme_color_override("font_color",Color("eed59c"))
	Design.apply_button($DetailPanel/Margin/Rows/Header/Close,false,true)
	$Card/Margin/Rows/Header/Details.pressed.connect(func():details_open=true;$DetailPanel.show();$Card.hide();_focus_details(true))
	$DetailPanel/Margin/Rows/Header/Close.pressed.connect(func():details_open=false;$DetailPanel.hide();$Card.show();_focus_details(false))
	if not Engine.is_editor_hint():hide()

func update_observation(view: Dictionary, selected: String, cinematic: bool, suppress_automatic: bool=false) -> void:
	var salvage: Dictionary = view.get("salvage", {})
	var open_intel:bool=view.get("contacts",[]).any(func(row):return row.has("intelligence"))
	if cinematic or (not salvage.has("adventure") and not open_intel):
		hide(); details_open=false;_focus_details(false); observed_id = ""; return
	var chosen: Dictionary = {}
	var warning: Dictionary = {}
	for contact in view.get("contacts", []):
		if str(contact.get("id", "")) == selected and (contact.has("attack") or contact.has("intelligence")):
			chosen = contact; break
	# A real, visible attack may surface its counter even before the player selects the source.
	if chosen.is_empty() and not suppress_automatic:
		for entry in salvage.get("telegraphs", []):
			if not preload("res://scripts/monster_renderer.gd").threatens_fleet(view,entry):continue
			for contact in view.get("contacts", []):
				if str(contact.get("id", "")) == str(entry.get("source_contact", "")) and contact.has("attack"):
					chosen = contact; warning = entry; break
			if not chosen.is_empty():break
	if chosen.is_empty():
		hide(); details_open=false;_focus_details(false); observed_id = ""; return
	if observed_id!=str(chosen.get("id","")):details_open=false;_focus_details(false)
	observed_id = str(chosen.get("id", ""))
	$DetailPanel.visible=details_open and chosen.has("intelligence")
	$Card.visible=not $DetailPanel.visible
	$Card/Margin/Rows/Header/Details.visible=chosen.has("intelligence")
	var next_signature := str(hash([chosen, warning]))
	show()
	if next_signature == signature:return
	signature = next_signature
	var attack: Dictionary = chosen.get("attack", {})
	var current := maxf(0.0, float(chosen.get("health", 0)))
	var maximum := maxf(1.0, float(chosen.get("max_health", 1)))
	$Card/Margin/Rows/Header/Name.text = str(chosen.get("name", "异种"))
	$Card/Margin/Rows/Header/Vital.text = "%d / %d" % [ceili(current), ceili(maximum)]
	$Card/Margin/Rows/Health.value = current / maximum * 100.0
	var state := str(attack.get("state", "approach"))
	var seconds := maxi(0, ceili(float(attack.get("seconds", 0))))
	var state_text := "蓄力 %ds" % seconds if state == "windup" else "恢复 %ds" % seconds if state == "recover" else "寻找目标"
	$Card/Margin/Rows/Attack.text = "%s  ·  %s" % [str(attack.get("label", "攻击")), state_text]
	$Card/Margin/Rows/Attack.visible=not attack.is_empty()
	$Card/Margin/Rows/Attack.modulate = Color("ffc2a2") if state == "windup" else Color("d3e4e3")
	$Card/Margin/Rows/Counter.text = str(warning.get("counter", attack.get("counter", "离开预警区域")))
	$Card/Margin/Rows/Counter.visible=not attack.is_empty()

	if chosen.has("intelligence"):_update_details(chosen)

func _update_details(contact:Dictionary)->void:
	var info:Dictionary=contact.intelligence
	var box:Node=$DetailPanel/Margin/Rows/Content/Stats
	$DetailPanel/Margin/Rows/Header/Title.text=str(contact.get("name","实体情报"))
	box.get_node("HP").text="耐久\n%d / %d"%[ceili(float(contact.get("health",0))),ceili(float(contact.get("max_health",0)))]
	box.get_node("Speed").text="最高航速\n%s 节"%str(info.get("speed_max","—"))
	box.get_node("Damage").text="攻击伤害\n%s"%str(info.get("attack_damage","—"))
	box.get_node("Range").text="攻击距离\n%s 米"%str(info.get("attack_range","—"))
	box.get_node("Cooldown").text="攻击间隔\n%s 秒"%str(info.get("attack_cooldown","—"))
	box.get_node("Armor").text="装甲\n%s"%str(info.get("armor","—"))
	var weak:Variant=info.get("weaknesses",[])
	var summary:String=" / ".join(PackedStringArray(weak)) if weak is Array else str(weak)
	$DetailPanel/Margin/Rows/Weakness.text="弱点  ·  "+summary
	$DetailPanel/Margin/Rows/Response.text=str(contact.get("attack",{}).get("counter","观察已经公布的攻击预警"))
	$DetailPanel/Margin/Rows/Response.visible=$DetailPanel/Margin/Rows/Response.text!=summary
	var frames:SpriteFrames=CasEnemyAnimation.frames_for(str(contact.get("visualType",contact.get("species",""))),{})
	$DetailPanel/Margin/Rows/Content/Art.texture=frames.get_frame_texture("idle",0) if frames!=null else null

func _focus_details(value:bool)->void:
	var guide:Control=get_tree().root.find_child("ChapterBattleGuide",true,false)
	if guide==null:return
	guide.set_meta("enemy_details_open",value)
	if value:guide.hide()
	else:guide.show()
