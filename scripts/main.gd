class_name Main extends Node3D
## 主控制器:建场、发牌(清单)、计时与打烊、限时特价、计分结算、寻路服务、联机粘合。
## 联机为主机权威:世界用共享种子两端确定性重建,客户端只发输入、收状态渲染。

const MATCH_TIME := 300.0        # 5分钟
const GRACE_TIME := 30.0         # 打烊宽限
const CLOSING_WARN := 120.0      # 剩2分钟进入打烊冲刺
const CAM_SENS := 0.003          # 鼠标灵敏度
const CAM_DIST := 5.2            # 第三人称跟随距离

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
var camera: Camera3D
var cam_pivot: Node3D
var cam_spring: SpringArm3D
var cam_yaw := 0.0
var cam_pitch := -0.38
var cam_shake := 0.0
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

# ---------- 启动与开始界面 ----------

func _ready() -> void:
	instance = self
	print("疯抢星期五 白盒Demo ", Catalog.GAME_VERSION)
	_setup_input_map()
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
	elif DisplayServer.get_name() == "headless" or OS.get_environment("WHITEBOX_AUTOSTART") != "":
		_start_match(false)
	else:
		_set_mouse_captured(false)

func _start_match(tut: bool) -> void:
	if game_started:
		return
	game_started = true
	tutorial = tut
	_build_world(randi(), 0 if tut else pending_npc, 1)
	hud.hide_menu()
	_set_mouse_captured(true)
	if tut:
		_setup_tutorial()

## 联机开局(各端各自调用,种子一致→世界一致)。my_seat:本机座位(主机0)。
func start_mp(host: bool, wseed: int, npc: int, my_seat: int, nplayers: int) -> void:
	if game_started:
		return
	game_started = true
	net_mp = true
	net_client = not host
	local_idx = 0 if host else my_seat
	tutorial = false
	_build_world(wseed, npc, nplayers)
	if net_client:
		_make_client_puppets()
	net.register_world()
	hud.hide_menu()
	_set_mouse_captured(true)
	hud.set_menu_status("")
	if host:
		hud.broadcast("联机对局开始!%d位顾客已入场,黑五愉快,手下无情~" % nplayers)

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
	hud.broadcast("玩家%d已提前离场。他的购物车留在原地——商品先到先得~" % (seat + 1))

func _menu_host() -> void:
	if game_started:
		return
	var ips := net.host_room()
	if ips == "":
		hud.set_menu_status("创建房间失败(端口可能被占用)")
	else:
		hud.lock_menu_for_host()
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
	hud.broadcast("亲爱的顾客,欢迎光临疯抢超市。今天是疯抢星期五,祝您购物愉快～")
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
				tv.set_shelved(Vector3(tp.x, 0.4 + tv.box_size.y * 0.5 + 0.05, tp.z))
				all_items.append(tv)
			continue
		var slots: Array = zone_slots[info["zone"]]
		for i in int(info["stock"]):
			if slots.is_empty():
				break
			var pos: Vector3 = slots.pop_back()
			var it := Item.create(id)
			add_child(it)
			it.set_shelved(pos + Vector3(0, it.box_size.y * 0.5, 0))
			all_items.append(it)

## 每名玩家一张清单:2必需+4常规+1大件(策划案§四)
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
const PLAYER_COLORS: Array = [
	Color(0.25, 0.5, 0.9),    # 蓝
	Color(0.95, 0.55, 0.2),   # 橙
	Color(0.3, 0.8, 0.45),    # 绿
	Color(0.7, 0.4, 0.9),     # 紫
	Color(0.95, 0.4, 0.55),   # 粉
	Color(0.35, 0.8, 0.85),   # 青
]

func _spawn_players(data: Dictionary, nplayers: int) -> void:
	for i in nplayers:
		var p := Player.new()
		p.main = self
		p.remote = (i != local_idx)
		p.avatar_color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.seat_label = "你" if i == local_idx else "玩家%d" % (i + 1)
		add_child(p)
		p.global_position = data["player_spawn"] + Vector3(-2.2 * i, 0, 0.9 * (i % 2))
		var cart := Cart.create(p.avatar_color, "你的车" if i == local_idx else "玩家%d的车" % (i + 1))
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

var tut_step := 0
var _tut_origin := Vector3.ZERO
var _tut_dist := 0.0
var _tut_last_cart := Vector3.ZERO
var _tut_sprint := 0.0
var _tut_marks := {}

