class_name Main extends Node3D
## 主控制器:建场、发牌(代购清单)、计时与打烊、限时特价、计分结算、寻路服务、联机粘合。
## 联机为主机权威:世界用共享种子两端确定性重建,客户端只发输入、收状态渲染。

const MATCH_TIME := 300.0        # 5分钟
const GRACE_TIME := 30.0         # 打烊宽限
const CLOSING_WARN := 120.0      # 剩2分钟进入打烊冲刺
const THROW_SPEED := 16.0
const THROW_UPWARD_SPEED := 1.2
const THROW_ORIGIN_HEIGHT := 1.62
const THROW_FORWARD_OFFSET := 1.15
const CENTRAL_EVENT_EARLIEST := 165.0 # 过半后15秒
const CENTRAL_EVENT_LATEST := 195.0   # 过半后45秒
const CENTRAL_EVENT_WARNING := 10.0
const TEAM_PREP_DURATION := 5.0 # 四队短暂整备，倒计时结束后入口同步开门
const GATE_SLIDE_DURATION := 0.9
const TEAM_ORDER_TOTAL := 25      # 每队两名成员共同完成的一份点名订单
const ORDER_LINE_MAX := 3        # 同一SKU每行最多3件，避免清单被单一商品占满
## 四个等待室进入卖场后首先接触的专区（A南西/B南东/C北西/D北东）。
const TEAM_ENTRY_ORDER_ZONES := [
	Catalog.ZONE_SNACK, Catalog.ZONE_CLOTHING,
	Catalog.ZONE_FRESH, Catalog.ZONE_FROZEN,
]
const LAYOUT_ZONE_TO_ORDER_ZONE := {
	"Fresh": Catalog.ZONE_FRESH,
	"Frozen": Catalog.ZONE_FROZEN,
	"Snacks": Catalog.ZONE_SNACK,
	"Toys": Catalog.ZONE_TOY,
	"Electronics": Catalog.ZONE_APPLIANCE,
	"Daily": Catalog.ZONE_DAILY,
	"Beauty": Catalog.ZONE_BEAUTY,
	"Clothing": Catalog.ZONE_CLOTHING,
}

static var instance: Main

## New_Level 等手工场景设为true：正式对局直接读取场景中的功能节点，
## 不再调用 MarketBuilder 叠加旧卖场。教学关会暂时禁用手工场景。
@export var embedded_level := false

## 开发者模式:所有技能无冷却(F1 面板开关)。
## 做成 static 是为了让 player.gd 在不持有 Main 引用时也能读到;
## 每帧在 Player._physics_process 里统一清零,因此无论 CD 在哪里被赋值都能覆盖。
static var dev_no_cd := false

# 碰撞拟声词库(浮夸搞笑)
const BAM := ["哐当!!", "咣!!!", "duang~!!", "嘭!!!", "咔嚓!!", "哐叽!!", "biu嘭!!"]
const BAM_PED := ["人仰马翻!", "撞了个满怀!", "鞋都撞飞了!", "菜篮子保卫战失败!", "原地起飞!"]
const BAM_ELBOW := ["哎哟喂!!", "嗷!!", "咔!!", "哼!!", "着实一记!"]

static func bam() -> String:
	return BAM.pick_random()

var hud: Hud
var net: Net
var player: Player               # 本机操控的玩家
var players: Array[Player] = []  # 全部玩家(联机=2,单机=1),两端顺序一致
var local_idx := 0               # 本机玩家在players中的下标(主机0/客户端1)
var cam_rig: CameraRig
## 镜头水平朝向:player.gd 与 net.gd 直接读取,故在 Main 上保留代理属性
var cam_yaw: float:
	get:
		return cam_rig.yaw if cam_rig != null else 0.0
	set(value):
		if cam_rig != null:
			cam_rig.yaw = value
var mouse_captured := true
var grid: AStarGrid2D
var checkouts: Array[Checkout] = []
var grannies: Array[Granny] = []
var warehouse_buddies: Array = []
var all_items: Array[Item] = []
var _mp_interaction_test_items := {}

# 每名玩家一份对局数据:{list, score, counts, orig, saved, settled, done}
var pdata: Array = []

var elapsed := 0.0
var time_left := MATCH_TIME
var grace_left := GRACE_TIME
var in_grace := false
var game_over := false
var closing_announced := false
var sale_times: Array = []
var sale_points: Array = []
var central_open_at := -1.0
var central_warned := false
var central_opened := false
var central_locked_items: Array[Item] = []
var central_feature_id := ""
var central_feature_ids: Array[String] = []
var team_prep_active := false
var team_prep_left := 0.0
var team_prep_last_second := -1
var team_entrance_opened := false

var game_started := false
var tutorial := false
var net_mp := false              # 联机对局
var net_client := false          # 本机是客户端
var pending_npc := 4             # 固定4支参赛队；旧参数名保留以兼容联机协议入口
## 无头运行(自动化测试);为true时把关键里程碑打到 stdout 供 tools/smoke_test.ps1 断言
var headless := false
var active_layout: Dictionary = {}
var team_data: Array = []       # 四份权威共享订单/分数
var team_bots: Array[Granny] = []
var region_director: RegionDirector
var active_checkout_indices: Array[int] = []
var match_seed := 0

## 里程碑日志:只在无头测试下输出,不干扰正常游玩
func _log_milestone(msg: String) -> void:
	if headless:
		print("[headless] ", msg)

# ---------- 启动与开始界面 ----------

func _ready() -> void:
	instance = self
	headless = DisplayServer.get_name() == "headless"
	_set_runtime_only_visible(false)
	print("疯抢星期五 白盒Demo ", Catalog.GAME_VERSION)
	InputActions.setup()
	_setup_environment()

	net = Net.new()
	net.name = "Net"
	net.main = self
	net.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(net)

	hud = Hud.new()
	add_child(hud)
	hud.npc_count_changed.connect(_set_npc_count)
	hud.no_cd_changed.connect(func(on: bool) -> void: Main.dev_no_cd = on)
	hud.mouse_sensitivity_changed.connect(func(multiplier: float) -> void:
		if cam_rig != null:
			cam_rig.set_sensitivity_multiplier(multiplier))
	hud.start_game_pressed.connect(func() -> void: _start_match(false))
	hud.start_tutorial_pressed.connect(func() -> void: _start_match(true))
	hud.host_pressed.connect(_menu_host)
	hud.join_pressed.connect(_menu_join)
	hud.begin_pressed.connect(net_begin_match)
	hud.leave_room_pressed.connect(_menu_leave_room)
	hud.quit_pressed.connect(func() -> void: get_tree().quit())
	# 固定四队模式：旧 WHITEBOX_NPC 参数不再改变参赛者编制。
	pending_npc = 4
	hud.set_npc_count_display(pending_npc)

	# 调试：普通截图沿用WHITEBOX_SHOT；施工图比对使用独立的正交俯视钩子。
	var topdown_shot := OS.get_environment("WHITEBOX_TOPDOWN_SHOT")
	_shot_path = topdown_shot if topdown_shot != "" else OS.get_environment("WHITEBOX_SHOT")

	# 开始界面阶段不暂停场景树:世界尚未构建,无可模拟之物,
	# 且暂停态下ENet大厅长时间挂机会出现轮询不稳(踩过坑)
	var env_join := OS.get_environment("WHITEBOX_JOIN")
	var env_host := OS.get_environment("WHITEBOX_HOST") != ""
	if env_host:
		_set_mouse_captured(false)
		_menu_host()
	elif env_join != "":
		_set_mouse_captured(false)
		_menu_join(env_join)
	elif OS.get_environment("WHITEBOX_HOSTJOIN") != "":
		# 测试钩子:复现"先建房再加入"的真实操作序列
		_set_mouse_captured(false)
		_menu_host()
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			_menu_join(OS.get_environment("WHITEBOX_HOSTJOIN")))
	elif headless or OS.get_environment("WHITEBOX_AUTOSTART") != "":
		# WHITEBOX_TUTORIAL=1 时无头跑教学关,用于覆盖九步指引代码路径
		_start_match(OS.get_environment("WHITEBOX_TUTORIAL") != "")
	else:
		_set_mouse_captured(false)
	if topdown_shot != "":
		call_deferred("_activate_topdown_audit")

func _start_match(tut: bool) -> void:
	if game_started:
		return
	game_started = true
	tutorial = tut
	# 天花板等运行时白盒在编辑器与开始菜单中保持隐藏，正式对局开始后才显示。
	# 教学关使用独立房间，不能让 New_Level 天花板盖在教学地图上。
	_set_runtime_only_visible(embedded_level and not tut)
	# 单人/教学:用本机档案里选定的角色
	PlayerProfile.ensure_loaded()
	var env_char := OS.get_environment("WHITEBOX_CHAR")
	if env_char != "":
		PlayerProfile.char_id = CharacterDef.valid_id(env_char)
	seat_chars = [PlayerProfile.char_id]
	seat_team_ids = [PlayerProfile.team_index]
	_build_world(randi(), 0 if tut else pending_npc, 1)
	hud.hide_menu()
	_set_mouse_captured(true)
	_log_milestone("单人开局 角色=%s" % PlayerProfile.char_id)
	if tut:
		tutorial_guide = TutorialGuide.new(self)
		tutorial_guide.setup()
		if OS.get_environment("WHITEBOX_TUTORIALTEST") != "":
			tutorial_probe = TutorialProbe.new(self, tutorial_guide)
			tutorial_probe.setup()
	# 测试钩子:车斗物理压力测试(回归"薄商品被挤出车外/穿模")
	if OS.get_environment("WHITEBOX_PHYSTEST") != "":
		phys_stress = PhysStress.new(self)
		phys_stress.setup()
	# 测试钩子:角色技能自检(无头下没人按键,技能代码否则零覆盖)
	if OS.get_environment("WHITEBOX_CHARTEST") != "":
		char_probe = CharProbe.new(self)
		char_probe.setup()
	# 测试钩子:NPC争抢/互殴与HUD满槽回归。
	if OS.get_environment("WHITEBOX_NPCTEST") != "":
		npc_probe = NpcProbe.new(self)
		npc_probe.setup()
	if OS.get_environment("WHITEBOX_PROPTEST") != "":
		prop_probe = PropProbe.new(self)
		prop_probe.setup()
	if OS.get_environment("WHITEBOX_ORDERTEST") != "":
		order_probe = OrderProbe.new(self)
		order_probe.setup()
	if OS.get_environment("WHITEBOX_LEVELTEST") != "":
		new_level_probe = NewLevelProbe.new(self)
		new_level_probe.setup()
	# GUI视觉回归：自动展示当前角色主技能，配合 WHITEBOX_SHOT 截图。
	if OS.get_environment("WHITEBOX_SHOW_CHAR_SKILL") != "":
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(player):
				trigger_char_skill(player, cam_rig.forward()))
	if OS.get_environment("WHITEBOX_WHEEL_DEMO") != "":
		for i in ["detergent", "thermos", "cola", "treadmill", "candy"].size():
			var id: String = ["detergent", "thermos", "cola", "treadmill", "candy"][i]
			var demo_item := Item.create(id)
			add_child(demo_item)
			all_items.append(demo_item)
			demo_item.set_free_at(player.cart.to_global(Vector3((i % 3 - 1) * 0.22, 1.1 + (i / 3) * 0.32, (i % 2) * 0.18)))
	# GUI回归钩子：搭配轮盘演示和截图，固定展示按住右键后的肩射构图与轨迹线。
	if OS.get_environment("WHITEBOX_AIM_PREVIEW") != "":
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(player):
				if not player.attached and is_instance_valid(player.cart):
					player.attach_cart()
				player.throw_aiming = true)
	if OS.get_environment("WHITEBOX_FIRST_PERSON_ZOOM") != "":
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(player) and not player.attached:
				player.throw_aiming = true)
	if OS.get_environment("WHITEBOX_FIRST_PERSON_HANDS") != "":
		get_tree().create_timer(0.75).timeout.connect(func() -> void:
			if is_instance_valid(player):
				if player.attached:
					player.detach_cart()
				if player.held.is_empty():
					var held_demo := Item.create("thermos")
					add_child(held_demo)
					all_items.append(held_demo)
					player.take_item(held_demo)
				if OS.get_environment("WHITEBOX_FIRST_PERSON_PUNCH") != "":
					player.do_elbow(cam_rig.forward())
					Main.float_text(player, player.global_position + Vector3.UP * 2.2,
							"咚!!  肘击+15", Color(1.0, 0.7, 0.2), 76))
	var show_throw_effect := OS.get_environment("WHITEBOX_SHOW_THROW_EFFECT")
	if show_throw_effect != "" and Catalog.ITEMS.has(show_throw_effect):
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(player):
				_apply_throw_effect(show_throw_effect,
						player.global_position + cam_rig.forward() * 2.4, player, null))

## 联机开局(各端各自调用,种子一致→世界一致)。my_seat:本机座位(主机0)。
func start_mp(host: bool, wseed: int, npc: int, my_seat: int, nplayers: int,
		names: Array = [], colors: Array = [], chars: Array = [], teams: Array = []) -> void:
	if game_started:
		return
	game_started = true
	net_mp = true
	net_client = not host
	local_idx = 0 if host else my_seat
	tutorial = false
	# 主机下发的全员档案(已消歧),各端一致
	seat_names = PlayerProfile.resolve_names(names) if not names.is_empty() else []
	seat_colors = PlayerProfile.resolve_colors(colors) if not colors.is_empty() else []
	seat_chars = []
	for c in chars:
		seat_chars.append(CharacterDef.valid_id(str(c)))
	seat_team_ids = PlayerProfile.resolve_teams(teams) if not teams.is_empty() else []
	_build_world(wseed, npc, nplayers)
	if OS.get_environment("WHITEBOX_MP_INTERACTION_TEST") != "":
		_setup_mp_interaction_test(nplayers)
	if net_client:
		client_view = ClientView.new(self)
		_make_client_puppets()
	net.register_world()
	hud.hide_menu()
	_set_mouse_captured(true)
	hud.set_menu_status("")
	_log_milestone("联机开局 seat=%d/%d host=%s npc=%d" % [local_idx, nplayers, host, npc])
	if OS.get_environment("WHITEBOX_MP_DRIVE_TEST") != "":
		# 主机和每台客机先各自验证出生/徒步镜头，证明本机相机不依赖房主状态。
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if not is_instance_valid(player):
				return
			_update_camera(0.2)
			var passed := not player.attached and not cam_rig.is_first_person() \
					and player.body_root.visible and not cam_rig.first_person_hands_visible()
			print("[mp] LOCAL_ON_FOOT_CAMERA=%s seat=%d host=%s third_person=%s" % [
					"PASS" if passed else "FAIL", local_idx, str(not net_client),
					str(not cam_rig.is_first_person())]))
	if net_client and OS.get_environment("WHITEBOX_MP_DRIVE_TEST") != "":
		# 联机回归：客户端按F只向主机发动作，必须等权威玩家包把attached同步回来。
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(player):
				net.send_action("drive"))
		get_tree().create_timer(1.8).timeout.connect(func() -> void:
			if not is_instance_valid(player):
				return
			_update_camera(0.2)
			var passed := player.attached and player.cart.attached_agent == player \
					and not cam_rig.is_first_person() and player.body_root.visible
			print("[mp] CLIENT_DRIVE_CAMERA=%s seat=%d attached=%s first_person=%s" % [
					"PASS" if passed else "FAIL", local_idx, str(player.attached),
					str(cam_rig.is_first_person())]))
	if net_client and OS.get_environment("WHITEBOX_MP_INTERACTION_TEST") != "":
		_run_mp_interaction_test()
	if host:
		hud.broadcast("联机对局开始!%d位\"热心顾客\"已入场,黑五愉快,手下无情~" % nplayers)

