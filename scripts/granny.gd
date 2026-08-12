class_name Granny extends Actor
## 大妈NPC:人手一辆购物车。开车扫货、按清单抢购、偷车、
## 开车冲撞或徒步肘击对手(玩家与其他大妈)、抢夺手中商品，打烊前结算。

enum GState {
	IDLE,        # 决策
	DRIVE,       # 推车沿寻路网格开往目的地
	WALK,        # 徒步(车已停好)
	TAKE,        # 货架搜货1秒
	STEAL_CH,    # 翻别人车斗1.2秒
	LOAD,        # 把手里的货装进自己车0.6秒
	RAM,         # 开车冲撞目标车
	CHASE,       # 追逐偷了她东西的对手,夺回商品
	BRAWL,       # 徒步追打有货的对手,肘击或直接抢走手中商品
	Q_DRIVE,     # 直线开进收银通道(闸机前排队)
	SCANNING,    # 通道内等扫码
	EXIT_DRIVE,  # 扫完开出通道
	DONE,        # 收工,停在出口区
}

const WALK_SPEED := 2.3
const RUSH_SPEED := 3.7    # 追逐/冲刺时的徒步速度
const DRIVE_FORCE := 520.0
const DRIVE_STEER := 60.0
const STEAL_SCAN_INTERVAL := 30.0
const STEAL_RANGE := 9.0
const RAM_RANGE := 18.0     # 别人车里有想要的货时,这个距离内会开车冲撞(对全场生效)
const RAM_CD_HIT := 6.0     # 冲撞得手后的冷却(越短越凶)
const RAM_CD_FAIL := 3.5    # 冲撞失败/放弃的冷却
const AGGRO_RANGE := 10.0    # 徒步争抢搜索半径
const AGGRO_TIME := 6.0      # 单次追打最长时间，避免全场只顾打架
const ELBOW_CD := 0.9        # NPC肘击间隔
const EXIT_X := MapLayout.EXIT_X   # 收银后离场出口的x位置

# 大妈语录(带方言味,对玩家操作做反应)
const SAY_HURT := ["哎哟我的老腰!!", "造孽哦——!", "哪个挨千刀的撞我!", "哎呀妈呀!!", "撞人啦!没王法啦!"]
const SAY_KNOCKDOWN := ["扶我起来...俺还能抢!", "哎哟喂——!!", "老婆子跟你拼了!", "我这把老骨头哟!"]
const SAY_STOLEN := ["贼娃子!放下俺的货!", "抓贼啊!!光天化日!", "哎呀我的宝贝!!", "遭不住咯,遭贼咯!"]
const SAY_ELBOWED := ["打人啦!打人啦!", "反了天了!!", "小年轻下手冇轻重!", "妈呀,胳膊肘子恁硬!"]
const SAY_HUNT := ["你车里那个是俺的!", "站住!莫跑!", "后生仔,让让让!", "小伙子,识相点撒!"]
const SAY_SLAM := ["都是俺的!都是俺的!", "大妈我先来的!", "闪开闪开!!", "跟俺抢?嫩着呢!"]
const SAY_SHOP := ["便宜!快囤!", "又抢到一个,美滋滋~", "这个俺屋里正缺!", "过年就靠它咯!"]

var main: Main
var body_color := Color(0, 0, 0, 0)   # 由main指定,与自己的车同色
var shopping_list: Array = []          # 购物清单(商品id)。大妈是真顾客,玩家才是投机者
var acquired := {}                     # 已到手的清单项
var want_label: Label3D
var bubble: Label3D                    # 对话气泡
var _say_cd := 0.0
var _say_time := 0.0

var state: GState = GState.IDLE
var path: Array = []
var path_idx := 0
var final_dest := Vector3.ZERO
var target_item: Item = null
var target_cart: Cart = null
var target_actor: Actor = null
var target_checkout: Checkout = null
var action_timer := 0.0
var steal_timer := 0.0
var checkout_deadline := 0.0   # 剩余时间低于此值就去结算
var _charge_cd := 0.0
var _aggression_timer := 0.0
var _elbow_cd := 0.0
var _after_drive := ""         # DRIVE到达后: "shop"/"steal"/"queue"/""
var _after_walk := ""          # WALK到达后: "take"/"steal"/"return"
var _lane_pts: Array = []
var _lane_idx := 0
var _leave_world := false      # 结算完成:驶出出口后从场上移除
var _stuck_time := 0.0
var _repathed := false
var _last_pos := Vector3.ZERO
var _drive_reverse := 0.0      # 开车卡住时倒车恢复
var _rev_turn := 0.0           # 倒车时的随机转向
var _state_time := 0.0         # 看门狗:单一状态停留过久强制重置
var _prev_state: GState = GState.IDLE