func _setup_tutorial() -> void:
	var c := Cart.create(Color(0.6, 0.6, 0.6), "无主购物车(练手)")
	add_child(c)
	c.global_position = Vector3(11, 0.2, 17.0)
	var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
	for i in 2:
		var it := Item.create(normals.pick_random())
		add_child(it)
		it.set_free_at(Vector3(11, 1.2 + i * 0.5, 17.0))
		all_items.append(it)
	tut_step = 0
	_tut_origin = player.global_position

func _tick_tutorial(delta: float) -> void:
	match tut_step:
		0:
			hud.set_tutorial_text("① 移动:WASD 走两步,动动鼠标转转视角")
			if player.global_position.distance_to(_tut_origin) > 5.0:
				tut_step = 1
		1:
			hud.set_tutorial_text("② 靠近你的购物车,按 F 抓住车把")
			if player.attached and is_instance_valid(player.cart):
				tut_step = 2
				_tut_last_cart = player.cart.global_position
				_tut_dist = 0.0
		2:
			hud.set_tutorial_text("③ 驾驶:W 前进 · A/D 转向 · S 刹车/倒车(推着逛10米)")
			if player.attached:
				_tut_dist += player.cart.global_position.distance_to(_tut_last_cart)
				_tut_last_cart = player.cart.global_position
				if _tut_dist > 10.0:
					tut_step = 3
		3:
			hud.set_tutorial_text("④ 按住 Shift 冲刺1秒——撞翻对手全靠它")
			if player.attached and is_instance_valid(player.cart) and player.cart.sprinting:
				_tut_sprint += delta
				if _tut_sprint > 1.0:
					tut_step = 4
		4:
			hud.set_tutorial_text("⑤ 按 F 停车,走到货架前,按住 E 搜出一件商品(0.8秒)")
			if not player.held.is_empty():
				tut_step = 5
		5:
			hud.set_tutorial_text("⑥ 走回自己车旁,按 E 把商品放入购物车(R 可随时放下)")
			if is_instance_valid(player.cart) and not player.cart.items_in_basket().is_empty():
				tut_step = 6
		6:
			hud.set_tutorial_text("⑦ 入口旁停着辆无主购物车:按住 E 偷一件(1.2秒)")
			if _tut_marks.get("stole", false):
				tut_step = 7
		7:
			if player.locate_cd > 0.0:
				_tut_marks["q"] = true
			if player.bottle_cd > 0.0:
				_tut_marks["rmb"] = true
			if player.braced:
				_tut_marks["space"] = true
			var q_mark := "✓" if _tut_marks.get("q", false) else "…"
			var r_mark := "✓" if _tut_marks.get("rmb", false) else "…"
			var s_mark := "✓" if _tut_marks.get("space", false) else "…"
			hud.set_tutorial_text("⑧ 试用技能:Q 找货雷达%s · 右键 掷水瓶%s · 空格 稳住%s" % [q_mark, r_mark, s_mark])
			if _tut_marks.get("q", false) and _tut_marks.get("rmb", false) and _tut_marks.get("space", false):
				tut_step = 8
		8:
			hud.set_tutorial_text("⑨ 最后:推车开进收银通道,停稳自动扫码——扫完即毕业!")

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
	cam_pivot = Node3D.new()
	cam_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam_pivot)
	cam_pivot.position = Vector3(15, 1.5, 19.5)
	cam_spring = SpringArm3D.new()
	cam_spring.spring_length = CAM_DIST
	cam_spring.collision_mask = Catalog.L_WORLD
	cam_spring.margin = 0.3
	cam_pivot.add_child(cam_spring)
	camera = Camera3D.new()
	cam_spring.add_child(camera)
	camera.make_current()

## 碰撞相机震动:只震"这名玩家"所在的机器
func add_camera_shake(v: float) -> void:
	cam_shake = minf(cam_shake + v, 1.2)

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

	if tutorial:
		_tick_tutorial(delta)
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

	# 兜底:掉出世界的散货拉回入口
	_void_sweep_timer -= delta
	if _void_sweep_timer <= 0.0:
		_void_sweep_timer = 2.0
		for it in all_items:
			if is_instance_valid(it) and it.state == Item.ItemState.FREE and it.global_position.y < -5.0:
				it.set_free_at(Vector3(15, 0.8, 19.0))

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

func _apply_highlights_local() -> void:
	var missing_hl := missing_list_ids(local_idx)
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c):
			continue
		if c == player.cart:
			c.set_highlight(false)
			continue
		var hot := false
		for it2 in c.items_in_basket():
			if missing_hl.has(it2.item_id):
				hot = true
				break
		c.set_highlight(hot)

func _hot_carts_for(idx: int) -> Array:
	var missing := missing_list_ids(idx)
	var out: Array = []
	for i in net.carts_net.size():
		var c = net.carts_net[i]
		if not is_instance_valid(c) or c == players[idx].cart:
			continue
		for it in c.items_in_basket():
			if missing.has(it.item_id):
				out.append(i)
				break
	return out