## 联机交互回归场景：为每个客户端生成一台不会被NPC随机拿走的电视，
## 各端按相同座位顺序创建，因而商品索引也完全一致。
func _setup_mp_interaction_test(nplayers: int) -> void:
	for seat in range(1, nplayers):
		var test_item := Item.create("treadmill")
		add_child(test_item)
		all_items.append(test_item)
		# 驾驶回归结束后玩家会在车把处下车，因此以车把为基准布置目标。
		test_item.set_shelved(players[seat].cart.handle_pos() + Vector3(0, 1.15, -1.2))
		_mp_interaction_test_items[seat] = test_item

## 自动化走真实客户端路径：先完成上车回归并下车，再让准星对准测试商品，
## 真实长按E；最终同时核验主机回传的手持归属与本机第三人称持物渲染。
func _run_mp_interaction_test() -> void:
	var target: Item = _mp_interaction_test_items.get(local_idx)
	if not is_instance_valid(target):
		print("[mp] CLIENT_SHELF_INTERACTION=FAIL seat=%d reason=no_target" % local_idx)
		return
	get_tree().create_timer(2.05).timeout.connect(func() -> void:
		if is_instance_valid(player) and player.attached:
			net.send_action("drive"))
	get_tree().create_timer(2.45).timeout.connect(func() -> void:
		if not is_instance_valid(player) or not is_instance_valid(target):
			return
		var origin := player.global_position + Vector3.UP * THROW_ORIGIN_HEIGHT
		var aim := (target.global_position - origin).normalized()
		cam_rig.yaw = atan2(-aim.x, -aim.z)
		cam_rig.pitch = clampf(atan2(aim.y, Vector2(aim.x, aim.z).length()),
				CameraRig.PITCH_MIN, CameraRig.PITCH_MAX))
	get_tree().create_timer(2.7).timeout.connect(func() -> void:
		if is_instance_valid(player):
			Input.action_press("interact")
			net.send_action("interact_press", cam_rig.aim_direction()))
	get_tree().create_timer(3.9).timeout.connect(func() -> void:
		Input.action_release("interact")
		net.send_action("interact_release"))
	get_tree().create_timer(4.45).timeout.connect(func() -> void:
		var passed := is_instance_valid(player) and is_instance_valid(target) \
				and player.held.has(target) and target.state == Item.ItemState.HELD \
				and target.collision_layer == 0 and not cam_rig.is_first_person() \
				and player.body_root.visible and cam_rig.first_person_held_item_count() == 0
		print("[mp] CLIENT_SHELF_INTERACTION=%s seat=%d held=%d item_state=%d third_person=%s" % [
				"PASS" if passed else "FAIL", local_idx, player.held.size(), target.state,
				str(not cam_rig.is_first_person())]))

## 主机点"开始对局"
func net_begin_match() -> void:
	net.start_game()

## 对局中有玩家掉线:该座位退场,他的车留在场上(欢迎打劫),比赛继续
func on_player_disconnected(seat: int) -> void:
	if seat <= 0 or seat >= players.size():
		return
	var p := players[seat]
	if is_instance_valid(p):
		if p.attached:
			p.detach_cart()
		p.finished = true
	if seat < pdata.size():
		pdata[seat]["done"] = true
	hud.broadcast("%s 已提前离场。他的购物车留在原地——商品先到先得~" % seat_name(seat))

func _menu_host() -> void:
	if game_started:
		return
	var ips := net.host_room()
	if ips == "":
		hud.set_menu_status("创建房间失败(端口可能被占用)")
	else:
		hud.lock_menu_for_host()
		# 房主自己也要出现在成员列表里
		net.push_profile()
		hud.set_menu_status("房间已创建!本机IP: %s (端口%d)\n把IP告诉大家,最多可容纳8人,空席由AI补齐;准备后点\"开始对局\"\n(也可改填别人的IP点\"加入房间\",本机自动改当客户端)\n若别人连不上:在本机Windows防火墙里\"允许\"本程序(UDP %d)" % [ips, Net.PORT, Net.PORT])

func _menu_join(ip: String) -> void:
	if game_started:
		return
	if ip.strip_edges() == "":
		hud.set_menu_status("请先在输入框填写主机IP")
		return
	if net.join_room(ip):
		hud.lock_menu_for_join()
		hud.set_menu_status("正在连接 %s ,连上后自动开局..." % ip.strip_edges())
		# 8秒还没进对局→给出排障提示
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if not game_started:
				hud.set_menu_status("仍在连接 %s ...\n若一直连不上:①确认主机已点\"创建房间\" ②核对IP\n③主机电脑的Windows防火墙需\"允许\"本程序(UDP %d)\n④两台电脑需在同一路由器/热点下" % [ip.strip_edges(), Net.PORT])
		)
	else:
		hud.set_menu_status("连接失败,IP格式有误?")
		hud.reset_menu_network()

## 离开房间:断开连接、清空大厅状态,菜单退回联机页
func _menu_leave_room() -> void:
	if game_started:
		return
	net.leave_lobby()
	hud.reset_menu_network()
	hud.set_menu_status("已离开房间")

# ---------- 世界构建(所有随机都在seed之后,两端一致) ----------

func _set_embedded_level_active(on: bool) -> void:
	for node_name in ["Architecture", "PerimeterCases", "ShelfIslands",
			"FeatureIslands", "RegionalArchitecture", "CheckoutZone", "WaitingRooms",
			"ServicePoints", "ZoneFloors", "ExitAprons", "LevelSignage",
			"GameplayMarkers", "AisleClearanceMarkers", "RuntimeOnly"]:
		var branch := find_child(node_name, true, false)
		if branch is Node3D:
			branch.visible = on
			_set_embedded_collision(branch, on)

func _set_runtime_only_visible(on: bool) -> void:
	_set_runtime_only_visible_recursive(self, on)

func _set_runtime_only_visible_recursive(node: Node, on: bool) -> void:
	if node != self and node.is_in_group("runtime_only") and node is Node3D:
		(node as Node3D).visible = on
	for child in node.get_children():
		_set_runtime_only_visible_recursive(child, on)

## v6施工图核对专用：隐藏天花板、HUD和运行时角色，仅由场景内正交相机出图。
## 这不会改变正常对局的相机或显示状态。
func _activate_topdown_audit() -> void:
	var audit_camera := find_child("TopDownAuditCamera", true, false) as Camera3D
	if audit_camera == null:
		push_error("New_Level缺少TopDownAuditCamera，无法生成施工俯视图")
		return
	_set_runtime_only_visible(false)
	if hud != null:
		hud.visible = false
	for child in get_children():
		if child is Actor or child is Cart or child is Item or child is Checkout:
			(child as Node3D).visible = false
	audit_camera.current = true

func _set_embedded_collision(node: Node, on: bool) -> void:
	if node is CSGShape3D:
		(node as CSGShape3D).use_collision = on and bool(node.get_meta("gameplay_collision", true))
	for child in node.get_children():
		_set_embedded_collision(child, on)

func layout_respawn_pos(height: float) -> Vector3:
	var p: Vector3 = active_layout.get("respawn_pos", MapLayout.respawn_pos(height))
	p.y = height
	return p

func layout_wander_x() -> Vector2:
	return active_layout.get("wander_x", MapLayout.wander_x())

func layout_wander_z() -> Vector2:
	return active_layout.get("wander_z", MapLayout.wander_z())

func layout_slippery_x() -> Vector2:
	return active_layout.get("slippery_x", MapLayout.slippery_x())

func layout_slippery_z() -> Vector2:
	return active_layout.get("slippery_z", MapLayout.slippery_z())

func layout_exit_x() -> float:
	return float(active_layout.get("exit_x", MapLayout.EXIT_X))

func layout_exit_inner_z() -> float:
	return float(active_layout.get("exit_inner_z", MapLayout.exit_inner_z()))

func layout_exit_outer_z() -> float:
	return float(active_layout.get("exit_outer_z", MapLayout.exit_outer_z()))

func _build_world(wseed: int, npc: int, nplayers: int) -> void:
	match_seed = wseed
	seed(wseed)
	if tutorial:
		if embedded_level:
			_set_embedded_level_active(false)
		tutorial_data = TutorialRoomBuilder.build(self)
		grid = tutorial_data["grid"]
		sale_points = []
		_make_tutorial_list()
		_spawn_players(tutorial_data, 1)
		hud.set_npc_count_display(0)
		return
	if embedded_level:
		_configure_freezer_curtains()
	var data: Dictionary = NewLevelLayout.build(self) if embedded_level else MarketBuilder.build(self)
	active_layout = data.get("layout", {})
	grid = data["grid"]
	sale_points = data["sale_points"]
	var lane_i := 0
	if data.has("checkout_specs") and not (data["checkout_specs"] as Array).is_empty():
		for spec in data["checkout_specs"]:
			lane_i += 1
			var co := Checkout.new()
			add_child(co)
			var rects := co.setup_oriented(spec, lane_i)
			for r in rects:
				MarketBuilder._mark_solid(grid, r)
			co.item_scanned.connect(_on_item_scanned)
			co.lane_settled.connect(_on_lane_settled)
			checkouts.append(co)
	else:
		for x in data["lane_x"]:
			lane_i += 1
			var co := Checkout.new()
			add_child(co)
			var rects: Array
			if data.has("checkout_config"):
				rects = co.setup_custom(x, lane_i, data["checkout_config"])
			else:
				rects = co.setup(x, lane_i)
			for r in rects:
				MarketBuilder._mark_solid(grid, r)
			co.item_scanned.connect(_on_item_scanned)
			co.lane_settled.connect(_on_lane_settled)
			checkouts.append(co)
	_setup_active_checkouts()
	_spawn_stock(data)
	_setup_central_black_friday_event()
	_make_lists(nplayers)
	_spawn_players(data, nplayers)
	_spawn_team_fillers(data, nplayers)
	_granny_spawns = data["granny_spawns"]
	region_director = RegionDirector.new(self)
	region_director.setup(data.get("zone_bounds", {}))
	_setup_sample_stands()
	hud.set_minimap_bounds(data.get("zone_bounds", {}))
	_setup_team_entrance_countdown()
	sale_times = [randf_range(55.0, 110.0), randf_range(150.0, 220.0)]
	_spawn_random_slippery(3, 0.0)
	hud.set_npc_count_display(4)
	hud.broadcast("亲爱的顾客,欢迎光临疯抢超市。今天是疯抢星期五,每人限购,理性消费,祝您购物愉快～")
	hud.broadcast("温馨提示:货架商品先到先得,请文明抢购～")

## 软门帘采用单向碰撞筛选：布条仍能感知人物和购物车并被推得摆动，
## 但人物/车辆自身的mask不识别L_CURTAIN，因此不会被门帘当成实体墙挡住。
func _configure_freezer_curtains() -> void:
	for node in get_tree().get_nodes_in_group("freezer_curtain_strip"):
		if node is RigidBody3D:
			var strip := node as RigidBody3D
			strip.collision_layer = Catalog.L_CURTAIN
			strip.collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART

## 将场边原有四座展示柜改造成可交互试吃摊。保留场景中的CSG白盒柜体，
## 仅在运行时补上统一标识，方便后续继续在编辑器里移动或替换资产。
func _setup_sample_stands() -> void:
	for node in get_tree().get_nodes_in_group("sample_stand"):
		if not (node is Node3D):
			continue
		var stand := node as Node3D
		if stand.get_node_or_null("SampleStandLabel") != null:
			continue
		var label := Label3D.new()
		label.name = "SampleStandLabel"
		label.text = "免费试吃摊\nE 互动 · 技能CD加速50%"
		label.font = Catalog.ui_font_bold()
		label.font_size = 42
		label.modulate = Color(1.0, 0.76, 0.18)
		label.outline_modulate = Color(0.12, 0.05, 0.01)
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.position = Vector3(0.0, 1.55, 0.0)
		stand.add_child(label)

## 八条收银道每局只开放四条。每个出口的两条车道随机开一条，
## 因而探索结果会变化，但不会出现某支队伍所在方向整组关闭的不公平局面。
func _setup_active_checkouts() -> void:
	active_checkout_indices = []
	if checkouts.is_empty():
		return
	if tutorial or not embedded_level:
		for i in checkouts.size():
			checkouts[i].set_round_open(true)
			active_checkout_indices.append(i)
		return
	var by_side := {}
	for i in checkouts.size():
		var side := str(checkouts[i].name).trim_prefix("Checkout_").get_slice("_", 0)
		if not by_side.has(side):
			by_side[side] = []
		by_side[side].append(i)
	for side in by_side:
		var candidates: Array = by_side[side]
		var chosen: int = candidates.pick_random()
		active_checkout_indices.append(chosen)
	for i in checkouts.size():
		checkouts[i].set_round_open(active_checkout_indices.has(i))

## 四队入口门：每端从同一关闭姿态开始；只有单机/主机推进倒计时，
## 联机客户端最终以主机可靠事件为准开门，避免帧率与入场时差造成碰撞分歧。
func _setup_team_entrance_countdown() -> void:
	team_prep_active = embedded_level and not tutorial \
			and not get_tree().get_nodes_in_group("team_start_gate").is_empty()
	team_prep_left = TEAM_PREP_DURATION if team_prep_active else 0.0
	team_prep_last_second = int(ceil(team_prep_left))
	team_entrance_opened = not team_prep_active
	for node in get_tree().get_nodes_in_group("team_start_gate"):
		if node is CSGBox3D:
			var gate := node as CSGBox3D
			gate.position.y = 1.65
			gate.use_collision = true
	if not team_prep_active:
		if hud != null:
			hud.set_prep_countdown(0, false)
		return
	# 准备阶段只封住入口；玩家仍可在等待室内活动，参赛AI保持物理帧存活，
	# 但由prep_locked暂停决策，避免联机/动画事件漏掉后永久停摆。
	if not net_client:
		for g in grannies:
			if is_instance_valid(g):
				g.prep_locked = true
	_apply_team_prep_hud(team_prep_last_second)

func _tick_team_entrance_countdown(delta: float) -> void:
	if not team_prep_active:
		return
	team_prep_left = maxf(0.0, team_prep_left - delta)
	var seconds := int(ceil(team_prep_left))
	if seconds != team_prep_last_second:
		team_prep_last_second = seconds
		_apply_team_prep_hud(seconds)
		if not net_client and seconds <= 5 and seconds > 0:
			var callout := "入口将在 %d 秒后开放——准备冲刺!" % seconds
			hud.broadcast(callout)
	if not net_client and team_prep_left <= 0.0:
		open_team_entrances()

func _apply_team_prep_hud(seconds: int) -> void:
	if hud == null or not team_prep_active:
		return
	hud.set_timer_text("准备 %02d" % maxi(seconds, 0), Color(1.0, 0.82, 0.25))
	hud.set_prep_countdown(seconds, true)
	hud.set_phase("队伍等待室 · 倒计时后大门开启")

func open_team_entrances(from_network := false) -> void:
	if team_entrance_opened:
		return
	team_entrance_opened = true
	team_prep_active = false
	team_prep_left = 0.0
	if hud != null:
		hud.set_prep_countdown(0, false)
		hud.set_sensitivity_panel(false)
	_set_mouse_captured(true)
	for node in get_tree().get_nodes_in_group("team_start_gate"):
		if not (node is CSGBox3D):
			continue
		var gate := node as CSGBox3D
		_slide_csg_gate_up(gate, 0.75, GATE_SLIDE_DURATION)
	if not net_client:
		for g in grannies:
			if is_instance_valid(g):
				g.release_from_prep()
	var announcement := "开门!四队入口同步开放——开始扫货!"
	hud.broadcast(announcement)
	if net_mp and not net_client and not from_network:
		net.rpc("ev_team_entrances_open")

## 教学关固定三件结业清单，避免随机清单与房间内训练物资错位。
func _make_tutorial_list() -> void:
	var list: Array = []
	for id in ["tissue", "thermos"]:
		list.append(OrderSystem.exact(id))
	pdata = [{"list": list, "score": 0, "counts": {}, "orig": 0, "saved": 0,
			"settled": false, "done": false}]

