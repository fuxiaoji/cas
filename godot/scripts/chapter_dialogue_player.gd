extends Node
## Local reading controls; never advance or decide a native battle.
var app
var text_label:RichTextLabel
var advance:Callable
var elapsed:=0.0
var hold:=0.0
var automatic:=false
var plain_text:=""
var text_effect:="none"
var characters_per_second:=34.0
var reduced_motion:=false
var _settled:=false

func _ready()->void:
	plain_text=text_label.get_parsed_text()
	text_label.visible_characters=0
	if text_effect in ["tremble","echo"] and not reduced_motion:
		var amplitude:=1.7 if text_effect=="tremble" else 1.0
		text_label.text="[wave amp=%s freq=5.0 connected=1]%s[/wave]"%[amplitude,plain_text.replace("[","[lb]")]
	text_label.set_meta("chapter_text_effect",text_effect if not reduced_motion else "none")

func _visible_count()->int:
	var time:=0.0
	for i in range(plain_text.length()):
		time+=1.0/maxf(15.0,characters_per_second)
		if time>elapsed:return i
		var character:=plain_text.substr(i,1)
		if character in ["。","？","！","…"]:time+=.16
		elif character in ["，","、","；","\n"]:time+=.07
	return plain_text.length()

func _process(delta:float)->void:
	if not is_instance_valid(text_label) or is_instance_valid(app.modal):return
	elapsed+=delta
	var length:=text_label.get_total_character_count()
	text_label.visible_characters=mini(length,_visible_count())
	if text_label.visible_characters>=length:
		hold+=delta
		if hold>=.35:_settle()
		if automatic and hold>=2.2:
			set_process(false)
			advance.call_deferred()

func continue_reading()->void:
	if text_label.visible_characters>=0 and text_label.visible_characters<text_label.get_total_character_count():
		elapsed=1000.0;text_label.visible_characters=-1
		_settle()
		return
	set_process(false);advance.call()

func _settle()->void:
	if _settled:return
	_settled=true
	var visible:=text_label.visible_characters
	text_label.text=plain_text.replace("[","[lb]")
	text_label.visible_characters=visible
	text_label.set_meta("chapter_effect_settled",true)

func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ENTER] and not is_instance_valid(app.modal):
		get_viewport().set_input_as_handled()
		continue_reading()
