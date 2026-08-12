class_name StartMenu extends Control
## 开始界面(分级导航)+ 联机大厅。
##
## 页面结构参照常见联机游戏的信息架构:主界面只放三个入口,
## 其余内容按需下钻,每一层都能返回上一层。
##
##   主界面 ── 单人游戏 → 选择角色页──→开局
##          ├─ 多人联机 → 联机页 ─┬ 创建房间 → 房间页 → 开局
##          │     └ 加入游戏 → 输入IP页 → 房间页(等房主)
##          └─ 教学模式 ─────────→ 开局
##
## 选择角色页与房间页共用同一套角色选择组件(见 _build_char_picker)。

signal start_game_pressed
signal start_tutorial_pressed
signal host_pressed
signal join_pressed(ip: String)
signal begin_pressed
signal leave_room_pressed
signal quit_pressed
signal npc_changed(count: int)

const PAGE_MAIN := "main"
const PAGE_SOLO := "solo"
const PAGE_MP := "mp"
const PAGE_JOIN := "join"
const PAGE_ROOM := "room"

const PANEL_W := 560.0
const CARD_W := 250.0

var _pages := {}
var _page := PAGE_MAIN
var _status: Label

# 角色选择:两处页面各一套控件
var _char_cards := {}      # page -> Array[Button]
var _char_detail := {}     # page -> RichTextLabel
var _char_id := CharacterDef.ORDER[0]

# 档案编辑控件(单人页与房间页各一套)
var _name_edits: Array[LineEdit] = []
var _color_btn_sets: Array = []

var _ip_edit: LineEdit
var _btn_host: Button
var _btn_join_go: Button
var _btn_begin: Button
var _btn_leave: Button
var _npc_slider: HSlider
var _npc_label: Label
var _room_title: Label
var _room_rows: VBoxContainer
var _room_hint: Label
var _btn_quit: Button      # 只在主界面显示
var _in_network := false   # 已建房/已连接:禁止再从本机发起另一种身份

func _ready() -> void:
	# 用 set_anchors_and_offsets_preset:只设 anchors 会留下 offsets,
	# 代码创建的 Control 初始 size 为 0,子节点会全部堆到左上角(踩过)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlayerProfile.ensure_loaded()
	_char_id = PlayerProfile.char_id

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	for id in [PAGE_MAIN, PAGE_SOLO, PAGE_MP, PAGE_JOIN, PAGE_ROOM]:
		# 页面内容超过当前窗口时允许纵向滚动。旧实现直接把 VBox 放进
		# CenterContainer：当选角页的最小高度略大于 900px 时会从上下两端
		# 同时溢出，导致标题在标准 1600×900 下被裁掉。
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.draw_focus_border = false
		scroll.visible = false
		add_child(scroll)
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_top", 28)
		margin.add_theme_constant_override("margin_bottom", 28)
		scroll.add_child(margin)
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(center)
		var page := VBoxContainer.new()
		page.alignment = BoxContainer.ALIGNMENT_CENTER
		page.add_theme_constant_override("separation", 12)
		center.add_child(page)
		_pages[id] = scroll
		match id:
			PAGE_MAIN: _build_main(page)
			PAGE_SOLO: _build_solo(page)
			PAGE_MP: _build_mp(page)
			PAGE_JOIN: _build_join(page)
			PAGE_ROOM: _build_room(page)

	# 状态条:所有页面共用,固定在底部(联机排障信息可能很长)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(0.95, 0.9, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 24)

	_go(PAGE_MAIN)
	_refresh_profile_ui()

	# 调试钩子:WHITEBOX_MENU_PAGE=solo|mp|join|room 直接打开指定页面。
	# UI 无法被无头测试覆盖,只能靠截图人眼确认——这个钩子让"截某一层界面"变成一条命令。
	var forced := OS.get_environment("WHITEBOX_MENU_PAGE")
	if forced != "" and _pages.has(forced):
		if forced == PAGE_ROOM:
			show_lobby([
				{"name": "房主本人", "color": 0, "char": CharacterDef.ZHAO},
				{"name": "老马", "color": 2, "char": CharacterDef.MA},
				{"name": "洋哥", "color": 4, "char": CharacterDef.LI},
			], true)
		else:
			_go(forced)

# ================================================================ 主界面

