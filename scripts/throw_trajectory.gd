class_name ThrowTrajectory extends Node3D
## 商品投掷瞄准线。用一组短圆柱拼成半透明白色抛物线，射线逐段截断于首个落点。

const SEGMENT_COUNT := 32
const STEP_TIME := 0.055
const LINE_RADIUS := 0.032
const MAX_TIME := SEGMENT_COUNT * STEP_TIME

var _segments: Array[MeshInstance3D] = []
var _outlines: Array[MeshInstance3D] = []
var _landing: MeshInstance3D
var _landing_outline: MeshInstance3D

func _ready() -> void:
	top_level = true
	visible = false
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 1
	var outline_material := material.duplicate() as StandardMaterial3D
	outline_material.albedo_color = Color(0.06, 0.08, 0.11, 0.42)
	outline_material.render_priority = 0

	var segment_mesh := CylinderMesh.new()
	segment_mesh.top_radius = LINE_RADIUS
	segment_mesh.bottom_radius = LINE_RADIUS
	segment_mesh.height = 1.0
	segment_mesh.radial_segments = 6
	segment_mesh.rings = 1
	segment_mesh.material = material
	var outline_mesh := CylinderMesh.new()
	outline_mesh.top_radius = LINE_RADIUS * 1.75
	outline_mesh.bottom_radius = LINE_RADIUS * 1.75
	outline_mesh.height = 1.0
	outline_mesh.radial_segments = 6
	outline_mesh.rings = 1
	outline_mesh.material = outline_material
	for i in SEGMENT_COUNT:
		var outline := MeshInstance3D.new()
		outline.name = "ArcOutline_%02d" % i
		outline.mesh = outline_mesh
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.visible = false
		add_child(outline)
		_outlines.append(outline)
		var segment := MeshInstance3D.new()
		segment.name = "Arc_%02d" % i
		segment.mesh = segment_mesh
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.visible = false
		add_child(segment)
		_segments.append(segment)

	var landing_mesh := SphereMesh.new()
	landing_mesh.radius = 0.085
	landing_mesh.height = 0.17
	landing_mesh.radial_segments = 12
	landing_mesh.rings = 6
	landing_mesh.material = material
	var landing_outline_mesh := SphereMesh.new()
	landing_outline_mesh.radius = 0.125
	landing_outline_mesh.height = 0.25
	landing_outline_mesh.radial_segments = 12
	landing_outline_mesh.rings = 6
	landing_outline_mesh.material = outline_material
	_landing_outline = MeshInstance3D.new()
	_landing_outline.name = "LandingOutline"
	_landing_outline.mesh = landing_outline_mesh
	_landing_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_landing_outline)
	_landing = MeshInstance3D.new()
	_landing.name = "LandingDot"
	_landing.mesh = landing_mesh
	_landing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_landing)

func hide_path() -> void:
	visible = false

func draw_path(origin: Vector3, velocity: Vector3, space: PhysicsDirectSpaceState3D,
		collision_mask: int, exclusions: Array[RID]) -> void:
	visible = true
	var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var point := origin
	var speed := velocity
	var used := 0
	for i in SEGMENT_COUNT:
		var next := point + speed * STEP_TIME + gravity * (0.5 * STEP_TIME * STEP_TIME)
		var query := PhysicsRayQueryParameters3D.create(point, next, collision_mask, exclusions)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			next = hit["position"]
		_place_segment(_outlines[i], point, next)
		_place_segment(_segments[i], point, next)
		used += 1
		point = next
		if not hit.is_empty():
			break
		speed += gravity * STEP_TIME
	for i in range(used, _segments.size()):
		_segments[i].visible = false
		_outlines[i].visible = false
	_landing.global_position = point
	_landing_outline.global_position = point
	_landing.visible = true
	_landing_outline.visible = true

func _place_segment(segment: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.002:
		segment.visible = false
		return
	segment.visible = true
	segment.global_position = (from + to) * 0.5
	segment.global_basis = Basis(Quaternion(Vector3.UP, delta / length)).scaled(Vector3(1.0, length, 1.0))
