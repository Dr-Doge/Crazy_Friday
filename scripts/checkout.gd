class_name Checkout extends Node3D
## 自助收银通道:闸机一次放行一车,通道内免战,逐件扫码1秒/件。
## 通道沿z 向:北口 MapLayout.GATE_IN_Z 进,南口 MapLayout.GATE_OUT_Z 出。
## 几何体一律用 CSG 节点,便于后续换成正式模型(闸机是 AnimatableBody3D+CSG 子节点)。

signal item_scanned(item: Item, by_actor: Actor)
signal lane_settled(by_player: Player)

const SCAN_INTERVAL := 1.0

var lane_open := true
var lane_index := 1
var lane_x := 0.0
var gate: AnimatableBody3D          # 北口:入口闸机
var south_gate: AnimatableBody3D    # 南口:防止从出口倒灌
var inner_area: Area3D
var sign_label: Label3D
var _gate_closed_pos := 0.55
var _gate_open_pos := 2.25
var _scan_timer := 0.0
var _was_scanning := false
var _immune_actors: Array = []
var _active_cart: Cart = null

## 车尾越过这条线就放行南口(通道后段)
var _south_release_z := 0.0
var _gate_in_z := MapLayout.GATE_IN_Z
var _gate_out_z := MapLayout.GATE_OUT_Z
var _lane_half_w := MapLayout.LANE_HALF_W
var _belt_dx := MapLayout.BELT_DX
var lane_center := Vector3.ZERO
var lane_forward := Vector3.FORWARD
var lane_side := Vector3.RIGHT
var _lane_length := 0.0
var _lane_yaw := 0.0
var _exit_outer := Vector3.ZERO

## 返回需要标记为寻路障碍的矩形
func setup(x: float, index: int) -> Array:
	return setup_custom(x, index, {
		"gate_in_z": MapLayout.GATE_IN_Z,
		"gate_out_z": MapLayout.GATE_OUT_Z,
		"lane_half_w": MapLayout.LANE_HALF_W,
		"belt_dx": MapLayout.BELT_DX,
	})

## 手工关卡入口：收银几何和判定读取场景配置，不再写死旧MapLayout坐标。
func setup_custom(x: float, index: int, config: Dictionary) -> Array:
	var gate_in := float(config.get("gate_in_z", MapLayout.GATE_IN_Z))
	var gate_out := float(config.get("gate_out_z", MapLayout.GATE_OUT_Z))
	var belt_offsets: Array = config.get("belt_dx_by_lane", [])
	var belt_offset := float(belt_offsets[index - 1]) if index - 1 < belt_offsets.size() \
			else float(config.get("belt_dx", MapLayout.BELT_DX))
	return setup_oriented({
		"name": "South_%d" % index,
		"center": Vector3(x, 0.0, (gate_in + gate_out) * 0.5),
		"outward": Vector3.FORWARD,
		"side": Vector3.RIGHT,
		"length": gate_out - gate_in,
		"lane_half_w": float(config.get("lane_half_w", MapLayout.LANE_HALF_W)),
		"belt_offset": belt_offset,
		"exit_outer": Vector3(x, 0.0, gate_out + 4.0),
	}, index)