# ---------- 客户端渲染 ----------

var _net_state := {}
var _client_rows: Array = []
var _client_score := 0

func apply_net_state(d: Dictionary) -> void:
	# 拆分包按键合并(A包:玩家/车/闸机/计时,B包:大妈/商品)
	for k in d:
		_net_state[k] = d[k]

func client_hud(rows: Array, score: int, hot_carts: Array) -> void:
	_client_rows = rows
	_client_score = score
	for i in net.carts_net.size():
		var c = net.carts_net[i]
		if is_instance_valid(c):
			c.set_highlight(hot_carts.has(i))

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
	if not _net_state.is_empty():
		var k := 1.0 - exp(-14.0 * delta)
		var ps: Array = _net_state.get("p", [])
		for i in mini(ps.size(), players.size()):
			var a: Array = ps[i]
			var p := players[i]
			p.global_position = p.global_position.lerp(a[0], k)
			p.body_root.rotation.y = lerp_angle(p.body_root.rotation.y, a[1], k)
			p.hand_pose = a[2]
			p.imbalance = a[3]
			p.stamina = a[4]
			p.downed = a[5]
			p.braced = a[6]
			p.channel_progress = a[7]
			p.body_root.rotation.x = lerpf(p.body_root.rotation.x, a[8], k)
			p.locate_cd = a[9]
			p.bottle_cd = a[10]
			p.brace_cd = a[11]
			p.puppet_update(delta)
		var cs: Array = _net_state.get("c", [])
		for i in mini(cs.size(), net.carts_net.size()):
			if cs[i] == null:
				continue
			var c = net.carts_net[i]
			if not is_instance_valid(c):
				continue
			c.global_position = c.global_position.lerp(cs[i][0], k)
			var r: Vector3 = cs[i][1]
			c.global_rotation = Vector3(
					lerp_angle(c.global_rotation.x, r.x, k),
					lerp_angle(c.global_rotation.y, r.y, k),
					lerp_angle(c.global_rotation.z, r.z, k))
		var gs: Array = _net_state.get("g", [])
		for i in mini(gs.size(), net.grannies_net.size()):
			if gs[i] == null:
				continue
			var g = net.grannies_net[i]
			if not is_instance_valid(g):
				continue
			g.global_position = g.global_position.lerp(gs[i][0], k)
			g.body_root.rotation.y = lerp_angle(g.body_root.rotation.y, gs[i][1], k)
			g.hand_pose = gs[i][2]
			g.body_root.rotation.x = lerpf(g.body_root.rotation.x, gs[i][3], k)
			g.puppet_update(delta)
		for e in _net_state.get("i", []):
			var idx: int = e[0]
			if idx < 0 or idx >= all_items.size():
				continue
			var it = all_items[idx]
			if not is_instance_valid(it):
				continue
			it.state = e[1]
			it.global_position = it.global_position.lerp(e[2], k)
			it.global_rotation.y = lerp_angle(it.global_rotation.y, e[3], k)
			if it.state == Item.ItemState.SCANNED and it.label != null:
				it.label.modulate = Color(0.1, 0.55, 0.2)
		var cos: Array = _net_state.get("co", [])
		for i in mini(cos.size(), checkouts.size()):
			checkouts[i].gate.position.y = cos[i][0]
			checkouts[i].south_gate.position.y = cos[i][1]
		time_left = _net_state.get("t", time_left)
		in_grace = _net_state.get("ig", false)
		grace_left = _net_state.get("gl", grace_left)
	_tick_locate_visual(delta)
	_update_hud_client()

func _update_hud_client() -> void:
	_update_timer_hud()
	hud.set_bars(player.stamina, player.imbalance)
	hud.set_prompt(player.prompt_text, player.channel_progress)
	hud.set_score(_client_score)
	_update_skill_hud()
	hud.set_list(_client_rows)

# ---------- 技能 ----------

