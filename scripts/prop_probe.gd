class_name PropProbe extends RefCounted
## 全商品投掷专项回归：车斗轮盘、实际物权、差异伤害、落点效果与准星方向。

var _m: Main
var _p: Player
var _dummy: Actor
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []
var _item: Item
var _zone_before := 0

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	_p = _m.player
	if _p.attached:
		_p.detach_cart()
	_p.drop_all_held(false)
	_p.cart.right_up()
	_p.cart.global_position = Vector3(0, 0.2, 12)
	_p.cart.linear_velocity = Vector3.ZERO
	_p.cart.angular_velocity = Vector3.ZERO
	_p.attach_cart()
	_dummy = Actor.new()
	_m.add_child(_dummy)
	_dummy.build_body(Color(0.75, 0.75, 0.75), "投掷靶子")
	_dummy.global_position = _p.global_position + Vector3(5.0, 0, 0)
	_check(Catalog.THROW_IMBALANCE.size() == Catalog.ITEMS.size(), "目录：所有商品均配置投掷失衡值")
	for id in Catalog.ITEMS:
		_check(Catalog.is_prop(id) and Catalog.throw_imbalance(id) > 0.0, "全商品可投掷：%s" % id)
	print("[prop] 全商品投掷自检开始")

func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[0.3, _setup_wheel], [0.7, _check_wheel],
		[0.9, _throw_detergent], [1.1, _hit_detergent], [1.4, _check_detergent],
		[1.6, _throw_thermos], [1.8, _hit_thermos], [2.1, _check_thermos],
		[2.3, _throw_candy], [2.5, _hit_candy], [2.9, _check_candy],
		[3.1, _check_pedestrian_hits], [3.4, _report],
	]
	while _step < schedule.size() and _t >= float(schedule[_step][0]):
		var fn: Callable = schedule[_step][1]
		_step += 1
		fn.call()

func _put(id: String) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_free_at(_p.cart.to_global(Vector3(randf_range(-0.18, 0.18), 1.28, randf_range(-0.18, 0.18))))
	return it

func _count_zones(type_name: String) -> int:
	var n := 0
	for node in _m.get_children():
		if (type_name == "slip" and node is SlipperyZone) or (type_name == "slow" and node is SlowZone):
			n += 1
	return n

func _setup_wheel() -> void:
	_put("tissue")
	_put("cola")
	_put("tv")

func _check_wheel() -> void:
	var items := _m.cart_throw_items(_p)
	_check(items.size() >= 3, "轮盘：读取购物车内全部商品")
	var before := _m.selected_cart_item_id(_p)
	_m.cycle_cart_item(_p, 1)
	var after := _m.selected_cart_item_id(_p)
	_check(before != after, "轮盘：滚轮循环切换选中商品")
	var aim := _m.cam_rig.aim_direction()
	_check(aim.is_finite() and absf(aim.length() - 1.0) < 0.02, "准星：屏幕中心生成单位三维投掷方向")

func _clear_cart() -> void:
	for it in _m.cart_throw_items(_p):
		it.queue_free()

func _throw_detergent() -> void:
	_clear_cart()
	_item = _put("detergent")
	_zone_before = _count_zones("slip")
	_p.prop_cd = 0.0

func _hit_detergent() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "detergent")
	_check(bool(_item.get_meta("throw_active", false)), "洗衣液：从车斗取出真实商品并进入投掷态")
	_m._thrown_item_hit(_item, _m, _p)

func _check_detergent() -> void:
	_check(is_instance_valid(_item) and _item.state == Item.ItemState.FREE, "投掷商品：命中后留在场内而非消失")
	_check(_count_zones("slip") == _zone_before + 1, "洗衣液：落点生成大范围湿滑区")

func _throw_thermos() -> void:
	_clear_cart()
	_item = _put("thermos")
	_dummy.imbalance = 0.0
	_p.prop_cd = 0.0

func _hit_thermos() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "thermos")
	_m._thrown_item_hit(_item, _dummy, _p)

func _check_thermos() -> void:
	_check(absf(_dummy.imbalance - Catalog.throw_imbalance("thermos")) < 0.5,
			"保温杯：直击造成独立配置的30失衡(实际%.0f)" % _dummy.imbalance)

func _throw_candy() -> void:
	_clear_cart()
	_item = _put("candy")
	_zone_before = _count_zones("slow")
	_dummy.slow_time = 0.0
	_dummy.slow_factor = 1.0
	_p.prop_cd = 0.0

func _hit_candy() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "candy")
	_item.global_position = _dummy.global_position
	_m._thrown_item_hit(_item, _m, _p)

func _check_candy() -> void:
	_check(_count_zones("slow") == _zone_before + 1, "软糖：落点生成黏地减速区")
	_check(_dummy.movement_factor() <= 0.61, "软糖：区域内角色保留60%移动能力")

func _check_pedestrian_hits() -> void:
	_dummy.imbalance = 0.0
	_dummy.downed = false
	_p.cart.sprinting = false
	_p.cart.sprint_level = 0.0
	_p.cart.hit_mult = 1.0
	_dummy.hit_by_cart(_p.cart)
	_check(absf(_dummy.imbalance - 50.0) < 0.5, "徒步受撞：普通购物车造成基础值2倍，即50失衡")
	_dummy.imbalance = 0.0
	_dummy.downed = false
	_p.cart.sprinting = true
	_p.cart.sprint_level = 1.0
	_dummy.hit_by_cart(_p.cart)
	_check(_dummy.downed and _dummy.imbalance >= 100.0, "徒步受撞：加速购物车直接满失衡并撞倒")

func _check(ok: bool, msg: String) -> void:
	_notes.append(("  OK   " if ok else "  FAIL ") + msg)
	if not ok:
		_fails.append(msg)

func _report() -> void:
	for line in _notes:
		print("[prop]", line)
	print("[prop] RESULT=%s assertions=%d" % ["PASS" if _fails.is_empty() else "FAIL", _notes.size()])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
