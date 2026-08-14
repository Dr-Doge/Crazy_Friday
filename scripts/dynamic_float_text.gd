class_name DynamicFloatText extends Label3D
## 世界拟声字幕：保留远近层次，但对透视缩小做部分补偿，避免第一人称近战时忽大忽小。

const REFERENCE_DISTANCE := 5.0
const MIN_SCALE := 0.72
const MAX_SCALE := 2.15
const DISTANCE_COMPENSATION := 0.58
const VISIBILITY_CHECK_INTERVAL := 0.06

var player_feedback := false
var _visibility_timer := 0.0

func _ready() -> void:
	add_to_group("dynamic_float_text")

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var distance := maxf(0.1, global_position.distance_to(cam.global_position))
	# 完全按距离等比放大会失去远近感；指数补偿让远处变大、近处收小，同时仍能辨认深度。
	var factor := pow(distance / REFERENCE_DISTANCE, DISTANCE_COMPENSATION)
	factor = clampf(factor, MIN_SCALE, MAX_SCALE)
	scale = Vector3.ONE * factor
	_visibility_timer -= delta
	if _visibility_timer <= 0.0:
		_visibility_timer = VISIBILITY_CHECK_INTERVAL
		_update_first_person_visibility(cam)

## 第一人称不再把附近所有世界字幕吸进HUD：非本人反馈必须真实位于视锥内，
## 且相机到字幕之间不能先撞上墙体/货架等场景碰撞。
func _update_first_person_visibility(cam: Camera3D) -> void:
	if Main.instance == null or Main.instance.cam_rig == null \
			or not Main.instance.cam_rig.is_first_person():
		visible = true
		return
	if player_feedback:
		visible = true
		return
	if cam.is_position_behind(global_position):
		visible = false
		return
	var screen := cam.unproject_position(global_position)
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-24.0)
	if not viewport_rect.has_point(screen):
		visible = false
		return
	var origin := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, global_position, Catalog.L_WORLD)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	visible = hit.is_empty() or origin.distance_to(hit["position"]) >= origin.distance_to(global_position) - 0.15
