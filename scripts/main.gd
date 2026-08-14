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

static var instance: Main

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
var _camera_first_person := false
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

var game_started := false
var tutorial := false
var net_mp := false              # 联机对局
var net_client := false          # 本机是客户端
var pending_npc := 8             # 开始界面滑块选定的NPC数量
## 无头运行(自动化测试);为true时把关键里程碑打到 stdout 供 tools/smoke_test.ps1 断言
var headless := false

## 里程碑日志:只在无头测试下输出,不干扰正常游玩
func _log_milestone(msg: String) -> void:
	if headless:
		print("[headless] ", msg)

# ---------- 启动与开始界面 ----------

func _ready() -> void:
	instance = self
	headless = DisplayServer.get_name() == "headless"
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
	hud.start_game_pressed.connect(func() -> void: _start_match(false))
	hud.start_tutorial_pressed.connect(func() -> void: _start_match(true))
	hud.host_pressed.connect(_menu_host)
	hud.join_pressed.connect(_menu_join)
	hud.begin_pressed.connect(net_begin_match)
	hud.leave_room_pressed.connect(_menu_leave_room)
	hud.quit_pressed.connect(func() -> void: get_tree().quit())
	if OS.get_environment("WHITEBOX_NPC") != "":
		pending_npc = clampi(int(OS.get_environment("WHITEBOX_NPC")), 0, 10)
	hud.set_npc_count_display(pending_npc)

	# 调试:设置环境变量 WHITEBOX_SHOT=<png路径> 时,运行约2秒自动截图退出(hud常驻层执行)
	_shot_path = OS.get_environment("WHITEBOX_SHOT")

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

func _start_match(tut: bool) -> void:
	if game_started:
		return
	game_started = true
	tutorial = tut
	# 单人/教学:用本机档案里选定的角色
	PlayerProfile.ensure_loaded()
	var env_char := OS.get_environment("WHITEBOX_CHAR")
	if env_char != "":
		PlayerProfile.char_id = CharacterDef.valid_id(env_char)
	seat_chars = [PlayerProfile.char_id]
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
	# GUI视觉回归：自动展示当前角色主技能，配合 WHITEBOX_SHOT 截图。
	if OS.get_environment("WHITEBOX_SHOW_CHAR_SKILL") != "":
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(player):
				trigger_char_skill(player, cam_rig.forward()))
	if OS.get_environment("WHITEBOX_WHEEL_DEMO") != "":
		for i in ["detergent", "thermos", "cola", "tv", "candy"].size():
			var id: String = ["detergent", "thermos", "cola", "tv", "candy"][i]
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
		names: Array = [], colors: Array = [], chars: Array = []) -> void:
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
		var test_item := Item.create("tv")
		add_child(test_item)
		all_items.append(test_item)
		# 驾驶回归结束后玩家会在车把处下车，因此以车把为基准布置目标。
		test_item.set_shelved(players[seat].cart.handle_pos() + Vector3(0, 1.15, -1.2))
		_mp_interaction_test_items[seat] = test_item

## 自动化走真实客户端路径：先完成上车回归并下车，再让准星对准测试商品，
## 真实长按E；最终同时核验主机回传的手持归属与第一人称手持渲染。
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
				and target.collision_layer == 0 and cam_rig.first_person_held_item_count() == 1
		print("[mp] CLIENT_SHELF_INTERACTION=%s seat=%d held=%d item_state=%d fp_items=%d" % [
				"PASS" if passed else "FAIL", local_idx, player.held.size(), target.state,
				cam_rig.first_person_held_item_count()]))

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
		hud.set_menu_status("房间已创建!本机IP: %s (端口%d)\n把IP告诉大家,最多可容纳6人,人齐后点\"开始对局\"\n(也可改填别人的IP点\"加入房间\",本机自动改当客户端)\n若别人连不上:在本机Windows防火墙里\"允许\"本程序(UDP %d)" % [ips, Net.PORT, Net.PORT])

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