## 四向收银入口：所有位置均由场景中对应收银组的变换推导。
func setup_oriented(spec: Dictionary, index: int) -> Array:
	lane_index = index
	name = "Checkout_%s" % str(spec.get("name", index))
	lane_center = spec.get("center", Vector3.ZERO)
	lane_forward = (spec.get("outward", Vector3.FORWARD) as Vector3).normalized()
	lane_side = (spec.get("side", Vector3.RIGHT) as Vector3).normalized()
	_lane_length = float(spec.get("length", 6.0))
	_lane_half_w = float(spec.get("lane_half_w", 1.3))
	_belt_dx = float(spec.get("belt_offset", -1.95))
	_exit_outer = spec.get("exit_outer", lane_center + lane_forward * (_lane_length * 0.5 + 7.0))
	_lane_yaw = atan2(lane_forward.x, lane_forward.z)
	lane_x = lane_center.x
	_gate_in_z = -_lane_length * 0.5
	_gate_out_z = _lane_length * 0.5
	var rects: Array = []
	_south_release_z = _gate_out_z - _lane_length * 0.25

	# 两侧围栏
	var i := 0
	for side_value in [-_lane_half_w, _lane_half_w]:
		var rail_pos: Vector3 = lane_center + lane_side * float(side_value) + Vector3.UP * 0.5
		var rail_size := Vector3(0.25, 1.0, _lane_length)
		_csg_box("Rail_%d" % i, rail_pos, rail_size, Color(0.5, 0.52, 0.56), _lane_yaw)
		rects.append(_oriented_rect(rail_pos, rail_size, _lane_yaw))
		i += 1

	# 收银带位于车道外侧，通道本身保持整车净宽。
	var belt_pos := lane_center + lane_side * _belt_dx - lane_forward * 0.5 + Vector3.UP * 0.38
	var belt_size := Vector3(0.9, 0.7, 3.2)
	_csg_box("Belt", belt_pos, belt_size, Color(0.35, 0.38, 0.42), _lane_yaw)
	rects.append(_oriented_rect(belt_pos, belt_size, _lane_yaw))

	# 入口隔离门在首车进入后立即闭合；出口门只为已扫码车辆开放。
	gate = _make_gate("Gate_In", _lane_point(_gate_in_z, _gate_closed_pos), _lane_yaw)
	south_gate = _make_gate("Gate_Out", _lane_point(_gate_out_z, _gate_closed_pos), _lane_yaw)

	# 通道内部感应：占用判定、免战区和逐件扫码。
	inner_area = Area3D.new()
	inner_area.name = "InnerArea"
	inner_area.monitoring = true
	inner_area.monitorable = false
	inner_area.collision_layer = 0
	inner_area.collision_mask = Catalog.L_CART | Catalog.L_CHAR
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(_lane_half_w * 1.5, 2.4, _lane_length - 0.8)
	ac.shape = ab
	ac.position = lane_center + Vector3.UP * 1.2
	ac.rotation.y = _lane_yaw
	inner_area.add_child(ac)
	add_child(inner_area)

	sign_label = Label3D.new()
	sign_label.name = "Sign"
	sign_label.text = "自助收银 %d" % index
	sign_label.font = Catalog.ui_font()
	sign_label.font_size = 90
	sign_label.pixel_size = 0.006
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.no_depth_test = true
	sign_label.modulate = Color(0.2, 0.75, 0.35)
	sign_label.outline_size = 12
	sign_label.position = _lane_point(_gate_in_z, 3.0)
	add_child(sign_label)
	return rects

## 打烊冲刺:通道关闭
func force_close() -> void:
	lane_open = false
	sign_label.text = "已关闭"
	sign_label.modulate = Color(0.9, 0.25, 0.2)

func set_round_open(open: bool) -> void:
	lane_open = open
	if not is_instance_valid(sign_label):
		return
	sign_label.text = "自助收银 %d · 开放" % lane_index if open else "自助收银 %d · 本局关闭" % lane_index
	sign_label.modulate = Color(0.2, 0.9, 0.38) if open else Color(0.9, 0.25, 0.2)

