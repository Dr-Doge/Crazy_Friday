class_name Main extends Node3D
## 主控制器:建场、发牌(代购清单)、计时与打烊、限时特价、计分结算、寻路服务、联机粘合。
## 联机为主机权威:世界用共享种子两端确定性重建,客户端只发输入、收状态渲染。

const MATCH_TIME := 300.0        # 5分钟
const GRACE_TIME := 30.0         # 打烊宽限
const CLOSING_WARN := 120.0      # 剩2分钟进入打烊冲刺

static var instance: Main

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
var all_items: Array[Item] = []

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
	# 测试钩子:车斗物理压力测试(回归"薄商品被挤出车外/穿模")
	if OS.get_environment("WHITEBOX_PHYSTEST") != "":
		phys_stress = PhysStress.new(self)
		phys_stress.setup()
	# 测试钩子:角色技能自检(无头下没人按键,技能代码否则零覆盖)
	if OS.get_environment("WHITEBOX_CHARTEST") != "":
		char_probe = CharProbe.new(self)
		char_probe.setup()

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
	if net_client:
		client_view = ClientView.new(self)
		_make_client_puppets()
	net.register_world()
	hud.hide_menu()
	_set_mouse_captured(true)
	hud.set_menu_status("")
	_log_milestone("联机开局 seat=%d/%d host=%s npc=%d" % [local_idx, nplayers, host, npc])
	if host:
		hud.broadcast("联机对局开始!%d位\"热心顾客\"已入场,黑五愉快,手下无情~" % nplayers)

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
	player = players[local_idx]

var _granny_spawns: Array = []
var _granny_seq := 0

func _spawn_one_granny() -> void:
	var pos: Vector3 = _granny_spawns[_granny_seq % _granny_spawns.size()]
	_granny_seq += 1
	var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
	# 与所有玩家清单的重叠池(大件除外):保证对抗
	var overlap_pool: Array = []
	for pd in pdata:
		for entry in pd["list"]:
			if entry["cat"] != Catalog.CAT_LARGE and not overlap_pool.has(entry["id"]):
				overlap_pool.append(entry["id"])
	var g := Granny.new()
	g.main = self
	g.body_color = Color.from_hsv(randf(), 0.45, 0.85)
	overlap_pool.shuffle()
	var list: Array = [overlap_pool[0], overlap_pool[1], overlap_pool[2]]
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
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		c.freeze = true
		c.set_physics_process(false)
	for co in checkouts:
		co.set_physics_process(false)

# ---------- 教学关 ----------

## 仅教学模式下创建;九步指引的全部逻辑在 tutorial.gd
var tutorial_guide: TutorialGuide

## 仅 WHITEBOX_PHYSTEST 下创建:车斗物理压力测试,见 phys_stress.gd
var phys_stress: PhysStress

## 仅 WHITEBOX_CHARTEST 下创建:角色技能自检,见 char_probe.gd
var char_probe: CharProbe

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

	if tutorial:
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
## - 李洋「爆款嗅觉」:全场无距离限制,并在车顶浮出具体商品名
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
		if hot and not sniff and origin.distance_to(c.global_position) > CharSkills.SNIFF_RANGE_OTHERS:
			hot = false
		c.set_highlight(hot)
		c.set_hot_name(hot_name if (hot and sniff) else "")

## 发给某客户端的红壳数据:[[车下标, 商品名或""], ...]
## 商品名只对李洋(爆款嗅觉)非空;非李洋还要过 12 米距离门槛
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
		if not sniff and p.global_position.distance_to(c.global_position) > CharSkills.SNIFF_RANGE_OTHERS:
			continue
		out.append([i, hot_name if sniff else ""])
	return out

# ---------- 客户端渲染 ----------

## 仅客户端创建:状态包缓存与插值渲染,详见 client_view.gd
var client_view: ClientView

func apply_net_state(d: Dictionary) -> void:
	if client_view != null:
		client_view.apply_state(d)

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

## Ctrl:角色专属技能。实现见 char_skills.gd(主机权威:联机时远程动作也走这里)
func trigger_char_skill(p: Player = null, dir := Vector3.ZERO) -> void:
	if p == null:
		p = player
	if game_over or p == null:
		return
	CharSkills.trigger(self, p, dir)

