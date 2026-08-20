extends SceneTree
## 将原始FBX/GLB/Blend和分离贴图一次性烘焙为Godot可直接拖入的TS CN prefab。

const LIBRARY_PATH := "res://scenes/Art_Asset_Library.tscn"

func _initialize() -> void:
	call_deferred("_bake_all")

func _bake_all() -> void:
	_make_dir(ArtAssetCatalog.ITEM_PREFAB_ROOT)
	_make_dir(ArtAssetCatalog.FIXTURE_PREFAB_ROOT)
	_make_dir(ArtAssetCatalog.LIBRARY_PREFAB_ROOT)
	var saved_items: Array[String] = []
	var saved_fixtures: Array[String] = []
	var saved_library_assets: Array[Dictionary] = []
	var failures: Array[String] = []
	var gameplay_sources := {}

	for item_id in ArtAssetCatalog.source_item_ids():
		var source_path := ArtAssetCatalog.item_source_model_path(item_id)
		var output_path := ArtAssetCatalog.ITEM_PREFAB_ROOT + "/" + item_id + ".tscn"
		gameplay_sources[source_path] = true
		if _bake_one(source_path, output_path, ArtAssetCatalog.item_material_profile(item_id),
				false, {"item_id":item_id, "asset_kind":"item"}):
			saved_items.append(item_id)
		else:
			failures.append("item:%s (%s)" % [item_id, source_path])

	for kind in ArtAssetCatalog.fixture_kinds():
		var source_path := ArtAssetCatalog.fixture_source_model_path(kind)
		var output_path := ArtAssetCatalog.FIXTURE_PREFAB_ROOT + "/" + kind + ".tscn"
		gameplay_sources[source_path] = true
		if _bake_one(source_path, output_path, ArtAssetCatalog.material_profile(kind),
				true, {"fixture_kind":kind, "asset_kind":"fixture"}):
			saved_fixtures.append(kind)
		else:
			failures.append("fixture:%s (%s)" % [kind, source_path])

	for source_path in ArtAssetCatalog.all_source_model_paths():
		if gameplay_sources.has(source_path):
			continue
		var display_name := ArtAssetCatalog.source_display_name(source_path)
		var output_path := ArtAssetCatalog.library_prefab_path(source_path)
		if _bake_one(source_path, output_path, {}, false,
				{"display_name":display_name, "asset_kind":"library"}):
			saved_library_assets.append({"name":display_name, "path":output_path})
		else:
			failures.append("library:%s" % source_path)

	var library_ok := _build_library(saved_fixtures, saved_items, saved_library_assets)
	print("ART_PREFAB_BAKE items=%d fixtures=%d other=%d library=%s failures=%d" % [
		saved_items.size(), saved_fixtures.size(), saved_library_assets.size(),
		str(library_ok), failures.size()])
	for failure in failures:
		push_error("ART_PREFAB_BAKE_FAILED " + failure)
	quit(0 if failures.is_empty() and library_ok else 1)

func _bake_one(source_path: String, output_path: String, profile: Dictionary,
		orient_long_axis: bool, metadata: Dictionary) -> bool:
	if source_path == "":
		return false
	var root := ArtAssetFitter.create_baked_prefab(source_path, profile, orient_long_axis)
	if root == null:
		return false
	root.name = str(metadata.get("item_id", metadata.get("fixture_kind",
			metadata.get("display_name", "ArtPrefab"))))
	root.set_script(load("res://scripts/art_prefab_material_binder.gd"))
	root.set("material_profile_key", "item:" + str(metadata["item_id"]) \
			if metadata.has("item_id") else str(metadata.get("fixture_kind", "")))
	for key in metadata:
		root.set_meta(key, metadata[key])
	# 仅保存两层封装节点；导入模型的内部节点继续作为源PackedScene实例引用，
	# 避免把高面数网格和贴图复制进每个prefab。
	_set_wrapper_owners(root)
	var packed := PackedScene.new()
	var packed_ok := packed.pack(root) == OK
	var saved_ok := packed_ok and ResourceSaver.save(packed, output_path) == OK
	root.free()
	return saved_ok