var _large_slots: Array = []

## 货位每局随机:目录商品按库存洗牌进本分区货位
func _spawn_stock(data: Dictionary) -> void:
	_large_slots = data["tv_slots"].duplicate()
	var zone_slots := {}
	for s in data["slots"]:
		if not zone_slots.has(s["zone"]):
			zone_slots[s["zone"]] = []
		zone_slots[s["zone"]].append(s)
	for zone in zone_slots:
		zone_slots[zone].shuffle()
	# 大件仍使用家电区专用地面展示位，不与双层货架商品争槽位。
	for id in Catalog.ITEMS:
		var info: Dictionary = Catalog.ITEMS[id]
		if info["cat"] == Catalog.CAT_LARGE:
			for i in int(info["stock"]):
				if _large_slots.is_empty():
					break
				var tp: Vector3 = _large_slots.pop_front()
				var tv := Item.create(id)
				add_child(tv)
				tv.set_shelved(Vector3(tp.x, 0.4 + tv.shelf_display_half_height() + 0.05, tp.z))
				all_items.append(tv)
	# 每区依次执行6低档、3中档、1高档的十件循环；每档内部轮换SKU，
	# 既让层板更满，也避免单一低价包装铺满整条货架。
	for zone in zone_slots:
		var slots: Array = zone_slots[zone]
		var stock_ids := _tiered_shelf_stock(str(zone), slots.size())
		for id in stock_ids:
			if slots.is_empty():
				break
			var info: Dictionary = Catalog.ITEMS[id]
			var slot: Dictionary = slots.pop_back()
			var pos: Vector3 = slot["pos"]
			var it := Item.create(id)
			add_child(it)
			# 货架展示尺寸为车内真实尺寸2倍，摆位也使用放大后的物理半高。
			it.set_shelved(pos + Vector3(0, it.shelf_display_half_height(), 0),
					float(slot.get("yaw", 0.0)))
			if embedded_level and str(zone) == Catalog.ZONE_PREMIUM:
				it.set_event_locked(true)
				central_locked_items.append(it)
			all_items.append(it)

func _tiered_shelf_stock(zone: String, slot_count: int) -> Array[String]:
	var count := Catalog.shelf_stock_target(zone, slot_count)
	var pools := {}
	var cursors := {}
	for tier in [Catalog.TIER_LOW, Catalog.TIER_MID, Catalog.TIER_HIGH]:
		var pool := Catalog.ids_of_zone_tier(zone, tier)
		if zone == Catalog.ZONE_FRESH:
			# 会蹦跳的皮皮虾/闲鱼只在地面生态中生成，货柜用同档其他生鲜补位。
			pool = pool.filter(func(id: String) -> bool:
				return not Catalog.LIVE_FRESH_IDS.has(id))
		pool.shuffle()
		pools[tier] = pool
		cursors[tier] = 0
	var out: Array[String] = []
	for i in count:
		var tier: int = Catalog.TIER_PATTERN[i % Catalog.TIER_PATTERN.size()]
		var pool: Array = pools[tier]
		if pool.is_empty():
			# 数据漏档时才回退到本区任意SKU，防止整区因为策划表错误而空架。
			for fallback_tier in [Catalog.TIER_LOW, Catalog.TIER_MID, Catalog.TIER_HIGH]:
				pool.append_array(pools[fallback_tier])
		if pool.is_empty():
			continue
		var cursor := int(cursors[tier])
		out.append(str(pool[cursor % pool.size()]))
		cursors[tier] = cursor + 1
	return out

## 中央黑五区：默认封闭并隐藏压轴货，比赛过半后15–45秒随机开启。
## 门是场景内手工CSG节点；这里只负责状态，不生成任何关卡几何。
func _setup_central_black_friday_event() -> void:
	central_warned = false
	central_opened = false
	central_open_at = -1.0
	central_feature_id = ""
	central_feature_ids = []
	if not embedded_level:
		return
	var gates := get_tree().get_nodes_in_group("central_black_friday_gate")
	if gates.is_empty():
		for it in central_locked_items:
			if is_instance_valid(it):
				it.set_event_locked(false)
		return
	central_open_at = randf_range(CENTRAL_EVENT_EARLIEST, CENTRAL_EVENT_LATEST)
	# 只从本局中央展台实际生成的SKU中选1—3种，避免抽到场内不存在的商品。
	var candidates: Array[String] = []
	var candidate_stock := {}
	for it in central_locked_items:
		if not is_instance_valid(it):
			continue
		candidate_stock[it.item_id] = int(candidate_stock.get(it.item_id, 0)) + 1
		if not candidates.has(it.item_id):
			candidates.append(it.item_id)
	if not candidates.is_empty():
		var feature_rng := RandomNumberGenerator.new()
		feature_rng.seed = match_seed ^ 0x4B1ACF
		var feature_count := feature_rng.randi_range(1, mini(3, candidates.size()))
		# 先随机打散同库存候选，再优先从库存较足的SKU里抽取。若初抽种类合计
		# 不足4件，则在最多3种的限制内继续补种类，确保开门必有4—5件可揭晓。
		for i in range(candidates.size() - 1, 0, -1):
			var j := feature_rng.randi_range(0, i)
			var temp := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = temp
		candidates.sort_custom(func(a: String, b: String) -> bool:
			return int(candidate_stock.get(a, 0)) > int(candidate_stock.get(b, 0)))
		for id in candidates:
			if central_feature_ids.size() >= feature_count:
				break
			central_feature_ids.append(id)
		var selected_stock := 0
		for id in central_feature_ids:
			selected_stock += int(candidate_stock.get(id, 0))
		for id in candidates:
			if selected_stock >= 4 or central_feature_ids.size() >= 3:
				break
			if not central_feature_ids.has(id):
				central_feature_ids.append(id)
				selected_stock += int(candidate_stock.get(id, 0))
		central_feature_id = central_feature_ids[0]
	for node in gates:
		if node is CSGBox3D:
			var gate := node as CSGBox3D
			gate.position.y = 1.5
			gate.use_collision = true

func _tick_central_black_friday_event() -> void:
	if central_opened or central_open_at < 0.0:
		return
	if not central_warned and elapsed >= central_open_at - CENTRAL_EVENT_WARNING:
		central_warned = true
		var warning := "黑五压轴区即将开放!四个方向大门准备升起——"
		hud.broadcast(warning)
		if net_mp and not net_client:
			net.rpc("ev_broadcast", warning)
	if elapsed >= central_open_at:
		open_central_black_friday()

func open_central_black_friday(from_network := false) -> void:
	if central_opened:
		return
	central_opened = true
	for node in get_tree().get_nodes_in_group("central_black_friday_gate"):
		if not (node is CSGBox3D):
			continue
		var gate := node as CSGBox3D
		_slide_csg_gate_up(gate, 0.9, GATE_SLIDE_DURATION)
	# 最终只留下4—5件，并保证抽中的1—3种各至少出现一件。
	var stock_rng := RandomNumberGenerator.new()
	stock_rng.seed = match_seed ^ 0x71C0A5
	var desired_total := stock_rng.randi_range(4, 5)
	var by_id := {}
	for it in central_locked_items:
		if is_instance_valid(it) and central_feature_ids.has(it.item_id):
			if not by_id.has(it.item_id):
				by_id[it.item_id] = []
			by_id[it.item_id].append(it)
	var keep: Array[Item] = []
	for id in central_feature_ids:
		var pool: Array = by_id.get(id, [])
		if not pool.is_empty():
			keep.append(pool.pop_front())
	while keep.size() < desired_total:
		var available_ids: Array = by_id.keys().filter(func(id): return not (by_id[id] as Array).is_empty())
		if available_ids.is_empty():
			break
		var picked_id = available_ids[stock_rng.randi_range(0, available_ids.size() - 1)]
		keep.append((by_id[picked_id] as Array).pop_front())
	for it in central_locked_items:
		if not is_instance_valid(it):
			continue
		if keep.has(it):
			it.set_event_locked(false)
		else:
			net_item_gone_notify(it)
			it.queue_free()
	var reveal_names: Array[String] = []
	for id in central_feature_ids:
		if Catalog.ITEMS.has(id):
			reveal_names.append(str(Catalog.ITEMS[id]["name"]))
	var reveal_stock := keep.size()
	var announcement := "黑五压轴区现已开放!本局%d种高价爆款揭晓:%s（全场%d件）!" \
			% [reveal_names.size(), " / ".join(reveal_names), reveal_stock]
	hud.broadcast(announcement)
	# 黑五开门后抽取一部分非主控AI，将其临时购物欲切向中央热点。
	if not net_client and not team_bots.is_empty():
		var contenders: Array = team_bots.filter(func(bot): return is_instance_valid(bot))
		contenders.shuffle()
		var rush_count := randi_range(1, mini(5, contenders.size()))
		var center := Vector3.ZERO
		for it in keep:
			center += it.global_position
		if not keep.is_empty():
			center /= float(keep.size())
		for i in rush_count:
			(contenders[i] as Granny).rush_to_black_friday(center, central_feature_ids)
	if net_mp and not net_client and not from_network:
		net.rpc("ev_central_black_friday_open")

## 所有整扇CSG门共用向上滑入门楣的开启动画。碰撞保留到动画结束，
## 防止视觉门板还在半空时角色或购物车提前穿过去。
func _slide_csg_gate_up(gate: CSGBox3D, top_clearance: float, duration: float) -> void:
	if not is_instance_valid(gate):
		return
	var start_y := gate.position.y
	var target_y := start_y + gate.size.y + top_clearance
	gate.use_collision = true
	gate.set_meta("slide_open_start_y", start_y)
	gate.set_meta("slide_open_target_y", target_y)
	gate.set_meta("slide_open_animating", true)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(gate, "position:y", target_y, maxf(duration, 0.05))
	tween.finished.connect(func() -> void:
		if is_instance_valid(gate):
			gate.use_collision = false
			gate.set_meta("slide_open_animating", false))

## 正式对局使用纯点名订单。每队共享25件，并只从四个专区抽取：本队入口
## 首区保底、两处全队共享热点、剩余专区随机。商品实例无放回分配，因此
## 同SKU可形成×N，但四队合计需求绝不会超过开局真实库存。
func _make_lists(nplayers: int) -> void:
	team_data = []
	var stock_by_zone := {}
	for zone in Catalog.SHOPPING_ZONES:
		stock_by_zone[zone] = []
	for it in all_items:
		if not is_instance_valid(it) or it.state != Item.ItemState.SHELVED \
				or not Catalog.ITEMS.has(it.item_id):
			continue
		var info: Dictionary = Catalog.ITEMS[it.item_id]
		# 中央压轴商品保持额外争夺价值，不在开局订单中提前泄露或占用25件额度。
		if str(info.get("zone", "")) == Catalog.ZONE_PREMIUM \
				or str(info.get("cat", "")) == Catalog.CAT_SALE:
			continue
		var zone := str(info.get("zone", ""))
		if stock_by_zone.has(zone):
			(stock_by_zone[zone] as Array).append(it.item_id)
	var team_counts: Array = [{}, {}, {}, {}]
	var team_totals := [0, 0, 0, 0]
	var order_rng := RandomNumberGenerator.new()
	order_rng.seed = int(match_seed) ^ 0x30D3A
	# 两个共享热点对四队一致，确保每队至少有两个专区会与其他队发生交集。
	var shuffled_zones: Array = Catalog.SHOPPING_ZONES.duplicate()
	for i in range(shuffled_zones.size() - 1, 0, -1):
		var j := order_rng.randi_range(0, i)
		var temp = shuffled_zones[i]
		shuffled_zones[i] = shuffled_zones[j]
		shuffled_zones[j] = temp
	var shared_zones := [str(shuffled_zones[0]), str(shuffled_zones[1])]
	var team_zones: Array = []
	for team_id in 4:
		var zones: Array[String] = [str(TEAM_ENTRY_ORDER_ZONES[team_id])]
		for shared in shared_zones:
			if not zones.has(shared):
				zones.append(shared)
		var random_candidates: Array = shuffled_zones.duplicate()
		while zones.size() < 4 and not random_candidates.is_empty():
			var candidate := str(random_candidates.pop_front())
			if not zones.has(candidate):
				zones.append(candidate)
		team_zones.append(zones)
	# 每个指定专区先保底抽一件，确保订单确实由四区构成，而非仅限制候选范围。
	for team_id in 4:
		for zone in team_zones[team_id]:
			var zone_pool: Array = stock_by_zone.get(zone, [])
			if zone_pool.is_empty():
				push_error("订单专区%s没有可分配库存" % zone)
				continue
			var pool_index := order_rng.randi_range(0, zone_pool.size() - 1)
			var chosen := str(zone_pool[pool_index])
			zone_pool.remove_at(pool_index)
			team_counts[team_id][chosen] = int(team_counts[team_id].get(chosen, 0)) + 1
			team_totals[team_id] += 1
	# 逐轮给四队补货，避免第一队先吃完共享专区库存。
	while team_totals.any(func(total: int) -> bool: return total < TEAM_ORDER_TOTAL):
		var made_progress := false
		for team_id in 4:
			if team_totals[team_id] >= TEAM_ORDER_TOTAL:
				continue
			var available_zones: Array = (team_zones[team_id] as Array).filter(func(zone):
				return not (stock_by_zone.get(zone, []) as Array).is_empty())
			if available_zones.is_empty():
				continue
			var chosen_zone := str(available_zones[order_rng.randi_range(0, available_zones.size() - 1)])
			var zone_pool: Array = stock_by_zone[chosen_zone]
			var pool_index := order_rng.randi_range(0, zone_pool.size() - 1)
			var chosen: String = str(zone_pool[pool_index])
			zone_pool.remove_at(pool_index)
			team_counts[team_id][chosen] = int(team_counts[team_id].get(chosen, 0)) + 1
			team_totals[team_id] += 1
			made_progress = true
		if not made_progress:
			push_error("场内可分配库存不足，无法为四队生成各25件四区点名订单")
			break
	for team_id in 4:
		var list: Array = []
		var ids: Array = team_counts[team_id].keys()
		ids.sort_custom(func(a, b) -> bool:
			var zone_a := str(Catalog.ITEMS[a]["zone"])
			var zone_b := str(Catalog.ITEMS[b]["zone"])
			return str(Catalog.ITEMS[a]["name"]) < str(Catalog.ITEMS[b]["name"]) \
					if zone_a == zone_b else zone_a < zone_b)
		for id in ids:
			list.append(OrderSystem.exact_count(str(id), int(team_counts[team_id][id])))
		team_data.append({"team_id": team_id, "list": list,
				"order_zones": team_zones[team_id].duplicate(), "score": 0,
				"counts": {}, "orig": 0, "saved": 0, "vouchers": [],
				"checkout_ready_slots": [false, false]})
	pdata = []
	for seat in nplayers:
		var tid := team_id_for_seat(seat)
		pdata.append({"team_id": tid, "list": team_data[tid]["list"], "score": 0,
				"counts": {}, "orig": 0, "saved": 0, "settled": false, "done": false})

## 玩家出生:最多8人，固定四队各两席；空席由AI队友补齐。
## 各座位的昵称与旧协议色索引。正式比赛外观以seat_team_ids的队伍色为准。
var seat_names: Array[String] = []
var seat_colors: Array[int] = []
var seat_team_ids: Array[int] = []
## 各座位所选角色 id(见 character_def.gd)。联机由主机下发,保证各端一致。
var seat_chars: Array[String] = []

## 座位 i 的显示名。没有档案时回落到"玩家N"
func seat_name(i: int) -> String:
	if i >= 0 and i < seat_names.size():
		return seat_names[i]
	return "玩家%d" % (i + 1)

## 第二人称称呼:本机是"你",别人用昵称
func seat_name_2nd(i: int) -> String:
	return "你" if i == local_idx else seat_name(i)