func _ready() -> void:
	if body_color.a == 0.0:
		body_color = Color.from_hsv(randf(), 0.45, 0.85)
	build_body(body_color, "大妈", 1.55)
	# 大妈不与其他角色互相物理阻挡(防止人群互卡死锁;玩家撞她们仍然有效)
	collision_mask = Catalog.L_WORLD | Catalog.L_CART
	hold_capacity = 2
	steal_timer = randf_range(12.0, STEAL_SCAN_INTERVAL)
	_aggression_timer = randf_range(2.5, 6.0)
	# 只在临近打烊才去结算(剩50-110秒),保证全场大部分时间都在场上和玩家博弈,
	# 且终局所有人挤向收银台——排队区互撞的名场面
	checkout_deadline = randf_range(50.0, 110.0)
	# 头顶小字:她想要什么(白盒可读性)
	want_label = Label3D.new()
	want_label.font = Catalog.ui_font()
	want_label.font_size = 38
	want_label.pixel_size = 0.0035
	want_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	want_label.no_depth_test = true
	want_label.modulate = Color(1, 0.85, 0.5)
	want_label.outline_size = 8
	want_label.outline_modulate = Color(0, 0, 0, 0.8)
	want_label.position = Vector3(0, 2.35, 0)
	add_child(want_label)
	_update_want_label()
	# 对话气泡
	bubble = Label3D.new()
	bubble.font = Catalog.ui_font_bold()
	bubble.font_size = 46
	bubble.pixel_size = 0.0038
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.modulate = Color(1, 1, 1)
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0.15, 0.1, 0.25, 0.95)
	bubble.position = Vector3(0, 2.85, 0)
	bubble.visible = false
	add_child(bubble)

## 大妈开腔(1.2秒内不重复开口,气泡挂2.5秒)
func say_from_pool(pool: Array) -> void:
	if _say_cd > 0.0:
		return
	_say_cd = 1.2
	_say_time = 2.5
	bubble.text = "「%s」" % pool.pick_random()
	bubble.visible = true

func on_cart_hit(_by: Cart) -> void:
	say_from_pool(SAY_HURT)

func on_elbowed(_by: Actor) -> void:
	say_from_pool(SAY_ELBOWED)

func is_running() -> bool:
	return state in [GState.RAM, GState.CHASE, GState.BRAWL]

## 对手从她这里偷走商品:该商品重新变回"想要"(acquired擦除),并当场追逐夺回。
## 追不上/商品进了对手车斗,常规决策的冲撞/偷窃会自然接管——记仇但不死盯。
var chase_target: Actor = null

func on_robbed(item: Item, thief: Actor) -> void:
	acquired.erase(item.item_id)
	_update_want_label()
	say_from_pool(SAY_STOLEN)
	if downed or _in_checkout_chain():
		return
	target_item = item
	chase_target = thief
	action_timer = 9.0
	state = GState.CHASE

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	if downed or main == null or main.game_over:
		apply_motion(delta, Vector3.ZERO, 0.0)
		return
	steal_timer -= delta
	_charge_cd = maxf(0.0, _charge_cd - delta)
	_aggression_timer = maxf(0.0, _aggression_timer - delta)
	_elbow_cd = maxf(0.0, _elbow_cd - delta)
	_say_cd = maxf(0.0, _say_cd - delta)
	if _say_time > 0.0:
		_say_time -= delta
		if _say_time <= 0.0:
			bubble.visible = false

	# 看门狗:同一状态卡超过20秒(排队/扫码/收工除外)→强制重置决策
	if state == _prev_state:
		_state_time += delta
	else:
		_prev_state = state
		_state_time = 0.0
	if _state_time > 20.0 and not (state in [GState.IDLE, GState.DONE, GState.SCANNING, GState.Q_DRIVE]):
		_state_time = 0.0
		target_item = null
		target_cart = null
		target_actor = null
		_charge_cd = maxf(_charge_cd, 2.0)
		state = GState.IDLE

	# 车被撞翻:人车分离,重新决策
	if attached and is_instance_valid(cart) and cart.global_transform.basis.y.dot(Vector3.UP) < 0.35:
		detach_cart()
		state = GState.IDLE

	# 手部姿态
	if attached:
		hand_pose = "push"
	elif state in [GState.TAKE, GState.STEAL_CH, GState.LOAD]:
		hand_pose = "channel"
	elif not held.is_empty():
		hand_pose = "carry"
	else:
		hand_pose = "idle"

	# 打烊临近:带着货去结算
	if state != GState.DONE and not _in_checkout_chain() \
			and main.time_left < checkout_deadline and attached \
			and not cart.items_in_basket().is_empty():
		_start_checkout()

	match state:
		GState.IDLE:
			apply_motion(delta, Vector3.ZERO, 0.0)
			_decide()
		GState.DRIVE:
			_drive_state(delta)
		GState.WALK:
			_walk_state(delta)
		GState.TAKE:
			apply_motion(delta, Vector3.ZERO, 0.0)
			action_timer -= delta
			if action_timer <= 0.0:
				if is_instance_valid(target_item) and target_item.state == Item.ItemState.SHELVED and can_hold(target_item):
					target_item.set_held()
					take_item(target_item)
					_register_acquired(target_item)
					if randf() < 0.3:
						say_from_pool(SAY_SHOP)
				_return_to_cart()
		GState.STEAL_CH:
			apply_motion(delta, Vector3.ZERO, 0.0)
			if not is_instance_valid(target_cart) or target_cart.attached_agent != null:
				_return_to_cart()
				return
			action_timer -= delta
			if action_timer <= 0.0:
				_do_steal()
				_return_to_cart()
		GState.LOAD:
			apply_motion(delta, Vector3.ZERO, 0.0)
			action_timer -= delta
			if action_timer <= 0.0:
				while not held.is_empty():
					var it: Item = held.pop_back()
					it.set_free_at(cart.to_global(Vector3(randf_range(-0.25, 0.25), 1.5, randf_range(-0.4, 0.4))), Vector3(0, -1, 0))
				attach_cart()
				state = GState.IDLE
		GState.RAM:
			_ram_state(delta)
		GState.CHASE:
			_chase_state(delta)
		GState.BRAWL:
			_brawl_state(delta)
		GState.Q_DRIVE:
			_queue_state(delta)
		GState.SCANNING:
			_scanning_state(delta)
		GState.EXIT_DRIVE:
			_exit_state(delta)
		GState.DONE:
			apply_motion(delta, Vector3.ZERO, 0.0)