func _build_library(fixture_kinds: Array[String], item_ids: Array[String],
		library_assets: Array[Dictionary]) -> bool:
	var root := Node3D.new()
	root.name = "ArtAssetLibrary"
	root.set_meta("purpose", "已连接贴图、可直接拖入场景的美术资产总览")

	var floor := MeshInstance3D.new()
	floor.name = "ReviewFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(28.0, 0.15, 48.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.1, 15.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.135, 0.16)
	floor_mat.roughness = 0.9
	floor.material_override = floor_mat
	root.add_child(floor)

	var sun := DirectionalLight3D.new()
	sun.name = "ReviewSun"
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	root.add_child(sun)

	var camera := Camera3D.new()
	camera.name = "ReviewCamera"
	camera.position = Vector3(0, 31, 49)
	camera.rotation_degrees = Vector3(-36, 0, 0)
	camera.current = true
	root.add_child(camera)

	var fixtures_holder := Node3D.new()
	fixtures_holder.name = "Fixtures_DragPrefabsFromFileSystem"
	root.add_child(fixtures_holder)
	fixtures_holder.owner = root
	for i in fixture_kinds.size():
		var kind := fixture_kinds[i]
		_add_library_instance(fixtures_holder, ArtAssetCatalog.fixture_prefab_path(kind), kind,
			Vector3(-9.0 + float(i) * 6.0, 0, -5.5), Vector3(4.5, 2.7, 2.5))

	var items_holder := Node3D.new()
	items_holder.name = "Items_DragPrefabsFromFileSystem"
	root.add_child(items_holder)
	items_holder.owner = root
	for i in item_ids.size():
		var item_id := item_ids[i]
		var column := i % 8
		var row := i / 8
		_add_library_instance(items_holder, ArtAssetCatalog.item_prefab_path(item_id), item_id,
			Vector3(-10.5 + float(column) * 3.0, 0, -1.0 + float(row) * 4.4), Vector3(1.7, 2.2, 1.7))

	var library_holder := Node3D.new()
	library_holder.name = "OtherSourceAssets_DragPrefabsFromFileSystem"
	root.add_child(library_holder)
	library_holder.owner = root
	for i in library_assets.size():
		var entry := library_assets[i]
		var column := i % 8
		var row := i / 8
		_add_library_instance(library_holder, str(entry["path"]), str(entry["name"]),
			Vector3(-10.5 + float(column) * 3.0, 0, 13.0 + float(row) * 4.4),
			Vector3(1.7, 2.2, 1.7))

	for child in root.get_children():
		child.owner = root
	var packed := PackedScene.new()
	var ok := packed.pack(root) == OK and ResourceSaver.save(packed, LIBRARY_PATH) == OK
	root.free()
	return ok

func _add_library_instance(parent: Node3D, prefab_path: String, label_text: String,
		position: Vector3, target_size: Vector3) -> void:
	var packed := load(prefab_path) as PackedScene
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	var source_size: Vector3 = visual.get_meta("source_size", Vector3.ONE)
	var ratio := minf(target_size.x / maxf(source_size.x, 0.0001),
			minf(target_size.y / maxf(source_size.y, 0.0001),
			target_size.z / maxf(source_size.z, 0.0001)))
	visual.name = label_text
	visual.scale = Vector3.ONE * ratio
	visual.position = position + Vector3(0, target_size.y * 0.5, 0)
	parent.add_child(visual)
	visual.owner = parent.owner
	var label := Label3D.new()
	label.name = label_text + "_Label"
	label.text = label_text
	label.font_size = 48
	label.outline_size = 8
	label.position = position + Vector3(0, 0.18, target_size.z * 0.75)
	label.rotation_degrees.x = -90
	label.no_depth_test = false
	parent.add_child(label)
	label.owner = parent.owner

func _set_wrapper_owners(root: Node) -> void:
	for child in root.get_children():
		child.owner = root
		for source_instance in child.get_children():
			source_instance.owner = root

func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