##「上链接」抢到货的播报与标记下发(只在主机侧调用)。
##注意:victim 可能是大妈或测试靶子,而 players 是 Array[Player]——
## 不先判类型就 find() 会触发 TypedArray 校验报错(踩过)
func on_char_grab(thief: Player, victim: Actor, item: Item) -> void:
	if net_client:
		return
	var thief_seat := players.find(thief)
	var vname := "大妈"
	var victim_seat := -1
	if victim is Player:
		victim_seat = players.find(victim)
		vname = seat_name_2nd(victim_seat)
	hud.broadcast("直播间提示:%s 对着%s大喊\"上链接\",%s 就这么没了~" % [
			seat_name(thief_seat), vname, item.display_name])
	# 标记是低频事件,走可靠 RPC 而不是塞进 20Hz 状态包
	if net_mp:
		if victim_seat > 0:
			var vpid := net.peer_of_seat(victim_seat)
			if net.peer_alive(vpid):
				net.rpc_id(vpid, "ev_mark", "track", thief_seat, CharSkills.GRAB_MARK)
		if thief_seat > 0:
			var tpid := net.peer_of_seat(thief_seat)
			if net.peer_alive(tpid):
				net.rpc_id(tpid, "ev_mark", "exposed", victim_seat, CharSkills.GRAB_MARK)

## 客户端收到标记事件
func client_mark(kind: String, seat: int, dur: float) -> void:
	if kind == "track":
		player.track_time = dur
		player.track_target = players[seat] if seat >= 0 and seat < players.size() else null
	else:
		player.exposed_time = dur

##右键:向镜头方向掷出水瓶,落地生成临时湿滑地面(CD8秒)
func trigger_throw_bottle(p: Player = null, dir := Vector3.ZERO) -> void:
	if p == null:
		p = player
	if game_over or p == null:
		return
	if p.bottle_cd > 0.0:
		if p == player:
			Main.float_text(self, p.global_position + Vector3.UP * 2.4, "水瓶冷却中(%d秒)" % int(ceil(p.bottle_cd)), Color(0.8, 0.8, 0.8))
		return
	p.bottle_cd = 8.0
	var fwd := dir
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = cam_rig.forward()
	fwd = fwd.normalized()
	var b := RigidBody3D.new()
	b.mass = 1.0
	b.collision_layer = 0
	b.collision_mask = Catalog.L_WORLD
	b.contact_monitor = true
	b.max_contacts_reported = 4
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.75, 0.95, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = mat
	mi.mesh = cm
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.09
	sh.height = 0.32
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = p.global_position + Vector3.UP * 1.6 + fwd * 0.6
	b.linear_velocity = fwd * 13.0 + Vector3.UP * 4.5
	b.angular_velocity = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	b.body_entered.connect(func(_bd: Node) -> void: _bottle_land(b))

func _bottle_land(b: RigidBody3D) -> void:
	if not is_instance_valid(b):
		return
	var pos := b.global_position
	pos.y = 0.0
	b.queue_free()
	SlipperyZone.create(self, pos, Vector3(3.5, 2, 3.5), 12.0)
	if net_mp and not net_client:
		net.rpc("ev_slippery", pos, 12.0)
	Main.float_text(self, pos + Vector3.UP * 1.0, "哗啦!!地面湿滑!", Color(0.4, 0.8, 1.0), 72)

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
	if game_over or p == null:
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

func _update_camera(delta: float) -> void:
	if player == null or cam_rig == null:
		return
	# 推车时镜头跟车(视野中心是车头,便于瞄准撞击)
	var target := player.global_position + Vector3.UP * 1.5
	if player.attached and is_instance_valid(player.cart):
		target = player.cart.global_position + Vector3.UP * 1.4
	cam_rig.follow(target, delta)