# ---------- 决策 ----------

func _decide() -> void:
	# 手里有货先装车;没抓着车先回车
	if not held.is_empty() or not attached:
		_return_to_cart()
		return
	# 清单买齐?大妈的购物欲没有尽头——立刻补新目标继续抢。
	# 提前结算离场会让玩家失去博弈对象,结算只由打烊时间驱动(见_physics_process)。
	if _list_complete():
		_refill_appetite()
	# 冲撞:别人(玩家或大妈)车里有我要的货
	if _charge_cd <= 0.0:
		var rc := _find_ram_target()
		if rc != null:
			target_cart = rc
			action_timer = 7.0
			state = GState.RAM
			if rc.attached_agent is Player:
				say_from_pool(SAY_HUNT)
			return
	# 徒步争抢:优先盯住手里/车里有我想要商品的人；即使不是目标货，
	# 玩家和满载对手也会因“不能让别人占便宜”进入候选。
	if _aggression_timer <= 0.0:
		_aggression_timer = randf_range(4.0, 8.0)
		var rival := _find_brawl_target()
		if rival != null:
			_start_brawl(rival)
			return
	# 偷:没人看的车里有我要的货
	var sc := _find_steal_cart(true, RAM_RANGE)
	if sc != null:
		_go_steal(sc)
		return
	# 30秒一次的顺手牵羊(不挑货)
	if steal_timer <= 0.0:
		steal_timer = STEAL_SCAN_INTERVAL
		var sc2 := _find_steal_cart(false, STEAL_RANGE)
		if sc2 != null:
			_go_steal(sc2)
			return
	# 找清单上的货:货架与地上散落一起比,优先取距离近的
	var wi := _find_wanted_shelved()
	var wf := _find_wanted_free()
	if wi != null and wf != null:
		var d_shelf := global_position.distance_to(wi.global_position)
		var d_free := global_position.distance_to(wf.global_position)
		if d_free < d_shelf:
			_go_shop(wf)
		else:
			_go_shop(wi)
		return
	elif wi != null:
		_go_shop(wi)
		return
	elif wf != null:
		_go_shop(wf)
		return
	# 清单没得抢了:随便扫点货(库存流失压力),车里太满就不拿了
	# 避开别的大妈已认领的目标,防止全员挤同一个货位
	if cart.items_in_basket().size() < 7:
		for attempt in 4:
			var ri := main.random_shelved_item()
			if ri == null:
				break
			if not _claimed_by_other(ri):
				_go_shop(ri)
				return
	# 溜达
	_after_drive = ""
	_drive_path_to(Vector3(
			randf_range(MapLayout.wander_x().x, MapLayout.wander_x().y), 0,
			randf_range(MapLayout.wander_z().x, MapLayout.wander_z().y)))
	state = GState.DRIVE

func _go_shop(it: Item) -> void:
	target_item = it
	_after_drive = "shop"
	_drive_path_to(it.global_position)
	state = GState.DRIVE

