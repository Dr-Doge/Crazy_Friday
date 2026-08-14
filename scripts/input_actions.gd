class_name InputActions
## 输入映射的唯一定义处。
##
## 本项目 project.godot 里刻意不存 [input] 段:全部动作在运行时用
## physical_keycode 注册(对非 QWERTY 键盘友好)。InputMap 是全局的,
## 重开一局会再次进入,故用 has_action 做幂等守卫。
##
## 要改键位,只需改下面两张表。

## 键盘绑定表:一个动作可绑多个键
const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
	"load_cart": [KEY_R],
	"drive": [KEY_F],
	"locate": [KEY_Q],
	"brace": [KEY_CTRL],
	"char_skill": [KEY_SPACE],
	"debug_time": [KEY_T],
	"dev_mode": [KEY_F1],
	"tutorial_reset": [KEY_F2],
	"debug_sale": [KEY_F3],
	"debug_down": [KEY_F4],
	"restart": [KEY_ENTER],
}

## 鼠标绑定表
const MOUSE_BUTTONS := {
	"elbow": MOUSE_BUTTON_LEFT,
	"use_prop": MOUSE_BUTTON_RIGHT,
}

## 幂等:已注册过则直接返回
static func setup() -> void:
	if InputMap.has_action("move_forward"):
		return
	for action in KEYS:
		for key in KEYS[action]:
			_add_key(action, key)
	for action in MOUSE_BUTTONS:
		_add_mouse(action, MOUSE_BUTTONS[action])

static func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

static func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
