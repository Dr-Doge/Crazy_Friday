class_name Hud extends CanvasLayer
## 白盒HUD:计时/阶段、代购清单、体力与失衡条、交互提示、超市广播、结算面板。
## 开始界面与联机大厅在 start_menu.gd,本类只做信号转发。

signal npc_count_changed(count: int)
signal no_cd_changed(on: bool)   # 开发者模式:所有技能无冷却
signal start_game_pressed
signal start_tutorial_pressed
signal host_pressed
signal join_pressed(ip: String)
signal begin_pressed          # 主机大厅:开始对局
signal leave_room_pressed     # 大厅:离开房间
signal quit_pressed           # 主界面:退出游戏

var time_label: Label
var phase_label: Label
var score_label: Label
var list_vbox: VBoxContainer
var list_rows: Array[RichTextLabel] = []
var dev_panel: PanelContainer
var npc_slider: HSlider
var npc_count_label: Label
var no_cd_check: CheckBox     # 开发者模式:所有技能无 CD
var skill_label: Label
var cd_wheel: Control         # 角色技能冷却圆环(塞尔达体力轮风格)
var _cd_ratio := 0.0
var _cd_ready := true
var _cd_pulse := 0.0
var _cd_fade := 0.0           # ready后渐隐计时
var marquee: Label            # 大喇叭滚动横幅
var menu: StartMenu           # 开始界面 + 联机大厅
var tutorial_label: Label     # 教学指引大字
var controls_hint: Label      # 常规局右上完整键位表；教学中由逐步指引替代
var prompt_label: Label
var broadcast_panel: PanelContainer
var broadcast_label: Label
var stamina_fill: ColorRect
var imbalance_fill: ColorRect
var channel_bg: ColorRect
var channel_fill: ColorRect
var result_overlay: Control
var result_vbox: VBoxContainer
var threat_layer: Control          # 「余光」被动:屏幕边缘威胁方向箭头
var threat_arrows: Array[Label] = []
var item_wheel: Control            # 右下购物车商品投掷轮盘
var crosshair: Control             # 屏幕中心白点准星
var obscure_overlay: Control       # 散落遮挡类商品的本机视野效果
var _wheel_items: Array = []
var _wheel_selected := 0
var _wheel_available := false
var _tutorial_room := -1
var _obscured := false
## 局内 HUD 元素:开始界面阶段一律隐藏(开局前显示计时与体力条毫无意义)
var _ingame_nodes: Array[Control] = []

var _bc_queue: Array = []
var _mq_active := false
var _mq_time := 0.0

const BAR_W := 440.0      # 加长加粗的状态条
const BAR_H := 24.0
const MQ_SPEED := 480.0   # 横幅滚动速度(像素/秒)
const ITEM_RING_INNER_RADIUS := 270.0
const ITEM_RING_OLD_OUTER_RADIUS := 354.0
## 外圈直径扩大为旧版1.5倍；内圈直径保持不变。
const ITEM_RING_OUTER_RADIUS := ITEM_RING_OLD_OUTER_RADIUS * 1.5
const ITEM_RING_RADIUS := (ITEM_RING_INNER_RADIUS + ITEM_RING_OUTER_RADIUS) * 0.5
const ITEM_RING_GAP := ITEM_RING_OUTER_RADIUS - ITEM_RING_INNER_RADIUS
## 商品圆正好嵌入环带，预留描边和框选线宽。
const ITEM_NODE_RADIUS := ITEM_RING_GAP * 0.5 - 12.0
const ITEM_RING_SIZE := ITEM_RING_OUTER_RADIUS + 22.0
const ITEM_SELECTOR_ANGLE := -PI * 0.75
const OBSCURE_SCREEN_ALPHA := 0.38
const OBSCURE_BLOB_ALPHA := 0.68