func seat_color(i: int) -> Color:
	if not tutorial:
		return Catalog.team_color(team_id_for_seat(i))
	if i >= 0 and i < seat_colors.size():
		return PlayerProfile.color_of(seat_colors[i])
	return PlayerProfile.color_of(i)

func team_id_for_seat(i: int) -> int:
	if i >= 0 and i < seat_team_ids.size():
		return clampi(seat_team_ids[i], 0, 3)
	return posmod(i, 4)

func team_slot_for_seat(i: int) -> int:
	var tid := team_id_for_seat(i)
	var slot := 0
	for previous in i:
		if team_id_for_seat(previous) == tid:
			slot += 1
	return clampi(slot, 0, 1)

func _competition_spawn(seat: int) -> Vector3:
	var tid := team_id_for_seat(seat)
	var slot := team_slot_for_seat(seat)
	return _competition_spawn_for_team(tid, slot)

func _competition_spawn_for_team(tid: int, slot: int) -> Vector3:
	var centers := [Vector3(-27.5, 0.1, 33.75), Vector3(27.5, 0.1, 33.75),
			Vector3(-27.5, 0.1, -33.75), Vector3(27.5, 0.1, -33.75)]
	var center: Vector3 = centers[clampi(tid, 0, 3)]
	var facing := Vector3(-center.x, 0.0, -center.z).normalized()
	var side := Vector3(facing.z, 0.0, -facing.x).normalized()
	var specs: Array = active_layout.get("team_spawn_specs", [])
	if tid >= 0 and tid < specs.size():
		var spec: Dictionary = specs[tid]
		center = spec.get("center", center)
		facing = spec.get("facing", facing)
		side = spec.get("side", side)
	# 两席以等待室中心为中点，只错开0.7米防止胶囊重叠。
	return center + side * (-0.7 if slot == 0 else 0.7)

func _competition_facing_for_team(tid: int) -> Vector3:
	var specs: Array = active_layout.get("team_spawn_specs", [])
	if tid >= 0 and tid < specs.size():
		return Vector3((specs[tid] as Dictionary).get("facing", Vector3.FORWARD)).normalized()
	var pos := _competition_spawn_for_team(tid, 0)
	return Vector3(-pos.x, 0.0, -pos.z).normalized()

func _face_actor_and_cart_to_store(actor: Actor, actor_cart: Cart, tid: int) -> void:
	var facing := _competition_facing_for_team(tid)
	var yaw := atan2(-facing.x, -facing.z)
	actor.body_root.global_rotation = Vector3(0.0, yaw, 0.0)
	actor_cart.global_rotation = Vector3(0.0, yaw, 0.0)
	actor_cart.global_position = actor.global_position + facing * 1.28 + Vector3.UP * 0.1

func team_inventory_actors(team_id: int) -> Array[Actor]:
	var out: Array[Actor] = []
	for p in players:
		if is_instance_valid(p) and p.team_id == team_id:
			out.append(p)
	for bot in team_bots:
		if is_instance_valid(bot) and bot.team_id == team_id:
			out.append(bot)
	return out

## 座位 i 的角色 id。缺档时回落到首个角色
func seat_char(i: int) -> String:
	if i >= 0 and i < seat_chars.size():
		return CharacterDef.valid_id(seat_chars[i])
	return CharacterDef.ORDER[0]

func _spawn_players(data: Dictionary, nplayers: int) -> void:
	# 单机:直接使用本机昵称、角色与队伍偏好。
	if seat_names.is_empty():
		PlayerProfile.ensure_loaded()
		seat_names = [PlayerProfile.display_name]
		seat_colors = [PlayerProfile.color_index]
	if seat_chars.is_empty():
		PlayerProfile.ensure_loaded()
		seat_chars = [PlayerProfile.char_id]
	for i in nplayers:
		var p := Player.new()
		p.main = self
		p.remote = (i != local_idx)
		p.team_id = team_id_for_seat(i)
		p.team_slot = team_slot_for_seat(i)
		p.avatar_color = seat_color(i)
		p.seat_label = "%s%d · %s" % [Catalog.team_name(p.team_id, true), p.team_slot + 1, seat_name(i)]
		p.char_id = seat_char(i)
		add_child(p)
		if embedded_level and not tutorial:
			p.global_position = _competition_spawn(i)
		elif data.has("player_spawns") and not data["player_spawns"].is_empty():
			var spawn_list: Array = data["player_spawns"]
			p.global_position = spawn_list[i % spawn_list.size()]
		else:
			p.global_position = data["player_spawn"] + Vector3(-2.2 * i, 0, 0.9 * (i % 2))
		var cart := Cart.create(p.avatar_color, "%s的车" % seat_name(i))
		cart.cart_owner = p
		add_child(cart)
		_face_actor_and_cart_to_store(p, cart, p.team_id)
		p.cart = cart
		players.append(p)
		if p.char_id == CharacterDef.MA:
			for buddy_slot in 2:
				var buddy := WarehouseBuddy.new()
				add_child(buddy)
				buddy.setup(p, buddy_slot)
				p.buddies.append(buddy)
				warehouse_buddies.append(buddy)
	# 所有玩家车都与两名随从双向忽略；这里在玩家全部生成后补齐跨玩家组合。
	for buddy in warehouse_buddies:
		for p in players:
			buddy.ignore_player_cart(p.cart)
	player = players[local_idx]
	# 自己的头顶名牌对本机没有信息价值，且近镜头时会挡住视野。
	# 其他队员/对手的名牌仍按原有遮挡规则正常显示。
	if is_instance_valid(player.name_label):
		player.name_label.visible = false
	if embedded_level and not tutorial:
		var local_facing := _competition_facing_for_team(player.team_id)
		cam_rig.yaw = atan2(-local_facing.x, -local_facing.z)

func _spawn_team_fillers(_data: Dictionary, human_count: int) -> void:
	team_bots = []
	if tutorial or not embedded_level:
		return
	var occupied := {}
	for seat in human_count:
		occupied[Vector2i(team_id_for_seat(seat), team_slot_for_seat(seat))] = true
	for tid in 4:
		for slot in 2:
			if occupied.has(Vector2i(tid, slot)):
				continue
			var bot := Granny.new()
			bot.main = self
			bot.is_team_bot = true
			bot.team_id = tid
			bot.team_slot = slot
			bot.body_color = Catalog.team_color(tid)
			bot.shopping_list = _team_bot_targets(tid, slot)
			add_child(bot)
			bot.global_position = _competition_spawn_for_team(tid, slot)
			bot.name_label.text = "%s%d · AI队友" % [Catalog.team_name(tid, true), slot + 1]
			bot.name_label.modulate = Catalog.team_color(tid).lightened(0.35)
			var cart := Cart.create(bot.body_color,
					"%s%d AI车" % [Catalog.team_name(tid, true), slot + 1])
			cart.cart_owner = bot
			add_child(cart)
			_face_actor_and_cart_to_store(bot, cart, tid)
			bot.cart = cart
			bot.attach_cart()
			team_bots.append(bot)
			grannies.append(bot)

func _team_bot_targets(team_id: int, slot: int) -> Array:
	var out: Array = []
	if team_id < 0 or team_id >= team_data.size():
		return out
	for entry in team_data[team_id]["list"]:
		var candidates: Array = OrderSystem.candidate_ids(entry)
		if candidates.is_empty():
			continue
		# 每条点名数量在两个席位间交错拆分；重复ID代表该AI需要取得多件同名商品。
		# 真人占据其中一席时，AI仍只承担自己的半份，剩余缺口留给真人协作完成。
		for unit in OrderSystem.required(entry):
			if posmod(unit, 2) == posmod(slot, 2):
				out.append(str(candidates[0]))
	return out

var _granny_spawns: Array = []
var _granny_seq := 0

func _spawn_one_granny() -> void:
	var pos: Vector3 = _granny_spawns[_granny_seq % _granny_spawns.size()]
	_granny_seq += 1
	var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
	# 从点名项目和类别候选池共同抽取NPC目标。类别单会把压力分散到多个货架，
	# 点名爆款仍会保持明确争夺热点。
	var overlap_pool: Array = []
	var large_pool: Array = []
	for pd in pdata:
		for entry in pd["list"]:
			for id in OrderSystem.candidate_ids(entry):
				if Catalog.ITEMS[id]["cat"] == Catalog.CAT_LARGE:
					if not large_pool.has(id):
						large_pool.append(id)
				elif not overlap_pool.has(id):
					overlap_pool.append(id)
	var g := Granny.new()
	g.main = self
	g.body_color = Color.from_hsv(randf(), 0.45, 0.85)
	overlap_pool.shuffle()
	var list: Array = [overlap_pool[0], overlap_pool[1], overlap_pool[2]]
	# 每位大妈有概率(60%)额外追加一件大件到清单,保证大件货也有人抢
	large_pool.shuffle()
	if not large_pool.is_empty() and randf() < 0.6:
		list.append(large_pool[0])
	normals.shuffle()
	for id in normals:
		if list.size() >= 5:
			break
		if not list.has(id):
			list.append(id)
	g.shopping_list = list
	add_child(g)
	g.global_position = pos
	var gc := Cart.create(g.body_color, "大妈%d的车" % _granny_seq)
	gc.cart_owner = g
	add_child(gc)
	gc.global_position = pos + Vector3(1.3, 0.2, 0)
	g.cart = gc
	grannies.append(g)

## 开发者模式:滑块调NPC数量(0-10)。开局前只记数;联机中禁用(会破坏同步)。
func _set_npc_count(n: int) -> void:
	if not game_started:
		pending_npc = 4
		if hud != null:
			hud.set_npc_count_display(4)
		return
	# 四队模式不允许运行时增删扫货参赛者；环境大妈由RegionDirector管理。
	return

func _neutral_granny_count() -> int:
	var count := 0
	for g in grannies:
		if is_instance_valid(g) and not g.is_team_bot:
			count += 1
	return count

## 客户端:所有实体转为傀儡(不模拟,只按同步状态摆位)
func _make_client_puppets() -> void:
	for p in players:
		p.set_physics_process(false)
		p.set_process_unhandled_input(false)
	for g in grannies:
		g.set_physics_process(false)
	for buddy in warehouse_buddies:
		if is_instance_valid(buddy):
			buddy.set_physics_process(false)
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		c.freeze = true
		c.set_physics_process(false)
	for co in checkouts:
		co.set_physics_process(false)
	# 软门帘也由主机物理权威模拟；客户端冻结刚体，只插值显示主机下发的姿态。
	for node in get_tree().get_nodes_in_group("freezer_curtain_strip"):
		if node is RigidBody3D:
			(node as RigidBody3D).freeze = true

# ---------- 教学关 ----------

## 仅教学模式下创建；独立五房地图数据与教学导演。
var tutorial_guide: TutorialGuide
var tutorial_data: Dictionary = {}
var tutorial_probe

## 仅 WHITEBOX_PHYSTEST 下创建:车斗物理压力测试,见 phys_stress.gd
var phys_stress: PhysStress

## 仅 WHITEBOX_CHARTEST 下创建:角色技能自检,见 char_probe.gd
var char_probe: CharProbe

## 仅 WHITEBOX_NPCTEST 下创建:NPC争抢/互殴与HUD满槽自检,见 npc_probe.gd
var npc_probe: NpcProbe

## 仅 WHITEBOX_PROPTEST 下创建:场内商品道具专项回归,见 prop_probe.gd
var prop_probe: PropProbe

## 仅 WHITEBOX_ORDERTEST 下创建:25件四专区队伍订单与库存匹配专项回归。
var order_probe: OrderProbe

## 仅 WHITEBOX_LEVELTEST 下创建：New_Level实体CSG与过道净宽专项回归。
var new_level_probe: NewLevelProbe

# ---------- 环境与相机 ----------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.9, 0.92, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	# ACES压高光，避免美术资产的亮色贴图在顶灯下截成纯白。
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.88
	# 顶灯是主光源；环境光只负责补足阴影，不再叠加一盏全场太阳。
	env.ambient_light_energy = 0.4
	# 个护美妆区使用局部FogVolume。全局密度保持0，只启用体积采样能力。
	env.volumetric_fog_enabled = embedded_level
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 1.6
	var we := WorldEnvironment.new()
	we.name = "GameEnvironment"
	we.environment = env
	add_child(we)
	if embedded_level:
		for node in get_tree().get_nodes_in_group("aisle_downlight"):
			if node is SpotLight3D:
				var aisle_light := node as SpotLight3D
				aisle_light.light_energy = 1.05
				aisle_light.spot_range = 12.0
				aisle_light.shadow_enabled = true
	cam_rig = CameraRig.new()
	add_child(cam_rig)

## 碰撞相机震动:只震"这名玩家"所在的机器(net.gd 收到 ev_shake 也走这里)
func add_camera_shake(v: float) -> void:
	if cam_rig != null:
		cam_rig.add_shake(v)

func shake_for(a: Actor, v: float) -> void:
	if not (a is Player):
		return
	if a == player:
		add_camera_shake(v)
	elif net_mp and not net_client:
		var pid := net.peer_of_seat(players.find(a))
		if net.peer_alive(pid):
			net.rpc_id(pid, "ev_shake", v)

# ---------- 主循环 ----------

var _shot_path := ""
var _void_sweep_timer := 2.0
var _hl_timer := 0.5
var _hud_net_timer := 0.0

# Q技能:找货雷达(本机视觉)
var locate_time := 0.0
var locate_targets: Array = []

# 保洁阿姨定时拖地(随机临时地滑)
var _mop_timer := 50.0
var _time_calls: Array = [
	[240.0, "温馨提示:距离本店打烊还有4分钟,请合理规划您的抢购路线~"],
	[180.0, "距离打烊还有3分钟。犹豫就会败北,下手就在此刻~"],
	[60.0, "距离打烊还有1分钟,收银台不提供讨价还价服务~"],
	[30.0, "距离打烊还有30秒!跑起来!文明地跑起来!"],
]
var _steal_bc_cd := 0.0
var _down_bc_cd := 0.0

func _process(delta: float) -> void:
	_update_camera(delta)
	if not game_started:
		return
	if net_client:
		if not game_over:
			_tick_team_entrance_countdown(delta)
			_client_tick(delta)
		return
	if game_over:
		return
	if team_prep_active:
		_tick_team_entrance_countdown(delta)
		_update_hud()
		return
	if region_director != null:
		region_director.tick(delta)
	_tick_locate(delta)

	if phys_stress != null:
		phys_stress.tick(delta)
	if char_probe != null:
		char_probe.tick(delta)
	if npc_probe != null:
		npc_probe.tick(delta)
	if prop_probe != null:
		prop_probe.tick(delta)

	if tutorial:
		if tutorial_probe != null:
			tutorial_probe.tick()
		tutorial_guide.tick(delta)
	else:
		elapsed += delta
		_tick_central_black_friday_event()
		if not in_grace:
			time_left = maxf(0.0, time_left - delta)
			if not closing_announced and time_left <= CLOSING_WARN:
				closing_announced = true
				hud.broadcast("亲爱的顾客,本店即将打烊,请您尽快前往收银区完成结算——两条收银通道打烊前持续开放~")
			if time_left <= 0.0:
				in_grace = true
				hud.broadcast("叮——本店已打烊。仍在卖场内的顾客请注意:30秒内未完成结算的商品将全部作废哦～")
		else:
			grace_left -= delta
			if grace_left <= 0.0:
				_match_time_up()

		if not sale_times.is_empty() and elapsed >= float(sale_times[0]):
			sale_times.pop_front()
			_trigger_flash_sale()

		if not in_grace:
			while not _time_calls.is_empty() and time_left <= float(_time_calls[0][0]):
				hud.broadcast(_time_calls.pop_front()[1])

		_mop_timer -= delta
		if _mop_timer <= 0.0:
			_mop_timer = randf_range(55.0, 85.0)
			_spawn_random_slippery(1, 25.0)
			hud.broadcast("保洁阿姨已上线:拖把所到之处寸步难行,请各位顾客小心地滑~")

	# 兜底:掉出世界的散货拉回入口。0.5秒一扫(穿模已在物理层修掉,这里只是保险)
	_void_sweep_timer -= delta
	if _void_sweep_timer <= 0.0:
		_void_sweep_timer = 0.5
		for it in all_items:
			if is_instance_valid(it) and it.state == Item.ItemState.FREE and it.global_position.y < -5.0:
				it.set_free_at(layout_respawn_pos(0.8))

	# 红色高亮(杀意感知):本机玩家"还缺"的商品在谁车里,那辆车亮红壳
	_hl_timer -= delta
	if _hl_timer <= 0.0:
		_hl_timer = 0.25
		_apply_highlights_local()

	# 联机:定期把每名客户端玩家的HUD数据发给对应的人
	if net_mp:
		_hud_net_timer -= delta
		if _hud_net_timer <= 0.0:
			_hud_net_timer = 0.25
			for i in range(1, players.size()):
				var pid := net.peer_of_seat(i)
				if net.peer_alive(pid):
					net.rpc_id(pid, "ev_hud", _build_rows(i), pdata[i]["score"], _hot_carts_for(i))

	_update_hud()

