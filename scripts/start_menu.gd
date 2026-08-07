class_name StartMenu extends Control
## 开始界面 + 联机大厅。
##
## 布局分两栏:左栏是单机入口与开发者选项,右栏是「我的黄牛」角色自定义
## 与局域网联机。进入房间后,右栏下方会展开房间成员列表(实时显示每个人的
## 昵称与配色),主机独有「开始对局」按钮。

signal start_game_pressed
signal start_tutorial_pressed
signal host_pressed
signal join_pressed(ip: String)
signal begin_pressed
signal npc_changed(count: int)

const PANEL_W := 560.0

var _name_edit: LineEdit
var _color_btns: Array[Button] = []
var _preview_dot: ColorRect
var _preview_name: Label
var _ip_edit: LineEdit
var _btn_start: Button
var _btn_tut: Button
var _btn_host: Button
var _btn_join: Button
var _btn_begin: Button
var _status: Label
var _npc_slider: HSlider
var _npc_label: Label
var _lobby_panel: PanelContainer
var _lobby_title: Label
var _lobby_rows: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PlayerProfile.ensure_loaded()

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 10)
	center.add_child(page)

	_build_title(page)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cols)
	_build_left(cols)
	_build_right(cols)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(0.95, 0.9, 0.5))
	_status.custom_minimum_size = Vector2(PANEL_W * 2.0, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)

	_refresh_preview()

# ---------------------------------------------------------------- 标题

func _build_title(page: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "黄 牛 模 拟 器"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Catalog.ui_font_bold())
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color(1, 0.12, 0.08))
	title.add_theme_color_override("font_outline_color", Color(1, 0.9, 0.15))
	title.add_theme_constant_override("outline_size", 22)
	page.add_child(title)

	var sub := Label.new()
	sub.text = "黑五超市代购争夺战 · 白盒Demo %s —— 低价扫进来,加价倒出去" % Catalog.GAME_VERSION
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	page.add_child(sub)

# ---------------------------------------------------------------- 左栏

func _build_left(cols: HBoxContainer) -> void:
	var box := _panel(cols)

	_btn_start = _button(box, "开 始 单干", 38, true)
	_btn_start.pressed.connect(func() -> void: start_game_pressed.emit())
	_btn_tut = _button(box, "新手 教 学", 30)
	_btn_tut.pressed.connect(func() -> void: start_tutorial_pressed.emit())

	_section(box, "🔧 开发者选项", Color(1, 0.8, 0.3))
	_npc_label = Label.new()
	_npc_label.text = "同场大妈数量: 8"
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_npc_label)
	_npc_slider = HSlider.new()
	_npc_slider.min_value = 0
	_npc_slider.max_value = 10
	_npc_slider.step = 1
	_npc_slider.value = 8
	_npc_slider.custom_minimum_size = Vector2(PANEL_W - 60.0, 34)
	_npc_slider.value_changed.connect(func(v: float) -> void: npc_changed.emit(int(v)))
	box.add_child(_npc_slider)

	var tip := Label.new()
	tip.text = "0 人 = 纯净跑图· 10 人 = 收银口地狱"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(tip)

# ---------------------------------------------------------------- 右栏