func _build_world(wseed: int, npc: int, nplayers: int) -> void:
	seed(wseed)
	if tutorial:
		tutorial_data = TutorialRoomBuilder.build(self)
		grid = tutorial_data["grid"]
		sale_points = []
		_make_tutorial_list()
		_spawn_players(tutorial_data, 1)
		hud.set_npc_count_display(0)
		return
	var data := MarketBuilder.build(self)
	grid = data["grid"]
	sale_points = data["sale_points"]
	var lane_i := 0
	for x in data["lane_x"]:
		lane_i += 1
		var co := Checkout.new()
		add_child(co)
		var rects: Array = co.setup(x, lane_i)
		for r in rects:
			MarketBuilder._mark_solid(grid, r)
		co.item_scanned.connect(_on_item_scanned)
		co.lane_settled.connect(_on_lane_settled)
		checkouts.append(co)
	_spawn_stock(data)
	_make_lists(nplayers)
	_spawn_players(data, nplayers)
	_granny_spawns = data["granny_spawns"]
	for i in npc:
		_spawn_one_granny()
	sale_times = [randf_range(55.0, 110.0), randf_range(150.0, 220.0)]
	_spawn_random_slippery(3, 0.0)
	hud.set_npc_count_display(grannies.size())
	hud.broadcast("亲爱的顾客,欢迎光临疯抢超市。今天是疯抢星期五,每人限购,理性消费,祝您购物愉快～")
	hud.broadcast("温馨提示:货架商品先到先得,请文明抢购～")

## 教学关固定三件结业清单，避免随机清单与房间内训练物资错位。
func _make_tutorial_list() -> void:
	var list: Array = []
	for id in ["tissue", "thermos", "drone"]:
		list.append({
			"id": id,
			"name": Catalog.ITEMS[id]["name"],
			"cat": Catalog.ITEMS[id]["cat"],
			"scanned": false,
			"via_sale": false,
		})
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
		zone_slots[s["zone"]].append(s["pos"])
	for zone in zone_slots:
		zone_slots[zone].shuffle()
	for id in Catalog.ITEMS:
		var info: Dictionary = Catalog.ITEMS[id]
		if info["cat"] == Catalog.CAT_SALE:
			continue
		if info["cat"] == Catalog.CAT_LARGE:
			for i in int(info["stock"]):
				if _large_slots.is_empty():
					break
				var tp: Vector3 = _large_slots.pop_front()
				var tv := Item.create(id)
				add_child(tv)
				tv.set_shelved(Vector3(tp.x, 0.4 + tv.collider_half_height() + 0.05, tp.z))
				all_items.append(tv)
			continue
		var slots: Array = zone_slots[info["zone"]]
		for i in int(info["stock"]):
			if slots.is_empty():
				break
			var pos: Vector3 = slots.pop_back()
			var it := Item.create(id)
			add_child(it)
			# 用物理半高而非视觉半高:扁平商品的碰撞体被加厚过(见 Item.MIN_COLLIDER_THICKNESS),
			# 若按视觉半高摆放,碰撞体下半会陷进货架板里,解算时被弹出去
			it.set_shelved(pos + Vector3(0, it.collider_half_height(), 0))
			all_items.append(it)

## 每名玩家一张代购清单:2硬需求+4常规+1大件。这是客户下的单,不是自己要用的东西
func _make_lists(nplayers: int) -> void:
	pdata = []
	for pi in nplayers:
		var needs := Catalog.ids_of_cat(Catalog.CAT_NEED)
		needs.shuffle()
		var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
		normals.shuffle()
		var larges := Catalog.ids_of_cat(Catalog.CAT_LARGE)
		larges.shuffle()
		var list: Array = []
		for id in [needs[0], needs[1], normals[0], normals[1], normals[2], normals[3], larges[0]]:
			list.append({
				"id": id,
				"name": Catalog.ITEMS[id]["name"],
				"cat": Catalog.ITEMS[id]["cat"],
				"scanned": false,
				"via_sale": false,
			})
		pdata.append({"list": list, "score": 0, "counts": {}, "orig": 0, "saved": 0, "settled": false, "done": false})

## 玩家出生:最多6人,6种配色,沿入口区一字排开
## 各座位的昵称与配色。联机时由主机下发(已消歧),单机时只有本机一人。
var seat_names: Array[String] = []
var seat_colors: Array[int] = []
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
	if i >= 0 and i < seat_colors.size():
		return PlayerProfile.color_of(seat_colors[i])
	return PlayerProfile.color_of(i)

## 座位 i 的角色 id。缺档时回落到首个角色
func seat_char(i: int) -> String:
	if i >= 0 and i < seat_chars.size():
		return CharacterDef.valid_id(seat_chars[i])
	return CharacterDef.ORDER[0]

func _spawn_players(data: Dictionary, nplayers: int) -> void:
	# 单机:直接用本机档案,让玩家在单人局也能看到自己起的名字与配色
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
		p.avatar_color = seat_color(i)
		p.seat_label = seat_name(i)
		p.char_id = seat_char(i)
		add_child(p)
		p.global_position = data["player_spawn"] + Vector3(-2.2 * i, 0, 0.9 * (i % 2))
		var cart := Cart.create(p.avatar_color, "%s的车" % seat_name(i))
		cart.cart_owner = p
		add_child(cart)
		cart.global_position = p.global_position + Vector3(-1.6, 0.2, -0.5)
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