## 红壳(杀意感知):本机玩家"还缺"的商品在谁车里,那辆车亮红壳。
##
## 距离规则(《05·三》与《16·五·5.2》):
## - 通用版:仅 12 米内亮壳,不显示商品名
## - 李洋「主播手速」:仅 8 米内提示链接图标,不显示具体商品名
func _apply_highlights_local() -> void:
	var missing_hl := missing_list_ids(local_idx)
	var sniff := CharSkills.has_sniff(player)
	var origin := player.global_position
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c):
			continue
		if c == player.cart:
			c.set_highlight(false)
			continue
		var hot_name := ""
		for it2 in c.items_in_basket():
			if missing_hl.has(it2.item_id):
				hot_name = it2.display_name
				break
		var hot := hot_name != ""
		var sense_range := CharSkills.LI_LINK_RANGE if sniff else CharSkills.SNIFF_RANGE_OTHERS
		if hot and origin.distance_to(c.global_position) > sense_range:
			hot = false
		c.set_highlight(hot)
		c.set_hot_name("🔗" if (hot and sniff) else "")

## 发给某客户端的红壳数据:[[车下标, 商品名或""], ...]
## 李洋只在 8 米内收到链接图标；非李洋沿用 12 米通用红壳。
func _hot_carts_for(idx: int) -> Array:
	var missing := missing_list_ids(idx)
	var p := players[idx]
	var sniff := CharSkills.has_sniff(p)
	var out: Array = []
	for i in net.carts_net.size():
		var c = net.carts_net[i]
		if not is_instance_valid(c) or c == p.cart:
			continue
		var hot_name := ""
		for it in c.items_in_basket():
			if missing.has(it.item_id):
				hot_name = it.display_name
				break
		if hot_name == "":
			continue
		var sense_range := CharSkills.LI_LINK_RANGE if sniff else CharSkills.SNIFF_RANGE_OTHERS
		if p.global_position.distance_to(c.global_position) > sense_range:
			continue
		out.append([i, "🔗" if sniff else ""])
	return out

# ---------- 客户端渲染 ----------

## 仅客户端创建:状态包缓存与插值渲染,详见 client_view.gd
var client_view: ClientView

func apply_net_state(d: Dictionary) -> void:
	if client_view != null:
		client_view.apply_state(d)

## 李洋截货成功后，仅让受害玩家看见李洋名牌的红色追踪描边。
func expose_li_to(victim_seat: int, li_seat: int, duration: float) -> void:
	if victim_seat < 0 or li_seat < 0 or li_seat >= players.size():
		return
	if victim_seat == local_idx:
		_show_li_exposure(li_seat, duration)
	if net_mp and not net_client and victim_seat > 0:
		var peer := net.peer_of_seat(victim_seat)
		if peer > 0:
			net.rpc_id(peer, "ev_li_exposed", li_seat, duration)

func _show_li_exposure(li_seat: int, duration: float) -> void:
	var li: Player = players[li_seat]
	if not is_instance_valid(li) or li.name_label == null:
		return
	var until := Time.get_ticks_msec() * 0.001 + duration
	li.set_meta("li_exposed_until", until)
	li.name_label.outline_modulate = Color(1.0, 0.05, 0.08, 0.98)
	li.name_label.outline_size = 24
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(li) and li.name_label != null \
				and float(li.get_meta("li_exposed_until", 0.0)) <= Time.get_ticks_msec() * 0.001:
			li.name_label.outline_modulate = Color(0, 0, 0, 0.85)
			li.name_label.outline_size = 14)

func client_hud(rows: Array, score: int, hot_carts: Array) -> void:
	if client_view != null:
		client_view.set_hud(rows, score, hot_carts)

func client_locate(idxs: Array) -> void:
	locate_time = 3.0
	locate_targets = []
	for i in idxs:
		if i >= 0 and i < all_items.size() and is_instance_valid(all_items[i]):
			locate_targets.append(all_items[i])

func client_spawn_items(ids: Array, poss: Array) -> void:
	for i in ids.size():
		var it := Item.create(ids[i])
		add_child(it)
		it.set_free_at(poss[i])
		it.freeze = true
		all_items.append(it)

func client_item_gone(idx: int) -> void:
	if idx >= 0 and idx < all_items.size() and is_instance_valid(all_items[idx]):
		all_items[idx].queue_free()

func client_show_result(lines: Array) -> void:
	game_over = true
	_set_mouse_captured(false)
	hud.show_result(lines)

func _client_tick(delta: float) -> void:
	# 本机技能CD等由同步覆盖;这里只做插值渲染+HUD
	client_view.interpolate(delta)
	_tick_locate_visual(delta)
	_update_hud_client()

func _update_hud_client() -> void:
	if team_prep_active:
		_apply_team_prep_hud(int(ceil(team_prep_left)))
	else:
		_update_timer_hud()
	hud.set_bars(player.stamina, player.imbalance)
	hud.set_prompt(player.prompt_text, player.channel_progress)
	hud.set_score(client_view.score)
	_update_skill_hud()
	hud.set_list(ListRows.present(client_view.rows, _local_order_zone(),
			Input.is_action_pressed("show_orders")))
	hud.set_aimed_item(player.aimed_pickup_item(), cam_rig.camera)

# ---------- 技能 ----------

## 空格:角色专属技能。实现见 char_skills.gd(主机权威:联机时远程动作也走这里)
func trigger_char_skill(p: Player = null, dir := Vector3.ZERO) -> void:
	if p == null:
		p = player
	if game_over or p == null:
		return
	if p.taser_time > 0.0:
		return
	CharSkills.trigger(self, p, dir)
	if tutorial_guide != null and p == player:
		tutorial_guide.on_char_skill_used(p)

## 主机创建减速区并广播视觉参数。客户端不做区域判定，位置仍由权威状态包同步。
func spawn_slow_zone(pos: Vector3, radius: float, life: float, factor: float,
		immune_actor: Actor, title: String, color: Color, traction := 1.0) -> SlowZone:
	var zone := SlowZone.create(self, pos, radius, life, factor, immune_actor, title, color, traction)
	if net_mp and not net_client:
		var immune_seat := players.find(immune_actor) if immune_actor is Player else -1
		net.rpc("ev_slow_zone", pos, radius, life, factor, immune_seat, title, color, traction)
	return zone

func client_slow_zone(pos: Vector3, radius: float, life: float, factor: float,
		immune_seat: int, title: String, color: Color, traction := 1.0) -> void:
	var immune_actor: Actor = players[immune_seat] if immune_seat >= 0 and immune_seat < players.size() else null
	SlowZone.create(self, pos, radius, life, factor, immune_actor, title, color, traction)

## 商品湿滑效果与场地水渍统一：首次踏入立即满失衡倒地。主机负责判定，
## 客户端只复制高亮地面视觉，角色状态仍由权威状态包同步。
func spawn_slippery_zone(pos: Vector3, radius: float, life: float) -> SlipperyZone:
	var diameter := radius * 2.0
	var zone := SlipperyZone.create(self, pos, Vector3(diameter, 2.0, diameter), life)
	if net_mp and not net_client:
		net.rpc("ev_slippery", pos, life, Vector2(diameter, diameter))
	return zone

func _order_for_player(p: Player) -> Array:
	if p == null:
		return []
	if p.team_id >= 0 and p.team_id < team_data.size():
		return team_data[p.team_id].get("list", [])
	var player_index := players.find(p)
	if player_index >= 0 and player_index < pdata.size():
		return pdata[player_index].get("list", [])
	return []

func _item_is_on_player_order(p: Player, item_id: String) -> bool:
	for entry in _order_for_player(p):
		if OrderSystem.matches(entry, item_id):
			return true
	return false

## 驾车轮盘保护队伍尚缺的订单数量；同SKU在全队购物车中的超量部分可作弹药。
func cart_throw_items(p: Player) -> Array[Item]:
	var out: Array[Item] = []
	if p == null or not is_instance_valid(p.cart):
		return out
	var protected_instances := _protected_team_cart_order_items(p)
	for it in p.cart.items_in_basket():
		if is_instance_valid(it) and it.state == Item.ItemState.FREE \
				and not protected_instances.has(it.get_instance_id()):
			out.append(it)
	out.sort_custom(func(a: Item, b: Item) -> bool:
		if a.item_id == b.item_id:
			return a.get_instance_id() < b.get_instance_id()
		return a.item_id < b.item_id)
	return out

## 为每个订单SKU只保护“尚未交付”的件数。保护范围按队伍全部购物车合并计算，
## 并用席位与实例ID稳定排序，保证主机、轮盘刷新和实际投掷复核选择一致。
func _protected_team_cart_order_items(p: Player) -> Dictionary:
	var protected := {}
	if p == null:
		return protected
	var cart_items_by_id := {}
	var actors := team_inventory_actors(p.team_id)
	actors.sort_custom(func(a: Actor, b: Actor) -> bool:
		return a.team_slot < b.team_slot)
	for actor in actors:
		if not is_instance_valid(actor) or not is_instance_valid(actor.cart):
			continue
		for item in actor.cart.items_in_basket():
			if not is_instance_valid(item):
				continue
			if not cart_items_by_id.has(item.item_id):
				cart_items_by_id[item.item_id] = []
			(cart_items_by_id[item.item_id] as Array).append(item)
	for item_id in cart_items_by_id:
		var remaining := 0
		for entry in _order_for_player(p):
			if OrderSystem.matches(entry, str(item_id)):
				remaining += maxi(OrderSystem.required(entry) - OrderSystem.delivered(entry), 0)
		var candidates: Array = cart_items_by_id[item_id]
		candidates.sort_custom(func(a: Item, b: Item) -> bool:
			return a.get_instance_id() < b.get_instance_id())
		for i in mini(remaining, candidates.size()):
			protected[(candidates[i] as Item).get_instance_id()] = true
	return protected

## 手里的商品始终可以投掷；驾驶时再追加车斗内的非订单商品。
## 两种状态共用同一轮盘索引与联机商品ID，主机仍会按相同规则复核客户端选择。
func player_throw_items(p: Player) -> Array[Item]:
	if p == null:
		return []
	var out: Array[Item] = []
	for it in p.held:
		if is_instance_valid(it) and it.state == Item.ItemState.HELD:
			out.append(it)
	if p.attached:
		out.append_array(cart_throw_items(p))
	out.sort_custom(func(a: Item, b: Item) -> bool:
		if a.item_id == b.item_id:
			return a.get_instance_id() < b.get_instance_id()
		return a.item_id < b.item_id)
	return out

func cycle_cart_item(p: Player, step: int) -> void:
	var items := player_throw_items(p)
	if items.is_empty():
		p.throw_selection = 0
		return
	p.throw_selection = posmod(p.throw_selection + step, items.size())
	if tutorial_guide != null and p == player:
		tutorial_guide.on_wheel_cycled()

func selected_cart_item_id(p: Player) -> String:
	var items := player_throw_items(p)
	if items.is_empty():
		return ""
	p.throw_selection = posmod(p.throw_selection, items.size())
	return items[p.throw_selection].item_id

## 右键：驾驶时从购物车、徒步时从双手取出轮盘选中商品，沿准星投掷。
func trigger_throw_cart_item(p: Player = null, dir := Vector3.ZERO, wanted_id := "") -> void:
	if p == null:
		p = player
	if game_over or p == null or p.downed or p.finished or p.taser_time > 0.0:
		return
	if p.prop_cd > 0.0:
		if p == player:
			Main.float_text(self, p.global_position + Vector3.UP * 2.4,
					"道具冷却中(%d秒)" % int(ceil(p.prop_cd)), Color(0.8, 0.8, 0.8))
		return
	var items := player_throw_items(p)
	var prop: Item = null
	for it in items:
		if wanted_id == "" or it.item_id == wanted_id:
			prop = it
			break
	if prop == null:
		if p == player:
			Main.float_text(self, p.global_position + Vector3.UP * 2.4,
					"没有可投掷商品", Color(1.0, 0.75, 0.35), 52)
		return
	# 手持物必须先从持有数组移除，否则 Actor 每帧的手持摆位会把飞行中的商品拉回手上。
	if p.held.has(prop):
		p.held.erase(prop)
	p.prop_cd = Catalog.prop_cd(prop.item_id)
	var fwd := dir
	if fwd.length() < 0.1:
		fwd = cam_rig.aim_direction()
	fwd = fwd.normalized()
	_throw_item_body(prop, p, fwd)

func _throw_item_body(it: Item, owner: Player, fwd: Vector3) -> void:
	it.mark_flung()
	var launch := throw_launch_data(owner, fwd)
	var throw_origin: Vector3 = launch["origin"]
	var spawn_position: Vector3 = launch["spawn"]
	it.set_free_at(spawn_position)
	# 离手保护期仍可命中对手，但暂不与地面/场景接触。
	it.collision_mask = Catalog.L_CHAR | Catalog.L_CART
	it.contact_monitor = true
	it.max_contacts_reported = 6
	it.set_meta("throw_active", true)
	it.set_meta("throw_owner", owner)
	it.set_meta("throw_origin", throw_origin)
	it.set_meta("throw_spawn_position", spawn_position)
	it.set_meta("throw_started_msec", Time.get_ticks_msec())
	it.add_collision_exception_with(owner)
	if is_instance_valid(owner.cart):
		it.add_collision_exception_with(owner.cart)
	it.linear_velocity = launch["velocity"]
	it.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-5, 5), randf_range(-9, 9))
	it.body_entered.connect(func(body: Node) -> void: _thrown_item_hit(it, body, owner))
	# 飞出足够距离后再开启场景碰撞，并复查此刻的真实接触体。
	var item_ref: WeakRef = weakref(it)
	var owner_ref: WeakRef = weakref(owner)
	get_tree().create_timer(Catalog.THROW_WORLD_ARM_TIME).timeout.connect(func() -> void:
		var armed_item := item_ref.get_ref() as Item
		var throw_owner := owner_ref.get_ref() as Player
		if not is_instance_valid(armed_item) or not is_instance_valid(throw_owner) \
				or not bool(armed_item.get_meta("throw_active", false)):
			return
		armed_item.collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART
		var contacts := armed_item.get_colliding_bodies()
		for contact in contacts:
			if contact == throw_owner or contact == throw_owner.cart:
				continue
			_thrown_item_hit(armed_item, contact, throw_owner)
			break)

