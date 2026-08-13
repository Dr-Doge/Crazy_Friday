class_name CameraRig extends Node3D
## 第三人称跟随相机。本节点即 pivot,层级:CameraRig → SpringArm3D(防穿墙) → Camera3D。
##
## pivot 关闭物理插值:它在 _process 里用 lerp 自己平滑,再叠一层插值会与
## 抖动叠加导致画面发飘。

const DIST := 4.8               # 更贴近角色的越肩距离，参考用户给出的第三人称构图
const SHOULDER_OFFSET := 0.78   # 拉近后略收肩位，避免角色被挤到画面边缘
const AIM_HEIGHT_OFFSET := 0.55 # 将角色压到画面更下方，拉开角色与准星的屏幕距离
const FOV := 72.0               # 常见第三人称动作游戏的中等广角
const AIM_DISTANCE := 80.0      # 准星未命中实体时的远端会聚距离
const MIN_WORLD_AIM_DISTANCE := 10.0 # 近处场景不再把会聚点吸回角色脚边
## 近景视觉 LOD：仅作用于加入 camera_near_lod 组的场景网格，碰撞体始终保留。
const NEAR_LOD_HIDE_DISTANCE := 0.62
const NEAR_LOD_SHOW_DISTANCE := 0.92
const NEAR_LOD_SCAN_INTERVAL := 0.06
const SENS := 0.003             # 鼠标灵敏度
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

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = SPAWN_POS
	spring = SpringArm3D.new()
	spring.spring_length = DIST
	spring.position = Vector3(SHOULDER_OFFSET, AIM_HEIGHT_OFFSET, 0.0)
	spring.collision_mask = Catalog.L_WORLD
	spring.margin = 0.3
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = FOV
	spring.add_child(camera)
	camera.make_current()

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

## 每帧跟随目标点并施加震动
func follow(target: Vector3, delta: float) -> void:
	var k := 1.0 - exp(-FOLLOW_LAMBDA * delta)
	global_position = global_position.lerp(target, k)
	rotation = Vector3(pitch, yaw, 0)
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

## 用网格局部包围盒到镜头的最近距离做近景LOD。大型墙面/长货架不能只量中心点，
## 否则镜头贴住边缘时中心仍很远，遮挡永远不会被隐藏。
func _update_near_lod() -> void:
	if camera == null:
		return
	for node in get_tree().get_nodes_in_group("camera_near_lod"):
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
		if node.visible and distance < NEAR_LOD_HIDE_DISTANCE:
			node.visible = false
		elif not node.visible and distance > NEAR_LOD_SHOW_DISTANCE:
			node.visible = true