func _go_steal(c: Cart) -> void:
	target_cart = c
	_after_drive = "steal"
	_drive_path_to(c.global_position)
	state = GState.DRIVE

func _start_brawl(rival: Actor) -> void:
	target_actor = rival
	action_timer = AGGRO_TIME
	_elbow_cd = randf_range(0.1, 0.35)
	if attached:
		detach_cart()
	state = GState.BRAWL
	say_from_pool(SAY_HUNT if rival is Player else SAY_SLAM)

func _start_checkout() -> void:
	var best: Checkout = null
	var best_d := 9999.0
	for co in main.checkouts:
		if not co.lane_open:
			continue
		var d: float = absf(cart.global_position.x - co.lane_x) + absf(cart.global_position.z - 12.0)
		if d < best_d:
			best = co
			best_d = d
	if best == null:
		# 没有开放的通道:直接离场
		_leave_world = true
		_after_drive = "leave"
		_drive_path_to(Vector3(EXIT_X, 0, MapLayout.exit_inner_z()))
		state = GState.DRIVE
		return
	target_checkout = best
	_after_drive = "queue"
	# 网格寻路开到闸机口正前(避开货架行),之后再直线进通道
	_drive_path_to(Vector3(best.lane_x, 0, MapLayout.queue_wait_z()))
	state = GState.DRIVE

# ---------- 状态实现 ----------

func _drive_state(delta: float) -> void:
	if not attached:
		_return_to_cart()
		return
	# 购物/偷窃:开到目标附近就提前停车
	if _after_drive == "shop" and is_instance_valid(target_item) \
			and cart.global_position.distance_to(target_item.global_position) < 3.2:
		_park_and_walk(target_item.global_position, "take")
		return
	if _after_drive == "steal" and is_instance_valid(target_cart) \
			and cart.global_position.distance_to(target_cart.global_position) < 3.4:
		_park_and_walk(target_cart.global_position, "steal")
		return
	if _follow_path_drive(delta):
		match _after_drive:
			"queue":
				_lane_pts = [Vector3(target_checkout.lane_x, 0, MapLayout.scan_stop_z())]
				_lane_idx = 0
				action_timer = 30.0
				state = GState.Q_DRIVE
			"shop":
				if is_instance_valid(target_item):
					_park_and_walk(target_item.global_position, "take")
				else:
					state = GState.IDLE
			"steal":
				if is_instance_valid(target_cart):
					_park_and_walk(target_cart.global_position, "steal")
				else:
					state = GState.IDLE
			"leave":
				_lane_pts = [Vector3(EXIT_X, 0, MapLayout.exit_outer_z())]
				_lane_idx = 0
				state = GState.EXIT_DRIVE
			_:
				state = GState.IDLE

func _park_and_walk(dest: Vector3, after: String) -> void:
	detach_cart()
	_walk_to(dest, after)

func _walk_to(dest: Vector3, after: String) -> void:
	_after_walk = after
	final_dest = dest
	path = main.find_path(global_position, dest)
	path_idx = 0
	_stuck_time = 0.0
	_repathed = false
	_last_pos = global_position
	state = GState.WALK

func _walk_state(delta: float) -> void:
	# 提前到达判定:走到够得着就动手,不必走完路径最后一格(终点常在货架体内,走不到)
	if _try_arrive_walk():
		return
	if _follow_path(delta, WALK_SPEED):
		match _after_walk:
			"take":
				_arrive_take()
			"steal":
				_arrive_steal()
			"return":
				_return_to_cart()
			_:
				state = GState.IDLE

func _try_arrive_walk() -> bool:
	match _after_walk:
		"take":
			if is_instance_valid(target_item) and global_position.distance_to(target_item.global_position) < 1.9:
				_arrive_take()
				return true
		"steal":
			if is_instance_valid(target_cart) and global_position.distance_to(target_cart.global_position) < 2.3:
				_arrive_steal()
				return true
		"return":
			if is_instance_valid(cart) and global_position.distance_to(cart.global_position) < 2.7:
				_return_to_cart()
				return true
	return false

func _arrive_take() -> void:
	if is_instance_valid(target_item) and global_position.distance_to(target_item.global_position) < 2.2:
		if target_item.state == Item.ItemState.SHELVED:
			state = GState.TAKE
			action_timer = 1.0
			return
		elif target_item.state == Item.ItemState.FREE and can_hold(target_item) and not _in_any_basket(target_item):
			target_item.set_held()
			take_item(target_item)
			_register_acquired(target_item)
	_return_to_cart()

func _arrive_steal() -> void:
	if is_instance_valid(target_cart) and target_cart.attached_agent == null \
			and not target_cart.items_in_basket().is_empty() \
			and global_position.distance_to(target_cart.global_position) < 2.5:
		state = GState.STEAL_CH
		action_timer = 1.2
	else:
		_return_to_cart()

