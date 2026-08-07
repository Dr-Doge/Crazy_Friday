class_name CameraRig extends Node3D
## 第三人称跟随相机。本节点即 pivot,层级:CameraRig → SpringArm3D(防穿墙) → Camera3D。
##
## pivot 关闭物理插值:它在 _process 里用 lerp 自己平滑,再叠一层插值会与
## 抖动叠加导致画面发飘。

const DIST := 5.2               # 跟随距离
const SENS := 0.003             # 鼠标灵敏度
const PITCH_MIN := -1.15        # 俯角上限
const PITCH_MAX := 0.35         # 仰角上限
const FOLLOW_LAMBDA := 10.0     # 跟随平滑系数(越大越跟手)
const SHAKE_MAX := 1.2          # 震动强度上限
const SHAKE_DECAY := 2.5        # 震动每秒衰减
const SPAWN_POS := Vector3(15, 1.5, 19.5)

var yaw := 0.0
var pitch := -0.38
var shake := 0.0
var spring: SpringArm3D
var camera: Camera3D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = SPAWN_POS
	spring = SpringArm3D.new()
	spring.spring_length = DIST
	spring.collision_mask = Catalog.L_WORLD
	spring.margin = 0.3
	add_child(spring)
	camera = Camera3D.new()
	spring.add_child(camera)
	camera.make_current()

## 鼠标环绕视角
func look(rel: Vector2) -> void:
	yaw -= rel.x * SENS
	pitch = clampf(pitch - rel.y * SENS, PITCH_MIN, PITCH_MAX)

## 碰撞震动(可叠加,封顶)
func add_shake(v: float) -> void:
	shake = minf(shake + v, SHAKE_MAX)

## 镜头朝向的水平前向:徒步移动、肘击、掷水瓶都以此为准
func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD

## 每帧跟随目标点并施加震动
func follow(target: Vector3, delta: float) -> void:
	var k := 1.0 - exp(-FOLLOW_LAMBDA * delta)
	global_position = global_position.lerp(target, k)
	rotation = Vector3(pitch, yaw, 0)
	if shake > 0.002:
		var s := shake * shake
		rotation += Vector3(
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.055 * s,
				randf_range(-1, 1) * 0.04 * s)
		shake = maxf(0.0, shake - delta * SHAKE_DECAY)
