extends Control
## F6 presentation-only gallery. No account, world simulator, or random map is loaded.
class DemoRoster extends RefCounted:
	func roster() -> Array:
		return [{"chibi_generated":"res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png"}]

@onready var page:Control=$Backdrop
@onready var transition=$PageTransition
@onready var heading:Label=$Backdrop/Center/Content/Heading
@onready var caption:Label=$Backdrop/Center/Content/Caption
@onready var cloud_button:Button=$Backdrop/Center/Content/Buttons/CloudWave
@onready var iris_button:Button=$Backdrop/Center/Content/Buttons/CircularIris
@onready var sails_button:Button=$Backdrop/Center/Content/Buttons/PaperSails
@onready var motion:CheckButton=$Backdrop/Center/Content/ReducedMotion
var page_motion:=true
var screen:="harbor"
var economy:=DemoRoster.new()

func _ready() -> void:
	cloud_button.pressed.connect(_change_page.bind(0))
	iris_button.pressed.connect(_change_page.bind(1))
	sails_button.pressed.connect(_change_page.bind(2))
	motion.toggled.connect(func(off:bool):set_meta("reduced_motion",off))

func _change_page(kind:int) -> void:
	if transition.is_busy():return
	var previous:=screen
	var next:="voyage" if screen=="harbor" else "harbor"
	transition.capture_previous(self,next)
	screen=next
	$Backdrop/Sea.color=Color("476d83") if screen=="voyage" else Color("173f54")
	heading.text="启程，迎着海风。" if screen=="voyage" else "欢迎回港，指挥官。"
	caption.text="全屏遮盖后，展开下一幕。" if screen=="voyage" else "这是一间不写入存档的转场演示室。"
	set_meta("transition_style",kind)
	transition.play(self,page,previous,next)