func _ready() -> void:
	# 开始界面暂停游戏树时,HUD(含菜单按钮)仍需响应
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Catalog.ui_font()
	theme.default_font_size = 30
	root.theme = theme
	add_child(root)

	# 顶部:倒计时+阶段(整宽容器+文字居中,避开CENTER锚点的偏移问题)
	var top := VBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 10)
	time_label = Label.new()
	time_label.text = "5:00"
	time_label.add_theme_font_size_override("font_size", 68)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(time_label)
	phase_label = Label.new()
	phase_label.text = "开门冲刺"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	top.add_child(phase_label)

	# 超市大喇叭:乡土大广告精神污染大红字,破屏滚动播报
	marquee = Label.new()
	marquee.text = ""
	marquee.add_theme_font_size_override("font_size", 84)
	marquee.add_theme_color_override("font_color", Color(1, 0.08, 0.03))
	marquee.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.15))
	marquee.add_theme_constant_override("outline_size", 22)
	marquee.visible = false
	marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(marquee)
	marquee.position = Vector2(4000, 118)

	# 左上:代购清单(本局要抢齐的单子)
	var list_panel := PanelContainer.new()
	var lv := VBoxContainer.new()
	list_panel.add_child(lv)
	var title := Label.new()
	title.text = "📋 代购清单"
	title.add_theme_font_override("font", Catalog.ui_font_bold())
	title.add_theme_font_size_override("font_size", 44)
	lv.add_child(title)
	list_vbox = VBoxContainer.new()
	lv.add_child(list_vbox)
	score_label = Label.new()
	score_label.text = "已到手货值:0"
	score_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	lv.add_child(score_label)
	root.add_child(list_panel)
	list_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 14)

	# 底部:技能状态+体力/失衡
	var bars := VBoxContainer.new()
	skill_label = Label.new()
	skill_label.text = "Q 找货雷达:就绪"
	skill_label.add_theme_font_size_override("font_size", 24)
	skill_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bars.add_child(skill_label)
	# 技能冷却圆环(塞尔达体力轮风格:满时淡隐,cd中亮起并随进度消减)
	cd_wheel = Control.new()
	cd_wheel.custom_minimum_size = Vector2(0, 56)
	cd_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_wheel.draw.connect(_draw_cd_wheel)
	bars.add_child(cd_wheel)
	stamina_fill = _make_bar(bars, "体力槽 (Shift冲刺消耗)", Color(0.35, 0.85, 0.4))
	imbalance_fill = _make_bar(bars, "失衡值 (满100倒地翻车)", Color(0.95, 0.45, 0.2))
	var bars_wrap := CenterContainer.new()
	bars_wrap.add_child(bars)
	root.add_child(bars_wrap)
	bars_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 20)
	# 整体左移,给右下角加大的键位表让位
	bars_wrap.offset_left -= 340
	bars_wrap.offset_right -= 340

	# 交互提示+长按进度
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_override("font", Catalog.ui_font_bold())
	prompt_label.add_theme_font_size_override("font_size", 38)
	prompt_label.add_theme_color_override("font_color", Color(1, 0.28, 0.22))
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	prompt_label.add_theme_constant_override("outline_size", 8)
	root.add_child(prompt_label)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 232)
	channel_bg = ColorRect.new()
	channel_bg.color = Color(0, 0, 0, 0.5)
	channel_bg.custom_minimum_size = Vector2(220, 12)
	channel_bg.visible = false
	var ch_wrap := CenterContainer.new()
	ch_wrap.add_child(channel_bg)
	root.add_child(ch_wrap)
	ch_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 200)
	channel_fill = ColorRect.new()
	channel_fill.color = Color(1, 0.85, 0.3)
	channel_fill.position = Vector2(2, 2)
	channel_fill.size = Vector2(0, 8)
	channel_bg.add_child(channel_fill)

	# 右下:操作说明(精简三行)
	controls_hint = Label.new()
	controls_hint.text = "F 推/放车 · E 交互(准星锁货/长按搜偷) · R 装车 · Shift 冲刺\n驾驶时滚轮选商品 · 按住右键近距观察/驾驶时松开投掷 · 左键 肘击 · Q 雷达\n空格 角色技能 · Ctrl 稳住 · Esc鼠标 · F1 开发者"
	controls_hint.add_theme_font_override("font", Catalog.ui_font_bold())
	controls_hint.add_theme_font_size_override("font_size", 30)
	controls_hint.add_theme_color_override("font_color", Color(1, 0.25, 0.18))
	controls_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	controls_hint.add_theme_constant_override("outline_size", 6)
	root.add_child(controls_hint)
	controls_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	controls_hint.offset_top += 145
	controls_hint.offset_bottom += 145

	# 完整圆环的圆心贴住屏幕右下角，视口只露出左上四分之一。
	# 商品按整圆循环排列，固定金框内的商品就是右键投掷目标。
	item_wheel = Control.new()
	item_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_wheel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	item_wheel.offset_left = -ITEM_RING_SIZE
	item_wheel.offset_top = -ITEM_RING_SIZE
	item_wheel.offset_right = 0
	item_wheel.offset_bottom = 0
	item_wheel.draw.connect(_draw_item_wheel)
	root.add_child(item_wheel)

	# 散落物范围内的视野干扰；置于轮盘之上、准星之下，仍保留基本瞄准能力。
	obscure_overlay = Control.new()
	obscure_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	obscure_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obscure_overlay.draw.connect(_draw_obscure_overlay)
	root.add_child(obscure_overlay)

	# 极简准星：只保留屏幕中心白点和一圈暗边，避免遮挡商品标签。
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)

	# 「余光」威胁箭头层(马德胜被动):按方向摆在屏幕边缘,只给信息不给数值
	threat_layer = Control.new()
	threat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	threat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(threat_layer)
	for i in CharSkills.THREAT_MAX:
		var ar := Label.new()
		ar.text = "▲"
		ar.add_theme_font_size_override("font_size", 76)
		ar.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
		ar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		ar.add_theme_constant_override("outline_size", 10)
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ar.visible = false
		threat_layer.add_child(ar)
		threat_arrows.append(ar)

	# 结算面板
	result_overlay = Control.new()
	result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_overlay.add_child(dim)
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(660, 0)
	result_vbox = VBoxContainer.new()
	result_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rp.add_child(result_vbox)
	var rp_wrap := CenterContainer.new()
	rp_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	rp_wrap.add_child(rp)
	result_overlay.add_child(rp_wrap)
	root.add_child(result_overlay)

	# HUD纯展示,全部放行鼠标事件(肘击用左键,走_unhandled_input)
	_set_mouse_ignore(root)

	# 开发者面板(F1开关;在mouse_ignore之后创建,滑块保持可交互)
	dev_panel = PanelContainer.new()
	var dv := VBoxContainer.new()
	dev_panel.add_child(dv)
	var dtitle := Label.new()
	dtitle.text = "🔧 开发者模式"
	dtitle.add_theme_font_size_override("font_size", 32)
	dtitle.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	dv.add_child(dtitle)
	npc_count_label = Label.new()
	npc_count_label.text = "NPC数量: 8"
	dv.add_child(npc_count_label)
	npc_slider = HSlider.new()
	npc_slider.min_value = 0
	npc_slider.max_value = 10
	npc_slider.step = 1
	npc_slider.value = 8
	npc_slider.custom_minimum_size = Vector2(340, 36)
	npc_slider.value_changed.connect(func(v: float) -> void:
		npc_count_label.text = "NPC数量: %d" % int(v)
		npc_count_changed.emit(int(v))
	)
	dv.add_child(npc_slider)
	# 所有技能无冷却
	no_cd_check = CheckBox.new()
	no_cd_check.text = "所有技能无 CD 冷却"
	no_cd_check.button_pressed = Main.dev_no_cd
	no_cd_check.add_theme_font_size_override("font_size", 22)
	no_cd_check.toggled.connect(func(on: bool) -> void: no_cd_changed.emit(on))
	dv.add_child(no_cd_check)
	var dhint := Label.new()
	dhint.text = "F1 关闭面板"
	dhint.add_theme_font_size_override("font_size", 18)
	dhint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	dv.add_child(dhint)
	dev_panel.visible = false
	root.add_child(dev_panel)
	dev_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	dev_panel.offset_top = 470

	# 教学指引大字(教学模式用)
	tutorial_label = Label.new()
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.add_theme_font_override("font", Catalog.ui_font_bold())
	tutorial_label.add_theme_font_size_override("font_size", 40)
	tutorial_label.add_theme_color_override("font_color", Color(0.6, 1, 0.7))
	tutorial_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tutorial_label.add_theme_constant_override("outline_size", 10)
	tutorial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_label.visible = false
	root.add_child(tutorial_label)
	tutorial_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 200)

	# 开始界面 + 联机大厅(在 mouse_ignore 之后创建,保持可交互)
	menu = StartMenu.new()
	menu.start_game_pressed.connect(func() -> void: start_game_pressed.emit())
	menu.start_tutorial_pressed.connect(func() -> void: start_tutorial_pressed.emit())
	menu.host_pressed.connect(func() -> void: host_pressed.emit())
	menu.join_pressed.connect(func(ip: String) -> void: join_pressed.emit(ip))
	menu.begin_pressed.connect(func() -> void: begin_pressed.emit())
	menu.leave_room_pressed.connect(func() -> void: leave_room_pressed.emit())
	menu.quit_pressed.connect(func() -> void: quit_pressed.emit())
	menu.npc_changed.connect(func(n: int) -> void: npc_count_changed.emit(n))
	root.add_child(menu)

	# 菜单阶段隐藏所有局内 HUD(逐个 append:数组字面量无法直接赋给 Array[Control])
	for n in [top, marquee, list_panel, bars_wrap, prompt_label, ch_wrap, controls_hint, item_wheel, obscure_overlay, crosshair, threat_layer]:
		_ingame_nodes.append(n)
	_set_ingame_visible(false)