func _set_mouse_captured(c: bool) -> void:
	mouse_captured = c
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
	var s2 := "右键 水瓶:就绪" if player.bottle_cd <= 0.0 else "右键 水瓶:%d秒" % int(ceil(player.bottle_cd))
	var s3 := "空格稳住:就绪" if player.brace_cd <= 0.0 else ("空格 稳住:格挡中!" if player.braced else "空格 稳住:%d秒" % int(ceil(player.brace_cd)))
	var sk := CharacterDef.skill_name(player.char_id)
	var s4 := "Ctrl %s:就绪" % sk
	if player.stance_time > 0.0:
		s4 = "Ctrl %s:扎住了!" % sk
	elif player.stun_time > 0.0:
		s4 = "Ctrl %s:收不住脚(%.1f秒)" % [sk, player.stun_time]
	elif player.char_cd > 0.0:
		s4 = "Ctrl %s:%d秒" % [sk, int(ceil(player.char_cd))]
	var ready: bool = player.locate_cd <= 0.0 and player.bottle_cd <= 0.0 \
			and player.brace_cd <= 0.0 and player.char_cd <= 0.0
	# 「上链接」的双向反馈:抢人者知道自己暴露,被抢者知道能看见对方
	if player.exposed_time > 0.0:
		s4 += "⚠ 位置暴露 %.1f秒!" % player.exposed_time
	elif player.track_time > 0.0:
		s4 += "  👁 已锁定抢你货的人 %.1f秒" % player.track_time
	hud.set_skill(s1 + " · " + s2 + " · " + s3 + " · " + s4, ready)
	# 马德胜「余光」:屏幕边缘的威胁方向预警(只给信息,不给数值)
	hud.set_threats(CharSkills.threats_for(self, player), cam_yaw)
	# 李洋「上链接」的受害者:4秒内穿墙看到抢你货的人
	_update_track_mark()

## 被抢货后的追踪标记:只有受害者本机能看到那个红壳
func _update_track_mark() -> void:
	for p in players:
		if not is_instance_valid(p) or p.mark_shell == null:
			continue
		var show_it: bool = player.track_time > 0.0 and player.track_target == p
		p.mark_shell.visible = show_it

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
		game_over = true
		_set_mouse_captured(false)
		hud.set_tutorial_text("")
		hud.show_result(["🎓 教学完成!", "", "搜、抢、撤都会了——黑五见真章。", "", "按 回车 返回开始界面"])
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
		tutorial_guide.marks["stole"] = true
	# 车主大妈:开骂+追上来夺回
	if _cart.cart_owner is Granny and is_instance_valid(_cart.cart_owner):
		_cart.cart_owner.on_robbed(item, thief)
	if _steal_bc_cd <= 0.0:
		_steal_bc_cd = 15.0
		hud.broadcast("监控室提示:卖场内出现\"顺手牵羊\"行为。本店对此表示:抓到算你的~")

## 有人倒地:官方口吻围观播报(带冷却防刷屏)
func on_actor_downed(a: Actor) -> void:
	if game_over or _down_bc_cd > 0.0 or net_client:
		return
	_down_bc_cd = 12.0
	if a is Player:
		hud.broadcast("请注意:有顾客在卖场中央选择\"平躺\"。本店祝他早日站起来,继续消费~")
	else:
		hud.broadcast("工作人员请注意:卖场内有大妈倒地。经确认,商品完好无损,人也很乐观~")

func on_player_took_from_shelf(_item: Item) -> void:
	pass

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
			p._on_interact_pressed()
		"interact_release":
			p._cancel_channel()
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
		"throw":
			trigger_throw_bottle(p, dir)
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
	if event.is_action_pressed("restart") and game_over:
		net.shutdown()
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	# 客户端:动作发给主机执行
	if net_client and game_started and not game_over:
		if event.is_action_pressed("interact"):
			net.send_action("interact_press")
		elif event.is_action_released("interact"):
			net.send_action("interact_release")
		elif event.is_action_pressed("drive"):
			net.send_action("drive")
		elif event.is_action_pressed("load_cart"):
			net.send_action("drop")
		elif event.is_action_pressed("locate"):
			net.send_action("locate")
		elif event.is_action_pressed("throw"):
			net.send_action("throw", cam_rig.forward())
		elif event.is_action_pressed("char_skill"):
			net.send_action("char_skill", cam_rig.forward())
		elif event.is_action_pressed("elbow"):
			net.send_action("elbow", cam_rig.forward())
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
static func float_text(_ctx: Node, pos: Vector3, text: String, color: Color, size := 64) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	var lb := Label3D.new()
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
	lb.global_position = pos
	var tw := lb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "global_position", pos + Vector3.UP * 1.2, 1.1)
	tw.tween_property(lb, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(lb.queue_free)
	if instance.net != null and instance.net.active and instance.net.is_host:
		instance.net.rpc("ev_float", pos, text, color, size)
