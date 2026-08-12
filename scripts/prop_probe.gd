class_name PropProbe extends RefCounted
## 场内商品道具专项回归：消耗物权、洗衣液地形、保温杯命中、软糖减速。

var _m: Main
var _p: Player
var _dummy: Actor
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []
var _slip_before := 0
var _slow_before := 0

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	_p = _m.player
	if _p.attached:
		_p.detach_cart()
	_p.drop_all_held(false)
	_dummy = Actor.new()
	_m.add_child(_dummy)
	_dummy.build_body(Color(0.75, 0.75, 0.75), "道具靶子")
	_dummy.global_position = _p.global_position + Vector3(2.0, 0, 0)
	print("[prop] 自检开始")

func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[0.5, _test_detergent], [1.0, _check_detergent],
		[1.3, _test_thermos], [1.8, _check_thermos],
		[2.1, _test_candy], [2.8, _check_candy],
		[3.1, _report],
	]
	while _step < schedule.size() and _t >= float(schedule[_step][0]):
		var fn: Callable = schedule[_step][1]
		_step += 1
		fn.call()

func _give(id: String) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_held()
	_p.take_item(it)
	return it

func _projectile(kind: String) -> RigidBody3D:
	for node in _m.get_children():
		if node is RigidBody3D and str(node.get_meta("prop_kind", "")) == kind:
			return node
	return null

func _count_type(type_name: String) -> int:
	var n := 0
	for node in _m.get_children():
		if (type_name == "slip" and node is SlipperyZone) or (type_name == "slow" and node is SlowZone):
			n += 1
	return n

func _test_detergent() -> void:
	_p.prop_cd = 0.0
	var it := _give("detergent")
	_slip_before = _count_type("slip")
	_m.trigger_use_prop(_p, Vector3.FORWARD)
	_check(not _p.held.has(it), "洗衣液:右键后从手中消耗")
	var projectile := _projectile("slip")
	_check(projectile != null, "洗衣液:生成投掷物")
	if projectile != null:
		_m._prop_projectile_hit(projectile, _m)

func _check_detergent() -> void:
	_check(_count_type("slip") == _slip_before + 1, "洗衣液:落点生成大范围15秒湿滑地形")

func _test_thermos() -> void:
	_p.prop_cd = 0.0
	_dummy.imbalance = 0.0
	# 离开上一项洗衣液的湿滑区，隔离保温杯自身的 +25 失衡。
	_dummy.global_position = _p.global_position + Vector3(8.0, 0, 0)
	var it := _give("thermos")
	_m.trigger_use_prop(_p, Vector3.FORWARD)
	_check(not _p.held.has(it), "保温杯:右键后从手中消耗")
	var projectile := _projectile("impact")
	_check(projectile != null, "保温杯:生成投掷物")
	if projectile != null:
		_m._prop_projectile_hit(projectile, _dummy)

func _check_thermos() -> void:
	_check(_dummy.imbalance >= 24.0, "保温杯:命中对手造成25失衡(实际%.0f)" % _dummy.imbalance)

func _test_candy() -> void:
	_p.prop_cd = 0.0
	_dummy.slow_time = 0.0
	_dummy.slow_factor = 1.0
	_dummy.global_position = _p.global_position + Vector3(1.5, 0, 0)
	var it := _give("candy")
	_slow_before = _count_type("slow")
	_m.trigger_use_prop(_p, Vector3.FORWARD)
	_check(not _p.held.has(it), "软糖:右键后从手中消耗")
	var projectile := _projectile("sticky")
	_check(projectile != null, "软糖:生成投掷物")
	if projectile != null:
		projectile.global_position = _dummy.global_position
		_m._prop_projectile_hit(projectile, _m)

func _check_candy() -> void:
	_check(_count_type("slow") == _slow_before + 1, "软糖:落点生成7秒黏地减速区")
	_check(_dummy.movement_factor() <= 0.61, "软糖:区域内角色保留60%移动能力")

func _check(ok: bool, msg: String) -> void:
	_notes.append(("  OK   " if ok else "  FAIL ") + msg)
	if not ok:
		_fails.append(msg)

func _report() -> void:
	for line in _notes:
		print("[prop]", line)
	print("[prop] RESULT=%s assertions=%d" % ["PASS" if _fails.is_empty() else "FAIL", _notes.size()])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
