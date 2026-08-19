class_name NpcProbe extends RefCounted
## NPC仇恨与HUD状态槽回归探针。
## WHITEBOX_NPCTEST=1 下确定性覆盖满值状态条、需求车攻击与无关货物不攻击。

var _m: Main
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []
var _g1: Granny
var _g2: Granny
var _player_item: Item
var _unrelated_item: Item
var _stopped_after_loss := false
var _approached_for_attack := false

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	if _m.grannies.size() < 2:
		_fail("测试前置：至少需要2名NPC")
		_report()
		return
	_g1 = _m.grannies[0]
	_g2 = _m.grannies[1]
	# 四队模式下grannies[0]可能恰好是玩家同队AI；专项需要明确使用对手，
	# 否则友伤保护会把“有需求品才攻击”的验证误判成AI失效。
	_g1.team_id = (_m.player.team_id + 1) % 4
	# 第二名NPC作为稳定靶子，避免自己的AI决策把她带离测试区域。
	_g2.set_physics_process(false)
	_prepare_actor(_m.player)
	_prepare_actor(_g1)
	_prepare_actor(_g2)
	# 新旧正式地图共同的收银前开阔侧翼，远离货架与爆款展台。
	_place_cart_actor(_m.player, Vector3(-8.0, 0.2, 12.0))
	_g1.global_position = Vector3(-6.7, 0.2, 13.28)
	_g1.shopping_list = ["thermos"]
	_g1.acquired.clear()
	_unrelated_item = _put_in_cart(_m.player.cart, "chips")
	print("[npc] 自检开始")

func _prepare_actor(a: Actor) -> void:
	if a.attached:
		a.detach_cart()
	a.drop_all_held(false)
	a.imbalance = 0.0
	a.downed = false
	if a is Granny:
		a.state = Granny.GState.IDLE
		a.target_actor = null
		a.target_cart = null
		a.chase_target = null

func _place_cart_actor(a: Actor, pos: Vector3) -> void:
	var c := a.cart
	c.right_up()
	c.global_position = pos
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	a.attach_cart()

func _put_in_cart(c: Cart, id: String) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_free_at(c.to_global(Vector3(0, 1.25, 0)))
	return it

func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[0.4, _check_hud],
		[0.6, _check_no_blind_aggro],
		[0.8, _setup_player_aggro],
		[1.1, _start_player_aggro],
		[1.3, _check_lost_reason],
		[1.4, _setup_player_attack],
		[1.7, _start_player_attack],
		[2.8, _check_player_attack],
		[3.0, _check_elbow_reclaim_only],
		[3.2, _report],
	]
	while _step < schedule.size() and _t >= float(schedule[_step][0]):
		var fn: Callable = schedule[_step][1]
		_step += 1
		fn.call()

func _check(ok: bool, msg: String) -> void:
	if ok:
		_notes.append("  OK   " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	_fails.append(msg)
	_notes.append("  FAIL " + msg)

func _check_hud() -> void:
	_m.hud.set_bars(100.0, 100.0)
	var sf := _m.hud.stamina_fill
	var imf := _m.hud.imbalance_fill
	var sw := (sf.get_parent() as Control).size.x - 4.0
	var iw := (imf.get_parent() as Control).size.x - 4.0
	_check(absf(sf.size.x - sw) < 0.6, "HUD：100体力填满背景内沿(%.1f/%.1f)" % [sf.size.x, sw])
	_check(absf(imf.size.x - iw) < 0.6, "HUD：100失衡填满背景内沿(%.1f/%.1f)" % [imf.size.x, iw])

func _check_no_blind_aggro() -> void:
	_check(_m.player.cart.items_in_basket().has(_unrelated_item), "测试前置：玩家车内存在无关商品")
	_check(_g1._find_brawl_target() == null,
			"NPC仇恨：玩家车内没有需求品时不锁定、不主动攻击")

func _setup_player_aggro() -> void:
	_player_item = _put_in_cart(_m.player.cart, "thermos")

func _start_player_aggro() -> void:
	_check(_m.player.cart.items_in_basket().has(_player_item), "测试前置：玩家车内存在NPC需求品")
	var target := _g1._find_brawl_target()
	_check(target == _m.player, "NPC仇恨：只因玩家车内存在需求品而锁定玩家")
	if target != null:
		_g1._start_brawl(target)
		_player_item.set_held()
		_m.player.take_item(_player_item)
		_g1._brawl_state(0.05)
		_stopped_after_loss = _g1.state != Granny.GState.BRAWL and _g1.target_actor == null

func _check_lost_reason() -> void:
	_check(_stopped_after_loss,
			"NPC仇恨：需求品离开对方车斗后立即停止主动攻击")

func _setup_player_attack() -> void:
	_m.player.held.erase(_player_item)
	_player_item.queue_free()
	_player_item = _put_in_cart(_m.player.cart, "thermos")
	_m.player.imbalance = 0.0

func _start_player_attack() -> void:
	var target := _g1._find_brawl_target()
	_check(target == _m.player, "NPC仇恨：需求品重新入车后可再次建立仇恨")
	if target != null:
		# 关闭自主决策，直接推进真实BRAWL状态：先验证靠近，再验证贴身肘击。
		_g1.set_physics_process(false)
		_g1._start_brawl(target)
		_g1.global_position = _m.player.global_position + Vector3(2.4, 0.0, 0.0)
		var before := _g1.global_position.distance_to(_m.player.global_position)
		_g1._brawl_state(0.1)
		_approached_for_attack = _g1.global_position.distance_to(_m.player.global_position) < before
		_g1.global_position = _m.player.global_position + Vector3(1.2, 0.0, 0.0)
		_g1._elbow_cd = 0.0
		_g1._brawl_state(0.05)

func _check_player_attack() -> void:
	_check(_approached_for_attack and (_m.player.imbalance > 0.0 or _m.player.downed),
			"NPC：锁定需求车后会主动靠近并攻击玩家")

func _check_elbow_reclaim_only() -> void:
	# 暂停自主决策，确定性验证单次追讨动作。
	_g1.set_physics_process(false)
	_prepare_actor(_m.player)
	_prepare_actor(_g1)
	_m.player.cart.remove_collision_exception_with(_g1)
	_g1.global_position = _m.player.global_position + Vector3(0.0, 0.0, 1.2)
	var stolen := Item.create("thermos")
	_m.add_child(stolen)
	_m.all_items.append(stolen)
	stolen.set_held()
	_m.player.take_item(stolen)
	_g1.on_robbed(stolen, _m.player)
	_g1._elbow_cd = 0.0
	_g1._chase_state(0.05)
	_check(_m.player.held.has(stolen) and not _g1.held.has(stolen),
			"NPC追讨：首次贴身命中只累积失衡，不会立即夺回手持商品")
	_check(_m.player.imbalance > 0.0 and not _m.player.downed,
			"NPC追讨：会通过肘击逐步制造失衡")
	_m.player.imbalance = 90.0
	_g1._elbow_cd = 0.0
	_g1._chase_state(0.05)
	_check(_m.player.downed and stolen.state == Item.ItemState.FREE,
			"NPC追讨：只有将持有者肘击倒地后，商品才会掉落")
	_check(not _g1.held.has(stolen),
			"NPC追讨：倒地瞬间仍不瞬移夺货，必须再走正常拾取流程")

func _report() -> void:
	for line in _notes:
		print("[npc]", line)
	if _fails.is_empty():
		print("[npc] RESULT=PASS assertions=", _notes.size())
	else:
		print("[npc] RESULT=FAIL fails=", _fails.size())
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