func _return_to_cart() -> void:
	if not is_instance_valid(cart):
		state = GState.IDLE
		return
	if attached:
		# 人在车上(追逐夺回后可能手里有货):直接放进车斗
		while not held.is_empty():
			var it: Item = held.pop_back()
			it.set_free_at(cart.to_global(Vector3(randf_range(-0.25, 0.25), 1.5, randf_range(-0.4, 0.4))), Vector3(0, -1, 0))
		state = GState.IDLE
		return
	if global_position.distance_to(cart.global_position) < 2.8:
		if held.is_empty():
			attach_cart()
			state = GState.IDLE
		else:
			state = GState.LOAD
			action_timer = 0.6
	else:
		_walk_to(cart.global_position, "return")

func _do_steal() -> void:
	var items := target_cart.items_in_basket()
	var pick: Item = null
	for it in items:
		if _wanted(it.item_id):
			pick = it
			break
	if pick == null and not items.is_empty():
		pick = items.pick_random()
	if pick != null and can_hold(pick):
		pick.set_held()
		take_item(pick)
		_register_acquired(pick)
		target_cart.show_steal_alert()
		main.on_granny_stole(target_cart)
		if target_cart.cart_owner is Granny and is_instance_valid(target_cart.cart_owner):
			target_cart.cart_owner.on_robbed(pick, self)

func _ram_state(delta: float) -> void:
	action_timer -= delta
	if not attached or action_timer <= 0.0 or not is_instance_valid(target_cart) \
			or target_cart.attached_agent == null or target_cart.attached_agent.immune \
			or not _cart_has_wanted(target_cart):
		_charge_cd = RAM_CD_FAIL
		state = GState.IDLE
		return
	var d := cart.global_position.distance_to(target_cart.global_position)
	if d > RAM_RANGE + 8.0:
		_charge_cd = RAM_CD_FAIL
		state = GState.IDLE
		return
	if d < 2.1:
		# 怼上了,失衡结算交给撞击表(cart._on_body_entered)
		if target_cart.attached_agent is Player:
			say_from_pool(SAY_SLAM)
		_charge_cd = RAM_CD_HIT
		state = GState.IDLE
		return
	_drive_toward(delta, target_cart.global_position, true)

## 追逐偷货的玩家或NPC:抓到就把商品抢回来
func _chase_state(delta: float) -> void:
	action_timer -= delta
	var p: Actor = chase_target
	if action_timer <= 0.0 or p == null or not is_instance_valid(p) or p.immune or p.downed:
		_charge_cd = 2.0
		state = GState.IDLE
		return
	# 他手里还拿着我的东西吗?(进了他车斗则交给常规冲撞/偷窃接管)
	var loot: Item = null
	for it in p.held:
		if is_instance_valid(it) and _wanted(it.item_id):
			loot = it
			break
	if loot == null:
		state = GState.IDLE
		return
	var to := p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d < 1.7:
		# 夺回!
		p.held.erase(loot)
		loot.set_held()
		take_item(loot)
		_register_acquired(loot)
		p.add_imbalance(10.0, self)
		p.push_velocity += to.normalized() * 2.5
		Main.float_text(self, global_position + Vector3.UP * 2.2, "大妈夺回了%s!!" % loot.display_name, Color(1, 0.5, 0.6), 72)
		say_from_pool(SAY_SLAM)
		_charge_cd = 3.0
		state = GState.IDLE
		return
	if attached:
		_drive_toward(delta, p.global_position, true)
	else:
		apply_motion(delta, to.normalized(), RUSH_SPEED)

## 徒步抢夺与互殴。先抢对方手中商品；抢不到时连续肘击，既能打落手持货，
## 也能把正在推车的对手车斗商品肘飞。所有结算复用 Actor.try_elbow，玩家/NPC同规则。
func _brawl_state(delta: float) -> void:
	action_timer -= delta
	var rival: Actor = target_actor
	if action_timer <= 0.0 or rival == null or not is_instance_valid(rival) \
			or rival.downed or rival.immune:
		target_actor = null
		state = GState.IDLE
		return
	var to := rival.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > AGGRO_RANGE + 4.0:
		target_actor = null
		state = GState.IDLE
		return
	if d > 1.65:
		apply_motion(delta, to.normalized(), RUSH_SPEED)
		return
	apply_motion(delta, Vector3.ZERO, 0.0)
	if _elbow_cd > 0.0:
		return
	_elbow_cd = ELBOW_CD
	if _try_snatch_from(rival):
		target_actor = null
		state = GState.IDLE
		return
	try_elbow(to)
	say_from_pool(SAY_SLAM)