func _build_main(page: VBoxContainer) -> void:
	_build_title(page, true)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	page.add_child(box)

	var b1 := _big_button(box, "单 人 游 戏", Color(1, 0.85, 0.35))
	b1.pressed.connect(func() -> void: _go(PAGE_SOLO))
	var b2 := _big_button(box, "多 人 联 机", Color(0.5, 0.82, 1.0))
	b2.pressed.connect(func() -> void: _go(PAGE_MP))
	var b3 := _big_button(box, "教 学 模 式", Color(0.6, 1.0, 0.7))
	b3.pressed.connect(func() -> void: start_tutorial_pressed.emit())

	# 退出放在角落的小按钮:主界面的视觉重心只留给三个入口。
	# 手动摆 anchors/offsets:preset + MINSIZE 会在按钮尺寸变化后失准而贴边溢出(踩过)
	var quit := Button.new()
	quit.text = "退出游戏"
	quit.add_theme_font_size_override("font_size", 20)
	quit.pressed.connect(func() -> void: quit_pressed.emit())
	add_child(quit)
	quit.anchor_left = 1.0
	quit.anchor_top = 1.0
	quit.anchor_right = 1.0
	quit.anchor_bottom = 1.0
	quit.offset_left = -180.0
	quit.offset_top = -70.0
	quit.offset_right = -24.0
	quit.offset_bottom = -24.0
	_btn_quit = quit

# ================================================================ 单人游戏:选择角色

func _build_solo(page: VBoxContainer) -> void:
	_build_title(page, false)
	_section(page, "选 择 角 色", Color(1, 0.85, 0.35))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cols)
	_build_char_picker(cols, PAGE_SOLO)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size = Vector2(PANEL_W, 0)
	cols.add_child(side)
	_build_profile_editor(side)
	_build_dev_options(side)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)
	var back := _wide_button(row, "返回", 28, 220.0)
	back.pressed.connect(func() -> void: _go(PAGE_MAIN))
	var go := _wide_button(row, "开 始 游戏", 34, 380.0, true)
	go.pressed.connect(func() -> void:
		_commit_all()
		start_game_pressed.emit())

# ================================================================ 多人联机

