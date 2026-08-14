class_name CameraRig extends Node3D
## 徒步第一人称 / 驾车第三人称混合相机。
## 本节点即 pivot,层级:CameraRig → SpringArm3D(防穿墙) → Camera3D。
##
## pivot 关闭物理插值:它在 _process 里用 lerp 自己平滑,再叠一层插值会与
## 抖动叠加导致画面发飘。

const DIST := 3.0               # 常态3米近景，让角色占据左下角主要前景
const SHOULDER_OFFSET := 0.90   # 相机位于角色右后方，角色自然落在画面左侧
const HEIGHT_OFFSET := 0.68     # 抬高视点，将角色压到画面左下方
const FOV := 69.0
const THROW_AIM_DIST := 2.0     # 按住右键时收近至约2米右肩视角
const THROW_AIM_SHOULDER := 1.18
const THROW_AIM_HEIGHT := 0.75
const THROW_AIM_FOV := 62.0
const FIRST_PERSON_LENGTH := 0.05
const FIRST_PERSON_OFFSET := Vector3(0.0, 0.18, 0.0)
const FIRST_PERSON_FOV := 75.0
const FIRST_PERSON_ZOOM_FOV := 58.0
const FIRST_PERSON_ELBOW_FIST_SCALE := 2.35
const AIM_BLEND_LAMBDA := 13.0
const AIM_DISTANCE := 80.0      # 准星未命中实体时的远端会聚距离
const MIN_WORLD_AIM_DISTANCE := 10.0 # 近处场景不再把会聚点吸回角色脚边
## 第三人称告示牌 LOD：只处理头顶悬浮分区牌；第一人称完全停用。
const NEAR_LOD_HIDE_DISTANCE := 2.0
const NEAR_LOD_SHOW_DISTANCE := 2.65
const NEAR_LOD_SCAN_INTERVAL := 0.06
const SENS := 0.0025            # 鼠标灵敏度：降低约17%，第一人称精确瞄准更稳定
const PITCH_MIN := -1.15        # 俯角上限
const PITCH_MAX := 0.35         # 仰角上限
const FOLLOW_LAMBDA := 10.0     # 跟随平滑系数(越大越跟手)
const SHAKE_MAX := 1.2          # 震动强度上限
const SHAKE_DECAY := 2.5        # 震动每秒衰减
const SPAWN_POS := Vector3(MapLayout.PLAYER_SPAWN.x, 1.5, MapLayout.PLAYER_SPAWN.z)

var yaw := 0.0
var pitch := -0.30
var shake := 0.0
var spring: SpringArm3D
var camera: Camera3D
var _near_lod_timer := 0.0
var _throw_aiming := false
var _first_person := false
var _trajectory: ThrowTrajectory
var _fp_hands: Node3D
var _fp_arm_l: Node3D
var _fp_arm_r: Node3D
var _fp_fist_l: MeshInstance3D
var _fp_fist_r: MeshInstance3D
var _fp_held_root: Node3D
var _fp_held_signature := ""
var _fp_hidden_world_items: Array[Item] = []
var _fp_hand_time := 0.0
var _fp_hand_color := Color.TRANSPARENT

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = SPAWN_POS
	spring = SpringArm3D.new()
	spring.spring_length = DIST
	spring.position = Vector3(SHOULDER_OFFSET, HEIGHT_OFFSET, 0.0)
	spring.collision_mask = Catalog.L_WORLD
	spring.margin = 0.3
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = FOV
	spring.add_child(camera)
	camera.make_current()
	_trajectory = ThrowTrajectory.new()
	_trajectory.name = "ThrowTrajectory"
	add_child(_trajectory)
	_build_first_person_hands()

func _build_first_person_hands() -> void:
	_fp_hands = Node3D.new()
	_fp_hands.name = "FirstPersonHands"
	_fp_hands.visible = false
	camera.add_child(_fp_hands)
	_fp_arm_l = _make_first_person_arm("LeftArm")
	_fp_arm_r = _make_first_person_arm("RightArm")
	_fp_fist_l = _fp_arm_l.get_node("Fist") as MeshInstance3D
	_fp_fist_r = _fp_arm_r.get_node("Fist") as MeshInstance3D
	_fp_hands.add_child(_fp_arm_l)
	_fp_hands.add_child(_fp_arm_r)
	_fp_held_root = Node3D.new()
	_fp_held_root.name = "HeldItems"
	_fp_hands.add_child(_fp_held_root)

func _make_first_person_arm(arm_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = arm_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.75, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	var forearm := MeshInstance3D.new()
	forearm.name = "Forearm"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.048
	capsule.height = 0.34
	capsule.material = mat
	forearm.mesh = capsule
	forearm.position.y = -0.12
	forearm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(forearm)
	var fist := MeshInstance3D.new()
	fist.name = "Fist"
	var sphere := SphereMesh.new()
	sphere.radius = 0.078
	sphere.height = 0.156
	sphere.material = mat
	fist.mesh = sphere
	fist.position.y = 0.075
	fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fist)
	return root