## 贴身直接抢手中货：目标清单商品必抢，其他商品也有45%概率顺手夺走。
func _try_snatch_from(victim: Actor) -> bool:
	if victim.held.is_empty():
		return false
	var pick: Item = null
	for it in victim.held:
		if is_instance_valid(it) and _wanted(it.item_id) and can_hold(it):
			pick = it
			break
	if pick == null:
		if randf() > 0.45:
			return false
		for it in victim.held:
			if is_instance_valid(it) and can_hold(it):
				pick = it
				break
	if pick == null:
		return false
	victim.held.erase(pick)
	pick.set_held()
	take_item(pick)
	_register_acquired(pick)
	victim.add_imbalance(12.0, self)
	var shove := victim.global_position - global_position
	shove.y = 0.0
	if shove.length() > 0.1:
		victim.push_velocity += shove.normalized() * 2.8
	Main.float_text(victim, victim.global_position + Vector3.UP * 2.2,
			"大妈抢走了%s!!" % pick.display_name, Color(1, 0.45, 0.25), 72)
	victim.on_elbowed(self)
	if victim is Granny:
		victim.on_robbed(pick, self)
	return true

func _queue_state(delta: float) -> void:
	action_timer -= delta
	if not attached or target_checkout == null or not target_checkout.lane_open or action_timer <= 0.0:
		if attached and target_checkout != null and not target_checkout.lane_open \
				and cart.global_position.z > MapLayout.GATE_IN_Z + 0.5:
			# 已过闸机却赶上通道关闭:从南口离场,别困死在里面
			_lane_pts = [Vector3(target_checkout.lane_x, 0, MapLayout.lane_out_z())]
			_lane_idx = 0
			state = GState.EXIT_DRIVE
		else:
			state = GState.IDLE
		return
	if _lane_idx >= _lane_pts.size():
		state = GState.SCANNING
		action_timer = 45.0
		return
	var pt: Vector3 = _lane_pts[_lane_idx]
	if Vector2(cart.global_position.x - pt.x, cart.global_position.z - pt.z).length() < 0.9:
		_lane_idx += 1
		return
	_drive_toward(delta, pt, false)

func _scanning_state(delta: float) -> void:
	action_timer -= delta
	var give_up := action_timer <= 0.0 or target_checkout == null or not target_checkout.lane_open
	var finished := cart.items_in_basket().is_empty() and held.is_empty()
	if give_up or finished:
		var lx: float = target_checkout.lane_x if target_checkout != null else cart.global_position.x
		_leave_world = finished
		if finished:
			# 结算完毕:开去出口离场,不再挡道
			want_label.text = "买完收工~"
			want_label.modulate = Color(0.55, 0.95, 0.6)
			_lane_pts = [
				Vector3(lx, 0, MapLayout.lane_out_z()),
				Vector3(EXIT_X, 0, MapLayout.exit_inner_z()),
				Vector3(EXIT_X, 0, MapLayout.exit_outer_z()),
			]
		else:
			_lane_pts = [Vector3(lx, 0, MapLayout.lane_out_z())]
		_lane_idx = 0
		state = GState.EXIT_DRIVE
		return
	_drive_toward(delta, Vector3(target_checkout.lane_x, 0, MapLayout.scan_stop_z()), false)

func _exit_state(delta: float) -> void:
	# 已驶出出口豁口:从场上移除
	if _leave_world and cart.global_position.z > 23.0:
		_despawn_and_leave()
		return
	if _lane_idx >= _lane_pts.size():
		if _leave_world:
			_despawn_and_leave()
		else:
			state = GState.IDLE   # 只是被赶出通道,回场继续
		return
	var pt: Vector3 = _lane_pts[_lane_idx]
	if Vector2(cart.global_position.x - pt.x, cart.global_position.z - pt.z).length() < 1.1:
		_lane_idx += 1
		return
	_drive_toward(delta, pt, false)

## 从场上移除(离场/开发者滑块调低数量共用)
func despawn() -> void:
	drop_all_held(false)
	if attached:
		detach_cart()
	if is_instance_valid(cart):
		cart.queue_free()
	queue_free()

func _despawn_and_leave() -> void:
	main.net_granny_left_notify(self)
	main.grannies.erase(self)
	despawn()

## 限时特价:开车奔向掉落点(特价箱对所有人都算"想要",到附近后决策自然去捡)
func rush_to(pos: Vector3) -> void:
	if downed or not attached or _in_checkout_chain() or state == GState.DONE:
		return
	_after_drive = ""
	_drive_path_to(pos)
	state = GState.DRIVE

func _on_knockdown() -> void:
	_say_cd = 0.0   # 摔倒必喊
	say_from_pool(SAY_KNOCKDOWN)
	if attached and is_instance_valid(cart):
		detach_cart()
		cart.spill(clampf(0.3 + last_overflow / 100.0, 0.3, 1.0))