func _set_ingame_visible(on: bool) -> void:
	for n in _ingame_nodes:
		if is_instance_valid(n):
			n.visible = on

# ---------------------------------------------------------------- 菜单转发

func hide_menu() -> void:
	menu.visible = false
	_set_ingame_visible(true)

func set_menu_status(t: String) -> void:
	menu.set_status(t)

## 建房后:锁住"再建房",并把界面切到房间页
func lock_menu_for_host() -> void:
	menu.lock_for_host()

## 加入后:等待连接期间锁死操作
func lock_menu_for_join() -> void:
	menu.lock_for_join()

## 联机失败/离开房间:菜单退回联机页,解锁按钮
func reset_menu_network() -> void:
	menu.reset_network()

## 大厅成员变化:刷新成员列表(每行显示昵称、配色与角色)。
## members: [{name, color, char}],下标即座位号(0=房主)
func set_lobby(members: Array, is_host: bool) -> void:
	menu.show_lobby(members, is_host)

# ---------------------------------------------------------------- 局内 HUD

## 「余光」:把威胁方向画到屏幕边缘。threats 来自 CharSkills.threats_for()
func set_threats(threats: Array, cam_yaw: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var radius := minf(vp.x, vp.y) * 0.36
	for i in threat_arrows.size():
		var ar := threat_arrows[i]
		if i >= threats.size():
			ar.visible = false
			continue
		var t: Dictionary = threats[i]
		# 世界朝向→ 相对镜头的屏幕角度(0=正上方即镜头正前方)
		var rel: float = wrapf(float(t["yaw"]) - cam_yaw, -PI, PI)
		var dir := Vector2(sin(rel), -cos(rel))
		ar.visible = true
		ar.reset_size()
		ar.position = center + dir * radius - ar.size * 0.5
		ar.pivot_offset = ar.size * 0.5
		ar.rotation = atan2(dir.y, dir.x) + PI * 0.5
		var imminent: bool = bool(t["imminent"])
		var near: float = clampf(1.0 - float(t["dist"]) / CharSkills.THREAT_RANGE, 0.2, 1.0)
		ar.add_theme_color_override("font_color",
				Color(1, 1, 1) if imminent else Color(1, 0.3, 0.22, 0.35 + 0.65 * near))
		ar.scale = Vector2.ONE * (1.25 if imminent else 0.85 + 0.3 * near)

func set_tutorial_text(t: String) -> void:
	tutorial_label.visible = t != ""
	tutorial_label.text = t

func set_tutorial_room(index: int) -> void:
	_tutorial_room = index
	controls_hint.visible = false
	item_wheel.visible = index >= 3 and _wheel_available
	marquee.visible = false
	_bc_queue.clear()
	_mq_active = false

## 技能冷却:ratio = char_cd / skill_cd (0=就绪,1=满冷却)
func set_skill_cd(ratio: float) -> void:
	_cd_ratio = ratio
	_cd_ready = ratio < 0.01
	if _cd_ready and _cd_fade < 2.0:
		_cd_fade += 0.016
	else:
		_cd_fade = 0.0
	cd_wheel.queue_redraw()

## 塞尔达体力轮风格:环形冷却条。满时淡隐,cd中随剩余时间消减
func _draw_cd_wheel() -> void:
	var ctrl := cd_wheel
	var center := Vector2(ctrl.size.x * 0.5, 28)
	var r := 22.0          # 外半径
	var w := 4.5            # 环宽
	var inner := r - w

	# 底色环(深灰,半透明)
	ctrl.draw_arc(center, r, 0, TAU, 48, Color(0.12, 0.12, 0.12, 0.55), w, true)

	if _cd_ready:
		# 就绪:满环绿色,随 fade 渐隐,微微呼吸
		var a := clampf(1.0 - _cd_fade * 0.5, 0.15, 1.0)
		var pulse := 1.0 + 0.04 * sin(_cd_pulse * 3.5)
		ctrl.draw_arc(center, r, 0, TAU, 48, Color(0.25, 0.88, 0.45, a), w * pulse, true)
	else:
		# 冷却中:弧从正上方顺时针消减,颜色绿→黄→红
		var fill := 1.0 - _cd_ratio
		var from := -PI * 0.5
		var to := from + fill * TAU
		var hue := fill * 0.33   # 0→0.33 (红→绿)
		var c := Color.from_hsv(hue, 0.75, 0.92)
		ctrl.draw_arc(center, r, from, to, 48, c, w, true)

func set_skill(text: String, ready: bool) -> void:
	skill_label.text = text
	skill_label.add_theme_color_override("font_color",
			Color(0.55, 0.95, 0.6) if ready else Color(0.75, 0.75, 0.75))

func set_item_wheel(items: Array[Item], selected: int, available: bool) -> void:
	_wheel_items = items
	_wheel_selected = posmod(selected, items.size()) if not items.is_empty() else 0
	_wheel_available = available
	var tutorial_allows := Main.instance == null or not Main.instance.tutorial or _tutorial_room >= 3
	item_wheel.visible = available and tutorial_allows
	item_wheel.queue_redraw()

func _draw_crosshair() -> void:
	var c := crosshair.size * 0.5
	crosshair.draw_circle(c, 5.5, Color(0, 0, 0, 0.72))
	crosshair.draw_circle(c, 3.0, Color(1, 1, 1, 0.98))

func set_obscured(active: bool) -> void:
	if _obscured == active:
		return
	_obscured = active
	obscure_overlay.queue_redraw()

func _draw_obscure_overlay() -> void:
	if not _obscured:
		return
	var size := obscure_overlay.size
	var center := size * 0.5
	obscure_overlay.draw_rect(Rect2(Vector2.ZERO, size),
			Color(0.10, 0.085, 0.055, OBSCURE_SCREEN_ALPHA), true)
	var blobs := [
		[Vector2(0.0, 0.0), 0.30],
		[Vector2(-0.30, -0.20), 0.28], [Vector2(0.28, -0.22), 0.27],
		[Vector2(-0.30, 0.23), 0.29], [Vector2(0.31, 0.24), 0.28],
		[Vector2(-0.48, 0.02), 0.25], [Vector2(0.49, -0.01), 0.25],
		[Vector2(-0.05, -0.44), 0.25], [Vector2(0.06, 0.44), 0.26],
	]
	for entry in blobs:
		var p: Vector2 = center + Vector2(entry[0].x * size.x, entry[0].y * size.y)
		var r: float = float(entry[1]) * minf(size.x, size.y)
		obscure_overlay.draw_circle(p, r, Color(0.34, 0.30, 0.20, OBSCURE_BLOB_ALPHA))
		obscure_overlay.draw_circle(p + Vector2(r * 0.12, -r * 0.08), r * 0.72,
				Color(0.76, 0.66, 0.43, OBSCURE_BLOB_ALPHA * 0.58))
		obscure_overlay.draw_arc(p, r, 0, TAU, 40,
				Color(0.94, 0.82, 0.54, 0.58), 8.0, true)

func _draw_item_wheel() -> void:
	var c := item_wheel.size # 圆心即屏幕右下角
	# 只绘制左上象限；其余三象限在屏幕外，仅作为循环排布空间存在。
	item_wheel.draw_arc(c, ITEM_RING_RADIUS, PI, PI * 1.5, 64,
			Color(0.015, 0.02, 0.035, 0.9), ITEM_RING_GAP, true)
	item_wheel.draw_arc(c, ITEM_RING_INNER_RADIUS, PI, PI * 1.5, 64,
			Color(1, 0.7, 0.08, 1.0), 9.0, true)
	item_wheel.draw_arc(c, ITEM_RING_OUTER_RADIUS, PI, PI * 1.5, 64,
			Color(1, 0.48, 0.04, 1.0), 9.0, true)
	if _wheel_items.is_empty():
		item_wheel.draw_string(Catalog.ui_font_bold(), c + Vector2(-350, -205), "购物车无商品",
				HORIZONTAL_ALIGNMENT_CENTER, 250, 20, Color(0.75, 0.75, 0.75))
		return
	var count := _wheel_items.size()
	# 放大后的商品正好填满宽环带；可见象限容纳3个，更多商品随滚轮循环进入。
	var visible_count := mini(count, 3)
	var left_count := mini(1, int(ceil((visible_count - 1) * 0.5)))
	var right_count := visible_count - 1 - left_count
	var arc_step := (PI * 0.5 - 0.32) / 2.0
	for offset in range(-left_count, right_count + 1):
		var idx := posmod(_wheel_selected + offset, count)
		var angle := ITEM_SELECTOR_ANGLE + float(offset) * arc_step
		var p := c + Vector2(cos(angle), sin(angle)) * ITEM_RING_RADIUS
		var chosen := idx == _wheel_selected
		var node_radius := ITEM_NODE_RADIUS if chosen else ITEM_NODE_RADIUS - 8.0
		var effect_color := Catalog.prop_effect_color(_wheel_items[idx].item_id)
		item_wheel.draw_circle(p, node_radius,
				effect_color.darkened(0.18) if chosen else effect_color.darkened(0.72))
		item_wheel.draw_arc(p, node_radius, 0, TAU, 40,
				effect_color.lightened(0.28) if chosen else effect_color.darkened(0.18), 7.0, true)
		_draw_prop_type_icon(p + Vector2(0, -42), Catalog.prop_kind(_wheel_items[idx].item_id),
				effect_color.lightened(0.28), 23.0 if chosen else 19.0)
		var short_name: String = str(_wheel_items[idx].display_name).left(4)
		var text_width := node_radius * 1.65
		item_wheel.draw_string(Catalog.ui_font_bold(), p + Vector2(-text_width * 0.5, 18), short_name,
				HORIZONTAL_ALIGNMENT_CENTER, text_width, 23 if chosen else 20, Color.WHITE)
		var type_label := Catalog.prop_effect_short(_wheel_items[idx].item_id)
		item_wheel.draw_string(Catalog.ui_font_bold(), p + Vector2(-text_width * 0.5, 49), type_label,
				HORIZONTAL_ALIGNMENT_CENTER, text_width, 17 if chosen else 15, effect_color.lightened(0.32))
	# 固定框选位：滚轮改变商品角度，停在框里的商品就是当前弹药。
	var selector := c + Vector2(cos(ITEM_SELECTOR_ANGLE), sin(ITEM_SELECTOR_ANGLE)) * ITEM_RING_RADIUS
	var selector_half := Vector2(ITEM_NODE_RADIUS + 11.0, ITEM_NODE_RADIUS + 11.0)
	var selector_rect := Rect2(selector - selector_half, selector_half * 2.0)
	item_wheel.draw_rect(selector_rect, Color(1, 0.78, 0.18, 0.12), true)
	item_wheel.draw_rect(selector_rect, Color(1, 0.88, 0.18, 1.0), false, 8.0)
	var selected_item: Item = _wheel_items[_wheel_selected]
	var title := selected_item.display_name.left(9)
	var selected_color := Catalog.prop_effect_color(selected_item.item_id)
	var detail := "【%s】 · %d失衡" % [Catalog.prop_effect_name(selected_item.item_id), int(Catalog.throw_imbalance(selected_item.item_id))]
	var info_rect := Rect2(selector + Vector2(-190, -238), Vector2(380, 88))
	item_wheel.draw_rect(info_rect, Color(0.03, 0.04, 0.065, 0.9), true)
	item_wheel.draw_rect(info_rect, selected_color, false, 6.0)
	item_wheel.draw_line(info_rect.position + Vector2(190, 88), selector - Vector2(0, ITEM_NODE_RADIUS + 12.0), selected_color, 7.0)
	_draw_prop_type_icon(info_rect.position + Vector2(32, 27), Catalog.prop_kind(selected_item.item_id), selected_color, 16.0)
	item_wheel.draw_string(Catalog.ui_font_bold(), info_rect.position + Vector2(12, 35), title,
			HORIZONTAL_ALIGNMENT_CENTER, 356, 25, selected_color.lightened(0.35) if _wheel_available else Color(0.65, 0.65, 0.65))
	item_wheel.draw_string(Catalog.ui_font(), info_rect.position + Vector2(12, 68), detail,
			HORIZONTAL_ALIGNMENT_CENTER, 356, 17, Color.WHITE if _wheel_available else Color(0.6, 0.6, 0.6))

func _draw_prop_type_icon(center: Vector2, kind: String, color: Color, radius: float) -> void:
	match kind:
		Catalog.PROP_BURST:
			item_wheel.draw_circle(center, radius * 0.28, color)
			for i in 8:
				var dir := Vector2.from_angle(TAU * float(i) / 8.0)
				item_wheel.draw_line(center + dir * radius * 0.42,
						center + dir * radius, color, maxf(2.0, radius * 0.14), true)
		Catalog.PROP_WET:
			var points := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.72, radius * 0.25),
				center + Vector2(0, radius),
				center + Vector2(-radius * 0.72, radius * 0.25),
			])
			item_wheel.draw_colored_polygon(points, color)
		Catalog.PROP_SCATTER:
			item_wheel.draw_circle(center + Vector2(-radius * 0.38, radius * 0.14), radius * 0.46, color)
			item_wheel.draw_circle(center + Vector2(radius * 0.34, radius * 0.08), radius * 0.52, color)
			item_wheel.draw_circle(center + Vector2(0, -radius * 0.34), radius * 0.48, color)
		Catalog.PROP_TASER:
			var bolt := PackedVector2Array([
				center + Vector2(radius * 0.15, -radius),
				center + Vector2(-radius * 0.55, radius * 0.05),
				center + Vector2(-radius * 0.05, radius * 0.02),
				center + Vector2(-radius * 0.28, radius),
				center + Vector2(radius * 0.62, -radius * 0.2),
				center + Vector2(radius * 0.12, -radius * 0.18),
			])
			item_wheel.draw_colored_polygon(bolt, color)