## 瞄准预览与真实投掷共用这一份出手参数，避免白线落点和商品轨迹漂移。
func throw_launch_data(owner: Player, fwd: Vector3) -> Dictionary:
	# 出手点使用上半身高度，并只沿水平朝向前置：低视角不会把商品生成到脚下。
	var aim := fwd.normalized() if fwd.length() > 0.01 else -owner.global_transform.basis.z
	var horizontal := Vector3(aim.x, 0.0, aim.z)
	if horizontal.length() < 0.1:
		horizontal = -owner.global_transform.basis.z
		horizontal.y = 0.0
	if horizontal.length() < 0.1:
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	# 保留上抛瞄准，但不允许向下的初速度直接把物品送进地面。
	aim = Vector3(horizontal.x, maxf(aim.y, -0.05), horizontal.z).normalized()
	var throw_origin := owner.global_position + Vector3.UP * THROW_ORIGIN_HEIGHT
	var spawn_position := throw_origin + horizontal * THROW_FORWARD_OFFSET
	return {
		"aim": aim,
		"origin": throw_origin,
		"spawn": spawn_position,
		"velocity": aim * THROW_SPEED + Vector3.UP * THROW_UPWARD_SPEED,
	}

func _thrown_item_hit(it: Item, body: Node, owner: Player) -> void:
	if not is_instance_valid(it) or not bool(it.get_meta("throw_active", false)):
		return
	# 物理异常之外的结算层保险：投掷者和其购物车永远不能成为首个落点。
	if body == owner or body == owner.cart:
		return
	var throw_origin: Vector3 = it.get_meta("throw_origin", owner.global_position)
	var from_origin := it.global_position - throw_origin
	from_origin.y = 0.0
	var age := (Time.get_ticks_msec() - int(it.get_meta("throw_started_msec", 0))) * 0.001
	# 角色和购物车可近身直击；只有脚边世界碰撞需要等待投掷物真正离手。
	if not (body is Actor) and not (body is Cart) \
			and age < Catalog.THROW_WORLD_ARM_TIME \
			and from_origin.length() < Catalog.THROW_WORLD_ARM_DISTANCE:
		return
	it.set_meta("throw_active", false)
	var pos := it.global_position
	pos.y = 0.0
	it.set_meta("throw_effect_position", pos)
	var direct_actor: Actor = body if body is Actor else null
	var hit_cart: Cart = body if body is Cart else null
	var victim: Actor = direct_actor if direct_actor != null else (hit_cart.attached_agent if hit_cart != null else null)
	var damage_multiplier := Catalog.THROW_ACTOR_DAMAGE_MULTIPLIER \
			if direct_actor != null else Catalog.THROW_CART_DAMAGE_MULTIPLIER
	if victim != null and victim.is_friendly_source(owner):
		victim = null
	if victim != null and victim != owner and not victim.immune:
		var damage := Catalog.throw_imbalance(it.item_id) * damage_multiplier
		victim.add_imbalance(damage, owner)
		var away := victim.global_position - owner.global_position
		away.y = 0.0
		if away.length() > 0.1:
			victim.push_velocity += away.normalized() * Catalog.THROW_DIRECT_PUSH
		Main.float_text(victim, victim.global_position + Vector3.UP * 2.1,
				"%s%s +%d失衡!" % [it.display_name,
						(" 直击×1.5" if direct_actor != null else " 砸车×1.0"), int(damage)],
				Color(1.0, 0.58, 0.25), 66)
		shake_for(victim, clampf(damage / 70.0, 0.25, 0.8))
		CharSkills.mark_foreman_target(victim, owner)
	_apply_throw_effect(it.item_id, pos, owner, direct_actor)
	if tutorial_guide != null and owner == player:
		tutorial_guide.on_throw_hit(it, body, pos)
	# 数码家电区商品带有易碎特性：完成一次有效命中后永久损耗。
	if Catalog.is_fragile(it.item_id):
		Main.float_text(self, pos + Vector3.UP * 1.2, "易碎品损耗!", Color(1.0, 0.35, 0.18), 82)
		net_item_gone_notify(it)
		it.queue_free()
		return
	# 命中后商品仍留在场内，可再次拾取/装车；仅关闭角色碰撞避免持续蹭伤。
	var landed_item_ref: WeakRef = weakref(it)
	var landed_owner_ref: WeakRef = weakref(owner)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		var landed_item := landed_item_ref.get_ref() as Item
		var landed_owner := landed_owner_ref.get_ref() as Player
		if is_instance_valid(landed_item):
			landed_item.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
			if is_instance_valid(landed_owner):
				landed_item.remove_collision_exception_with(landed_owner)
				if is_instance_valid(landed_owner.cart):
					landed_item.remove_collision_exception_with(landed_owner.cart))

func _apply_throw_effect(id: String, pos: Vector3, owner: Player, direct_actor: Actor = null) -> void:
	match Catalog.prop_kind(id):
		Catalog.PROP_BURST:
			_throw_burst(pos, owner)
		Catalog.PROP_WET:
			spawn_slippery_zone(pos, Catalog.WET_RADIUS, Catalog.WET_LIFE)
		Catalog.PROP_SCATTER:
			spawn_obscure_zone(pos)
		Catalog.PROP_TASER:
			if direct_actor != null and direct_actor != owner:
				direct_actor.apply_taser(Catalog.TASER_TIME, Catalog.TASER_IMMUNITY, owner)

func _throw_burst(pos: Vector3, owner: Player) -> void:
	_spawn_burst_vfx(pos)
	for node in get_tree().get_nodes_in_group("characters"):
		if not (node is Actor):
			continue
		var a: Actor = node
		if a.is_friendly_source(owner):
			continue
		var away := a.global_position - pos
		away.y = 0.0
		if away.length() > Catalog.BURST_RADIUS:
			continue
		if away.length() <= 0.05:
			away = a.global_position - owner.global_position
			away.y = 0.0
		if away.length() <= 0.05:
			away = Vector3.FORWARD
		a.push_velocity += away.normalized() * Catalog.BURST_ACTOR_PUSH
	for node in get_tree().get_nodes_in_group("carts"):
		if not (node is Cart):
			continue
		var pushed_cart: Cart = node
		if is_instance_valid(pushed_cart.cart_owner) \
				and pushed_cart.cart_owner.is_friendly_source(owner):
			continue
		var cart_away := pushed_cart.global_position - pos
		cart_away.y = 0.0
		if cart_away.length() <= Catalog.BURST_RADIUS:
			if cart_away.length() <= 0.05:
				cart_away = pushed_cart.global_position - owner.global_position
				cart_away.y = 0.0
			if cart_away.length() <= 0.05:
				cart_away = Vector3.FORWARD
			# 直接写入速度增量，避免刚落地休眠的空车吞掉同帧刚体冲量；
			# 数值与原“冲量=目标速度×质量”等价，但节目效果更稳定。
			pushed_cart.sleeping = false
			pushed_cart.linear_velocity += cart_away.normalized() * Catalog.BURST_CART_PUSH \
					+ Vector3.UP * Catalog.BURST_CART_LIFT
			var flip_axis := Vector3(cart_away.z, 0.15, -cart_away.x).normalized()
			pushed_cart.angular_velocity += flip_axis * Catalog.BURST_CART_TORQUE
	Main.float_text(self, pos + Vector3.UP, "爆裂推离!", Color(1.0, 0.42, 0.08), 62)

func _spawn_burst_vfx(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos + Vector3.UP * 0.08
	add_child(root)
	for i in 3:
		var ring := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.7 + i * 0.18
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.045 + i * 0.018
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2 + i * 0.16, 0.03, 0.72 - i * 0.12)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.22 + i * 0.15, 0.02)
		mat.emission_energy_multiplier = 2.4
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		ring.mesh = mesh
		ring.scale = Vector3.ONE * 0.12
		ring.position.y = i * 0.12
		root.add_child(ring)
		var tween := root.create_tween().set_parallel(true)
		tween.tween_property(ring, "scale", Vector3.ONE * (3.4 + i * 0.8), 0.38 + i * 0.08) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "transparency", 1.0, 0.42 + i * 0.08)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.72, 0.18, 0.76)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.38, 0.03)
	flash_mat.emission_energy_multiplier = 3.2
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = flash_mat
	flash.mesh = sphere
	flash.position.y = 0.7
	root.add_child(flash)
	var flash_tween := root.create_tween().set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector3.ONE * 2.5, 0.28).set_trans(Tween.TRANS_QUAD)
	flash_tween.tween_property(flash, "transparency", 1.0, 0.3)
	get_tree().create_timer(0.65).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())

func spawn_obscure_zone(pos: Vector3) -> ObscureZone:
	var zone := ObscureZone.create(self, pos, Catalog.SCATTER_RADIUS,
			Catalog.SCATTER_LIFE, Catalog.SCATTER_PERCEPTION_FACTOR)
	if net_mp and not net_client:
		net.rpc("ev_obscure_zone", pos, Catalog.SCATTER_RADIUS,
				Catalog.SCATTER_LIFE, Catalog.SCATTER_PERCEPTION_FACTOR)
	Main.float_text(self, pos + Vector3.UP, "散落遮挡!", Color(1.0, 0.86, 0.58), 58)
	return zone

func client_obscure_zone(pos: Vector3, radius: float, life: float, factor: float) -> void:
	ObscureZone.create(self, pos, radius, life, factor)

## 随机位置生成地滑区(开局3块由种子决定两端一致;运行时的临时块走网络事件)
func _spawn_random_slippery(count: int, life: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 200:
		tries += 1
		var sx := layout_slippery_x()
		var sz := layout_slippery_z()
		var p := Vector3(randf_range(sx.x, sx.y), 0, randf_range(sz.x, sz.y))
		var cell := _cell(p)
		if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
			SlipperyZone.create(self, p, Vector3(3.5, 2, 3.5), life)
			if life > 0.0 and net_mp and not net_client:
				net.rpc("ev_slippery", p, life)
			placed += 1

## 某玩家当前仍可用于补单的商品ID集合。
## 点名项目只返回指定ID；类别项目在扣除手中/车斗已有件数后，返回该分区全部候选ID。
func missing_list_ids(idx: int = -1) -> Dictionary:
	if idx < 0:
		idx = local_idx
	var have := {}
	for actor in team_inventory_actors(players[idx].team_id):
		if is_instance_valid(actor.cart):
			for it in actor.cart.items_in_basket():
				have[it.item_id] = int(have.get(it.item_id, 0)) + 1
		for it2 in actor.held:
			if is_instance_valid(it2):
				have[it2.item_id] = int(have.get(it2.item_id, 0)) + 1
	var missing := {}
	# 先为点名项目预留同名商品，避免未来出现候选范围重叠时一件货重复满足两单。
	for entry in pdata[idx]["list"]:
		if OrderSystem.is_category(entry) or OrderSystem.is_complete(entry):
			continue
		var id := str(entry["id"])
		var remaining := OrderSystem.required(entry) - OrderSystem.delivered(entry)
		var owned := mini(int(have.get(id, 0)), remaining)
		have[id] = int(have.get(id, 0)) - owned
		if owned < remaining:
			missing[id] = true
	for entry in pdata[idx]["list"]:
		if not OrderSystem.is_category(entry) or OrderSystem.is_complete(entry):
			continue
		var remaining := OrderSystem.required(entry) - OrderSystem.delivered(entry)
		for id in OrderSystem.candidate_ids(entry):
			var used := mini(int(have.get(id, 0)), remaining)
			have[id] = int(have.get(id, 0)) - used
			remaining -= used
			if remaining <= 0:
				break
		if remaining > 0:
			for id in OrderSystem.candidate_ids(entry):
				missing[id] = true
	return missing

## Q：点名爆款高亮全部真实库存；类别单每缺1件只推荐最近2个候选，
## 避免整片分区同时发绿。推荐只负责导航，不改变“该类别任意商品都可交付”的规则。
func trigger_locate_skill(p: Player = null) -> void:
	if p == null:
		p = player
	if game_over or p == null or p.taser_time > 0.0:
		return
	if p.locate_cd > 0.0:
		if p == player:
			Main.float_text(self, p.global_position + Vector3.UP * 2.4, "找货雷达冷却中(%d秒)" % int(ceil(p.locate_cd)), Color(0.8, 0.8, 0.8))
		return
	p.locate_cd = 10.0
	var idx := players.find(p)
	var idxs := _locate_recommendations(idx)
	Main.float_text(self, p.global_position + Vector3.UP * 2.4,
			"找货雷达:代购单已备齐!" if idxs.is_empty() else "找货雷达!锁定 %d 件缺货" % idxs.size(),
			Color(0.3, 1.0, 0.5))
	if p == player:
		client_locate(idxs)   # 本机直接开始闪
	elif net_mp:
		var pid := net.peer_of_seat(idx)
		if net.peer_alive(pid):
			net.rpc_id(pid, "ev_locate", idxs)

func _locate_recommendations(idx: int) -> Array:
	var p := players[idx]
	var team_actors := team_inventory_actors(p.team_id)
	var selected := {}
	var out: Array = []
	for entry in pdata[idx]["list"]:
		if OrderSystem.is_complete(entry):
			continue
		var remaining := OrderSystem.required(entry) - OrderSystem.delivered(entry) \
				- _owned_matching_count(p, entry)
		if remaining <= 0:
			continue
		var pool: Array = []
		for i in all_items.size():
			var it: Item = all_items[i]
			if not is_instance_valid(it) or it.event_locked \
					or it.state == Item.ItemState.SCANNED \
					or selected.has(i) or not OrderSystem.matches(entry, it.item_id):
				continue
			var owned_by_team := false
			for actor in team_actors:
				if actor.held.has(it) or is_instance_valid(actor.cart) \
						and actor.cart.items_in_basket().has(it):
					owned_by_team = true
					break
			if owned_by_team:
				continue
			pool.append([p.global_position.distance_squared_to(it.global_position), i, it.item_id])
		pool.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var chosen: Array = pool
		if OrderSystem.is_category(entry):
			chosen = []
			var limit := mini(pool.size(), remaining * 2)
			var seen_ids := {}
			for candidate in pool:
				if chosen.size() >= limit:
					break
				if seen_ids.has(candidate[2]):
					continue
				seen_ids[candidate[2]] = true
				chosen.append(candidate)
			for candidate in pool:
				if chosen.size() >= limit:
					break
				if not chosen.has(candidate):
					chosen.append(candidate)
		for candidate in chosen:
			var item_index := int(candidate[1])
			if not selected.has(item_index):
				selected[item_index] = true
				out.append(item_index)
	return out

func _owned_matching_count(p: Player, entry: Dictionary) -> int:
	var count := 0
	for actor in team_inventory_actors(p.team_id):
		for it in actor.held:
			if is_instance_valid(it) and OrderSystem.matches(entry, it.item_id):
				count += 1
		if is_instance_valid(actor.cart):
			for it in actor.cart.items_in_basket():
				if is_instance_valid(it) and OrderSystem.matches(entry, it.item_id):
					count += 1
	return count

func _tick_locate(delta: float) -> void:
	_steal_bc_cd = maxf(0.0, _steal_bc_cd - delta)
	_down_bc_cd = maxf(0.0, _down_bc_cd - delta)
	_tick_locate_visual(delta)

func _tick_locate_visual(delta: float) -> void:
	if locate_time <= 0.0:
		return
	locate_time -= delta
	var blink := locate_time > 0.0 and fmod(locate_time * 4.0, 1.0) < 0.65
	var missing := missing_list_ids(local_idx)
	for t in locate_targets:
		if not is_instance_valid(t):
			continue
		if t.state == Item.ItemState.SCANNED or not missing.has(t.item_id):
			t.ping_shell.visible = false
			continue
		t.ping_shell.visible = blink
	if locate_time <= 0.0:
		for t in locate_targets:
			if is_instance_valid(t):
				t.ping_shell.visible = false
		locate_targets = []

# ---------- 相机与HUD ----------

## 主机为远程玩家执行的准星选货射线。射线起点取玩家头部而非房主相机，
## 同时保留场景遮挡与距离校验，客户端只能表达瞄准意图，不能直接指定商品。
func aimed_shelf_item_from(p: Player, direction: Vector3, max_distance := 8.0) -> Item:
	if not is_instance_valid(p) or not direction.is_finite() or direction.length_squared() < 0.001:
		return null
	var ray_origin := p.global_position + Vector3.UP * THROW_ORIGIN_HEIGHT
	var ray_dir := direction.normalized()
	var ray_end := ray_origin + ray_dir * max_distance
	# 货架商品不再有碰撞体，先做准星锥体选取，再单独用世界射线验证无遮挡。
	var candidates: Array = []
	for item in all_items:
		if not is_instance_valid(item) or item.state != Item.ItemState.SHELVED or item.event_locked:
			continue
		var rel: Vector3 = item.global_position - ray_origin
		var along := rel.dot(ray_dir)
		if along < 0.15 or along > max_distance:
			continue
		var radial := (rel - ray_dir * along).length()
		# 无中央准星后扩大人物面朝方向的容错锥；镜头俯仰仍负责区分上下层。
		var aim_radius := clampf(item.box_size.length() * Catalog.SHELF_DISPLAY_SCALE * 0.48,
				0.38, 1.05)
		if radial <= aim_radius:
			candidates.append([along, radial, item])
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if not is_equal_approx(a[0], b[0]) else a[1] < b[1])
	for entry in candidates:
		var along := float(entry[0])
		var query := PhysicsRayQueryParameters3D.create(ray_origin,
				ray_origin + ray_dir * along, Catalog.L_WORLD)
		query.collide_with_areas = false
		query.exclude = [p.get_rid()]
		if is_instance_valid(p.cart):
			query.exclude.append(p.cart.get_rid())
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		# 层板/背板可能紧贴商品后方；只把明显位于商品之前的墙体视为遮挡。
		if hit.is_empty() or ray_origin.distance_to(hit["position"]) >= along - 0.75:
			return entry[2] as Item
	return null

