extends SceneTree
## Read-only scene audit used to catch cameras/lights accidentally imported with art assets.

const LEVEL_PATH := "res://scenes/New_Level.tscn"

func _initialize() -> void:
	call_deferred("_audit")

func _audit() -> void:
	var packed := load(LEVEL_PATH) as PackedScene
	if packed == null:
		push_error("Cannot load " + LEVEL_PATH)
		quit(1)
		return
	var root := packed.instantiate()
	var cameras: Array[Camera3D] = []
	var lights: Array[Light3D] = []
	_collect(root, cameras, lights)
	var imported_cameras := 0
	var imported_lights := 0
	for camera in cameras:
		if _is_inside_art_prefab(camera):
			imported_cameras += 1
	for light in lights:
		if _is_inside_art_prefab(light):
			imported_lights += 1
	print("RENDER_NODE_AUDIT cameras=%d lights=%d imported_cameras=%d imported_lights=%d" % [
		cameras.size(), lights.size(), imported_cameras, imported_lights])
	for camera in cameras:
		print("CAMERA current=%s path=%s" % [camera.current, root.get_path_to(camera)])
	for light in lights:
		print("LIGHT energy=%.3f visible=%s path=%s" % [
			light.light_energy, light.is_visible_in_tree(), root.get_path_to(light)])
	root.free()
	quit(0)

func _is_inside_art_prefab(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor.has_meta("art_prefab"):
			return true
		cursor = cursor.get_parent()
	return false

func _collect(node: Node, cameras: Array[Camera3D], lights: Array[Light3D]) -> void:
	if node is Camera3D:
		cameras.append(node as Camera3D)
	elif node is Light3D:
		lights.append(node as Light3D)
	for child in node.get_children():
		_collect(child, cameras, lights)
