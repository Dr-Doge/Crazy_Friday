extends SceneTree
## 把正式资产实例真正写入New_Level场景树；不再依赖运行时ArtAssetInstaller。

const LEVEL_PATH := "res://scenes/New_Level.tscn"
const EPS := 0.0001

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var packed := load(LEVEL_PATH) as PackedScene
	if packed == null:
		push_error("无法加载 " + LEVEL_PATH)
		quit(1)
		return
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if root == null:
		quit(1)
		return
	_remove_named(root, "ArtAssetInstaller")
	_remove_named(root, "BakedArtAssets")
	_remove_named(root, "ShelfTopSightBlockers")
	_remove_named(root, "ImportedAssetPrefabs")

	var art_root := Node3D.new()
	art_root.name = "BakedArtAssets"
	art_root.editor_description = "真正写入场景树的货架、冰柜和灯管prefab实例；白盒仅保留碰撞/货位。"
	root.add_child(art_root)
	art_root.owner = root

	var cargo_root := Node3D.new()
	cargo_root.name = "ShelfTopSightBlockers"
	cargo_root.editor_description = "立式货架顶部直达天花板的浅灰色货箱CSG白盒；悬吊分区牌正下方留空。"
	root.add_child(cargo_root)
	cargo_root.owner = root

	var reference_root := Node3D.new()
	reference_root.name = "ImportedAssetPrefabs"
	reference_root.editor_description = "所有已烘焙资产的场景实例索引；隐藏展示，但每个资产均可在左侧场景树找到。"
	reference_root.visible = false
	root.add_child(reference_root)
	reference_root.owner = root

	var shelves: Array[CSGBox3D] = []
	_collect_shelves(root, shelves)
	shelves.sort_custom(func(a, b): return str(a.name) < str(b.name))
	var cold_index := 0
	var shelf_fixture_count := 0
	for shelf in shelves:
		var kind := "upright_shelf"
		if str(shelf.get_meta("fixture", "")) == "cold_case":
			cold_index += 1
			kind = "cold_case_%d" % (((cold_index - 1) % 2) + 1)
		else:
			if not _shelf_below_hanging_sign(root, shelf):
				_add_top_cargo(cargo_root, root, shelf)
		var bounds := _csg_hierarchy_bounds(shelf)
		var holder := _make_modular_holder(root, ArtAssetCatalog.fixture_prefab_path(kind),
				bounds.size, "Art_%s" % shelf.name, kind)
		if holder == null:
			continue
		art_root.add_child(holder)
		holder.owner = root
		holder.transform = _scene_transform(shelf)
		holder.position += holder.transform.basis * bounds.get_center()
		holder.set_meta("source_whitebox", "ShelfIslands/%s" % shelf.name)
		shelf.visible = false
		shelf_fixture_count += 1

	var light_count := 0
	var fixtures: Array[Node3D] = []
	_collect_group_nodes(root, ["aisle_light_fixture", "waiting_room_light_fixture"], fixtures)
	for fixture in fixtures:
		var tube := fixture.find_child("Tube", false, false) as CSGBox3D
		if tube == null:
			continue
		var holder := _make_modular_holder(root,
				ArtAssetCatalog.fixture_prefab_path("led_tube"), tube.size,
				"Art_%s_Tube" % fixture.name, "led_tube")
		if holder == null:
			continue
		art_root.add_child(holder)
		holder.owner = root
		holder.transform = _scene_transform(tube)
		tube.visible = false
		light_count += 1

	var ref_count := _add_all_prefab_references(reference_root, root)
	_set_generated_owner(art_root, root)
	_set_generated_owner(cargo_root, root)
	# reference节点是外部PackedScene实例，只设置实例根owner，保留轻量外部引用。
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = ResourceSaver.save(out, LEVEL_PATH)
	print("NEW_LEVEL_ART_BAKE shelves=%d lights=%d cargo=%d refs=%d result=%s" % [
		shelf_fixture_count, light_count, cargo_root.get_child_count(), ref_count, error_string(err)])
	root.free()
	var expected_ref_count := ArtAssetCatalog.all_source_model_paths().size()
	quit(0 if err == OK and shelf_fixture_count == 33 and light_count >= 30 \
			and ref_count == expected_ref_count else 1)

func _make_modular_holder(scene_root: Node, prefab_path: String, target_size: Vector3,
		holder_name: String, kind: String) -> Node3D:
	var packed := load(prefab_path) as PackedScene
	if packed == null:
		return null
	var probe := packed.instantiate() as Node3D
	if probe == null:
		return null
	var source_size: Vector3 = probe.get_meta("source_size", Vector3.ONE)
	probe.free()
	var uniform_scale := target_size.z / maxf(source_size.z, EPS)
	var natural_length := source_size.x * uniform_scale
	if natural_length <= EPS:
		return null
	var count := maxi(1, int(ceil(target_size.x / natural_length)))
	var step := 0.0 if count == 1 else \
			maxf(0.0, (target_size.x - natural_length) / float(count - 1))
	var holder := Node3D.new()
	holder.name = holder_name
	holder.add_to_group("installed_art_fixture", true)
	holder.set_meta("fixture_kind", kind)
	holder.set_meta("art_module_count", count)
	holder.set_meta("art_uniform_scale", uniform_scale)
	holder.set_meta("art_module_step", step)
	holder.set_meta("art_no_axis_deform", true)
	for i in count:
		var module := packed.instantiate() as Node3D
		module.name = "Module_%02d" % (i + 1)
		module.scale = Vector3.ONE * uniform_scale
		module.position.x = 0.0 if count == 1 else \
				-target_size.x * 0.5 + natural_length * 0.5 + step * float(i)
		holder.add_child(module)
	return holder

