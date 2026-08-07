class_name Hud extends CanvasLayer
## 白盒HUD:计时/阶段、购物清单、体力与失衡条、交互提示、超市广播、结算面板。
## 开始界面与联机大厅在 start_menu.gd,本类只做信号转发。

signal npc_count_changed(count: int)
signal start_game_pressed
signal start_tutorial_pressed
signal host_pressed
signal join_pressed(ip: String)
signal begin_pressed          # 主机大厅:开始对局

var time_label: Label
var phase_label: Label
var score_label: Label
var list_vbox: VBoxContainer
var list_rows: Array[RichTextLabel] = []
var dev_panel: PanelContainer
var npc_slider: HSlider
var npc_count_label: Label
var skill_label: Label
var marquee: Label            # 大喇叭滚动横幅
var menu: StartMenu           # 开始界面 + 联机大厅
var tutorial_label: Label     # 教学指引大字
var prompt_label: Label
var broadcast_panel: PanelContainer
var broadcast_label: Label
var stamina_fill: ColorRect
var imbalance_fill: ColorRect
var channel_bg: ColorRect
var channel_fill: ColorRect
var result_overlay: Control
var result_vbox: VBoxContainer

var _bc_queue: Array = []
var _mq_active := false
var _mq_time := 0.0

const BAR_W := 440.0      # 加长加粗的状态条
const BAR_H := 24.0
const MQ_SPEED := 480.0   # 横幅滚动速度(像素/秒)

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

	# 左上:购物清单
	var list_panel := PanelContainer.new()
	var lv := VBoxContainer.new()
	list_panel.add_child(lv)
	var title := Label.new()
	title.text = "📋 购物清单"
	title.add_theme_font_override("font", Catalog.ui_font_bold())
	title.add_theme_font_size_override("font_size", 44)
	lv.add_child(title)
	list_vbox = VBoxContainer.new()
	lv.add_child(list_vbox)
	score_label = Label.new()
	score_label.text = "已结算得分:0"
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
	var hint := Label.new()
	hint.text = "F 推/放车 · E 交互(长按搜/偷) · R 装车 · Shift 冲刺\n左键 肘击 · 右键 掷水瓶 · Q 找货雷达 · 空格 稳住(格挡撞击)\nEsc 鼠标 · F1 开发者 · T/F3/F4 调试"
	hint.add_theme_font_override("font", Catalog.ui_font_bold())
	hint.add_theme_font_size_override("font_size", 30)
	hint.add_theme_color_override("font_color", Color(1, 0.25, 0.18))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hint.add_theme_constant_override("outline_size", 6)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)

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
	menu.npc_changed.connect(func(n: int) -> void: npc_count_changed.emit(n))
	root.add_child(menu)

# ---------------------------------------------------------------- 菜单转发

func hide_menu() -> void:
	menu.visible = false

func set_menu_status(t: String) -> void:
	menu.set_status(t)

## 建房后:锁单机入口,但保留"加入对方房间"(join会正确切换身份)
func lock_menu_for_host() -> void:
	menu.lock_for_host()

## 加入后:全部锁死,防止等待连接时误开单机局
func lock_menu_for_join() -> void:
	menu.lock_for_join()

## 大厅成员变化:刷新成员列表(每行显示昵称与配色)。
## members: [{name, color}],下标即座位号(0=房主)
func set_lobby(members: Array, is_host: bool) -> void:
	menu.show_lobby(members, is_host)

# ---------------------------------------------------------------- 局内 HUD

func set_tutorial_text(t: String) -> void:
	tutorial_label.visible = t != ""
	tutorial_label.text = t

func set_skill(text: String, ready: bool) -> void:
	skill_label.text = text
	skill_label.add_theme_color_override("font_color",
			Color(0.55, 0.95, 0.6) if ready else Color(0.75, 0.75, 0.75))

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
	stamina_fill.size = Vector2((BAR_W - 4.0) * clampf(stamina / 100.0, 0, 1), BAR_H - 4.0)
	imbalance_fill.size = Vector2((BAR_W - 4.0) * clampf(imbalance / 100.0, 0, 1), BAR_H - 4.0)

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
	score_label.text = "已结算得分:%d" % score

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