func _set_first_person_hand_color(color: Color) -> void:
	if color.is_equal_approx(_fp_hand_color):
		return
	_fp_hand_color = color
	for arm in [_fp_arm_l, _fp_arm_r]:
		for child in arm.get_children():
			if child is MeshInstance3D:
				var mesh := (child as MeshInstance3D).mesh
				if mesh != null and mesh.material is StandardMaterial3D:
					(mesh.material as StandardMaterial3D).albedo_color = color.lightened(0.3)

## 第一人称专用手臂挂在相机下，沿用角色的动作状态，但重新编排在屏幕下缘的可读范围内。
func update_first_person_hands(actor: Player, delta: float) -> void:
	if _fp_hands == null:
		return
	_fp_hands.visible = _first_person and actor != null and not actor.downed and not actor.finished
	if not _fp_hands.visible:
		_clear_first_person_held_items()
		return
	_set_first_person_hand_color(actor.avatar_color)
	_update_first_person_held_items(actor, delta)
	_fp_hand_time += delta * clampf(3.0 + Vector2(actor.velocity.x, actor.velocity.z).length() * 1.5, 3.0, 10.0)
	var bob := sin(_fp_hand_time) * 0.018
	# 双臂固定在中央交互提示的左右下方，为准星和文字留出中间通道。
	var lp := Vector3(-0.40, -0.49 + bob, -0.90)
	var rp := Vector3(0.40, -0.49 - bob, -0.90)
	var lr := Vector3(0.18, 0.0, -0.34)
	var rr := Vector3(0.18, 0.0, 0.34)
	match actor.hand_pose:
		"channel":
			var rummage := sin(_fp_hand_time * 2.5) * 0.09
			lp = Vector3(-0.31, -0.42, -0.90 + rummage)
			rp = Vector3(0.31, -0.42, -0.90 - rummage)
			lr.z = -0.16
			rr.z = 0.16
		"carry":
			lp = Vector3(-0.30, -0.49, -0.88)
			rp = Vector3(0.30, -0.49, -0.88)
			lr.z = -0.12
			rr.z = 0.12
		"brace":
			lp = Vector3(0.12, -0.26, -0.74)
			rp = Vector3(-0.12, -0.22, -0.72)
			lr.z = -1.0
			rr.z = 1.0
		"speed":
			lp = Vector3(-0.42, -0.48, -0.78)
			rp = Vector3(0.42, -0.48, -0.78)
	if actor._elbow_anim > 0.0:
		var elbow := clampf(actor._elbow_anim, 0.0, 1.0)
		if actor._elbow_anim > 0.95:
			rp = rp.lerp(Vector3(0.50, -0.46, -0.70), elbow)
		else:
			rp = rp.lerp(Vector3(0.08, -0.12, -1.14), elbow)
			rr.x = -0.86
		lp += Vector3(-0.08, -0.08, 0.08) * elbow
	var k := 1.0 - exp(-22.0 * delta)
	_fp_arm_l.position = _fp_arm_l.position.lerp(lp, k)
	_fp_arm_r.position = _fp_arm_r.position.lerp(rp, k)
	_fp_arm_l.rotation = _fp_arm_l.rotation.lerp(lr, k)
	_fp_arm_r.rotation = _fp_arm_r.rotation.lerp(rr, k)
	# 夸张的是拳头本身：前送阶段最多放大到2.35倍，胳膊保持粗细稳定。
	var fist_scale := lerpf(1.0, FIRST_PERSON_ELBOW_FIST_SCALE,
			clampf(actor._elbow_anim, 0.0, 1.0))
	_fp_fist_r.scale = _fp_fist_r.scale.lerp(Vector3.ONE * fist_scale, k)
	_fp_fist_l.scale = _fp_fist_l.scale.lerp(Vector3.ONE, k)
	_fp_arm_r.scale = _fp_arm_r.scale.lerp(Vector3.ONE, k)
	_fp_arm_l.scale = _fp_arm_l.scale.lerp(Vector3.ONE, k)

