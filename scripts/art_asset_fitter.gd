class_name ArtAssetFitter extends RefCounted
## 将已经烘焙的美术prefab归一到玩法白盒。
## 商品采用等比内接；货架、冰柜与灯管按白盒宽度等比缩放，再沿长度重复排列。
const EPS := 0.0001

static var _bounds_cache := {}

static func create_product_visual(item_id: String, target_size: Vector3) -> Node3D:
	var path := ArtAssetCatalog.item_model_path(item_id)
	if path == "":
		return null
	var centered := _instantiate_centered(path)
	if centered == null:
		return null
	var source_size: Vector3 = centered.get_meta("source_size", Vector3.ONE)
	var ratio := minf(target_size.x / maxf(source_size.x, EPS),
			minf(target_size.y / maxf(source_size.y, EPS),
			target_size.z / maxf(source_size.z, EPS)))
	centered.scale = Vector3.ONE * ratio
	centered.name = "ArtModel"
	centered.set_meta("art_item_id", item_id)
	centered.set_meta("art_target_size", target_size)
	centered.set_meta("art_uniform_scale", ratio)
	# prefab自带材质绑定器；此处在进入SceneTree前同步应用，保证首帧即有贴图。
	apply_material_profile(centered, ArtAssetCatalog.item_material_profile(item_id))
	return centered

static func create_modular_line(path: String, target_size: Vector3,
		material_profile := {}) -> Node3D:
	if path == "":
		return null
	var probe := _instantiate_centered(path, true)
	if probe == null:
		return null
	var source_size: Vector3 = probe.get_meta("source_size", Vector3.ONE)
	# 探针从未进入SceneTree，立即释放即可；避免大量货架拼接时等待帧末回收。
	probe.free()
	# 以白盒宽度(Z)为唯一缩放基准：XYZ始终等比，不再拉伸单个美术资产。
	var uniform_scale := target_size.z / maxf(source_size.z, EPS)
	var natural_length := source_size.x * uniform_scale
	if natural_length <= EPS:
		return null
	var count := maxi(1, int(ceil(target_size.x / natural_length)))
	# 多段时让首尾边缘精确贴合白盒，中间允许轻微重叠；模型本身不发生形变。
	var step := 0.0 if count == 1 else \
		maxf(0.0, (target_size.x - natural_length) / float(count - 1))

	var result := Node3D.new()
	result.name = "ArtModules"
	for i in count:
		var module := _instantiate_centered(path, true)
		if module == null:
			continue
		module.name = "Module_%02d" % (i + 1)
		module.scale = Vector3.ONE * uniform_scale
		module.position.x = 0.0 if count == 1 else \
			-target_size.x * 0.5 + natural_length * 0.5 + step * float(i)
		apply_material_profile(module, material_profile)
		result.add_child(module)
	result.set_meta("art_asset_path", path)
	result.set_meta("art_target_size", target_size)
	result.set_meta("art_module_count", count)
	result.set_meta("art_uniform_scale", uniform_scale)
	result.set_meta("art_module_step", step)
	result.set_meta("art_no_axis_deform", true)
	return result

static func create_contained_visual(path: String, target_size: Vector3,
		material_profile := {}) -> Node3D:
	var centered := _instantiate_centered(path)
	if centered == null:
		return null
	var source_size: Vector3 = centered.get_meta("source_size", Vector3.ONE)
	var ratio := minf(target_size.x / maxf(source_size.x, EPS),
			minf(target_size.y / maxf(source_size.y, EPS),
			target_size.z / maxf(source_size.z, EPS)))
	centered.scale = Vector3.ONE * ratio
	apply_material_profile(centered, material_profile)
	return centered

## 烘焙工具专用：从原始模型生成居中、定向且材质完整的可保存节点。
static func create_baked_prefab(source_path: String, profile := {},
		orient_long_axis := false) -> Node3D:
	var centered := _instantiate_centered(source_path, orient_long_axis)
	if centered == null:
		return null
	centered.set_meta("source_asset_path", source_path)
	centered.set_meta("art_prefab", true)
	return centered

static func first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := first_mesh(child)
		if found != null:
			return found
	return null

static func mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(root, out)
	return out

static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)