func set_npc_count_display(n: int) -> void:
	npc_slider.set_value_no_signal(n)
	npc_count_label.text = "NPC数量: %d" % n
	if menu != null:
		menu.set_npc_display(n)

func _set_mouse_ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_set_mouse_ignore(c)

func _make_bar(parent: Control, text: String, color: Color) -> ColorRect:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", Catalog.ui_font_bold())
	lb.add_theme_font_size_override("font_size", 26)
	lb.add_theme_color_override("font_color", color.lightened(0.25))
	parent.add_child(lb)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.custom_minimum_size = Vector2(BAR_W, BAR_H)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(0, BAR_H - 4.0)
	bg.add_child(fill)
	return fill

func _process(delta: float) -> void:
	# 截图调试口(挪到常驻层:开始界面暂停时也能截)
	if Main.instance != null and Main.instance._shot_path != "" and Engine.get_frames_drawn() > 120:
		var img := get_viewport().get_texture().get_image()
		img.save_png(Main.instance._shot_path)
		Main.instance._shot_path = ""
		get_tree().quit()
	_mq_time += delta
	_cd_pulse += delta
	if is_instance_valid(cd_wheel):
		cd_wheel.queue_redraw()
	if _mq_active:
		# 破屏滚动+轻微歪扭抖动(精神污染)
		marquee.position.x -= MQ_SPEED * delta
		marquee.pivot_offset = marquee.size * 0.5
		marquee.rotation = sin(_mq_time * 7.0) * 0.022
		marquee.scale = Vector2.ONE * (1.0 + 0.05 * sin(_mq_time * 9.0))
		if marquee.position.x < -marquee.size.x - 60.0:
			_mq_active = false
			marquee.visible = false
			marquee.rotation = 0.0
	elif not _bc_queue.is_empty():
		var text: String = _bc_queue.pop_front()
		marquee.text = "★超市大喇叭★ %s ★★" % text
		marquee.reset_size()
		marquee.visible = true
		_mq_active = true
		var vw := get_viewport().get_visible_rect().size.x
		marquee.position = Vector2(vw + 60.0, 118.0)

