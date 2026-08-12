class_name NpcProbe extends RefCounted
## NPC争抢与HUD状态槽回归探针。
## WHITEBOX_NPCTEST=1 下确定性覆盖满值状态条、抢玩家、NPC互抢与互肘。

var _m: Main
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []
var _g1: Granny
var _g2: Granny
var _player_item: Item
var _rival_item: Item

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	if _m.grannies.size() < 2:
		_fail("测试前置：至少需要2名NPC")
		_report()
		return
	_g1 = _m.grannies[0]
	_g2 = _m.grannies[1]
	# 第二名NPC作为稳定靶子，避免自己的AI决策把她带离测试区域。
	_g2.set_physics_process(false)
	_prepare_actor(_m.player)
	_prepare_actor(_g1)
	_prepare_actor(_g2)
	_m.player.global_position = Vector3(0, 0.2, 12)
	_g1.global_position = Vector3(1.3, 0.2, 12)
	_g2.global_position = Vector3(-1.3, 0.2, 12)
	_g1.shopping_list = ["thermos"]
	_g1.acquired.clear()
	_player_item = _give_item(_m.player, "thermos")
	var first_target := _g1._find_brawl_target()
	_check(first_target == _m.player, "NPC决策：主动锁定手持目标货的玩家")
	_g1._start_brawl(first_target)
	print("[npc] 自检开始")

func _prepare_actor(a: Actor) -> void:
	if a.attached:
		a.detach_cart()
	a.drop_all_held(false)
	a.imbalance = 0.0
	a.downed = false

func _give_item(a: Actor, id: String) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_held()
	a.take_item(it)
	return it

func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[0.4, _check_hud],
		[1.8, _check_player_snatch],
		[2.0, _setup_rival_snatch],
		[3.6, _check_rival_snatch],
		[3.8, _setup_elbow],
		[5.2, _check_elbow],
		[5.5, _report],
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

func _owns(g: Granny, it: Item) -> bool:
	return g.held.has(it) or (is_instance_valid(g.cart) and g.cart.items_in_basket().has(it))

func _check_hud() -> void:
	_m.hud.set_bars(100.0, 100.0)
	var sf := _m.hud.stamina_fill
	var imf := _m.hud.imbalance_fill
	var sw := (sf.get_parent() as Control).size.x - 4.0
	var iw := (imf.get_parent() as Control).size.x - 4.0
	_check(absf(sf.size.x - sw) < 0.6, "HUD：100体力填满背景内沿(%.1f/%.1f)" % [sf.size.x, sw])
	_check(absf(imf.size.x - iw) < 0.6, "HUD：100失衡填满背景内沿(%.1f/%.1f)" % [imf.size.x, iw])

func _check_player_snatch() -> void:
	_check(_owns(_g1, _player_item) and not _m.player.held.has(_player_item),
			"NPC：主动追近并抢走玩家手中目标商品")

func _setup_rival_snatch() -> void:
	_prepare_actor(_g1)
	_prepare_actor(_g2)
	_g1.global_position = Vector3(0, 0.2, 12)
	_g2.global_position = Vector3(1.3, 0.2, 12)
	_g1.shopping_list = ["chips"]
	_g1.acquired.clear()
	_rival_item = _give_item(_g2, "chips")
	var rival_target := _g1._find_brawl_target()
	_check(rival_target == _g2, "NPC决策：主动锁定手持目标货的其他NPC")
	_g1._start_brawl(rival_target)

func _check_rival_snatch() -> void:
	_check(_owns(_g1, _rival_item) and not _g2.held.has(_rival_item),
			"NPC：会从另一名NPC手中争抢商品")

func _setup_elbow() -> void:
	_prepare_actor(_g1)
	_prepare_actor(_g2)
	_g1.global_position = Vector3(0, 0.2, 12)
	_g2.global_position = Vector3(1.3, 0.2, 12)
	_g1.shopping_list = ["king_crab"]
	_g1.acquired.clear()
	_g1._start_brawl(_g2)

func _check_elbow() -> void:
	_check(_g2.imbalance > 0.0 or _g2.downed, "NPC：无货可直接抢时会肘击另一名NPC")

func _report() -> void:
	for line in _notes:
		print("[npc]", line)
	if _fails.is_empty():
		print("[npc] RESULT=PASS assertions=", _notes.size())
	else:
		print("[npc] RESULT=FAIL fails=", _fails.size())
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