func _physics_process(delta: float) -> void:
	var carts_inside: Array = []
	var actors_inside: Array = []
	for b in inner_area.get_overlapping_bodies():
		if b is Cart:
			carts_inside.append(b)
		elif b is Actor:
			actors_inside.append(b)
	# 隔离门只登记一辆占用车；后车即使贴门也不能获得扫码权。
	if not is_instance_valid(_active_cart) or not carts_inside.has(_active_cart):
		_active_cart = null
	if _active_cart == null and not carts_inside.is_empty():
		carts_inside.sort_custom(func(a: Cart, b: Cart) -> bool:
			return progress_along_lane(a.global_position) > progress_along_lane(b.global_position))
		_active_cart = carts_inside[0]
	# 推车中的玩家碰撞层为0，Area探测不到，从唯一占用车补入免战名单。
	if _active_cart != null and _active_cart.attached_agent != null \
			and not actors_inside.has(_active_cart.attached_agent):
		actors_inside.append(_active_cart.attached_agent)

	# 已关闭的通道不再授予免战(下方移除循环会清掉存量)
	if not lane_open:
		actors_inside = []

	# 免战:进入通道的角色不吃失衡
	for a in actors_inside:
		if not _immune_actors.has(a):
			a.immune = true
			_immune_actors.append(a)
	for i in range(_immune_actors.size() - 1, -1, -1):
		var a2 = _immune_actors[i]
		if not is_instance_valid(a2) or not actors_inside.has(a2):
			if is_instance_valid(a2):
				a2.immune = false
			_immune_actors.remove_at(i)

	# 北口闸机：空闲时向上升起开放；占用或关闭时向下降回地面。
	# 有车正压在闸机上时暂缓下降，避免把车卡在门板里。
	var closed := (not lane_open) or _active_cart != null
	var target_y := _gate_closed_pos if closed else _gate_open_pos
	if closed and _cart_on_gate(_gate_in_z):
		target_y = _gate_open_pos
	gate.position.y = move_toward(gate.position.y, target_y, 3.0 * delta)

	# 南口闸机：默认落下封住；车扫完往外走时向上滑行放行。
	# 压车保护只认通道内侧的车,南侧来的车不触发,否则又能绕过排队
	var south_open := false
	if lane_open and _active_cart != null:
		south_open = progress_along_lane(_active_cart.global_position) > _south_release_z
	var south_target := _gate_open_pos if south_open else _gate_closed_pos
	if not south_open and _cart_on_gate(_gate_out_z, _gate_out_z + 0.05):
		south_target = _gate_open_pos
	south_gate.position.y = move_toward(south_gate.position.y, south_target, 3.0 * delta)

	# 已关闭的通道不扫码不结算
	if not lane_open:
		_scan_timer = 0.0
		_was_scanning = false
		return

	# 扫码:任何推着车在通道内的人,1秒一件。玩家的货上收银带,大妈的货直接装袋带走。
	var scanning_cart: Cart = _active_cart
	if scanning_cart != null and scanning_cart.attached_agent == null:
		scanning_cart = null
	# 已结算的玩家不能二次扫码。
	if scanning_cart != null and scanning_cart.attached_agent is Player \
			and Main.instance != null and Main.instance.is_settled_agent(scanning_cart.attached_agent):
		scanning_cart = null
	if scanning_cart == null:
		_scan_timer = 0.0
		_was_scanning = false
		return
	var agent: Actor = scanning_cart.attached_agent
	_scan_timer += delta
	if _scan_timer < SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	var it := scanning_cart.take_top_item()
	if it == null and not agent.held.is_empty():
		it = agent.held.pop_back()
	if it != null:
		_was_scanning = true
		if agent is Player or (agent is Granny and agent.is_team_bot):
			it.set_scanned_at(_next_belt_pos())
			item_scanned.emit(it, agent)
			# AI队员完成计分后商品直接装袋离场，避免扫描带永久堆满阻塞下一辆车。
			if agent is Granny:
				if Main.instance != null:
					Main.instance.net_item_gone_notify(it)
				it.queue_free()
		else:
			# 大妈装袋带走(联机时通知客户端同步移除)
			if Main.instance != null:
				Main.instance.net_item_gone_notify(it)
			it.queue_free()
	elif _was_scanning:
		_was_scanning = false
		if agent is Player:
			lane_settled.emit(agent)

