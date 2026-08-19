class_name RegionNpc extends Actor
## 不占参赛席位的卖场生态NPC。熊孩子高速乱跑冲撞；挡路大妈低速成群但保持间距。

enum Kind { KID, BLOCKING_GRANNY }

var kind := Kind.KID
var roam_bounds := Rect2()
var roam_target := Vector3.ZERO
var main
var _retarget_time := 0.0
var _impact_cd := 0.0
var _index := 0
var _mischief_timer := 0.0
var _charge_target: Node3D = null
var _charge_time := 0.0
var _aggro_target: Actor = null
var _aggro_time := 0.0
var _elbow_cd := 0.0

const KID_CHARGE_SPEED := 7.4
const GRANNY_AGGRO_TIME := 12.0
const GRANNY_AGGRO_SPEED := 3.0

func setup(owner_main, npc_kind: Kind, bounds: Rect2, index: int) -> void:
	main = owner_main
	kind = npc_kind
	roam_bounds = bounds
	_index = index
	team_id = -1
	var color := Color(1.0, 0.52, 0.08) if kind == Kind.KID else Color(0.42, 0.24, 0.52)
	var title := "熊孩子" if kind == Kind.KID else "挡路大妈"
	build_body(color, title, 1.05 if kind == Kind.KID else 1.55)
	name = "%s_%02d" % ["RegionKid" if kind == Kind.KID else "RegionGranny", index + 1]
	add_to_group("region_kids" if kind == Kind.KID else "region_grannies")
	_add_distinctive_visuals(color)
	_pick_target()
	_mischief_timer = 3.5 + float(index) * 1.35 + randf_range(0.0, 2.0)

func _add_distinctive_visuals(color: Color) -> void:
	if kind == Kind.KID:
		body_root.scale = Vector3(0.78, 0.78, 0.78)
		_add_sphere(Vector3(0, 1.22, 0), 0.34, Color(1.0, 0.78, 0.55))
		_add_box(Vector3(0, 1.46, 0), Vector3(0.62, 0.12, 0.52), Color(0.1, 0.75, 0.95))
		_add_box(Vector3(0, 0.72, 0.28), Vector3(0.58, 0.55, 0.22), Color(0.18, 0.82, 0.36))
		name_label.position.y = 1.75
		name_label.modulate = Color(1.0, 0.82, 0.2)
	else:
		body_root.scale = Vector3(1.3, 1.0, 1.08)
		_add_sphere(Vector3(0, 1.68, 0), 0.28, Color(0.86, 0.68, 0.54))
		_add_sphere(Vector3(0, 1.92, 0.12), 0.19, Color(0.72, 0.72, 0.76))
		_add_box(Vector3(0.52, 0.72, 0), Vector3(0.36, 0.58, 0.28), Color(0.82, 0.12, 0.42))
		name_label.position.y = 2.18
		name_label.modulate = Color(1.0, 0.62, 0.82)

func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	mesh_node.mesh = mesh
	mesh_node.position = pos
	body_root.add_child(mesh_node)

func _add_sphere(pos: Vector3, radius: float, color: Color) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _material(color)
	mesh_node.mesh = mesh
	mesh_node.position = pos
	body_root.add_child(mesh_node)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	return mat

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	if downed or main == null or main.game_over:
		apply_motion(delta, Vector3.ZERO, 0.0)
		return
	_retarget_time -= delta
	_impact_cd = maxf(0.0, _impact_cd - delta)
	_elbow_cd = maxf(0.0, _elbow_cd - delta)
	if kind == Kind.KID:
		_tick_kid_intent(delta)
	else:
		_tick_granny_aggro(delta)
	var special_target := is_instance_valid(_charge_target) or is_instance_valid(_aggro_target)
	if not special_target and (_retarget_time <= 0.0 or global_position.distance_to(roam_target) < 1.0):
		_pick_target()
	if is_instance_valid(_charge_target):
		roam_target = _charge_target.global_position
	elif is_instance_valid(_aggro_target):
		roam_target = _aggro_target.global_position
	var wish := roam_target - global_position
	wish.y = 0.0
	if wish.length() > 0.1:
		wish = (wish.normalized() + _separation() * 0.9).normalized()
	var speed := KID_CHARGE_SPEED if is_instance_valid(_charge_target) else \
			(5.2 if kind == Kind.KID else (GRANNY_AGGRO_SPEED if is_instance_valid(_aggro_target) else 0.72))
	hand_pose = "idle"
	apply_motion(delta, wish, speed)
	if kind == Kind.KID and _impact_cd <= 0.0:
		_try_kid_impact()
	elif kind == Kind.BLOCKING_GRANNY and is_instance_valid(_aggro_target) \
			and _elbow_cd <= 0.0 and global_position.distance_to(_aggro_target.global_position) < 1.35:
		_elbow_aggro_target()