func _on_recover() -> void:
	state = GState.IDLE
	_after_walk = ""

func _in_checkout_chain() -> bool:
	return (state == GState.DRIVE and _after_drive == "queue") \
			or state in [GState.Q_DRIVE, GState.SCANNING, GState.EXIT_DRIVE, GState.DONE]

# ---------- 清单 ----------

func _wanted(id: String) -> bool:
	if id == "sale_box":
		return true   # 特价箱人人都想要
	return shopping_list.has(id) and not acquired.has(id)

func _list_complete() -> bool:
	for id in shopping_list:
		if not acquired.has(id):
			return false
	return true

## 购物欲无底洞:清单买齐就补1-2个新目标(上限9项,防止头顶字条无限变长)。
## 库存被抢空时补的目标只能靠偷/撞获得→大妈越到后期越有攻击性。
func _refill_appetite() -> void:
	if shopping_list.size() >= 9:
		return
	var pool := Catalog.ids_of_cat(Catalog.CAT_NORMAL) + Catalog.ids_of_cat(Catalog.CAT_NEED)
	pool.shuffle()
	var added := 0
	for id in pool:
		if not shopping_list.has(id):
			shopping_list.append(id)
			added += 1
			if added >= 2:
				break
	_update_want_label()

func _cart_has_wanted(c: Cart) -> bool:
	for it in c.items_in_basket():
		if _wanted(it.item_id):
			return true
	return false

func _register_acquired(it: Item) -> void:
	if shopping_list.has(it.item_id):
		acquired[it.item_id] = true
		_update_want_label()

func _update_want_label() -> void:
	if want_label == null:
		return
	var missing: Array = []
	for id in shopping_list:
		if not acquired.has(id):
			missing.append(Catalog.ITEMS[id]["name"])
	if missing.is_empty():
		want_label.text = "买齐了!"
		want_label.modulate = Color(0.55, 0.95, 0.6)
	else:
		# 最多显示3样,防止字条拖到天边
		var shown: Array = missing.slice(0, 3)
		var tail := "、等%d样" % (missing.size() - 3) if missing.size() > 3 else ""
		want_label.text = "想要:" + "、".join(shown) + tail
		want_label.modulate = Color(1, 0.85, 0.5)

# ---------- 目标搜索 ----------

func _find_ram_target() -> Cart:
	var best: Cart = null
	var best_d := RAM_RANGE
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c) or c == cart or c.attached_agent == null or c.attached_agent == self:
			continue
		if c.attached_agent.immune or not _cart_has_wanted(c):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best = c
			best_d = d
	return best

func _find_brawl_target() -> Actor:
	var best: Actor = null
	var best_score := -9999.0
	for node in get_tree().get_nodes_in_group("characters"):
		if node == self or not (node is Actor):
			continue
		var rival: Actor = node
		if rival.downed or rival.immune or (rival is Player and rival.finished):
			continue
		if rival is Granny and rival._in_checkout_chain():
			continue
		var d := global_position.distance_to(rival.global_position)
		if d > AGGRO_RANGE:
			continue
		var goods := rival.held.size()
		var wanted_goods := 0
		for it in rival.held:
			if is_instance_valid(it) and _wanted(it.item_id):
				wanted_goods += 1
		var rival_cart := rival.get_pushed_cart()
		if rival_cart != null:
			var cart_items := rival_cart.items_in_basket()
			goods += cart_items.size()
			for it in cart_items:
				if _wanted(it.item_id):
					wanted_goods += 1
		# 没货的人通常不值得浪费时间；但玩家偶尔会因挡路/挑衅被盯上。
		if goods == 0 and not (rival is Player and randf() < 0.28):
			continue
		var score := float(wanted_goods * 45 + goods * 5) - d * 2.2
		if rival is Player:
			score += 8.0
		if rival.imbalance >= 55.0:
			score += 6.0   # 争强好胜：优先补刀已经站不稳的对手
		if score > best_score:
			best = rival
			best_score = score
	return best

func _find_steal_cart(wanted_only: bool, rng: float) -> Cart:
	var best: Cart = null
	var best_d := rng
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c) or c == cart or c.attached_agent != null:
			continue
		if c.items_in_basket().is_empty():
			continue
		if wanted_only and not _cart_has_wanted(c):
			continue
		if _cart_claimed_by_other(c):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best = c
			best_d = d
	return best

## 目标认领:别的大妈已经在奔某件商品/某辆车,自己就换个目标(防扎堆)
func _claimed_by_other(it: Item) -> bool:
	for g in main.grannies:
		if g != self and is_instance_valid(g) and g.target_item == it:
			return true
	return false

