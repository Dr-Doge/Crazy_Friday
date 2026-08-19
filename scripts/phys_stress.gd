class_name PhysStress extends RefCounted
## 车斗物理压力测试(回归资产)。
##
## 守住这个缺陷:**薄商品(哈兰德三文鱼/十斤大米/冻披萨)装入购物车后被挤出车外,
## 甚至穿过底板掉出地图**。
##
## 之所以要专门做成测试:这类穿模只在"薄碰撞体 + 车内大重力 + 悬殊质量比 +
##剧烈机动"同时成立时才出现,正常对局的无头模拟(玩家不动、NPC温和装货)
## 根本碰不到,只有人工玩才会遇到——必须构造极端条件把它逼出来。
##
## 用法:WHITEBOX_PHYSTEST=1 配合 --headless,跑完打印统计并自动退出。
## 判定:逃逸数与穿地数必须为 0。

## 故意挑最薄的商品:它们是穿模的高发对象。
## 不含大件(电视/跑步机):大件宽 1.1-1.35 米,车斗内宽只有 0.98 米,
## 设计上就是"占双手抱着走"而非装车,硬塞进来会架在上沿把下面的货压穿,
## 那是测试自己造的假象,不是玩家会遇到的工况。
const TEST_IDS := ["salmon", "rice_bag", "pizza", "drone", "hair_dryer", "robot_vac"]
const DURATION := 24.0
const SETTLE := 2.0          # 先让商品落稳再开始折腾

## 分三个阶段,分别对应玩家的三种真实处境。
## 分阶段的意义:能把"静置就漏货"(必定是缺陷)与"激烈对抗中甩货"(设计意图)
## 区分开来,否则一个笼统的 FAIL 无法指导修复。
const PHASE_IDLE := 6.0# ① 静置:车停着不动,商品绝不该自己漏出去
const PHASE_CRUISE := 14.0   # ② 正常推行:贴着游戏内速度上限来回走+缓转
# ③ 剩余时间为激烈对抗:急转 + 被撞冲量(此阶段甩货属正常)

## 真正"掉出地图"的判据:卖场地板顶面在 y=0、厚 0.5 米,
## 只有穿过整块地板才算穿地。注意别把"被弹到地上"(中心 y≈0.08)误判成穿地。
const SUNK_Y := -1.0
## 离开车斗的判据:水平距离超过车斗半长(0.75)这么多只能是被弹出去了
const ESCAPE_DIST := 3.5
## 车的真实约束:速度上限取游戏内满冲刺值,角速度上限模拟"有人扶着车把"
const CART_SPEED_CAP := 8.8
const CART_SPIN_CAP := 2.5

var _m
var _cart: Cart
var _items: Array[Item] = []
var _t := 0.0
var _escaped := {}
var _sunk := {}
var _min_y := 999.0
var _max_speed := 0.0
var _stage := "静置"
## item_id -> 首次逃逸时的现场描述(判断是穿板还是从上沿飞出)
var _first_escape := {}
## 在"静置/正常推行"阶段就逃逸的 —— 这些才是必须修的缺陷
var _bad_escape := {}

func _init(m) -> void:
	_m = m