func _tick_kid_intent(delta: float) -> void:
	if is_instance_valid(_charge_target):
		_charge_time -= delta
		if _charge_time <= 0.0:
			_charge_target = null
			_mischief_timer = randf_range(6.0, 10.0)
		return
	_mischief_timer -= delta
	if _mischief_timer > 0.0:
		return
	_charge_target = _nearest_competitor_target(16.0)
	if is_instance_valid(_charge_target):
		_charge_time = 3.6
		Main.float_text(self, global_position + Vector3.UP * 1.8,
				"看我创你!", Color(1.0, 0.45, 0.05), 58)
	else:
		_mischief_timer = 2.0

func _nearest_competitor_target(max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_distance
	for node in get_tree().get_nodes_in_group("characters"):
		if node == self or node is RegionNpc or not is_instance_valid(node):
			continue
		var actor := node as Actor
		var target: Node3D = actor.cart if actor.attached and is_instance_valid(actor.cart) else actor
		var distance := global_position.distance_to(target.global_position)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best

func _tick_granny_aggro(delta: float) -> void:
	if not is_instance_valid(_aggro_target):
		_aggro_target = null
		_aggro_time = 0.0
		return
	_aggro_time -= delta
	if _aggro_time <= 0.0 or _aggro_target.downed:
		_aggro_target = null
		_pick_target()

func _elbow_aggro_target() -> void:
	if not is_instance_valid(_aggro_target):
		return
	var direction := (_aggro_target.global_position - global_position)
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD
	_aggro_target.push_velocity += direction.normalized() * 4.2 + Vector3.UP * 0.7
	_aggro_target.add_imbalance(18.0, self)
	_aggro_target.on_elbowed(self)
	_elbow_cd = 1.05
	Main.float_text(_aggro_target, _aggro_target.global_position + Vector3.UP * 2.0,
			"大妈抱团追打! +18", Color(1.0, 0.35, 0.62), 62)

func add_imbalance(amount: float, source: Node = null) -> void:
	var attacker := _attacker_from(source)
	super.add_imbalance(amount, source)
	if kind == Kind.BLOCKING_GRANNY and amount > 0.0 and is_instance_valid(attacker):
		_alert_granny_group(attacker)

func _attacker_from(source: Node) -> Actor:
	if source is Cart:
		return (source as Cart).cart_owner as Actor
	if source is Actor and not source is RegionNpc:
		return source as Actor
	return null

func _alert_granny_group(attacker: Actor) -> void:
	for node in get_tree().get_nodes_in_group("region_grannies"):
		if not is_instance_valid(node):
			continue
		var granny := node as RegionNpc
		granny._aggro_target = attacker
		granny._aggro_time = GRANNY_AGGRO_TIME
		granny._elbow_cd = randf_range(0.15, 0.65)
	Main.float_text(self, global_position + Vector3.UP * 2.25,
			"姐妹们，有人欺负我!", Color(1.0, 0.38, 0.68), 68)

func _pick_target() -> void:
	if roam_bounds.size == Vector2.ZERO:
		return
	var margin := Vector2(minf(1.2, roam_bounds.size.x * 0.15), minf(1.2, roam_bounds.size.y * 0.15))
	roam_target = Vector3(
			randf_range(roam_bounds.position.x + margin.x, roam_bounds.end.x - margin.x),
			0.1,
			randf_range(roam_bounds.position.y + margin.y, roam_bounds.end.y - margin.y))
	_retarget_time = randf_range(1.1, 2.4) if kind == Kind.KID else randf_range(4.0, 8.0)

func _separation() -> Vector3:
	var result := Vector3.ZERO
	var group := "region_kids" if kind == Kind.KID else "region_grannies"
	var radius := 1.7 if kind == Kind.KID else 2.4
	for node in get_tree().get_nodes_in_group(group):
		if node == self or not is_instance_valid(node):
			continue
		var away := global_position - (node as Node3D).global_position
		away.y = 0.0
		var distance := away.length()
		if distance > 0.05 and distance < radius:
			result += away.normalized() * (1.0 - distance / radius)
	return result.limit_length(1.0)

func _try_kid_impact() -> void:
	for node in get_tree().get_nodes_in_group("characters"):
		if node == self or node is RegionNpc or not is_instance_valid(node):
			continue
		var actor := node as Actor
		if global_position.distance_to(actor.global_position) < 1.05:
			var direction := (actor.global_position - global_position).normalized()
			actor.push_velocity += direction * 4.8
			actor.add_imbalance(14.0, self)
			_impact_cd = 1.0
			_charge_target = null
			_mischief_timer = randf_range(7.0, 11.0)
			Main.float_text(actor, actor.global_position + Vector3.UP * 2.0,
					"熊孩子创飞!", Color(1.0, 0.55, 0.08), 62)
			return
	for node in get_tree().get_nodes_in_group("carts"):
		if not is_instance_valid(node):
			continue
		var cart := node as Cart
		if global_position.distance_to(cart.global_position) < 1.25:
			var direction := (cart.global_position - global_position).normalized()
			cart.apply_central_impulse(direction * 92.0 + Vector3.UP * 18.0)
			_impact_cd = 1.0
			_charge_target = null
			_mischief_timer = randf_range(7.0, 11.0)
			return