func _build_right(cols: HBoxContainer) -> void:
	var box := _panel(cols)

	_section(box, "🧢 我的黄牛", Color(0.55, 0.95, 0.6))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var name_tag := Label.new()
	name_tag.text = "名号"
	name_tag.add_theme_font_size_override("font_size", 24)
	name_row.add_child(name_tag)
	_name_edit = LineEdit.new()
	_name_edit.text = PlayerProfile.display_name
	_name_edit.max_length = PlayerProfile.MAX_NAME_LEN
	_name_edit.placeholder_text = "最多%d字" % PlayerProfile.MAX_NAME_LEN
	_name_edit.custom_minimum_size = Vector2(PANEL_W - 150.0, 48)
	_name_edit.add_theme_font_size_override("font_size", 24)
	_name_edit.text_changed.connect(_on_name_typed)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	name_row.add_child(_name_edit)

	var color_tag := Label.new()
	color_tag.text = "配色(撞色会自动错开)"
	color_tag.add_theme_font_size_override("font_size", 20)
	color_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(color_tag)

	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	box.add_child(swatches)
	for i in PlayerProfile.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 48)
		b.tooltip_text = PlayerProfile.color_name_of(i)
		var idx := i
		b.pressed.connect(func() -> void: _on_color_picked(idx))
		swatches.add_child(b)
		_color_btns.append(b)

	# 预览:场上头顶名牌就是这个样子
	var prev := HBoxContainer.new()
	prev.add_theme_constant_override("separation", 10)
	box.add_child(prev)
	var prev_tag := Label.new()
	prev_tag.text = "场上显示"
	prev_tag.add_theme_font_size_override("font_size", 20)
	prev_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	prev.add_child(prev_tag)
	_preview_dot = ColorRect.new()
	_preview_dot.custom_minimum_size = Vector2(30, 30)
	prev.add_child(_preview_dot)
	_preview_name = Label.new()
	_preview_name.add_theme_font_override("font", Catalog.ui_font_bold())
	_preview_name.add_theme_font_size_override("font_size", 26)
	prev.add_child(_preview_name)

	_section(box, "🌐 局域网联机(2-6人)", Color(0.45, 0.8, 1.0))
	var ip_info := Label.new()
	ip_info.text = "本机IP: %s" % Net.local_ips()
	ip_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_info.add_theme_font_size_override("font_size", 22)
	ip_info.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	box.add_child(ip_info)

	_btn_host = _button(box, "创建房间(当房主)", 26)
	_btn_host.pressed.connect(func() -> void: host_pressed.emit())

	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	box.add_child(jrow)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "房主IP,如 192.168.1.5"
	_ip_edit.custom_minimum_size = Vector2(PANEL_W - 210.0, 48)
	_ip_edit.add_theme_font_size_override("font_size", 22)
	jrow.add_child(_ip_edit)
	_btn_join = Button.new()
	_btn_join.text = "加入房间"
	_btn_join.custom_minimum_size = Vector2(140, 48)
	_btn_join.add_theme_font_size_override("font_size", 24)
	_btn_join.pressed.connect(func() -> void:
		_commit_name()
		join_pressed.emit(_ip_edit.text))
	jrow.add_child(_btn_join)

	_build_lobby(box)

	_btn_begin = _button(box, "开 始 对 局", 30, true)
	_btn_begin.visible = false
	_btn_begin.pressed.connect(func() -> void: begin_pressed.emit())

# ---------------------------------------------------------------- 大厅成员列表

func _build_lobby(box: VBoxContainer) -> void:
	_lobby_panel = PanelContainer.new()
	_lobby_panel.visible = false
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	_lobby_panel.add_child(lv)
	_lobby_title = Label.new()
	_lobby_title.text = "房间成员 1/6"
	_lobby_title.add_theme_font_override("font", Catalog.ui_font_bold())
	_lobby_title.add_theme_font_size_override("font_size", 26)
	_lobby_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	lv.add_child(_lobby_title)
	_lobby_rows = VBoxContainer.new()
	_lobby_rows.add_theme_constant_override("separation", 3)
	lv.add_child(_lobby_rows)
	box.add_child(_lobby_panel)