## NPC离场时立即释放占用与免战状态，不必等到下一帧Area重叠列表刷新。
func release_cart(cart: Cart) -> void:
	if cart != _active_cart:
		return
	if is_instance_valid(cart) and is_instance_valid(cart.attached_agent):
		cart.attached_agent.immune = false
		_immune_actors.erase(cart.attached_agent)
	_active_cart = null
	_scan_timer = 0.0
	_was_scanning = false

func _cart_on_gate(gate_progress: float, max_progress := 999.0) -> bool:
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c):
			continue
		var rel := c.global_position - lane_center
		if absf(rel.dot(lane_side)) < 1.3 \
				and absf(rel.dot(lane_forward) - gate_progress) < 0.7 \
				and rel.dot(lane_forward) < max_progress:
			return true
	return false

func _make_gate(node_name: String, pos: Vector3, yaw := 0.0) -> AnimatableBody3D:
	var g := AnimatableBody3D.new()
	g.name = node_name
	g.collision_layer = Catalog.L_WORLD
	g.collision_mask = 0
	g.sync_to_physics = false
	# 闸机杆本体用 CSG:换正式模型时把这个子节点替掉即可,父级动画逻辑不动
	var bar := CSGBox3D.new()
	bar.name = "Bar"
	bar.size = Vector3(_lane_half_w * 1.55, 1.1, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.45, 0.2)
	bar.material = mat
	bar.use_collision = false   # 碰撞由父 AnimatableBody3D 提供,随之移动
	g.add_child(bar)
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = bar.size
	gc.shape = gs
	g.add_child(gc)
	g.position = pos
	g.rotation.y = yaw
	add_child(g)
	return g

var _belt_count := 0
func _next_belt_pos() -> Vector3:
	var row := int(_belt_count / 7.0)
	var col := _belt_count % 7
	_belt_count += 1
	return lane_center + lane_side * (_belt_dx + row * 0.05) \
			+ lane_forward * (-2.0 + col * 0.45) \
			+ Vector3.UP * (1.15 + row * 0.35)

func lane_mid_z() -> float:
	return (_gate_in_z + _gate_out_z) * 0.5

func lane_len() -> float:
	return _lane_length if _lane_length > 0.0 else _gate_out_z - _gate_in_z

func queue_wait_pos() -> Vector3:
	return _lane_point(_gate_in_z - 1.0)

func scan_stop_pos() -> Vector3:
	return _lane_point(-0.3)

func lane_out_pos() -> Vector3:
	return _lane_point(_gate_out_z + 1.0)

func exit_outer_pos() -> Vector3:
	return _exit_outer

func progress_along_lane(world_pos: Vector3) -> float:
	return (world_pos - lane_center).dot(lane_forward)

func has_passed_entry(world_pos: Vector3, margin := 0.0) -> bool:
	return progress_along_lane(world_pos) > _gate_in_z + margin

func queue_wait_z() -> float:
	return queue_wait_pos().z

func scan_stop_z() -> float:
	return scan_stop_pos().z

func lane_out_z() -> float:
	return lane_out_pos().z

func gate_in_z() -> float:
	return _lane_point(_gate_in_z).z

func gate_out_z() -> float:
	return _lane_point(_gate_out_z).z

func _lane_point(progress: float, y := 0.0) -> Vector3:
	var p := lane_center + lane_forward * progress
	p.y = y
	return p

## 通道内的静态 CSG 构件(围栏/收银带)
func _csg_box(node_name: String, pos: Vector3, size: Vector3, color: Color,
		yaw := 0.0) -> CSGBox3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	add_child(body)

	var cs := CollisionShape3D.new()
	cs.name = "Collider"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)

	var b := CSGBox3D.new()
	b.name = "Visual"
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	b.material = mat
	b.use_collision = false   # 碰撞由父级 StaticBody3D 的凸体提供
	body.add_child(b)
	return b

func _oriented_rect(center: Vector3, size: Vector3, yaw: float) -> Rect2:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	var sx := c * size.x + s * size.z
	var sz := s * size.x + c * size.z
	return Rect2(center.x - sx * 0.5, center.z - sz * 0.5, sx, sz)
