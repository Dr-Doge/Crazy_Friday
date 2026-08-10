class_name Checkout extends Node3D
## 自助收银通道:闸机一次放行一车,通道内免战,逐件扫码1秒/件。
## 通道沿z 向:北口 MapLayout.GATE_IN_Z 进,南口 MapLayout.GATE_OUT_Z 出。
## 几何体一律用 CSG 节点,便于后续换成正式模型(闸机是 AnimatableBody3D+CSG 子节点)。

signal item_scanned(item: Item, by_player: Player)
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
var _gate_open_pos := -1.4
var _scan_timer := 0.0
var _was_scanning := false
var _immune_actors: Array = []

## 车尾越过这条线就放行南口(通道后段)
var _south_release_z := 0.0

## 返回需要标记为寻路障碍的矩形
func setup(x: float, index: int) -> Array:
	lane_x = x
	lane_index = index
	name = "Checkout_%d" % index
	var rects: Array = []
	var mid_z := MapLayout.lane_mid_z()
	var lane_len := MapLayout.lane_len()
	_south_release_z = MapLayout.GATE_OUT_Z - lane_len * 0.25

	# 两侧围栏
	var i := 0
	for side in [-MapLayout.LANE_HALF_W, MapLayout.LANE_HALF_W]:
		_csg_box("Rail_%d" % i, Vector3(x + side, 0.5, mid_z),
				Vector3(0.25, 1.0, lane_len), Color(0.5, 0.52, 0.56))
		rects.append(Rect2(x + side - 0.5, MapLayout.GATE_IN_Z, 1.0, lane_len))
		i += 1

	# 收银带(扫码后商品摆这,不可偷不可撞散)——放通道西侧,不挡东侧主走廊
	_csg_box("Belt", Vector3(x + MapLayout.BELT_DX, 0.48, mid_z - 0.5),
			Vector3(0.9, 0.95, 3.2), Color(0.35, 0.38, 0.42))
	rects.append(Rect2(x + MapLayout.BELT_DX - 0.45, mid_z - 2.1, 0.9, 3.2))

	# 闸机(升起挡路/沉入地面放行):北口入车,南口只出不进
	gate = _make_gate("Gate_In", Vector3(x, _gate_closed_pos, MapLayout.GATE_IN_Z))
	south_gate = _make_gate("Gate_Out", Vector3(x, _gate_closed_pos, MapLayout.GATE_OUT_Z))

	# 通道内部感应(闸机以南):占用判定+免战区+扫码区
	inner_area = Area3D.new()
	inner_area.name = "InnerArea"
	inner_area.monitoring = true
	inner_area.monitorable = false
	inner_area.collision_layer = 0
	inner_area.collision_mask = Catalog.L_CART | Catalog.L_CHAR
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(MapLayout.LANE_HALF_W * 1.5, 2.4, lane_len - 0.8)
	ac.shape = ab
	ac.position = Vector3(x, 1.2, mid_z)
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
	sign_label.position = Vector3(x, 3.0, MapLayout.GATE_IN_Z)
	add_child(sign_label)
	return rects

## 打烊冲刺:通道关闭
func force_close() -> void:
	lane_open = false
	sign_label.text = "已关闭"
	sign_label.modulate = Color(0.9, 0.25, 0.2)

func _physics_process(delta: float) -> void:
	var carts_inside: Array = []
	var actors_inside: Array = []
	for b in inner_area.get_overlapping_bodies():
		if b is Cart:
			carts_inside.append(b)
		elif b is Actor:
			actors_inside.append(b)
	# 推车中的玩家碰撞层为0,Area探测不到,从车上补
	for c in carts_inside:
		if c.attached_agent != null and not actors_inside.has(c.attached_agent):
			actors_inside.append(c.attached_agent)

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

	# 北口闸机:通道被占或已关闭→升起;有车正压在闸机上时不升,避免把车顶飞
	var closed := (not lane_open) or (not carts_inside.is_empty())
	var target_y := _gate_closed_pos if closed else _gate_open_pos
	if closed and _cart_on_gate(MapLayout.GATE_IN_Z):
		target_y = _gate_open_pos
	gate.position.y = move_toward(gate.position.y, target_y, 3.0 * delta)

	# 南口闸机:默认封住(防倒灌+防绕过排队);车扫完往外走时放行
	# 压车保护只认通道内侧的车,南侧来的车不触发,否则又能绕过排队
	var south_open := false
	if lane_open:
		for c in carts_inside:
			if c.global_position.z > _south_release_z:
				south_open = true
				break
	var south_target := _gate_open_pos if south_open else _gate_closed_pos
	if not south_open and _cart_on_gate(MapLayout.GATE_OUT_Z, MapLayout.GATE_OUT_Z + 0.05):
		south_target = _gate_open_pos
	south_gate.position.y = move_toward(south_gate.position.y, south_target, 3.0 * delta)

	# 已关闭的通道不扫码不结算
	if not lane_open:
		_scan_timer = 0.0
		_was_scanning = false
		return

	# 扫码:任何推着车在通道内的人,1秒一件。玩家的货上收银带,大妈的货直接装袋带走。
	var scanning_cart: Cart = null
	for c in carts_inside:
		if c.attached_agent == null:
			continue
		# 已结算的玩家不能二次扫码
		if c.attached_agent is Player and Main.instance != null and Main.instance.is_settled_agent(c.attached_agent):
			continue
		scanning_cart = c
		break
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
		if agent is Player:
			it.set_scanned_at(_next_belt_pos())
			item_scanned.emit(it, agent)
		else:
			# 大妈装袋带走(联机时通知客户端同步移除)
			if Main.instance != null:
				Main.instance.net_item_gone_notify(it)
			it.queue_free()
	elif _was_scanning:
		_was_scanning = false
		if agent is Player:
			lane_settled.emit(agent)

func _cart_on_gate(gate_z: float, max_z := 999.0) -> bool:
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if not is_instance_valid(c):
			continue
		if absf(c.global_position.x - lane_x) < 1.3 and absf(c.global_position.z - gate_z) < 0.7 \
				and c.global_position.z < max_z:
			return true
	return false

func _make_gate(node_name: String, pos: Vector3) -> AnimatableBody3D:
	var g := AnimatableBody3D.new()
	g.name = node_name
	g.collision_layer = Catalog.L_WORLD
	g.collision_mask = 0
	g.sync_to_physics = false
	# 闸机杆本体用 CSG:换正式模型时把这个子节点替掉即可,父级动画逻辑不动
	var bar := CSGBox3D.new()
	bar.name = "Bar"
	bar.size = Vector3(MapLayout.LANE_HALF_W * 1.55, 1.1, 0.22)
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
	add_child(g)
	return g

var _belt_count := 0
func _next_belt_pos() -> Vector3:
	var row := int(_belt_count / 7.0)
	var col := _belt_count % 7
	_belt_count += 1
	var z0 := MapLayout.lane_mid_z() - 2.0
	return Vector3(lane_x + MapLayout.BELT_DX + row * 0.05, 1.15 + row * 0.35, z0 + col * 0.45)

## 通道内的静态 CSG 构件(围栏/收银带)
func _csg_box(node_name: String, pos: Vector3, size: Vector3, color: Color) -> CSGBox3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	body.position = pos
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