static func _instantiate_centered(path: String, orient_long_axis := false) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var imported := packed.instantiate()
	if not (imported is Node3D):
		imported.free()
		return null
	_disable_imported_gameplay_nodes(imported)
	var orientation := Node3D.new()
	orientation.name = "SourceOrientation"
	orientation.add_child(imported)
	var bounds := _node_bounds(orientation)
	if orient_long_axis and bounds.size.z > bounds.size.x:
		orientation.rotation.y = PI * 0.5
		bounds = _node_bounds(orientation)
	if bounds.size.x <= EPS or bounds.size.y <= EPS or bounds.size.z <= EPS:
		orientation.free()
		return null
	var centered := Node3D.new()
	centered.name = "CenteredAsset"
	centered.add_child(orientation)
	orientation.position = -bounds.get_center()
	centered.set_meta("source_size", bounds.size)
	centered.set_meta("art_asset_path", path)
	return centered

static func _disable_imported_gameplay_nodes(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is Light3D or node is Camera3D:
		(node as Node3D).visible = false
	for child in node.get_children():
		_disable_imported_gameplay_nodes(child)

static func _node_bounds(root: Node) -> AABB:
	var state := {"has":false, "bounds":AABB()}
	_append_mesh_bounds(root, Transform3D.IDENTITY, state)
	return state["bounds"] if bool(state["has"]) else AABB()

static func _append_mesh_bounds(node: Node, parent_xform: Transform3D,
		state: Dictionary) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var transformed := _transform_aabb((node as MeshInstance3D).get_aabb(), xform)
		if not bool(state["has"]):
			state["bounds"] = transformed
			state["has"] = true
		else:
			state["bounds"] = (state["bounds"] as AABB).merge(transformed)
	for child in node.get_children():
		_append_mesh_bounds(child, xform, state)

static func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
	var first := true
	var out := AABB()
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]:
				var point := xform * Vector3(x, y, z)
				if first:
					out = AABB(point, Vector3.ZERO)
					first = false
				else:
					out = out.expand(point)
	return out

static func apply_material_profile(root: Node, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	var albedo := _load_texture(str(profile.get("albedo", "")))
	var albedo_sequence := _load_texture_sequence(
		str(profile.get("albedo_sequence_dir", "")),
		str(profile.get("albedo_sequence_suffix", "")))
	var metallic := _load_texture(str(profile.get("metallic", "")))
	var normal := _load_texture(str(profile.get("normal", "")))
	var roughness := _load_texture(str(profile.get("roughness", "")))
	var surface_index := 0
	for mesh_instance in mesh_instances(root):
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var active := mesh_instance.get_active_material(surface)
			var mat := active.duplicate(true) as StandardMaterial3D if active is StandardMaterial3D else StandardMaterial3D.new()
			if not albedo_sequence.is_empty():
				mat.albedo_texture = albedo_sequence[surface_index % albedo_sequence.size()]
			elif albedo != null:
				mat.albedo_texture = albedo
			if metallic != null:
				mat.metallic_texture = metallic
				mat.metallic = 1.0
			if normal != null:
				mat.normal_enabled = true
				mat.normal_texture = normal
			if roughness != null:
				mat.roughness_texture = roughness
				mat.roughness = 1.0
			else:
				mat.roughness = float(profile.get("roughness_value", mat.roughness))
			if metallic == null:
				mat.metallic = float(profile.get("metallic_value", mat.metallic))
			if bool(profile.get("emission", false)) and albedo != null:
				mat.emission_enabled = true
				mat.emission_texture = albedo
				mat.emission_energy_multiplier = 2.4
			mesh_instance.set_surface_override_material(surface, mat)
			surface_index += 1

static func _load_texture(relative_path: String) -> Texture2D:
	if relative_path == "":
		return null
	var path := ArtAssetCatalog.SOURCE_ROOT + "/" + relative_path
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func _load_texture_sequence(relative_dir: String, suffix: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if relative_dir == "":
		return out
	var dir := ArtAssetCatalog.SOURCE_ROOT + "/" + relative_dir
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for file_name in files:
		var file := str(file_name)
		if suffix != "" and not file.to_lower().ends_with(suffix.to_lower()):
			continue
		var texture := load(dir + "/" + file) as Texture2D
		if texture != null:
			out.append(texture)
	return out