## 右键:向镜头方向掷出水瓶,落地生成临时湿滑地面(CD8秒)
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
		fwd = Basis(Vector3.UP, cam_yaw) * Vector3.FORWARD
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
		var p := Vector3(randf_range(-25.0, 25.0), 0, randf_range(-17.0, 8.0))
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
			"找货雷达:清单货已备齐!" if idxs.is_empty() else "找货雷达!锁定 %d 件缺货" % idxs.size(),
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
	if player == null:
		return
	var target := player.global_position + Vector3.UP * 1.5
	if player.attached and is_instance_valid(player.cart):
		target = player.cart.global_position + Vector3.UP * 1.4
	var k := 1.0 - exp(-10.0 * delta)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, k)
	cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	if cam_shake > 0.002:
		var s := cam_shake * cam_shake
		cam_pivot.rotation += Vector3(
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.04 * s)
		cam_shake = maxf(0.0, cam_shake - delta * 2.5)

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
	var s1 := "Q 雷达:就绪" if player.locate_cd <= 0.0 else "Q 雷达:%d秒" % int(ceil(player.locate_cd))
	var s2 := "右键 水瓶:就绪" if player.bottle_cd <= 0.0 else "右键 水瓶:%d秒" % int(ceil(player.bottle_cd))
	var s3 := "空格 稳住:就绪" if player.brace_cd <= 0.0 else ("空格 稳住:格挡中!" if player.braced else "空格 稳住:%d秒" % int(ceil(player.brace_cd)))
	hud.set_skill(s1 + " · " + s2 + " · " + s3, player.locate_cd <= 0.0 and player.bottle_cd <= 0.0 and player.brace_cd <= 0.0)

func _update_hud() -> void:
	_update_timer_hud()
	hud.set_bars(player.stamina, player.imbalance)
	hud.set_prompt(player.prompt_text, player.channel_progress)
	hud.set_score(pdata[local_idx]["score"])
	_update_skill_hud()
	hud.set_list(_build_rows(local_idx))

## 清单行(按超市分区分组;入车/已结算标绿划线)
func _build_rows(idx: int) -> Array:
	var p := players[idx]
	var cart_ids := {}
	if is_instance_valid(p.cart):
		for it3 in p.cart.items_in_basket():
			cart_ids[it3.item_id] = true
	var rows: Array = []
	for zone in [Catalog.ZONE_PREMIUM, Catalog.ZONE_FRESH, Catalog.ZONE_APPLIANCE, Catalog.ZONE_DAILY, Catalog.ZONE_SNACK]:
		var group: Array = []
		for entry in pdata[idx]["list"]:
			if Catalog.ITEMS[entry["id"]]["zone"] == zone:
				group.append(entry)
		if group.is_empty():
			continue
		rows.append({"header": true, "text": "【%s】" % Catalog.ZONE_NAMES[zone], "color": Catalog.ZONE_COLORS[zone]})
		for entry in group:
			var status := ""
			var done: bool = entry["scanned"]
			if done:
				status = "已结算✓" + ("(特价抵扣)" if entry["via_sale"] else "")
			else:
				status = _item_whereabouts(entry["id"], p)
			var cat_tag: String = "必需" if entry["cat"] == Catalog.CAT_NEED else ("大件" if entry["cat"] == Catalog.CAT_LARGE else "常规")
			var green: bool = done or cart_ids.has(entry["id"])
			rows.append({"text": "  · %s [%s] — %s" % [entry["name"], cat_tag, status], "green": green})
	return rows

func _item_whereabouts(id: String, p: Player) -> String:
	var shelf_left := 0
	for it in all_items:
		if not is_instance_valid(it) or it.item_id != id:
			continue
		if p.held.has(it):
			return "手中"
		if it.state == Item.ItemState.FREE and is_instance_valid(p.cart) \
				and p.cart.basket_area.overlaps_body(it):
			return "车内"
		if it.state == Item.ItemState.SHELVED:
			shelf_left += 1
	if shelf_left > 0:
		return "货架剩%d件" % shelf_left
	return "场上库存告急!"

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
	hud.broadcast("限时特价!超值神秘箱已投放至卖场,数量有限,先到先得哦～(可抵扣清单上任意常规品)")
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