## 手中真实商品仍由角色持有并参与权威状态；第一人称只隐藏本机世界模型，
## 用稳定的相机内复制体展示。这样转身、上下坡和网络插值都不会让商品在眼前乱甩。
func _update_first_person_held_items(actor: Player, delta: float) -> void:
	var ids: Array[String] = []
	for item in actor.held:
		if is_instance_valid(item):
			ids.append(str(item.get_instance_id()))
	var signature := ",".join(ids)
	if signature != _fp_held_signature:
		_rebuild_first_person_held_items(actor)
	if _fp_held_root == null:
		return
	# 商品中心与两颗圆球拳头基本同高，视觉上由双手夹持，而非挂在前臂末端。
	var low_pose := Vector3(0.0, -0.415, -0.94)
	# 只保留非常轻微的呼吸起伏，不继承世界坐标抖动；搜货动作则略微前探以贴合双手。
	low_pose.y += sin(_fp_hand_time * 0.65) * 0.004
	if actor.hand_pose == "channel":
		low_pose += Vector3(0.0, 0.035, -0.04)
	var k := 1.0 - exp(-18.0 * delta)
	_fp_held_root.position = _fp_held_root.position.lerp(low_pose, k)
	_fp_held_root.rotation = _fp_held_root.rotation.lerp(Vector3(-0.10, 0.06, 0.0), k)

func _rebuild_first_person_held_items(actor: Player) -> void:
	_clear_first_person_held_items()
	if _fp_held_root == null:
		return
	var valid_items: Array[Item] = []
	var valid_ids: Array[String] = []
	for item in actor.held:
		if is_instance_valid(item):
			valid_items.append(item)
			valid_ids.append(str(item.get_instance_id()))
			item.visible = false
			item.set_meta("first_person_view_hidden", true)
			_fp_hidden_world_items.append(item)
	_fp_held_signature = ",".join(valid_ids)
	for i in valid_items.size():
		var item := valid_items[i]
		var visual := MeshInstance3D.new()
		visual.name = "Held_" + item.item_id
		var box := BoxMesh.new()
		var longest := maxf(item.box_size.x, maxf(item.box_size.y, item.box_size.z))
		var fit_scale := 0.24 / maxf(longest, 0.01)
		box.size = item.box_size * fit_scale
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(Catalog.ITEMS[item.item_id]["color"])
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 9
		box.material = mat
		visual.mesh = box
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.position.x = (float(i) - (valid_items.size() - 1) * 0.5) * 0.22
		visual.rotation.y = (float(i) - 0.5) * 0.08 if valid_items.size() > 1 else 0.0
		_fp_held_root.add_child(visual)

func _clear_first_person_held_items() -> void:
	for item in _fp_hidden_world_items:
		if is_instance_valid(item):
			item.visible = true
			item.remove_meta("first_person_view_hidden")
	_fp_hidden_world_items.clear()
	if _fp_held_root != null:
		for child in _fp_held_root.get_children():
			_fp_held_root.remove_child(child)
			child.queue_free()
	_fp_held_signature = ""

func first_person_hands_visible() -> bool:
	return _fp_hands != null and _fp_hands.visible

func first_person_held_item_count() -> int:
	return _fp_held_root.get_child_count() if _fp_held_root != null else 0

func set_throw_aiming(active: bool) -> void:
	_throw_aiming = active
	if not active and _trajectory != null:
		_trajectory.hide_path()

## 上下车属于视角范式切换，位置与FOV直接落到目标值，不拖着第三人称镜头穿过角色身体。
func set_first_person(active: bool) -> void:
	if _first_person == active:
		return
	_first_person = active
	if _fp_hands != null:
		_fp_hands.visible = active
	if not active:
		_clear_first_person_held_items()
	else:
		_restore_near_lod()
	if active:
		spring.spring_length = FIRST_PERSON_LENGTH
		spring.position = FIRST_PERSON_OFFSET
		camera.fov = FIRST_PERSON_FOV
	else:
		spring.spring_length = DIST
		spring.position = Vector3(SHOULDER_OFFSET, HEIGHT_OFFSET, 0.0)
		camera.fov = FOV

func is_first_person() -> bool:
	return _first_person

func update_throw_preview(origin: Vector3, velocity: Vector3, exclusions: Array[RID]) -> void:
	if not _throw_aiming or _trajectory == null:
		return
	_trajectory.draw_path(origin, velocity, get_world_3d().direct_space_state,
			Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART, exclusions)

func hide_throw_preview() -> void:
	if _trajectory != null:
		_trajectory.hide_path()

func throw_preview_visible() -> bool:
	return _trajectory != null and _trajectory.visible

## 鼠标环绕视角
func look(rel: Vector2) -> void:
	yaw -= rel.x * SENS
	pitch = clampf(pitch - rel.y * SENS, PITCH_MIN, PITCH_MAX)

## 碰撞震动(可叠加,封顶)
func add_shake(v: float) -> void:
	shake = minf(shake + v, SHAKE_MAX)

## 镜头朝向的水平前向:徒步移动与肘击使用；商品投掷改用 aim_direction()。
func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD

## 屏幕中心白点准星对应的三维射线，包含镜头俯仰。
func aim_direction() -> Vector3:
	if camera != null:
		var center := get_viewport().get_visible_rect().size * 0.5
		return camera.project_ray_normal(center).normalized()
	return forward()

