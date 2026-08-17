class_name TutorialRoomBuilder
## 独立串联房间式教学地图。只负责空间与固定标记，不承载教学推进逻辑。

const ROOM_CENTERS := [8.0, -20.0, -48.0, -76.0, -108.0]
const GATE_ZS := [-6.0, -34.0, -62.0, -90.0]
const HALF_W := 14.0
const NORTH_Z := 16.0
const SOUTH_Z := -128.0
const WALL_H := 4.8
const DOOR_W := 5.4

static func build(root: Node3D) -> Dictionary:
	var world := Node3D.new()
	world.name = "TutorialRooms"
	root.add_child(world)
	_box(world, "Floor", Vector3(0, -0.25, (NORTH_Z + SOUTH_Z) * 0.5),
			Vector3(HALF_W * 2.0, 0.5, NORTH_Z - SOUTH_Z), Color(0.88, 0.9, 0.93))
	_wall(world, "Wall_W", Vector3(-HALF_W, WALL_H * 0.5, (NORTH_Z + SOUTH_Z) * 0.5),
			Vector3(0.5, WALL_H, NORTH_Z - SOUTH_Z))
	_wall(world, "Wall_E", Vector3(HALF_W, WALL_H * 0.5, (NORTH_Z + SOUTH_Z) * 0.5),
			Vector3(0.5, WALL_H, NORTH_Z - SOUTH_Z))
	_wall(world, "Wall_N", Vector3(0, WALL_H * 0.5, NORTH_Z),
			Vector3(HALF_W * 2.0, WALL_H, 0.5))
	_wall(world, "Wall_S", Vector3(0, WALL_H * 0.5, SOUTH_Z),
			Vector3(HALF_W * 2.0, WALL_H, 0.5))

	var gates: Array[StaticBody3D] = []
	for i in GATE_ZS.size():
		var z: float = float(GATE_ZS[i])
		var side_w := HALF_W - DOOR_W * 0.5
		_wall(world, "Divider_%d_L" % (i + 1), Vector3(-(DOOR_W * 0.5 + side_w * 0.5), WALL_H * 0.5, z),
				Vector3(side_w, WALL_H, 0.5))
		_wall(world, "Divider_%d_R" % (i + 1), Vector3(DOOR_W * 0.5 + side_w * 0.5, WALL_H * 0.5, z),
				Vector3(side_w, WALL_H, 0.5))
		var gate := _wall(world, "Gate_%d" % (i + 1), Vector3(0, 1.6, z),
				Vector3(DOOR_W, 3.2, 0.42), Color(0.85, 0.2, 0.16))
		gate.set_meta("tutorial_gate", i)
		var gate_visual := gate.get_node("Visual") as MeshInstance3D
		gate.set_meta("gate_closed_visual_y", gate_visual.position.y)
		gates.append(gate)

	_build_room_decals(world)
	_build_room_one(world)
	_build_room_two(world)
	_build_room_three(world)
	_build_room_four(world)
	_build_room_five(world)

	return {
		"player_spawn": Vector3(0, 0.05, 11.0),
		"grid": _make_grid(),
		"sale_points": [],
		"gates": gates,
		"room_centers": ROOM_CENTERS,
		"points": {
			"goods_a": Vector3(-5.0, 1.28, -21.28),
			"goods_b": Vector3(5.0, 1.28, -26.28),
			"goods_decoy": Vector3(0.0, 0.78, -24.5),
			"steal_cart": Vector3(-5.0, 0.2, -48.0),
			"combat_dummy": Vector3(4.0, 0.05, -51.0),
			"brace_cart": Vector3(-7.5, 0.2, -57.0),
			"lab_dummy": Vector3(4.0, 0.05, -78.0),
			"lab_cart": Vector3(-4.5, 0.2, -78.0),
			"final_shelf": Vector3(-5.0, 1.28, -107.28),
			"final_cart": Vector3(5.0, 0.2, -108.0),
			"final_dummy": Vector3(0.0, 0.05, -116.0),
			"checkout": Vector3(0.0, 0.0, -124.0),
		}
	}

static func set_gate_open(gate: StaticBody3D, open: bool) -> void:
	if not is_instance_valid(gate):
		return
	gate.set_meta("open", open)
	gate.collision_layer = 0 if open else Catalog.L_WORLD
	var collider := gate.get_node_or_null("Collider") as CollisionShape3D
	if collider != null:
		collider.set_deferred("disabled", open)
	var visual := gate.get_node_or_null("Visual") as MeshInstance3D
	if visual != null:
		visual.visible = true
		var mat := visual.mesh.material as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.18, 0.92, 0.38) if open else Color(0.85, 0.2, 0.16)
		visual.set_meta("gate_color", "green" if open else "red")
		var closed_y := float(gate.get_meta("gate_closed_visual_y", 0.0))
		var target_y := closed_y + 3.55 if open else closed_y
		var previous_tween: Tween = gate.get_meta("gate_tween") as Tween if gate.has_meta("gate_tween") else null
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
		var tween := gate.create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "position:y", target_y, 0.38)
		gate.set_meta("gate_tween", tween)