## 徒步拾取散货沿用货架的“准星锥体 + 场景遮挡”判定。散货本身有刚体碰撞，
## 但不直接信任客户端命中的节点；联机主机仍按玩家上报的方向重新选择目标。
func aimed_free_item_from(p: Player, direction: Vector3, max_distance := 2.2) -> Item:
	if not is_instance_valid(p) or not direction.is_finite() or direction.length_squared() < 0.001:
		return null
	var ray_origin := p.global_position + Vector3.UP * THROW_ORIGIN_HEIGHT
	var ray_dir := direction.normalized()
	var candidates: Array = []
	for item in all_items:
		if not is_instance_valid(item) or item.state != Item.ItemState.FREE \
				or bool(item.get_meta("throw_active", false)) or _item_is_in_any_cart(item):
			continue
		var rel: Vector3 = item.global_position - ray_origin
		var along := rel.dot(ray_dir)
		if along < 0.1 or along > max_distance:
			continue
		var radial := (rel - ray_dir * along).length()
		var aim_radius := clampf(item.box_size.length() * 0.52, 0.38, 0.92)
		if radial <= aim_radius:
			candidates.append([along, radial, item])
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if not is_equal_approx(a[0], b[0]) else a[1] < b[1])
	for entry in candidates:
		var along := float(entry[0])
		var query := PhysicsRayQueryParameters3D.create(ray_origin,
				ray_origin + ray_dir * along, Catalog.L_WORLD)
		query.collide_with_areas = false
		query.exclude = [p.get_rid()]
		if is_instance_valid(p.cart):
			query.exclude.append(p.cart.get_rid())
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or ray_origin.distance_to(hit["position"]) >= along - 0.35:
			return entry[2] as Item
	return null

func _item_is_in_any_cart(item: Item) -> bool:
	for node in get_tree().get_nodes_in_group("carts"):
		var candidate_cart := node as Cart
		if is_instance_valid(candidate_cart) and candidate_cart.basket_area.overlaps_body(item):
			return true
	return false

func _update_camera(delta: float) -> void:
	if player == null or cam_rig == null:
		return
	var aiming := player.throw_aiming and not player.downed and not player.finished and not game_over
	# 徒步和驾车统一使用本机第三人称；右键由CameraRig平滑切入右肩越肩镜头。
	# 这里只读取本机player，因此主机与各客户端不会互相改写对方的相机状态。
	cam_rig.set_first_person(false)
	cam_rig.set_throw_aiming(aiming)
	if player.body_root != null:
		player.body_root.visible = true
	if player.name_label != null:
		# 本机永远不显示自己的头顶昵称；其他玩家仍通过各自客户端正常看到。
		player.name_label.visible = false
	# 推车时镜头跟车(视野中心是车头,便于瞄准撞击)
	var target := player.global_position + Vector3.UP * 1.5
	if player.attached and is_instance_valid(player.cart) and not aiming:
		target = player.cart.global_position + Vector3.UP * 1.4
	cam_rig.follow(target, delta)
	cam_rig.update_first_person_hands(player, delta)
	# 抛物线仍只服务驾车投掷；徒步越肩视角直接依靠中央白点方向。
	if aiming and player.attached and selected_cart_item_id(player) != "" \
			and player.prop_cd <= 0.0:
		var launch := throw_launch_data(player, player._aim_dir())
		var exclusions: Array[RID] = [player.get_rid()]
		if is_instance_valid(player.cart):
			exclusions.append(player.cart.get_rid())
		cam_rig.update_throw_preview(launch["spawn"], launch["velocity"], exclusions)
	else:
		cam_rig.hide_throw_preview()

func _set_mouse_captured(c: bool) -> void:
	mouse_captured = c
	if not c and player != null:
		player.throw_aiming = false
		if cam_rig != null:
			cam_rig.set_throw_aiming(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if c else Input.MOUSE_MODE_VISIBLE

func _update_timer_hud() -> void:
	if team_prep_active:
		_apply_team_prep_hud(int(ceil(team_prep_left)))
	elif tutorial:
		hud.set_timer_text("教学模式", Color(0.6, 1, 0.7))
		hud.set_phase("跟着屏幕上方的指引练一遍")
	elif in_grace:
		hud.set_timer_text("宽限 0:%02d" % int(ceil(grace_left)), Color(1, 0.3, 0.25))
		hud.set_phase("打烊宽限——最后机会!")
	else:
		var total := int(ceil(time_left))
		var m := int(total / 60.0)
		var s := total % 60
		var col := Color(1, 1, 1)
		if time_left <= CLOSING_WARN:
			col = Color(1, 0.6, 0.3)
		hud.set_timer_text("%d:%02d" % [m, s], col)
		if time_left > MATCH_TIME - 60.0:
			hud.set_phase("开门冲刺")
		elif not central_opened and central_warned:
			hud.set_phase("黑五压轴预警 · 四门即将开放")
		elif central_opened:
			hud.set_phase("黑五压轴已开放 · 中央争夺战")
		elif time_left > CLOSING_WARN:
			hud.set_phase("分区扫货 · 寻找本局开放收银台")
		else:
			hud.set_phase("打烊冲刺——全场挤向收银台")

func _update_skill_hud() -> void:
	var s1 := "Q雷达:就绪" if player.locate_cd <= 0.0 else "Q 雷达:%d秒" % int(ceil(player.locate_cd))
	s1 += " · Tab按住查看全部订单"
	var wheel_items := player_throw_items(player)
	var selected_id := selected_cart_item_id(player)
	var prop_text := "无可投掷商品" if selected_id == "" else "%s·%d失衡" % [Catalog.ITEMS[selected_id]["name"], int(Catalog.throw_imbalance(selected_id))]
	var s2 := "按住右键:近距观察"
	if selected_id != "":
		s2 = "按住右键瞄准/松开投掷:%s" % prop_text if player.prop_cd <= 0.0 \
				else "右键 投掷:%.1f秒" % player.prop_cd
	hud.set_item_wheel(wheel_items, player.throw_selection, not wheel_items.is_empty())
	hud.set_obscured(player.obscure_time > 0.0)
	hud.set_cold_meter(player.cold_meter,
			player.cold_meter > 0.01 or player.frozen_time > 0.0,
			player.frozen_time)
	var s3 := "Ctrl稳住:就绪" if player.brace_cd <= 0.0 else ("Ctrl 稳住:格挡中!" if player.braced else "Ctrl 稳住:%d秒" % int(ceil(player.brace_cd)))
	var sk := CharacterDef.skill_name(player.char_id)
	var max_cd := CharacterDef.skill_cd(player.char_id)
	var s4 := "空格 %s:就绪" % sk
	if player.taser_time > 0.0:
		s4 = "空格 %s:被电定身(%.1f秒)" % [sk, player.taser_time]
	elif player.stun_time > 0.0:
		s4 = "空格 %s:收不住脚(%.1f秒)" % [sk, player.stun_time]
	elif player.char_cd > 0.0:
		s4 = "空格 %s:%d秒" % [sk, int(ceil(player.char_cd))]
	var ready: bool = player.locate_cd <= 0.0 and player.prop_cd <= 0.0 \
			and player.brace_cd <= 0.0 and player.char_cd <= 0.0
	# 技能冷却圆环(塞尔达体力轮风格)
	hud.set_skill_cd(clampf(player.char_cd / maxf(max_cd, 1.0), 0.0, 1.0))
	hud.set_skill(s1 + " · " + s2 + " · " + s3 + " · " + s4, ready)
	# 旧威胁箭头层保持清空；马德胜被动已改为随从标记追击。
	hud.set_threats([], cam_yaw)

func _update_hud() -> void:
	_update_timer_hud()
	hud.set_bars(player.stamina, player.imbalance)
	hud.set_prompt(player.prompt_text, player.channel_progress)
	hud.set_score(pdata[local_idx]["score"])
	_update_skill_hud()
	hud.set_list(ListRows.present(_build_rows(local_idx), _local_order_zone(),
			Input.is_action_pressed("show_orders")))
	hud.set_aimed_item(player.aimed_pickup_item(), cam_rig.camera)

## 清单行(按超市分区分组;入车/已结算标绿划线):委托 ListRows
func _build_rows(idx: int) -> Array:
	var rows := ListRows.build(self, idx)
	var tid := int(pdata[idx].get("team_id", -1)) if idx >= 0 and idx < pdata.size() else -1
	if tid < 0 or tid >= team_data.size():
		return rows
	var vouchers: Array = team_data[tid].get("vouchers", [])
	if vouchers.is_empty():
		return rows
	rows.append({"header": true, "text": "【贩卖机优惠券】", "color": Color(1.0, 0.68, 0.84)})
	for voucher in vouchers:
		var item_id := str(voucher.get("item_id", ""))
		if not Catalog.ITEMS.has(item_id):
			continue
		var kind_text := "免费兑换" if str(voucher.get("kind", "half")) == "free" else "折上五折"
		rows.append({"text": "  · %s券 — 结算%s时自动使用" % [kind_text,
				Catalog.ITEMS[item_id]["name"]], "green": false})
	return rows

## RegionDirector沿用场景节点名作为键；订单层统一换算成Catalog专区ID。
func _local_order_zone() -> String:
	if region_director == null or not is_instance_valid(player):
		return ""
	var layout_zone := region_director.zone_at(player.global_position)
	return str(LAYOUT_ZONE_TO_ORDER_ZONE.get(layout_zone, ""))

# ---------- 事件与结算 ----------

func _trigger_flash_sale() -> void:
	var pos: Vector3 = sale_points.pick_random()
	var ids: Array = []
	var poss: Array = []
	for i in 3:
		var it := Item.create("sale_box")
		add_child(it)
		var sp := pos + Vector3(randf_range(-1.2, 1.2), 1.5 + i * 0.4, randf_range(-1.2, 1.2))
		it.set_free_at(sp, Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)))
		all_items.append(it)
		ids.append("sale_box")
		poss.append(sp)
	if net_mp and not net_client:
		net.rpc("ev_spawn_items", ids, poss)
	hud.broadcast("限时特价!超值神秘箱已投放至卖场,数量有限,先到先得哦～(可顶替类别订单1件，不能顶点名爆款)")
	for g in grannies:
		if is_instance_valid(g) and randf() < 0.6:
			g.rush_to(pos)

func _on_item_scanned(item: Item, by: Actor) -> void:
	var idx := players.find(by)
	var tid := by.team_id
	if tid < 0 or tid >= team_data.size():
		return
	var pd: Dictionary = team_data[tid]
	var pts := Catalog.points_for(item.item_id)
	if item.category == Catalog.CAT_SALE:
		pts += Catalog.SALE_BONUS
		OrderSystem.fulfill_sale(pd["list"])
	else:
		OrderSystem.fulfill_item(pd["list"], item.item_id)
	pd["score"] += pts
	pd["counts"][item.category] = int(pd["counts"].get(item.category, 0)) + 1
	var price := Catalog.price_of(item.item_id)
	pd["orig"] += price
	var base_saved := int(round(price * Catalog.discount_of(item.item_id)))
	pd["saved"] += base_saved + _redeem_vending_voucher(tid, item.item_id,
			price, base_saved, item.global_position)
	# 所有真人队员引用同一清单，并同步看到同一份队伍经济数据。
	for i in pdata.size():
		if int(pdata[i].get("team_id", -1)) != tid:
			continue
		pdata[i]["score"] = pd["score"]
		pdata[i]["counts"] = pd["counts"]
		pdata[i]["orig"] = pd["orig"]
		pdata[i]["saved"] = pd["saved"]
	Main.float_text(self, item.global_position + Vector3.UP * 0.8, "+%d" % pts, Color(0.5, 0.95, 0.55))

## 从当前仍可取得的普通货架库存中抽券，保证中奖商品确实能在本局找到。
func random_voucher_item_id() -> String:
	var candidates: Array[String] = []
	for it in all_items:
		if not is_instance_valid(it) or it.state != Item.ItemState.SHELVED \
				or bool(it.get_meta("live_fresh_good", false)) or it.event_locked:
			continue
		var data: Dictionary = Catalog.ITEMS.get(it.item_id, {})
		if data.is_empty() or data["cat"] == Catalog.CAT_LARGE or data["cat"] == Catalog.CAT_SALE:
			continue
		if not candidates.has(it.item_id):
			candidates.append(it.item_id)
	return candidates.pick_random() if not candidates.is_empty() else ""

func grant_vending_voucher(team_id: int, item_id: String, kind: String) -> void:
	if team_id < 0 or team_id >= team_data.size() or not Catalog.ITEMS.has(item_id):
		return
	var vouchers: Array = team_data[team_id].get("vouchers", [])
	vouchers.append({"item_id": item_id, "kind": "free" if kind == "free" else "half"})
	team_data[team_id]["vouchers"] = vouchers
	var kind_text := "免费兑换券" if kind == "free" else "折上五折券"
	var announcement := "%s砸出一张【%s·%s】! 把商品带到收银台才生效。" % [
			Catalog.team_name(team_id, true), Catalog.ITEMS[item_id]["name"], kind_text]
	hud.broadcast(announcement)
	if net_mp and not net_client:
		net.rpc("ev_broadcast", announcement)

func _redeem_vending_voucher(team_id: int, item_id: String, price: int,
		base_saved: int, at: Vector3) -> int:
	if team_id < 0 or team_id >= team_data.size():
		return 0
	var vouchers: Array = team_data[team_id].get("vouchers", [])
	var match_index := -1
	# 同商品同时有两种券时优先兑现免费券。
	for i in vouchers.size():
		if str(vouchers[i].get("item_id", "")) == item_id \
				and str(vouchers[i].get("kind", "")) == "free":
			match_index = i
			break
	if match_index < 0:
		for i in vouchers.size():
			if str(vouchers[i].get("item_id", "")) == item_id:
				match_index = i
				break
	if match_index < 0:
		return 0
	var voucher: Dictionary = vouchers[match_index]
	vouchers.remove_at(match_index)
	team_data[team_id]["vouchers"] = vouchers
	var remaining_price := maxi(0, price - base_saved)
	var extra := remaining_price if str(voucher.get("kind", "half")) == "free" \
			else int(round(remaining_price * 0.5))
	var label := "免费券兑现! ¥0拿下" if str(voucher.get("kind", "half")) == "free" \
			else "折上五折券兑现!"
	Main.float_text(self, at + Vector3.UP * 1.15, label, Color(1.0, 0.64, 0.84), 72)
	return extra