## 从角色/手部位置朝准星实际指向点会聚。相机射线先决定目标点，再从投掷起点
## 重新计算方向，解决越肩相机与角色不共轴时近距离投掷偏靶的问题。
func aim_direction_from(origin: Vector3, exclusions: Array[RID] = []) -> Vector3:
	if camera == null or not is_inside_tree():
		return forward()
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(viewport_center)
	var ray_dir := camera.project_ray_normal(viewport_center).normalized()
	var aim_point := ray_origin + ray_dir * AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, aim_point,
			Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART, exclusions)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_point: Vector3 = hit["position"]
		var collider: Object = hit.get("collider")
		# 近距离角色仍可精确瞄准；近处场景/购物车仍会实际挡住商品，
		# 但不再把投掷方向向角色脚边拖低。
		if collider is Actor or hit_point.distance_to(origin) >= MIN_WORLD_AIM_DISTANCE:
			aim_point = hit_point
		else:
			aim_point = ray_origin + ray_dir * MIN_WORLD_AIM_DISTANCE
	var converged := aim_point - origin
	return converged.normalized() if converged.length() > 0.01 else ray_dir

## 返回屏幕中心射线首先命中的货架商品。场景也参与遮挡，不能隔着货架或墙选货。
func aimed_shelf_item(max_distance := 8.0) -> Item:
	if camera == null or not is_inside_tree():
		return null
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_end := ray_origin + camera.project_ray_normal(center).normalized() * max_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end,
			Catalog.L_WORLD | Catalog.L_ITEM)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") is Item:
		var item := hit["collider"] as Item
		if item.state == Item.ItemState.SHELVED:
			return item
	return null

## 每帧跟随目标点并施加震动
func follow(target: Vector3, delta: float) -> void:
	var k := 1.0 - exp(-FOLLOW_LAMBDA * delta)
	global_position = global_position.lerp(target, k)
	rotation = Vector3(pitch, yaw, 0)
	var aim_k := 1.0 - exp(-AIM_BLEND_LAMBDA * delta)
	var wanted_length := DIST
	var wanted_offset := Vector3(SHOULDER_OFFSET, HEIGHT_OFFSET, 0.0)
	var wanted_fov := FOV
	if _first_person:
		wanted_length = FIRST_PERSON_LENGTH
		wanted_offset = FIRST_PERSON_OFFSET
		wanted_fov = FIRST_PERSON_ZOOM_FOV if _throw_aiming else FIRST_PERSON_FOV
	elif _throw_aiming:
		wanted_length = THROW_AIM_DIST
		wanted_offset = Vector3(THROW_AIM_SHOULDER, THROW_AIM_HEIGHT, 0.0)
		wanted_fov = THROW_AIM_FOV
	spring.spring_length = lerpf(spring.spring_length, wanted_length, aim_k)
	spring.position = spring.position.lerp(wanted_offset, aim_k)
	camera.fov = lerpf(camera.fov, wanted_fov, aim_k)
	_near_lod_timer -= delta
	if _near_lod_timer <= 0.0:
		_near_lod_timer = NEAR_LOD_SCAN_INTERVAL
		_update_near_lod()
	if shake > 0.002:
		var s := shake * shake
		rotation += Vector3(
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.04 * s)
		shake = maxf(0.0, shake - delta * SHAKE_DECAY)

## 用告示牌局部包围盒到镜头的最近距离做第三人称遮挡规避。
func _update_near_lod() -> void:
	if camera == null:
		return
	if _first_person:
		_restore_near_lod()
		return
	for node in get_tree().get_nodes_in_group("third_person_sign_lod"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var half: Vector3 = node.get_meta("camera_lod_half_extents", Vector3.ZERO)
		if half == Vector3.ZERO:
			continue
		var local: Vector3 = node.to_local(camera.global_position)
		var outside := Vector3(
				maxf(absf(local.x) - half.x, 0.0),
				maxf(absf(local.y) - half.y, 0.0),
				maxf(absf(local.z) - half.z, 0.0))
		var distance := outside.length()
		var hide_distance: float = node.get_meta("camera_lod_hide_distance", NEAR_LOD_HIDE_DISTANCE)
		var show_distance: float = node.get_meta("camera_lod_show_distance", NEAR_LOD_SHOW_DISTANCE)
		if node.visible and distance < hide_distance:
			node.set_meta("camera_lod_hidden", true)
			node.visible = false
		elif bool(node.get_meta("camera_lod_hidden", false)) and distance > show_distance:
			node.set_meta("camera_lod_hidden", false)
			node.visible = true

func _restore_near_lod() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("third_person_sign_lod"):
		if is_instance_valid(node) and bool(node.get_meta("camera_lod_hidden", false)):
			node.set_meta("camera_lod_hidden", false)
			node.visible = true