## 超市大喇叭广播(排队滚动播放;联机主机自动转发给客户端)
func broadcast(text: String) -> void:
	if Main.instance != null and Main.instance.tutorial:
		return
	_bc_queue.append(text)
	var m := Main.instance
	if m != null and m.net != null and m.net.active and m.net.is_host:
		m.net.rpc("ev_broadcast", text)

func set_timer_text(text: String, color: Color) -> void:
	time_label.text = text
	time_label.add_theme_color_override("font_color", color)

func set_phase(text: String) -> void:
	phase_label.text = text

func set_bars(stamina: float, imbalance: float) -> void:
	_set_bar_fill(stamina_fill, stamina)
	_set_bar_fill(imbalance_fill, imbalance)

## VBox 会把状态槽背景拉伸到最宽子项（通常是上方技能说明）的宽度。
## 填充条必须按背景的实际布局宽度计算，不能继续使用 BAR_W 固定值，否则
## 数值到 100 时右侧仍会留下一大段看似“没满”的空槽。
func _set_bar_fill(fill: ColorRect, value: float) -> void:
	var bg := fill.get_parent() as Control
	var inner_w := BAR_W - 4.0
	var inner_h := BAR_H - 4.0
	if bg != null and bg.size.x > 4.0:
		inner_w = bg.size.x - 4.0
		inner_h = maxf(0.0, bg.size.y - 4.0)
	fill.size = Vector2(inner_w * clampf(value / 100.0, 0.0, 1.0), inner_h)