func _result_lines(idx: int, settled: bool) -> Array:
	var pd: Dictionary = pdata[idx]
	var done := 0
	for entry in pd["list"]:
		if entry["scanned"]:
			done += 1
	var lines: Array = []
	lines.append("🛒 结算完成!" if settled else "🛒 打烊结算")
	lines.append("")
	lines.append("最终得分:%d" % pd["score"])
	if net_mp and pdata.size() > 1:
		# 全场排名(以此刻分数排序)
		var ranking: Array = []
		for i in pdata.size():
			ranking.append([pdata[i]["score"], i])
		ranking.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		lines.append("— 本局排名 —")
		for r in ranking.size():
			var who: String = "你" if ranking[r][1] == idx else "玩家%d" % (ranking[r][1] + 1)
			lines.append("  第%d名 %s:%d分" % [r + 1, who, ranking[r][0]])
	lines.append("清单完成:%d / %d" % [done, pd["list"].size()])
	for entry in pd["list"]:
		var mark: String = "✓" if entry["scanned"] else "✗"
		lines.append("  %s %s%s" % [mark, entry["name"], "(特价抵扣)" if entry["via_sale"] else ""])
	var cat_names := {Catalog.CAT_NEED: "必需品", Catalog.CAT_NORMAL: "常规品", Catalog.CAT_LARGE: "大件", Catalog.CAT_SALE: "特价"}
	for cat in pd["counts"]:
		lines.append("%s ×%d" % [cat_names.get(cat, cat), pd["counts"][cat]])
	lines.append("")
	lines.append("商品原价合计:¥%d · 黑五折后实付:¥%d" % [pd["orig"], pd["orig"] - pd["saved"]])
	lines.append("疯抢星期五,您总计省下了 ¥%d !" % pd["saved"])
	lines.append("")
	if settled and done == pd["list"].size():
		lines.append("清单全清,赶在打烊前扬长而去——黑五赢家!")
	elif settled:
		lines.append("落袋为安。没凑齐的,明年黑五再战。")
	elif done == pd["list"].size():
		lines.append("清单全清,满载而归!文明,打烊之前有效。")
	elif pd["score"] > 0:
		lines.append("保住了底,下次早点去排队。")
	else:
		lines.append("……您是来观光的吗?未过闸机的商品已全部作废。")
	lines.append("")
	lines.append("按 回车 " + ("断开并返回开始界面" if net_mp else "重开一局"))
	return lines

func on_granny_stole(cart: Cart) -> void:
	if cart.cart_owner is Player and _steal_bc_cd <= 0.0:
		_steal_bc_cd = 15.0
		hud.broadcast("温馨提示:请看管好您的随身物品与购物车,商品遗失本店概不负责哦~")

func on_player_stole(thief: Player, _cart: Cart, item: Item) -> void:
	Main.float_text(self, thief.global_position + Vector3.UP * 2.2, "顺走了 " + item.display_name, Color(1, 0.75, 0.3))
	_tut_marks["stole"] = true
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
		cam_yaw -= event.relative.x * CAM_SENS
		cam_pitch = clampf(cam_pitch - event.relative.y * CAM_SENS, -1.15, 0.35)
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
			net.send_action("throw", Basis(Vector3.UP, cam_yaw) * Vector3.FORWARD)
		elif event.is_action_pressed("elbow"):
			net.send_action("elbow", Basis(Vector3.UP, cam_yaw) * Vector3.FORWARD)
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

func _setup_input_map() -> void:
	# InputMap是全局的,重开一局时避免重复注册
	if InputMap.has_action("move_forward"):
		return
	_add_key("move_forward", KEY_W)
	_add_key("move_forward", KEY_UP)
	_add_key("move_back", KEY_S)
	_add_key("move_back", KEY_DOWN)
	_add_key("move_left", KEY_A)
	_add_key("move_left", KEY_LEFT)
	_add_key("move_right", KEY_D)
	_add_key("move_right", KEY_RIGHT)
	_add_key("sprint", KEY_SHIFT)
	_add_key("interact", KEY_E)
	_add_key("load_cart", KEY_R)
	_add_key("drive", KEY_F)
	_add_key("locate", KEY_Q)
	_add_key("brace", KEY_SPACE)
	_add_key("debug_time", KEY_T)
	_add_key("dev_mode", KEY_F1)
	_add_key("debug_sale", KEY_F3)
	_add_key("debug_down", KEY_F4)
	_add_key("restart", KEY_ENTER)
	# 肘击只绑鼠标左键
	if not InputMap.has_action("elbow"):
		InputMap.add_action("elbow")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("elbow", mb)
	# 掷水瓶:鼠标右键
	if not InputMap.has_action("throw"):
		InputMap.add_action("throw")
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("throw", mb2)

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

# ---------- 公共服务 ----------

## 大妈寻路:AStarGrid2D,格子1米
func find_path(from: Vector3, to: Vector3) -> Array:
	var a := _nearest_open(_cell(from))
	var b := _nearest_open(_cell(to))
	var fallback: Array = [Vector3(to.x, 0, to.z)]
	if a.x == 9999 or b.x == 9999:
		return fallback
	var ids := grid.get_id_path(a, b)
	if ids.is_empty():
		return fallback
	var pts: Array = []
	for id in ids:
		pts.append(Vector3(id.x + 0.5, 0, id.y + 0.5))
	pts.append(Vector3(to.x, 0, to.z))
	return pts

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.z)))

func _nearest_open(c: Vector2i) -> Vector2i:
	for r in 5:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var id := c + Vector2i(dx, dy)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
					return id
	return Vector2i(9999, 9999)

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