static func _build_room_decals(root: Node3D) -> void:
	var colors := [Color(0.3, 0.82, 0.45, 0.24), Color(0.25, 0.62, 1.0, 0.22),
			Color(1.0, 0.25, 0.2, 0.2), Color(1.0, 0.58, 0.12, 0.2), Color(0.35, 0.88, 0.52, 0.2)]
	var titles := ["01  移动与购物车", "02  拿货与装车", "03  偷窃与基础战斗",
			"04  商品道具与角色技能", "05  综合结业小卖场"]
	for i in ROOM_CENTERS.size():
		_decal(root, "RoomFloor_%d" % (i + 1), Vector3(0, 0.015, ROOM_CENTERS[i]),
				Vector3(HALF_W * 2.0 - 1.0, 0.03, 26.0), colors[i])
		_sign(root, "RoomSign_%d" % (i + 1), Vector3(0, 3.35, ROOM_CENTERS[i] + 9.5), titles[i], colors[i].lightened(0.25))
	for z in [-2.0, -30.0, -58.0, -86.0, -122.0]:
		_decal(root, "Route_%s" % str(z), Vector3(0, 0.035, z), Vector3(4.6, 0.04, 5.0), Color(0.25, 0.9, 0.45, 0.38))

static func _build_room_one(root: Node3D) -> void:
	for i in 3:
		var x := -5.0 if i % 2 == 0 else 5.0
		var z := 5.0 - i * 4.3
		_pylon(root, "DrivePylon_%d" % i, Vector3(x, 0, z))
		_decal(root, "DriveGate_%d" % i, Vector3(x, 0.035, z), Vector3(4.0, 0.04, 2.4), Color(0.25, 0.9, 0.45, 0.4))
	_decal(root, "ParkingBox", Vector3(0, 0.035, -3.0), Vector3(5.0, 0.04, 4.0), Color(0.95, 0.72, 0.1, 0.4))

static func _build_room_two(root: Node3D) -> void:
	_shelf(root, "GoodsShelf_A", Vector3(-5.0, 0, -22.0), Color(0.25, 0.6, 0.95))
	_shelf(root, "GoodsShelf_B", Vector3(5.0, 0, -27.0), Color(0.25, 0.6, 0.95))
	_decal(root, "WrongGoodsPad", Vector3(0.0, 0.035, -24.5), Vector3(3.0, 0.04, 2.0), Color(1.0, 0.2, 0.15, 0.4))
	_sign(root, "WrongGoodsSign", Vector3(0.0, 2.2, -25.2), "故意拿错一次", Color(1.0, 0.28, 0.2), 48)
	_decal(root, "GoodsParking", Vector3(0, 0.035, -30.0), Vector3(5.5, 0.04, 3.5), Color(0.25, 0.62, 1.0, 0.38))

static func _build_room_three(root: Node3D) -> void:
	_decal(root, "CombatMat", Vector3(0, 0.035, -51.0), Vector3(18.0, 0.04, 13.0), Color(0.95, 0.18, 0.16, 0.22))
	for x in [-9.0, 9.0]:
		_wall(root, "CombatRail_%s" % str(x), Vector3(x, 0.6, -51.0), Vector3(0.3, 1.2, 14.0), Color(0.65, 0.18, 0.16))

static func _build_room_four(root: Node3D) -> void:
	var colors := [Color(1.0, 0.34, 0.08), Color(0.28, 0.62, 1.0),
			Color(0.94, 0.84, 0.58), Color(0.35, 0.9, 1.0)]
	var labels := ["推离", "湿滑", "遮挡", "定身"]
	for i in 4:
		var x := -9.0 + i * 6.0
		_decal(root, "LabPad_%d" % i, Vector3(x, 0.035, -70.0), Vector3(4.5, 0.04, 3.5), Color(colors[i], 0.35))
		_sign(root, "LabLabel_%d" % i, Vector3(x, 2.3, -72.0), labels[i], colors[i], 56)

static func _build_room_five(root: Node3D) -> void:
	_shelf(root, "FinalShelf", Vector3(-5.0, 0, -108.0), Color(0.25, 0.75, 0.42))
	_decal(root, "CheckoutZone", Vector3(0, 0.035, -124.0), Vector3(7.0, 0.04, 5.5), Color(0.18, 0.9, 0.35, 0.55))
	_sign(root, "CheckoutSign", Vector3(0, 3.0, -125.0), "结业收银区", Color(0.2, 0.9, 0.42), 70)

static func _shelf(root: Node3D, node_name: String, pos: Vector3, color: Color) -> void:
	_wall(root, node_name, Vector3(pos.x, 0.65, pos.z), Vector3(5.0, 1.3, 1.2), color.darkened(0.25))
	# 教学路线始终由北向南推进，陈列沿统一放在货架北侧，正对进入房间的玩家。
	_box(root, node_name + "_Ledge", Vector3(pos.x, 1.18, pos.z + 0.72), Vector3(5.0, 0.12, 0.45), color)

static func _pylon(root: Node3D, node_name: String, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.18
	cylinder.bottom_radius = 0.35
	cylinder.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.42, 0.08)
	cylinder.material = mat
	mesh.mesh = cylinder
	mesh.position = pos + Vector3.UP * 0.5
	root.add_child(mesh)

static func _wall(root: Node3D, node_name: String, pos: Vector3, size: Vector3,
		color := Color(0.55, 0.58, 0.64)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	body.position = pos
	root.add_child(body)
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	visual.mesh = mesh
	body.add_child(visual)
	return body

static func _box(root: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	_wall(root, node_name, pos, size, color)

static func _decal(root: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	root.add_child(mesh)

static func _sign(root: Node3D, node_name: String, pos: Vector3, value: String,
		color: Color, size := 74) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = value
	label.font = Catalog.ui_font_bold()
	label.font_size = size
	label.pixel_size = 0.0045 if value.length() > 9 else 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = color
	label.outline_size = 14
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position = pos
	root.add_child(label)

static func _make_grid() -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(-16, -130, 32, 148)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	return grid