## 原CSG碰撞体保持不动，额外生成无碰撞高亮壳完成压扁、膨胀和闪白，避免动画卡住玩家。
func play_vending_hit_visual(machine_name: String, from_network := false) -> void:
	var machine := find_child(machine_name, true, false) as CSGBox3D
	if machine == null:
		return
	var flash := MeshInstance3D.new()
	flash.name = "VendingHitFlash"
	var box := BoxMesh.new()
	box.size = machine.size * 1.025
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.68, 0.88)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.34, 0.68)
	mat.emission_energy_multiplier = 2.5
	box.material = mat
	flash.mesh = box
	add_child(flash)
	flash.global_transform = machine.global_transform
	flash.scale = Vector3(1.34, 0.62, 1.18)
	flash.rotation.z += 0.11
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3(0.88, 1.22, 0.94), 0.11) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(flash, "rotation:z", -0.09, 0.11)
	tween.tween_property(flash, "scale", Vector3.ONE, 0.2) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0), 0.2)
	tween.finished.connect(flash.queue_free)
	if net_mp and not net_client and not from_network:
		net.rpc("ev_vending_hit", machine_name)

func is_settled_agent(a: Actor) -> bool:
	var i := players.find(a)
	return i >= 0 and pdata[i]["settled"]

## 玩家过完收银台只登记本队对应席位。正式比赛必须两个席位都完成，才给该队
## 的真人成员统一弹出结算；比赛时间耗尽仍会强制结算所有未完成队伍。
func _on_lane_settled(by: Player) -> void:
	if game_over:
		return
	var idx := players.find(by)
	if idx < 0 or pdata[idx]["settled"]:
		return
	pdata[idx]["settled"] = true
	by.settled_once = true
	teleport_checkout_agent_outside(by)
	if tutorial:
		by.finished = true
		complete_tutorial()
		return
	var team_finished := _mark_team_checkout_ready(by.team_id, by.team_slot)
	# 单人模式不要求玩家等待AI走完整段寻路；真人入场即携AI队友统一结算。
	if not net_mp:
		_mark_team_checkout_ready(by.team_id, 1 - clampi(by.team_slot, 0, 1))
		team_finished = true
	if team_finished:
		_finish_team(by.team_id)
	else:
		# 第一位队员仍可把空车驶离通道，但该车不会被重复扫码。
		if idx == local_idx:
			hud.broadcast("你已完成入场结算，等待队友进入收银台……")
		elif net_mp:
			var pid := net.peer_of_seat(idx)
			if net.peer_alive(pid):
				net.rpc_id(pid, "ev_broadcast", "你已完成入场结算，等待队友进入收银台……")

func on_team_bot_checkout_ready(bot: Granny) -> void:
	if game_over or not is_instance_valid(bot) or not bot.is_team_bot:
		return
	if _mark_team_checkout_ready(bot.team_id, bot.team_slot):
		_finish_team(bot.team_id)

## 结算完成后把人和车直接送到当前收银道的场外落点，并立即释放通道。
## 位姿由主机的常规玩家/车辆状态包同步到联机客户端。
func teleport_checkout_agent_outside(actor: Actor, checkout: Checkout = null) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.cart):
		return
	if checkout == null:
		for candidate in checkouts:
			if candidate._active_cart == actor.cart:
				checkout = candidate
				break
	if checkout == null:
		return
	checkout.release_cart(actor.cart)
	var outward := checkout.lane_forward.normalized()
	var yaw := atan2(-outward.x, -outward.z)
	actor.cart.global_position = checkout.exit_outer_pos() + Vector3.UP * 0.22
	actor.cart.global_rotation = Vector3(0.0, yaw, 0.0)
	actor.cart.linear_velocity = Vector3.ZERO
	actor.cart.angular_velocity = Vector3.ZERO
	actor.cart.reset_physics_interpolation()
	if actor.attached:
		actor.global_position = actor.cart.handle_pos()
	else:
		actor.global_position = checkout.exit_outer_pos() + outward * 1.1 + Vector3.UP * 0.1
	actor.reset_physics_interpolation()

func _mark_team_checkout_ready(team_id: int, team_slot: int) -> bool:
	if team_id < 0 or team_id >= team_data.size():
		return false
	var slots: Array = team_data[team_id].get("checkout_ready_slots", [false, false])
	while slots.size() < 2:
		slots.append(false)
	slots[clampi(team_slot, 0, 1)] = true
	team_data[team_id]["checkout_ready_slots"] = slots
	return bool(slots[0]) and bool(slots[1])

func _finish_team(team_id: int) -> void:
	for i in pdata.size():
		if int(pdata[i].get("team_id", -1)) == team_id and not bool(pdata[i]["done"]):
			_finish_player(i, true)

func _match_time_up() -> void:
	for i in pdata.size():
		if not pdata[i]["done"]:
			_finish_player(i, false)

func _finish_player(idx: int, settled: bool) -> void:
	if idx < 0 or idx >= pdata.size() or bool(pdata[idx]["done"]):
		return
	pdata[idx]["done"] = true
	players[idx].finished = true
	_log_milestone("%s 结算 settled=%s 得分=%d" % [seat_name(idx), settled, pdata[idx]["score"]])
	var lines := _result_lines(idx, settled)
	if idx == local_idx:
		hud.show_result(lines)
		_set_mouse_captured(false)
	elif net_mp:
		var pid := net.peer_of_seat(idx)
		if net.peer_alive(pid):
			net.rpc_id(pid, "ev_result", lines)
	var all_done := true
	for pd in pdata:
		if not pd["done"]:
			all_done = false
			break
	if all_done:
		game_over = true
		_set_mouse_captured(false)
		_log_milestone("对局结束(全员已结算)")
		# 测试钩子:WHITEBOX_QUIT_ON_END=1 时结算完自动退出。
		# 无头下游戏时间按真实时间走,用 --quit-after 帧数卡全场并不可靠,
		# 让对局自己决定何时结束才准。延迟半秒是为了让结算日志先刷出去。
		if OS.get_environment("WHITEBOX_QUIT_ON_END") != "":
			get_tree().create_timer(0.5).timeout.connect(get_tree().quit)

## 结算画面文案:委托 ResultReport
func _result_lines(idx: int, settled: bool) -> Array:
	return ResultReport.build(pdata, idx, settled, net_mp, seat_names)

func on_granny_stole(cart: Cart) -> void:
	if cart.cart_owner is Player and _steal_bc_cd <= 0.0:
		_steal_bc_cd = 15.0
		hud.broadcast("温馨提示:请看管好您的随身物品与购物车,商品遗失本店概不负责哦~")

func on_player_stole(thief: Player, _cart: Cart, item: Item) -> void:
	Main.float_text(self, thief.global_position + Vector3.UP * 2.2, "顺走了 " + item.display_name, Color(1, 0.75, 0.3))
	if tutorial_guide != null:
		tutorial_guide.on_player_stole(_cart, item)
		return
	# 车主大妈:开骂+追上来夺回
	if _cart.cart_owner is Granny and is_instance_valid(_cart.cart_owner):
		_cart.cart_owner.on_robbed(item, thief)
	if _steal_bc_cd <= 0.0:
		_steal_bc_cd = 15.0
		hud.broadcast("监控室提示:卖场内出现\"顺手牵羊\"行为。本店对此表示:抓到算你的~")

## 有人倒地:官方口吻围观播报(带冷却防刷屏)
func on_actor_downed(a: Actor) -> void:
	if tutorial_guide != null:
		tutorial_guide.on_actor_downed(a)
		return
	if game_over or _down_bc_cd > 0.0 or net_client:
		return
	_down_bc_cd = 12.0
	if a is Player:
		hud.broadcast("请注意:有顾客在卖场中央选择\"平躺\"。本店祝他早日站起来,继续消费~")
	else:
		hud.broadcast("工作人员请注意:卖场内有大妈倒地。经确认,商品完好无损,人也很乐观~")

func on_player_took_from_shelf(_item: Item) -> void:
	if tutorial_guide != null:
		tutorial_guide.on_shelf_item(_item)

func on_player_dropped_item(item: Item) -> void:
	if tutorial_guide != null:
		tutorial_guide.on_player_dropped_item(item)

func complete_tutorial() -> void:
	if game_over:
		return
	game_over = true
	if not pdata.is_empty():
		pdata[0]["settled"] = true
		pdata[0]["done"] = true
	player.settled_once = true
	player.finished = true
	_set_mouse_captured(false)
	hud.set_tutorial_text("")
	hud.show_result(["🎓 五房教学完成!", "", "移动、装车、抢夺、道具与角色技能都已通过。",
			"搜、抢、撤都会了——黑五见真章。", "", "按 回车 返回开始界面"])
	_log_milestone("教学完成 rooms=5")

# ---------- 联机粘合 ----------

## 主机执行客户端发来的动作(seat=该客户端的座位)
func apply_remote_action(seat: int, kind: String, dir: Vector3) -> void:
	if seat <= 0 or seat >= players.size() or game_over:
		return
	var p := players[seat]
	if p.downed or p.finished:
		return
	match kind:
		"interact_press":
			if OS.get_environment("WHITEBOX_MP_INTERACTION_TEST") != "":
				p.net_aim_dir = dir.normalized() if dir.length_squared() > 0.001 else p.net_aim_dir
				var debug_item := p._aimed_shelf_item()
				var debug_pick := p._best_interaction()
				print("[mp] HOST_INTERACT_RAY seat=%d hit=%s pick=%s distance=%.2f origin=%s dir=%s" % [seat,
						debug_item.item_id if is_instance_valid(debug_item) else "none",
						str(debug_pick.get("kind", "none")),
						p.global_position.distance_to(debug_item.global_position) if is_instance_valid(debug_item) else -1.0,
						str(p.global_position + Vector3.UP * THROW_ORIGIN_HEIGHT), str(dir)])
			p._on_interact_pressed(dir)
		"interact_release":
			p._on_interact_released()
		"drive":
			if p.attached:
				p.detach_cart()
			elif p.cart != null and is_instance_valid(p.cart) \
					and p.global_position.distance_to(p.cart.global_position) < 2.6:
				p.attach_cart()
		"drop":
			p._drop_held()
		"elbow":
			p.do_elbow(dir)
		"locate":
			trigger_locate_skill(p)
		"prop":
			trigger_throw_cart_item(p, dir)
		_ when kind.begins_with("throw:"):
			trigger_throw_cart_item(p, dir, kind.trim_prefix("throw:"))
		"char_skill":
			trigger_char_skill(p, dir)

func net_item_gone_notify(it: Item) -> void:
	if net_mp and not net_client:
		net.item_gone(it)

func net_granny_left_notify(g: Granny) -> void:
	if net_mp and not net_client:
		net.granny_left(g)

# ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	# 鼠标自由视角
	if event is InputEventMouseMotion and mouse_captured and not game_over:
		cam_rig.look(event.relative)
		return
	if event.is_action_pressed("ui_cancel"):
		if team_prep_active and hud != null:
			var showing := not hud.sensitivity_panel_visible()
			hud.set_sensitivity_panel(showing, cam_rig.sensitivity_multiplier())
			_set_mouse_captured(not showing)
		else:
			_set_mouse_captured(not mouse_captured)
		return
	# 右键按住进入第三人称越肩瞄准，松开才投掷；客户端仍由主机结算。
	if game_started and not game_over and player != null and event.is_action_pressed("use_prop"):
		if not player.downed and not player.finished:
			player.throw_aiming = true
		return
	if player != null and event.is_action_released("use_prop"):
		var was_aiming := player.throw_aiming
		player.throw_aiming = false
		if was_aiming and game_started and not game_over \
				and not player.downed and not player.finished:
			var selected_id := selected_cart_item_id(player)
			if selected_id != "":
				var throw_dir := player._aim_dir()
				if net_client:
					net.send_action("throw:" + selected_id, throw_dir)
				else:
					trigger_throw_cart_item(player, throw_dir, selected_id)
		return
	if tutorial and tutorial_guide != null and event.is_action_pressed("tutorial_reset"):
		tutorial_guide.reset_current_room()
		return
	if game_started and not game_over and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_cart_item(player, -1)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_cart_item(player, 1)
			return
	if event.is_action_pressed("restart") and game_over:
		net.shutdown()
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	# 客户端:动作发给主机执行
	if net_client and game_started and not game_over:
		if event.is_action_pressed("interact"):
			net.send_action("interact_press", cam_rig.aim_direction())
		elif event.is_action_released("interact"):
			net.send_action("interact_release")
		elif event.is_action_pressed("drive"):
			net.send_action("drive")
		elif event.is_action_pressed("load_cart"):
			net.send_action("drop")
		elif event.is_action_pressed("locate"):
			net.send_action("locate")
		elif event.is_action_pressed("char_skill"):
			net.send_action("char_skill", player._aim_dir())
		elif event.is_action_pressed("elbow"):
			net.send_action("elbow", player._aim_dir())
		return
	if event.is_action_pressed("dev_mode") and not game_over and not net_mp:
		var showing := not hud.dev_panel.visible
		hud.dev_panel.visible = showing
		_set_mouse_captured(not showing)
		return
	if event.is_action_pressed("debug_time") and not game_over and game_started:
		time_left = maxf(0.0, time_left - 60.0)
	elif event.is_action_pressed("debug_sale") and not game_over and game_started:
		_trigger_flash_sale()
	elif event.is_action_pressed("debug_down") and not game_over and game_started:
		player.add_imbalance(100.0)

# ---------- 公共服务 ----------

## 大妈寻路:委托 NavGrid(AStarGrid2D,格子1米)
func find_path(from: Vector3, to: Vector3) -> Array:
	return NavGrid.find_path(grid, from, to)

func _cell(p: Vector3) -> Vector2i:
	return NavGrid.cell(p)

func random_shelved_item() -> Item:
	var pool: Array = []
	for it in all_items:
		# 大件不参与随机顺手拿(避免大妈无意抬走玩家清单必需的电视)
		if is_instance_valid(it) and not it.event_locked \
				and it.state == Item.ItemState.SHELVED and it.category != Catalog.CAT_LARGE:
			pool.append(it)
	if pool.is_empty():
		return null
	return pool.pick_random()

## 白盒反馈:世界内飘字(size可调,碰撞类用大号)。联机主机自动转发给客户端。
static func float_text(ctx: Node, pos: Vector3, text: String, color: Color, size := 64) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	var lb := DynamicFloatText.new()
	lb.text = text
	lb.font = Catalog.ui_font_bold()
	lb.font_size = size
	lb.pixel_size = 0.005
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.modulate = color
	lb.outline_size = 12
	lb.outline_modulate = Color(0, 0, 0, 0.85)
	instance.add_child(lb)
	# 第一人称时，角色自身头顶或镜头后方的拟声字会完全离开视野；将这种近身反馈
	# 推到镜头前下方。正常处于视锥内的命中字幕仍留在实际事件位置。
	var display_pos := pos
	var cam := instance.get_viewport().get_camera_3d()
	var local_delta := pos - instance.player.global_position if is_instance_valid(instance.player) else Vector3.ZERO
	var own_feedback := ctx == instance.player or (ctx == instance \
			and Vector2(local_delta.x, local_delta.z).length() < 0.8 and absf(local_delta.y) < 3.0)
	lb.player_feedback = own_feedback
	if cam != null and instance.cam_rig != null and instance.cam_rig.is_first_person():
		var forward := -cam.global_transform.basis.z
		if own_feedback:
			display_pos = cam.global_position + forward * 2.1 - cam.global_transform.basis.y * 0.18
			lb.set_meta("first_person_safe_position", true)
	lb.global_position = display_pos
	if cam != null:
		lb._update_first_person_visibility(cam)
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "global_position", display_pos + Vector3.UP * 1.2, 1.1)
	tw.tween_property(lb, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(lb.queue_free)
	if instance.net != null and instance.net.active and instance.net.is_host:
		instance.net.rpc("ev_float", pos, text, color, size)