func _build_mp(page: VBoxContainer) -> void:
	_build_title(page, false)
	_section(page, "多 人 联 机 (2-6人局域网)", Color(0.5, 0.82, 1.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	page.add_child(box)

	var ip_info := Label.new()
	ip_info.text = "本机IP: %s(端口 %d)" % [Net.local_ips(), Net.PORT]
	ip_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_info.add_theme_font_size_override("font_size", 22)
	ip_info.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	box.add_child(ip_info)

	_btn_host = _big_button(box, "创 建 房 间", Color(0.5, 0.82, 1.0))
	_btn_host.pressed.connect(func() -> void:
		_commit_all()
		host_pressed.emit())
	var bj := _big_button(box, "加 入 游 戏", Color(0.85, 0.9, 1.0))
	bj.pressed.connect(func() -> void: _go(PAGE_JOIN))

	var tip := Label.new()
	tip.text = "同一个路由器/热点下即可联机。房主创建房间后,把上面的IP告诉其他人"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(tip)

	var back := _wide_button(page, "返 回", 28, 300.0)
	back.pressed.connect(func() -> void: _go(PAGE_MAIN))

# ================================================================ 加入游戏:填IP

func _build_join(page: VBoxContainer) -> void:
	_build_title(page, false)
	_section(page, "加 入 游 戏", Color(0.85, 0.9, 1.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	page.add_child(box)

	var tag := Label.new()
	tag.text = "输入房主的IP地址"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 24)
	box.add_child(tag)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "例如 192.168.1.5"
	_ip_edit.custom_minimum_size = Vector2(PANEL_W, 56)
	_ip_edit.add_theme_font_size_override("font_size", 26)
	_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _do_join())
	box.add_child(_ip_edit)

	_btn_join_go = _wide_button(box, "连接", 32, PANEL_W, true)
	_btn_join_go.pressed.connect(_do_join)

	var back := _wide_button(page, "返 回", 28, 300.0)
	back.pressed.connect(func() -> void: _go(PAGE_MP))

func _do_join() -> void:
	_commit_all()
	join_pressed.emit(_ip_edit.text)

# ================================================================ 房间页(大厅)

func _build_room(page: VBoxContainer) -> void:
	_build_title(page, false)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cols)

	# 左:成员列表
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(PANEL_W, 300)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	_room_title = Label.new()
	_room_title.text = "房间成员 1/6"
	_room_title.add_theme_font_override("font", Catalog.ui_font_bold())
	_room_title.add_theme_font_size_override("font_size", 30)
	_room_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	lv.add_child(_room_title)
	_room_rows = VBoxContainer.new()
	_room_rows.add_theme_constant_override("separation", 4)
	lv.add_child(_room_rows)
	cols.add_child(left)

	# 右:我的档案与角色(在房间里也能改,改动实时推给全房间)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(PANEL_W, 0)
	cols.add_child(right)
	_build_profile_editor(right)
	_section(right, "我的 角 色", Color(1, 0.85, 0.35))
	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 10)
	picker_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(picker_row)
	_build_char_picker(picker_row, PAGE_ROOM, true)

	_room_hint = Label.new()
	_room_hint.text = "等待房主开始对局..."
	_room_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_hint.add_theme_font_size_override("font_size", 22)
	_room_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	page.add_child(_room_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(row)
	_btn_leave = _wide_button(row, "离 开 房 间", 28, 260.0)
	_btn_leave.pressed.connect(func() -> void: leave_room_pressed.emit())
	_btn_begin = _wide_button(row, "开 始 对 局", 34, 380.0, true)
	_btn_begin.visible = false
	_btn_begin.pressed.connect(func() -> void: begin_pressed.emit())

## members: [{name, color, char}],下标即座位号(0=房主)
func show_lobby(members: Array, is_host: bool) -> void:
	if _page != PAGE_ROOM:
		_go(PAGE_ROOM)
	_room_title.text = "房间成员 %d/%d" % [members.size(), Net.MAX_CLIENTS + 1]
	for c in _room_rows.get_children():
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
		# 角色公开:技能是战术信息,应当让对手看见(《14·九》)
		var cid := CharacterDef.valid_id(str(m.get("char", "")))
		var cl := Label.new()
		cl.text = "  %s · %s" % [CharacterDef.full_name(cid), CharacterDef.skill_name(cid)]
		cl.add_theme_font_size_override("font_size", 20)
		cl.add_theme_color_override("font_color", CharacterDef.accent(cid))
		row.add_child(cl)
		if i == 0:
			var tag := Label.new()
			tag.text = "  房主"
			tag.add_theme_font_size_override("font_size", 20)
			tag.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
			row.add_child(tag)
		_room_rows.add_child(row)
	if is_host:
		_btn_begin.visible = true
		_btn_begin.disabled = members.size() < 2
		_btn_begin.text = "开 始 对 局(%d人)" % members.size() if members.size() >= 2 else "等 待 加入"
		_room_hint.text = "人齐了就点\"开始对局\"。所有人的角色与配色都会同步给全场"
	else:
		_btn_begin.visible = false
		_room_hint.text = "等待房主开始对局...(此时仍可改名、换色、换角色)"

# ================================================================ 角色选择组件

##三张角色卡 + 一块详情。compact=true 时用于房间页(卡片更小、详情更短)
func _build_char_picker(parent: BoxContainer, page_id: String, compact := false) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 10)
	parent.add_child(wrap)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(cards)

	var list: Array[Button] = []
	for cid in CharacterDef.ORDER:
		var d := CharacterDef.get_def(cid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(CARD_W if not compact else 168.0, 96.0 if not compact else 74.0)
		b.add_theme_font_override("font", Catalog.ui_font_bold())
		b.add_theme_font_size_override("font_size", 26 if not compact else 21)
		b.text = "%s\n「%s」" % [d["name"], d["nick"]]
		b.tooltip_text = "%s · %s" % [d["job"], d["role"]]
		var picked := cid
		b.pressed.connect(func() -> void: _on_char_picked(picked))
		cards.add_child(b)
		list.append(b)
	_char_cards[page_id] = list

	var detail := RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.scroll_active = false
	detail.custom_minimum_size = Vector2(CARD_W * 3.0 + 20.0 if not compact else PANEL_W, 0)
	detail.add_theme_font_size_override("normal_font_size", 20 if compact else 22)
	wrap.add_child(detail)
	_char_detail[page_id] = detail

func _on_char_picked(cid: String) -> void:
	_char_id = CharacterDef.valid_id(cid)
	PlayerProfile.set_char_and_save(_char_id)
	_refresh_profile_ui()
	_broadcast_profile()

## 角色详情文案:主技能与被动各一段,附代价说明(代价必须让玩家开局前就知道)
func _char_detail_text(cid: String, compact: bool) -> String:
	var d := CharacterDef.get_def(cid)
	var acc: String = CharacterDef.accent(cid).to_html(false)
	var out := "[color=#%s][b]%s「%s」[/b][/color]  [color=#aaaaaa]%s · %s[/color]\n" % [
			acc, d["name"], d["nick"], d["job"], d["role"]]
	out += "[color=#dddd88]\"%s\"[/color]\n\n" % d["quote"]
	out += "[color=#ffd24d][b]空格 主技能 · %s[/b][/color]  [color=#aaaaaa](冷却 %d 秒)[/color]\n" % [
			d["skill"], int(d["skill_cd"])]
	out += "[color=#ffffff]%s[/color]\n" % d["skill_line"]
	if not compact:
		for line in d["skill_desc"]:
			out += "  · %s\n" % line
	out += "\n[color=#8fe3ff][b]被动 · %s[/b][/color]\n" % d["passive"]
	out += "[color=#ffffff]%s[/color]\n" % d["passive_line"]
	if not compact:
		for line in d["passive_desc"]:
			out += "  · %s\n" % line
	return out

# ================================================================ 档案编辑(昵称+配色)

func _build_profile_editor(box: VBoxContainer) -> void:
	_section(box, "我 的 名号", Color(0.55, 0.95, 0.6))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var name_tag := Label.new()
	name_tag.text = "名号"
	name_tag.add_theme_font_size_override("font_size", 24)
	name_row.add_child(name_tag)
	var edit := LineEdit.new()
	edit.text = PlayerProfile.display_name
	edit.max_length = PlayerProfile.MAX_NAME_LEN
	edit.placeholder_text = "最多%d字" % PlayerProfile.MAX_NAME_LEN
	edit.custom_minimum_size = Vector2(PANEL_W - 150.0, 48)
	edit.add_theme_font_size_override("font_size", 24)
	edit.text_submitted.connect(func(_t: String) -> void: _commit_name(edit))
	edit.focus_exited.connect(func() -> void: _commit_name(edit))
	name_row.add_child(edit)
	_name_edits.append(edit)

	var color_tag := Label.new()
	color_tag.text = "配色(撞色会自动错开)"
	color_tag.add_theme_font_size_override("font_size", 20)
	color_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(color_tag)

	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	box.add_child(swatches)
	var btns: Array[Button] = []
	for i in PlayerProfile.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 44)
		b.tooltip_text = PlayerProfile.color_name_of(i)
		var idx := i
		b.pressed.connect(func() -> void: _on_color_picked(idx))
		swatches.add_child(b)
		btns.append(b)
	_color_btn_sets.append(btns)