func _cart_claimed_by_other(c: Cart) -> bool:
	for g in main.grannies:
		if g != self and is_instance_valid(g) and g.target_cart == c:
			return true
	return false

func _find_wanted_shelved() -> Item:
	var best: Item = null
	var best_d := 999.0
	for node in get_tree().get_nodes_in_group("items"):
		var it: Item = node
		if not is_instance_valid(it) or it.state != Item.ItemState.SHELVED or not _wanted(it.item_id):
			continue
		if _claimed_by_other(it):
			continue
		var d := global_position.distance_to(it.global_position)
		if d < best_d:
			best = it
			best_d = d
	return best

func _find_wanted_free() -> Item:
	var best: Item = null
	var best_d := 999.0
	for node in get_tree().get_nodes_in_group("items"):
		var it: Item = node
		if not is_instance_valid(it) or it.state != Item.ItemState.FREE or not _wanted(it.item_id):
			continue
		if _claimed_by_other(it):
			continue
		var d := global_position.distance_to(it.global_position)
		if d < best_d and not _in_any_basket(it):
			best = it
			best_d = d
	return best

func _in_any_basket(it: Item) -> bool:
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if is_instance_valid(c) and c.basket_area.overlaps_body(it):
			return true
	return false

# ---------- 驾驶 ----------

func _drive_toward(delta: float, dest: Vector3, sprint: bool) -> void:
	cart.sprinting = sprint
	cart.sprint_level = 1.0 if sprint else move_toward(cart.sprint_level, 0.0, 2.0 * delta)
	var to := dest - cart.global_position
	to.y = 0.0
	if to.length() > 0.15:
		var dir := to.normalized()
		var movement_mult := movement_factor()
		cart.apply_central_force(dir * DRIVE_FORCE * (1.6 if sprint else 1.0) * movement_mult)
		var target_yaw := atan2(-dir.x, -dir.z)
		var diff := wrapf(target_yaw - cart.rotation.y, -PI, PI)
		cart.apply_torque(Vector3(0, diff * DRIVE_STEER * cart.mass * 0.1 * movement_mult, 0))
	_stick_to_handle()

func _stick_to_handle() -> void:
	global_position = cart.handle_pos()
	body_root.global_rotation = Vector3(0, cart.global_rotation.y, 0)
	velocity = Vector3.ZERO

func _drive_path_to(dest: Vector3) -> void:
	final_dest = dest
	path = main.find_path(cart.global_position if attached else global_position, dest)
	path_idx = 0
	_stuck_time = 0.0
	_repathed = false
	_last_pos = cart.global_position if attached else global_position

## 返回true=到达终点
func _follow_path_drive(delta: float) -> bool:
	if _drive_reverse > 0.0:
		# 倒一小段车+随机拧方向脱困,然后重新寻路
		_drive_reverse -= delta
		var back := cart.global_transform.basis.z
		back.y = 0.0
		cart.apply_central_force(back.normalized() * DRIVE_FORCE * 0.7)
		cart.apply_torque(Vector3(0, _rev_turn * 25.0 * cart.mass * 0.1, 0))
		_stick_to_handle()
		if _drive_reverse <= 0.0:
			_drive_path_to(final_dest)
		return false
	if path_idx >= path.size():
		return true
	var next: Vector3 = path[path_idx]
	var to := next - cart.global_position
	to.y = 0.0
	if to.length() < 1.3:
		path_idx += 1
		return path_idx >= path.size()
	_drive_toward(delta, next, false)
	# 卡住(低于约0.35m/s):先倒车脱困,还不行就放弃
	if cart.global_position.distance_to(_last_pos) < 0.006:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = cart.global_position
	if _stuck_time > 4.5:
		_stuck_time = 0.0
		state = GState.IDLE
	elif _stuck_time > 1.6:
		_stuck_time = 0.0
		_drive_reverse = 0.9
		_rev_turn = randf_range(-1.0, 1.0)
	return false

# ---------- 徒步寻路(沿网格) ----------

## 返回true=已到达终点
func _follow_path(delta: float, speed: float) -> bool:
	if path_idx >= path.size():
		apply_motion(delta, Vector3.ZERO, 0.0)
		return true
	var next: Vector3 = path[path_idx]
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.5:
		path_idx += 1
		return path_idx >= path.size()
	apply_motion(delta, to.normalized(), speed)
	# 卡住检测(低于约0.5m/s才算):1.5秒没挪动就重新寻路,3秒放弃
	if global_position.distance_to(_last_pos) < 0.008:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = global_position
	if _stuck_time > 3.0:
		state = GState.IDLE
		_stuck_time = 0.0
		return false
	elif _stuck_time > 1.5 and not _repathed:
		_repathed = true
		path = main.find_path(global_position, final_dest)
		path_idx = 0
	return false