## members: [{name: String, color: int}],下标即座位号(0=房主)
func show_lobby(members: Array, is_host: bool) -> void:
	_lobby_panel.visible = true
	_lobby_title.text = "房间成员 %d/%d" % [members.size(), Net.MAX_CLIENTS + 1]
	for c in _lobby_rows.get_children():
		c.queue_free()
	for i in members.size():
		var m: Dictionary = members[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(24, 24)
		dot.color = PlayerProfile.color_of(int(m.get("color", 0)))
		row.add_child(dot)
		var lb := Label.new()
		lb.text = "%d. %s" % [i + 1, str(m.get("name", "?"))]
		lb.add_theme_font_size_override("font_size", 24)
		row.add_child(lb)
		var tag := Label.new()
		tag.text = "  房主" if i == 0 else ""
		tag.add_theme_font_size_override("font_size", 20)
		tag.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		row.add_child(tag)
		_lobby_rows.add_child(row)
	if is_host:
		_btn_begin.visible = true
		_btn_begin.disabled = members.size() < 2
		if members.size() >= 2:
			_btn_begin.text = "开 始 对 局(%d人)" % members.size()
		else:
			_btn_begin.text = "等 待 其 他 人 加 入"
	else:
		_btn_begin.visible = false

# ---------------------------------------------------------------- 档案编辑

func _on_name_typed(_t: String) -> void:
	_refresh_preview(_name_edit.text)

func _commit_name() -> void:
	var final_name := PlayerProfile.set_name_and_save(_name_edit.text)
	if _name_edit.text != final_name:
		_name_edit.text = final_name
	_refresh_preview()
	_broadcast_profile()

func _on_color_picked(idx: int) -> void:
	PlayerProfile.set_color_and_save(idx)
	_refresh_preview()
	_broadcast_profile()

## 已在大厅里改档案:实时同步给房间里的其他人
func _broadcast_profile() -> void:
	var m := Main.instance
	if m != null and m.net != null:
		m.net.push_profile()

func _refresh_preview(typing := "") -> void:
	var shown := PlayerProfile.sanitize(typing) if typing != "" else PlayerProfile.display_name
	if shown == "":
		shown = PlayerProfile.display_name
	var col := PlayerProfile.color()
	_preview_dot.color = col
	_preview_name.text = shown
	_preview_name.add_theme_color_override("font_color", col.lightened(0.25))
	for i in _color_btns.size():
		_color_btns[i].add_theme_stylebox_override("normal", _swatch_style(i, false))
		_color_btns[i].add_theme_stylebox_override("hover", _swatch_style(i, true))
		_color_btns[i].add_theme_stylebox_override("pressed", _swatch_style(i, true))

func _swatch_style(idx: int, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PlayerProfile.color_of(idx)
	sb.set_corner_radius_all(6)
	var selected := idx == PlayerProfile.color_index
	if selected or hover:
		sb.set_border_width_all(4 if selected else 2)
		sb.border_color = Color(1, 1, 1) if selected else Color(1, 1, 1, 0.6)
	return sb

# ---------------------------------------------------------------- 状态切换

func set_status(t: String) -> void:
	_status.text = t

## 建房后:锁单机入口,但保留"加入对方房间"(join会正确切换身份)
func lock_for_host() -> void:
	_btn_start.disabled = true
	_btn_start.text = "(联机模式进行中)"
	_btn_tut.disabled = true
	_btn_host.disabled = true
	_btn_begin.visible = true
	_btn_begin.disabled = true
	_btn_begin.text = "等 待 其 他 人 加 入"

## 加入后:全部锁死,防止等待连接时误开单机局
func lock_for_join() -> void:
	lock_for_host()
	_btn_join.disabled = true
	_ip_edit.editable = false
	_btn_begin.visible = false

func set_npc_display(n: int) -> void:
	_npc_slider.set_value_no_signal(n)
	_npc_label.text = "同场大妈数量: %d" % n

# ---------------------------------------------------------------- 小工具

func _panel(cols: HBoxContainer) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(PANEL_W, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	cols.add_child(p)
	return v

func _section(box: VBoxContainer, text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = "—— %s ——" % text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 24)
	lb.add_theme_color_override("font_color", color)
	box.add_child(lb)

func _button(box: VBoxContainer, text: String, size: int, bold := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(PANEL_W - 60.0, 70.0 if size >= 34 else 56.0)
	if bold:
		b.add_theme_font_override("font", Catalog.ui_font_bold())
	b.add_theme_font_size_override("font_size", size)
	box.add_child(b)
	return b