var _granny_spawns: Array = []
var _granny_seq := 0

func _spawn_one_granny() -> void:
	var pos: Vector3 = _granny_spawns[_granny_seq % _granny_spawns.size()]
	_granny_seq += 1
	var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
	# 与所有玩家清单的重叠池(常规品+大件都参与对抗)
	var overlap_pool: Array = []
	var large_pool: Array = []
	for pd in pdata:
		for entry in pd["list"]:
			if entry["cat"] == Catalog.CAT_LARGE:
				if not large_pool.has(entry["id"]):
					large_pool.append(entry["id"])
			elif not overlap_pool.has(entry["id"]):
				overlap_pool.append(entry["id"])
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
		pending_npc = n
		if hud != null:
			hud.set_npc_count_display(n)
		return
	if net_mp:
		return
	var valid: Array[Granny] = []
	for g in grannies:
		if is_instance_valid(g):
			valid.append(g)
	grannies = valid
	while grannies.size() > n:
		var g2: Granny = grannies.pop_back()
		g2.despawn()
	while grannies.size() < n:
		_spawn_one_granny()
	if hud != null:
		hud.set_npc_count_display(grannies.size())

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

# ---------- 环境与相机 ----------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.9, 0.92, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
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
			_client_tick(delta)
		return
	if game_over:
		return
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
				it.set_free_at(MapLayout.respawn_pos(0.8))

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
	_update_timer_hud()
	hud.set_bars(player.stamina, player.imbalance)
	hud.set_prompt(player.prompt_text, player.channel_progress)
	hud.set_score(client_view.score)
	_update_skill_hud()
	hud.set_list(client_view.rows)

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

## 购物车内所有自由商品都可作为弹药；排序固定，供滚轮与联机按商品ID选择。
func cart_throw_items(p: Player) -> Array[Item]:
	var out: Array[Item] = []
	if p == null or not is_instance_valid(p.cart):
		return out
	for it in p.cart.items_in_basket():
		if is_instance_valid(it) and it.state == Item.ItemState.FREE:
			out.append(it)
	out.sort_custom(func(a: Item, b: Item) -> bool:
		if a.item_id == b.item_id:
			return a.get_instance_id() < b.get_instance_id()
		return a.item_id < b.item_id)
	return out

func cycle_cart_item(p: Player, step: int) -> void:
	var items := cart_throw_items(p)
	if items.is_empty():
		p.throw_selection = 0
		return
	p.throw_selection = posmod(p.throw_selection + step, items.size())
	if tutorial_guide != null and p == player:
		tutorial_guide.on_wheel_cycled()

func selected_cart_item_id(p: Player) -> String:
	var items := cart_throw_items(p)
	if items.is_empty():
		return ""
	p.throw_selection = posmod(p.throw_selection, items.size())
	return items[p.throw_selection].item_id

## 右键:从自己的购物车取出轮盘选中商品，沿屏幕中心准星投掷。
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
	# 投掷是驾驶购物车时的专属动作；脱车右键只负责拉近观察镜头，静默不投掷。
	if not p.attached or not is_instance_valid(p.cart):
		return
	var items := cart_throw_items(p)
	var prop: Item = null
	for it in items:
		if wanted_id == "" or it.item_id == wanted_id:
			prop = it
			break
	if prop == null:
		if p == player:
			Main.float_text(self, p.global_position + Vector3.UP * 2.4,
					"购物车里没有可投掷商品", Color(1.0, 0.75, 0.35), 52)
		return
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
	get_tree().create_timer(Catalog.THROW_WORLD_ARM_TIME).timeout.connect(func() -> void:
		if not is_instance_valid(it) or not bool(it.get_meta("throw_active", false)):
			return
		it.collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART
		var contacts := it.get_colliding_bodies()
		for contact in contacts:
			if contact == owner or contact == owner.cart:
				continue
			_thrown_item_hit(it, contact, owner)
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
	# 命中后商品仍留在场内，可再次拾取/装车；仅关闭角色碰撞避免持续蹭伤。
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(it):
			it.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
			it.remove_collision_exception_with(owner)
			if is_instance_valid(owner.cart):
				it.remove_collision_exception_with(owner.cart))