func _build_dev_options(box: VBoxContainer) -> void:
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
	tip.text = "0 人 = 纯净跑图 · 10 人 = 收银口地狱"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(tip)

func _commit_name(edit: LineEdit) -> void:
	var final_name := PlayerProfile.set_name_and_save(edit.text)
	_refresh_profile_ui()
	if edit.text != final_name:
		edit.text = final_name
	_broadcast_profile()

func _commit_all() -> void:
	for e in _name_edits:
		if e.text.strip_edges() != "":
			PlayerProfile.set_name_and_save(e.text)
			break
	PlayerProfile.set_char_and_save(_char_id)
	_refresh_profile_ui()

func _on_color_picked(idx: int) -> void:
	PlayerProfile.set_color_and_save(idx)
	_refresh_profile_ui()
	_broadcast_profile()

## 已在房间里改档案:实时同步给房间里的其他人
func _broadcast_profile() -> void:
	var m := Main.instance
	if m != null and m.net != null:
		m.net.push_profile()

## 统一刷新:昵称输入框、配色按钮高亮、角色卡高亮与详情
func _refresh_profile_ui() -> void:
	for e in _name_edits:
		if not e.has_focus() and e.text != PlayerProfile.display_name:
			e.text = PlayerProfile.display_name
	for btns in _color_btn_sets:
		for i in btns.size():
			btns[i].add_theme_stylebox_override("normal", _swatch_style(i, false))
			btns[i].add_theme_stylebox_override("hover", _swatch_style(i, true))
			btns[i].add_theme_stylebox_override("pressed", _swatch_style(i, true))
	for page_id in _char_cards:
		var list: Array = _char_cards[page_id]
		for i in list.size():
			var cid := CharacterDef.id_at(i)
			var selected := cid == _char_id
			var b: Button = list[i]
			b.add_theme_stylebox_override("normal", _card_style(cid, selected, false))
			b.add_theme_stylebox_override("hover", _card_style(cid, selected, true))
			b.add_theme_stylebox_override("pressed", _card_style(cid, true, true))
			b.add_theme_color_override("font_color",
					Color(1, 1, 1) if selected else Color(1, 1, 1, 0.66))
	for page_id in _char_detail:
		var d: RichTextLabel = _char_detail[page_id]
		d.text = _char_detail_text(_char_id, page_id == PAGE_ROOM)