func set_prompt(text: String, progress: float) -> void:
	prompt_label.text = text
	channel_bg.visible = progress >= 0.0
	if progress >= 0.0:
		channel_fill.size = Vector2(216.0 * clampf(progress, 0, 1), 8)

## rows: [{text, green}] 或 {header:true, text, color} (行数按清单长度动态增补)
## green=true:商品已在购物车/已结算→标绿+划线;header:分区子标题
func set_list(rows: Array) -> void:
	while list_rows.size() < rows.size():
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.scroll_active = false
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(620, 0)
		list_vbox.add_child(row)
		list_rows.append(row)
	for i in list_rows.size():
		if i >= rows.size():
			list_rows[i].text = ""
			continue
		var r: Dictionary = rows[i]
		var t: String = r["text"]
		if r.get("header", false):
			var c: Color = r.get("color", Color.WHITE)
			list_rows[i].text = "[font_size=34][color=#%s]%s[/color][/font_size]" % [c.lightened(0.2).to_html(false), t]
		elif r.get("green", false):
			list_rows[i].text = "[s][color=#7ef291]%s[/color][/s]" % t
		else:
			list_rows[i].text = "[color=#ffffff]%s[/color]" % t

func set_score(score: int) -> void:
	score_label.text = "已到手货值:%d" % score

func show_result(lines: Array) -> void:
	for c in result_vbox.get_children():
		c.queue_free()
	for i in lines.size():
		var lb := Label.new()
		lb.text = lines[i]
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 0:
			lb.add_theme_font_size_override("font_size", 50)
			lb.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		result_vbox.add_child(lb)
	result_overlay.visible = true