func _apply_throw_effect(id: String, pos: Vector3, owner: Player, direct_actor: Actor = null) -> void:
	match Catalog.prop_kind(id):
		Catalog.PROP_BURST:
			_throw_burst(pos, owner)
		Catalog.PROP_WET:
			spawn_slow_zone(pos, Catalog.WET_RADIUS, Catalog.WET_LIFE,
					Catalog.WET_MOVE_FACTOR, null, "湿滑地面", Catalog.prop_effect_color(id),
					Catalog.WET_TRACTION_FACTOR)
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
		var cart_away := pushed_cart.global_position - pos
		cart_away.y = 0.0
		if cart_away.length() <= Catalog.BURST_RADIUS:
			if cart_away.length() <= 0.05:
				cart_away = pushed_cart.global_position - owner.global_position
				cart_away.y = 0.0
			if cart_away.length() <= 0.05:
				cart_away = Vector3.FORWARD
			var impulse := (cart_away.normalized() * Catalog.BURST_CART_PUSH \
					+ Vector3.UP * Catalog.BURST_CART_LIFT) * pushed_cart.mass
			pushed_cart.apply_central_impulse(impulse)
			var flip_axis := Vector3(cart_away.z, 0.15, -cart_away.x).normalized()
			pushed_cart.apply_torque_impulse(flip_axis * Catalog.BURST_CART_TORQUE * pushed_cart.mass)
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
		var sx := MapLayout.slippery_x()
		var sz := MapLayout.slippery_z()
		var p := Vector3(randf_range(sx.x, sx.y), 0, randf_range(sz.x, sz.y))
		var cell := _cell(p)
		if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
			SlipperyZone.create(self, p, Vector3(3.5, 2, 3.5), life)
			if life > 0.0 and net_mp and not net_client:
				net.rpc("ev_slippery", p, life)
			placed += 1

## 某玩家"还缺"的清单商品id集合:未结算,且其车斗/手里都没有同类
func missing_list_ids(idx: int = -1) -> Dictionary:
	if idx < 0:
		idx = local_idx
	var p := players[idx]
	var have := {}
	if is_instance_valid(p.cart):
		for it in p.cart.items_in_basket():
			have[it.item_id] = true
	for it2 in p.held:
		if is_instance_valid(it2):
			have[it2.item_id] = true
	var missing := {}
	for entry in pdata[idx]["list"]:
		if not entry["scanned"] and not have.has(entry["id"]):
			missing[entry["id"]] = true
	return missing

## Q:高亮全场所有"清单上还缺"的商品(车里已有同类的不亮),绿闪3秒,CD10秒
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
	var missing := missing_list_ids(idx)
	var idxs: Array = []
	for i in all_items.size():
		var it = all_items[i]
		if not is_instance_valid(it) or it.state == Item.ItemState.SCANNED:
			continue
		if missing.has(it.item_id):
			idxs.append(i)
	Main.float_text(self, p.global_position + Vector3.UP * 2.4,
			"找货雷达:代购单已备齐!" if idxs.is_empty() else "找货雷达!锁定 %d 件缺货" % idxs.size(),
			Color(0.3, 1.0, 0.5))
	if p == player:
		client_locate(idxs)   # 本机直接开始闪
	elif net_mp:
		var pid := net.peer_of_seat(idx)
		if net.peer_alive(pid):
			net.rpc_id(pid, "ev_locate", idxs)

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
	var ray_end := ray_origin + direction.normalized() * max_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end,
			Catalog.L_WORLD | Catalog.L_ITEM)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") is Item:
		var item := hit["collider"] as Item
		if item.state == Item.ItemState.SHELVED:
			return item
	return null

func _update_camera(delta: float) -> void:
	if player == null or cam_rig == null:
		return
	var aiming := player.throw_aiming and not player.downed and not player.finished and not game_over
	var first_person := not player.attached and not player.downed and not player.finished
	var entering_first_person := first_person and not _camera_first_person
	_camera_first_person = first_person
	cam_rig.set_first_person(first_person)
	cam_rig.set_throw_aiming(aiming)
	# 本机第一人称不渲染自己的胶囊、手和名牌；其他玩家实例不受影响。
	if player.body_root != null:
		player.body_root.visible = not first_person
	if player.name_label != null:
		player.name_label.visible = not first_person
	# 推车时镜头跟车(视野中心是车头,便于瞄准撞击)
	var target := player.global_position + Vector3.UP * 1.5
	if player.attached and is_instance_valid(player.cart) and not aiming:
		target = player.cart.global_position + Vector3.UP * 1.4
	if entering_first_person:
		cam_rig.global_position = target
	cam_rig.follow(target, delta)
	cam_rig.update_first_person_hands(player, delta)
	if aiming and player.attached and selected_cart_item_id(player) != "" and player.prop_cd <= 0.0 \
			and is_instance_valid(player.cart):
		var launch := throw_launch_data(player, player._aim_dir())
		var exclusions: Array[RID] = [player.get_rid(), player.cart.get_rid()]
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
	if tutorial:
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
		elif time_left > CLOSING_WARN:
			hud.set_phase("扫货中盘")
		else:
			hud.set_phase("打烊冲刺——全场挤向收银台")