func _swatch_style(idx: int, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PlayerProfile.color_of(idx)
	sb.set_corner_radius_all(6)
	var selected := idx == PlayerProfile.color_index
	if selected or hover:
		sb.set_border_width_all(4 if selected else 2)
		sb.border_color = Color(1, 1, 1) if selected else Color(1, 1, 1, 0.6)
	return sb

func _card_style(cid: String, selected: bool, hover: bool) -> StyleBoxFlat:
	var acc := CharacterDef.accent(cid)
	var sb := StyleBoxFlat.new()
	sb.bg_color = acc.darkened(0.55 if selected else 0.78)
	if hover and not selected:
		sb.bg_color = acc.darkened(0.66)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(4 if selected else 1)
	sb.border_color = acc if selected else Color(1, 1, 1, 0.25)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# ================================================================ 页面切换与状态

func _go(id: String) -> void:
	_page = id
	for k in _pages:
		_pages[k].visible = k == id
	if _btn_quit != null:
		_btn_quit.visible = id == PAGE_MAIN
	set_status("")
	_refresh_profile_ui()

func set_status(t: String) -> void:
	if _status != null:
		_status.text = t

## 建房后:切到房间页,锁住"再创建一次"
func lock_for_host() -> void:
	_in_network = true
	if _btn_host != null:
		_btn_host.disabled = true
	_go(PAGE_ROOM)
	_btn_begin.visible = true
	_btn_begin.disabled = true
	_btn_begin.text = "等 待 加 入"
	_room_hint.text = "房间已创建,等其他人加入..."

## 加入后:切到房间页等主机开局
func lock_for_join() -> void:
	_in_network = true
	if _btn_join_go != null:
		_btn_join_go.disabled = true
	_go(PAGE_ROOM)
	_btn_begin.visible = false
	_room_hint.text = "正在连接房主..."

## 离开房间/联机失败:回到联机页并解锁
func reset_network() -> void:
	_in_network = false
	if _btn_host != null:
		_btn_host.disabled = false
	if _btn_join_go != null:
		_btn_join_go.disabled = false
	if _btn_begin != null:
		_btn_begin.visible = false
	for c in _room_rows.get_children():
		c.queue_free()
	_go(PAGE_MP)

func set_npc_display(n: int) -> void:
	if _npc_slider != null:
		_npc_slider.set_value_no_signal(n)
	if _npc_label != null:
		_npc_label.text = "同场大妈数量: %d" % n

# ================================================================ 小工具

func _build_title(page: VBoxContainer, big: bool) -> void:
	var title := Label.new()
	title.text = "疯 抢 星 期 五"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Catalog.ui_font_bold())
	title.add_theme_font_size_override("font_size", 96 if big else 56)
	title.add_theme_color_override("font_color", Color(1, 0.12, 0.08))
	title.add_theme_color_override("font_outline_color", Color(1, 0.9, 0.15))
	title.add_theme_constant_override("outline_size", 22 if big else 14)
	page.add_child(title)
	if not big:
		return
	var sub := Label.new()
	sub.text = "黑五超市抢购对抗 · 白盒Demo %s —— 文明,打烊之前有效" % Catalog.GAME_VERSION
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	page.add_child(sub)

func _section(box: BoxContainer, text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = "—— %s ——" % text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 24)
	lb.add_theme_color_override("font_color", color)
	box.add_child(lb)

## 主界面用的大按钮
func _big_button(box: BoxContainer, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 86)
	b.add_theme_font_override("font", Catalog.ui_font_bold())
	b.add_theme_font_size_override("font_size", 42)
	b.add_theme_color_override("font_color", color)
	box.add_child(b)
	return b

func _wide_button(box: BoxContainer, text: String, size: int, width: float, bold := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 70.0 if size >= 32 else 56.0)
	if bold:
		b.add_theme_font_override("font", Catalog.ui_font_bold())
	b.add_theme_font_size_override("font_size", size)
	box.add_child(b)
	return b