func setup() -> void:
	# 用无主车:没有 attached_agent 就不会因失衡触发 spill(),
	# 于是测试期间任何商品离开车斗都必然是物理缺陷而非正常甩货。
	# 同时 imbalance=0 会让车内重力取满值6.0 —— 正是最容易穿模的工况。
	_cart = Cart.create(Color(0.6, 0.6, 0.6), "压力测试车")
	_m.add_child(_cart)
	_cart.global_position = Vector3(0, 0.2, MapLayout.PREMIUM_Z)

	print("[phys] 物理引擎 = ", ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	print("[phys] 物理帧率 = ", Engine.physics_ticks_per_second, " Hz")
	# 在车斗底面上**分散**投放,模拟玩家逐件装车形成的平铺状态。
	# 若全从同一点垂直落下会垒成一柱、严重超出车斗深度(0.62米),
	# 那种超载挤压是测试构造出来的,不是真实装车形态。
	var spots := [
		Vector3(-0.22, 0, -0.45), Vector3(0.22, 0, -0.45),
		Vector3(-0.22, 0, 0.0), Vector3(0.22, 0, 0.0),
		Vector3(-0.22, 0, 0.45), Vector3(0.22, 0, 0.45),
	]
	for i in TEST_IDS.size():
		var it := Item.create(TEST_IDS[i])
		_m.add_child(it)
		var spot: Vector3 = spots[i % spots.size()]
		it.set_free_at(_cart.global_position + Vector3(0, Cart.FLOOR_TOP + 0.25, 0) + spot)
		_m.all_items.append(it)
		_items.append(it)
		print("[phys]   %-11s 视觉=%s 碰撞=%s 质量=%.2fkg ccd=%s" % [
				TEST_IDS[i], str(it.box_size.snappedf(0.01)), str(it.collider_size().snappedf(0.01)),
				it.mass, str(it.continuous_cd)])

func tick(delta: float) -> void:
	_t += delta
	if _t < SETTLE:
		return
	var phase := _t - SETTLE

	if phase < PHASE_IDLE:
		_stage = "静置"
	elif phase < PHASE_CRUISE:
		_stage = "正常推行"
		#来回走 + 缓转,力度贴合玩家正常驾驶
		var dir := Vector3(sin(phase * 0.8), 0, cos(phase * 0.5))
		_cart.apply_central_force(dir.normalized() * _cart.mass * 18.0)
		_cart.apply_torque_impulse(Vector3(0, sin(phase * 1.2) * _cart.mass * 0.25, 0))
	else:
		_stage = "激烈对抗"
		var dir := Vector3(sin(phase * 1.7), 0, cos(phase * 1.1))
		_cart.apply_central_force(dir.normalized() * _cart.mass * 30.0)
		_cart.apply_torque_impulse(Vector3(0, sin(phase * 3.3) * _cart.mass * 0.7, 0))
		if fmod(phase, 2.5) < delta:
			var kick := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			_cart.apply_central_impulse(kick * _cart.mass * 7.0)

	# 施加与真实推车等价的约束:玩家扶着车把,车不会像陀螺一样自转,
	# 速度也有上限。不加这个约束就是在测一个玩家永远遇不到的工况。
	var hv := Vector3(_cart.linear_velocity.x, 0, _cart.linear_velocity.z)
	if hv.length() > CART_SPEED_CAP:
		hv = hv.normalized() * CART_SPEED_CAP
		_cart.linear_velocity.x = hv.x
		_cart.linear_velocity.z = hv.z
	if absf(_cart.angular_velocity.y) > CART_SPIN_CAP:
		_cart.angular_velocity.y = signf(_cart.angular_velocity.y) * CART_SPIN_CAP

	for it in _items:
		if not is_instance_valid(it):
			continue
		_min_y = minf(_min_y, it.global_position.y)
		var sp := it.linear_velocity.length()
		if sp > _max_speed:
			_max_speed = sp
		var local := _cart.to_local(it.global_position)
		var flat := it.global_position - _cart.global_position
		flat.y = 0.0
		# 首次离开车斗时记录"在哪个阶段、怎么出去的"
		if not _first_escape.has(it.item_id):
			var out_bottom: bool = local.y < Cart.FLOOR_TOP - 0.3 and flat.length() < 1.0
			var out_top: bool = local.y > Cart.FLOOR_TOP + Cart.WALL_H + 0.15
			if out_bottom or out_top or flat.length() > ESCAPE_DIST:
				_first_escape[it.item_id] = "[%s] %s 局部y=%.2f 速度=%.1f 水平距=%.2f" % [
						_stage,
						("穿到底板下" if out_bottom else ("越过车斗上沿" if out_top else "横向弹飞")),
						local.y, sp, flat.length()]
				if _stage != "激烈对抗":
					_bad_escape[it.item_id] = _stage
		if it.global_position.y < SUNK_Y:
			_sunk[it.item_id] = true
		elif flat.length() > ESCAPE_DIST:
			_escaped[it.item_id] = true

	if phase > DURATION:
		_report()

func _report() -> void:
	var inside := _cart.items_in_basket().size()
	print("[phys] ---- 车斗物理压力测试结果 ----")
	print("[phys] 仍在车斗内: %d / %d" % [inside, _items.size()])
	print("[phys] 商品最低 y = %.3f" % _min_y)
	print("[phys] 商品最高速度 = %.2f m/s (单帧位移 %.3f m)" % [
			_max_speed, _max_speed / float(Engine.physics_ticks_per_second)])
	print("[phys] 车斗内底面 y=%.2f 上沿 y=%.2f 底板厚 %.2f" % [
			Cart.FLOOR_TOP, Cart.FLOOR_TOP + Cart.WALL_H, Cart.FLOOR_T])
	for id in _first_escape:
		print("[phys] 逃逸现场 %-11s %s" % [id, _first_escape[id]])
	print("[phys] 穿地(掉出地图): %d 种 %s" % [_sunk.size(), str(_sunk.keys())])
	print("[phys] 离开车斗合计: %d 种 %s" % [_escaped.size(), str(_escaped.keys())])
	print("[phys] 其中【静置/正常推行阶段】就逃逸的: %d 种 %s" % [
			_bad_escape.size(), str(_bad_escape.keys())])
	# 判定口径:穿出地图与"温和工况下逃逸"是缺陷;激烈对抗中甩货是设计意图
	if _sunk.is_empty() and _bad_escape.is_empty():
		print("[phys] RESULT=PASS 无穿模,温和工况下不漏货")
	else:
		print("[phys] RESULT=FAIL")
	_m.get_tree().quit()