func _update_skill_hud() -> void:
	var s1 := "Q雷达:就绪" if player.locate_cd <= 0.0 else "Q 雷达:%d秒" % int(ceil(player.locate_cd))
	var wheel_items := cart_throw_items(player)
	var selected_id := selected_cart_item_id(player)
	var prop_text := "车内无商品" if selected_id == "" else "%s·%d失衡" % [Catalog.ITEMS[selected_id]["name"], int(Catalog.throw_imbalance(selected_id))]
	var s2 := "按住右键:近距观察"
	if player.attached:
		s2 = "按住右键瞄准/松开投掷:%s" % prop_text if player.prop_cd <= 0.0 \
				else "右键 投掷:%.1f秒" % player.prop_cd
	hud.set_item_wheel(wheel_items, player.throw_selection, player.attached)
	hud.set_obscured(player.obscure_time > 0.0)
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
	hud.set_list(_build_rows(local_idx))

## 清单行(按超市分区分组;入车/已结算标绿划线):委托 ListRows
func _build_rows(idx: int) -> Array:
	return ListRows.build(self, idx)

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
	hud.broadcast("限时特价!超值神秘箱已投放至卖场,数量有限,先到先得哦～(可顶替代购单上任意常规品)")
	for g in grannies:
		if is_instance_valid(g) and randf() < 0.6:
			g.rush_to(pos)

func _on_item_scanned(item: Item, by: Player) -> void:
	var idx := players.find(by)
	if idx < 0:
		return
	var pd: Dictionary = pdata[idx]
	var pts := Catalog.points_for(item.item_id)
	if item.category == Catalog.CAT_SALE:
		pts += Catalog.SALE_BONUS
		for entry in pd["list"]:
			if entry["cat"] == Catalog.CAT_NORMAL and not entry["scanned"]:
				entry["scanned"] = true
				entry["via_sale"] = true
				break
	else:
		for entry in pd["list"]:
			if entry["id"] == item.item_id and not entry["scanned"]:
				entry["scanned"] = true
				break
	pd["score"] += pts
	pd["counts"][item.category] = int(pd["counts"].get(item.category, 0)) + 1
	var price := Catalog.price_of(item.item_id)
	pd["orig"] += price
	pd["saved"] += int(round(price * Catalog.discount_of(item.item_id)))
	Main.float_text(self, item.global_position + Vector3.UP * 0.8, "+%d" % pts, Color(0.5, 0.95, 0.55))

func is_settled_agent(a: Actor) -> bool:
	var i := players.find(a)
	return i >= 0 and pdata[i]["settled"]

## 玩家过完收银台=该玩家终局(教学=毕业;联机中另一名玩家继续)
func _on_lane_settled(by: Player) -> void:
	if game_over:
		return
	var idx := players.find(by)
	if idx < 0 or pdata[idx]["settled"]:
		return
	pdata[idx]["settled"] = true
	by.settled_once = true
	by.finished = true
	if tutorial:
		complete_tutorial()
		return
	_finish_player(idx, true)

func _match_time_up() -> void:
	for i in pdata.size():
		if not pdata[i]["done"]:
			_finish_player(i, false)

func _finish_player(idx: int, settled: bool) -> void:
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
		_set_mouse_captured(not mouse_captured)
		return
	# 右键按住进入越肩瞄准，松开才投掷；客户端也只在松开时向主机发动作。
	if game_started and not game_over and player != null and event.is_action_pressed("use_prop"):
		if not player.downed and not player.finished:
			player.throw_aiming = true
		return
	if player != null and event.is_action_released("use_prop"):
		var was_aiming := player.throw_aiming
		player.throw_aiming = false
		if was_aiming and player.attached and game_started and not game_over \
				and not player.downed and not player.finished:
			var selected_id := selected_cart_item_id(player)
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
		if is_instance_valid(it) and it.state == Item.ItemState.SHELVED and it.category != Catalog.CAT_LARGE:
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
	lb.no_depth_test = true
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