func _add_top_cargo(parent: Node3D, scene_root: Node, shelf: CSGBox3D) -> void:
	var shelf_tx := _scene_transform(shelf)
	var columns := maxi(3, int(ceil(shelf.size.x / 2.25)))
	var box_length := shelf.size.x / float(columns) - 0.035
	var layer_height := 1.24
	var base_local_y := 2.05
	for layer in 4:
		for column in columns:
			var box := CSGBox3D.new()
			box.name = "%s_Cargo_L%02d_C%02d" % [shelf.name, layer + 1, column + 1]
			box.size = Vector3(box_length, layer_height - 0.035, shelf.size.z * 0.92)
			box.use_collision = false
			box.add_to_group("shelf_top_cargo", true)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.68, 0.71, 0.75)
			mat.roughness = 0.78
			box.set_meta("cargo_kind", "light_gray")
			box.material = mat
			var local_x := -shelf.size.x * 0.5 + box_length * 0.5 + 0.0175 \
					+ float(column) * (shelf.size.x / float(columns))
			var local_y := base_local_y + layer_height * (float(layer) + 0.5)
			box.transform = shelf_tx * Transform3D(Basis.IDENTITY,
					Vector3(local_x, local_y, 0.0))
			parent.add_child(box)
			box.owner = scene_root

func _shelf_below_hanging_sign(scene_root: Node, shelf: CSGBox3D) -> bool:
	var shelf_box := _transform_aabb(AABB(-shelf.size * 0.5, shelf.size),
			_scene_transform(shelf))
	var shelf_rect := Rect2(shelf_box.position.x - 0.35, shelf_box.position.z - 0.35,
			shelf_box.size.x + 0.7, shelf_box.size.z + 0.7)
	var signs: Array[Node3D] = []
	_collect_group_nodes(scene_root, ["zone_hanging_sign"], signs)
	for node in signs:
		if not (node is CSGBox3D):
			continue
		var sign := node as CSGBox3D
		var sign_box := _transform_aabb(AABB(-sign.size * 0.5, sign.size),
				_scene_transform(sign))
		var sign_rect := Rect2(sign_box.position.x, sign_box.position.z,
				sign_box.size.x, sign_box.size.z)
		if shelf_rect.intersects(sign_rect):
			return true
	return false

func _add_all_prefab_references(parent: Node3D, scene_root: Node) -> int:
	var paths: Array[String] = []
	for item_id in ArtAssetCatalog.source_item_ids():
		paths.append(ArtAssetCatalog.item_prefab_path(item_id))
	for kind in ArtAssetCatalog.fixture_kinds():
		paths.append(ArtAssetCatalog.fixture_prefab_path(kind))
	var gameplay_sources := {}
	for item_id in ArtAssetCatalog.source_item_ids():
		gameplay_sources[ArtAssetCatalog.item_source_model_path(item_id)] = true
	for kind in ArtAssetCatalog.fixture_kinds():
		gameplay_sources[ArtAssetCatalog.fixture_source_model_path(kind)] = true
	for source_path in ArtAssetCatalog.all_source_model_paths():
		if not gameplay_sources.has(source_path):
			paths.append(ArtAssetCatalog.library_prefab_path(source_path))
	var count := 0
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		instance.name = "Prefab_%03d_%s" % [count + 1, instance.name]
		parent.add_child(instance)
		instance.owner = scene_root
		count += 1
	return count

func _remove_named(root: Node, node_name: String) -> void:
	var node := root.find_child(node_name, true, false)
	if node != null:
		node.get_parent().remove_child(node)
		node.free()

func _collect_shelves(node: Node, out: Array[CSGBox3D]) -> void:
	if node is CSGBox3D and node.is_in_group("new_level_shelf"):
		out.append(node)
	for child in node.get_children():
		_collect_shelves(child, out)

func _collect_group_nodes(node: Node, groups: Array[String], out: Array[Node3D]) -> void:
	if node is Node3D:
		for group_name in groups:
			if node.is_in_group(group_name):
				out.append(node)
				break
	for child in node.get_children():
		_collect_group_nodes(child, groups, out)

func _set_generated_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
		# 外部prefab实例保留其内部ownership，避免把网格摊平成超大场景文件。
		if str(child.scene_file_path) == "":
			_set_generated_owner(child, scene_root)

func _scene_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

func _csg_hierarchy_bounds(root: CSGBox3D) -> AABB:
	var state := {"has":false, "bounds":AABB()}
	_append_csg_bounds(root, root, Transform3D.IDENTITY, state)
	return state["bounds"] if state["has"] else AABB()

func _append_csg_bounds(node: Node, root: CSGBox3D, parent_xform: Transform3D,
		state: Dictionary) -> void:
	var xform := parent_xform
	if node is Node3D and node != root:
		xform = parent_xform * (node as Node3D).transform
	if node is CSGBox3D:
		var box := node as CSGBox3D
		var transformed := _transform_aabb(AABB(-box.size * 0.5, box.size), xform)
		if not state["has"]:
			state["bounds"] = transformed
			state["has"] = true
		else:
			state["bounds"] = (state["bounds"] as AABB).merge(transformed)
	for child in node.get_children():
		_append_csg_bounds(child, root, xform, state)

func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
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
