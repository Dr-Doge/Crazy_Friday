class_name NewLevelLayout extends RefCounted
## 将手工搭建的 New_Level 场景翻译为 Main 所需的玩法数据。
## 只读取场景节点和元数据：不会生成墙体、货架或其他关卡几何。

const GRID_MIN := Vector2i(-68, -51)
const GRID_SIZE := Vector2i(136, 102)
# 商品生成面严格贴合当前手工白盒：立式架使用双层，平面生鲜/冷冻货柜只使用最上层。
const UPRIGHT_SHELF_LEVELS := [0.27, 1.25]
const COLD_CASE_LEVELS := [0.92]

static func build(root: Node3D) -> Dictionary:
	var solids: Array[Rect2] = []
	var shelves: Array[Node] = []
	var premium_stands: Array[Node] = []
	var player_markers: Array[Node] = []
	var granny_markers: Array[Node] = []
	var sale_markers: Array[Node] = []
	var large_markers: Array[Node] = []
	var checkout_markers: Array[Node] = []
	var checkout_guides: Array[Node] = []
	_scan_nodes(root, solids, shelves, premium_stands, player_markers,
			granny_markers, sale_markers, large_markers, checkout_markers,
			checkout_guides)

	var slots: Array = []
	for shelf in shelves:
		_append_shelf_slots(shelf as CSGBox3D, slots)
	for stand in premium_stands:
		_append_premium_slots(stand as CSGBox3D, slots)

	var player_spawns := _sorted_positions(player_markers)
	var granny_spawns := _sorted_positions(granny_markers)
	# 特价刷新点从当前货架/展柜排版实时求中心。场景作者移动货架后，
	# 不必再手工同步一套容易遗忘的隐藏 Marker3D。
	var sale_points := _zone_sale_points(shelves, premium_stands, sale_markers)
	var tv_slots := _sorted_positions(large_markers)
	# 收银道以红色车道引导块为准。它们既是编辑器中的所见排版，
	# 也是运行时闸机、围栏、扫码区和NPC排队路径的唯一坐标源。
	var checkout := _checkout_geometry(checkout_guides, checkout_markers)
	var lane_x: Array[float] = checkout["lane_x"]
	var checkout_specs := _checkout_specs(root)
	# 分类范围以设计师在场景中手调的彩色地板为唯一来源，避免维护第二套坐标。
	var zone_bounds := _zone_floor_bounds(root)
	# 四队出生直接读取等待室地板中心；两名队员以中心为中点轻微错开，
	# 朝向由等待室中心指向卖场原点，因此手调等待室后无需同步隐藏Marker。
	var team_spawn_specs := _waiting_room_spawn_specs(root)

	var nav := AStarGrid2D.new()
	nav.region = Rect2i(GRID_MIN, GRID_SIZE)
	nav.cell_size = Vector2(1, 1)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	_mark_grid_border(nav)
	for rect in solids:
		MarketBuilder._mark_solid(nav, rect)

	var entrance := player_spawns[0] if not player_spawns.is_empty() \
			else Vector3(18.0, 0.0, 18.0)
	return {
		"slots": slots,
		"tv_slots": tv_slots,
		"sale_points": sale_points,
		"grid": nav,
		"granny_spawns": granny_spawns,
		"player_spawn": entrance,
		"player_spawns": player_spawns,
		"parked_cart_spawns": [],
		"stash_points": [],
		"lane_x": lane_x,
		"checkout_specs": checkout_specs,
		"checkout_config": {
			"gate_in_z": checkout["gate_in_z"],
			"gate_out_z": checkout["gate_out_z"],
			"lane_half_w": checkout["lane_half_w"],
			"belt_dx": -2.0,
			"belt_dx_by_lane": [-1.95, 1.95],
		},
		"zone_bounds": zone_bounds,
		"team_spawn_specs": team_spawn_specs,
		"layout": {
			"respawn_pos": entrance,
			"wander_x": Vector2(-40.0, 40.0),
			"wander_z": Vector2(-23.75, 23.75),
			"slippery_x": Vector2(-38.75, 38.75),
			"slippery_z": Vector2(-22.5, 22.5),
			"exit_x": checkout["exit_x"],
			"exit_inner_z": checkout["gate_out_z"] + 0.8,
			"exit_outer_z": checkout["gate_out_z"] + 2.6,
			"team_spawn_specs": team_spawn_specs,
		},
	}

static func _waiting_room_spawn_specs(root: Node3D) -> Array:
	var out: Array = []
	for suffix in ["A", "B", "C", "D"]:
		var room := root.find_child("WaitingRoom_%s" % suffix, true, false) as Node3D
		var floor := room.find_child("Floor", false, false) as CSGBox3D if room != null else null
		if floor == null:
			continue
		var center := _scene_transform(floor).origin
		center.y = 0.1
		# 朝向对应准备室的大门，而不是泛化地朝向商场原点；设计师移动入口后自动跟随。
		var entrance := root.find_child("TeamEntrance_%s" % suffix, true, false) as Node3D
		var entrance_pos := _scene_transform(entrance).origin if entrance != null else Vector3.ZERO
		var facing := entrance_pos - center
		facing.y = 0.0
		if facing.length_squared() < 0.01:
			facing = Vector3(-center.x, 0.0, -center.z)
		facing = facing.normalized()
		var side := Vector3(facing.z, 0.0, -facing.x).normalized()
		out.append({"center": center, "facing": facing, "side": side})
	return out

static func _zone_floor_bounds(root: Node3D) -> Dictionary:
	var out := {}
	var floors := root.find_child("ZoneFloors", true, false)
	if floors == null:
		return out
	for child in floors.get_children():
		if not (child is CSGBox3D) or not str(child.name).begins_with("ZoneFloor_"):
			continue
		var floor := child as CSGBox3D
		var tx := _scene_transform(floor)
		var center := tx.origin
		var half_x := (absf(tx.basis.x.x) * floor.size.x
				+ absf(tx.basis.z.x) * floor.size.z) * 0.5
		var half_z := (absf(tx.basis.x.z) * floor.size.x
				+ absf(tx.basis.z.z) * floor.size.z) * 0.5
		out[str(floor.name).trim_prefix("ZoneFloor_")] = Rect2(
				center.x - half_x, center.z - half_z, half_x * 2.0, half_z * 2.0)
	return out

static func _scan_nodes(node: Node, solids: Array[Rect2], shelves: Array[Node],
		premium: Array[Node], players: Array[Node], grannies: Array[Node],
		sales: Array[Node], large: Array[Node], checkouts: Array[Node],
		checkout_guides: Array[Node]) -> void:
	if node is CSGBox3D:
		var box := node as CSGBox3D
		# 升降门由运行时开关碰撞；导航按“最终可通行”状态构建，避免开门后AI仍把门洞视为永久墙。
		if box.use_collision and box.name != "Floor" \
				and not box.is_in_group("walkable_floor") \
				and not box.is_in_group("dynamic_nav_gate"):
			# CSG白盒允许关卡设计师任意旋转。导航障碍必须使用变换后的
			# 世界空间AABB，否则斜墙/斜置壁柜会在错误方向封死整条过道。
			var tx := _scene_transform(box)
			var p := tx.origin
			var hx := (absf(tx.basis.x.x) * box.size.x
					+ absf(tx.basis.y.x) * box.size.y
					+ absf(tx.basis.z.x) * box.size.z) * 0.5
			var hz := (absf(tx.basis.x.z) * box.size.x
					+ absf(tx.basis.y.z) * box.size.y
					+ absf(tx.basis.z.z) * box.size.z) * 0.5
			solids.append(Rect2(p.x - hx, p.z - hz, hx * 2.0, hz * 2.0))
		if box.is_in_group("new_level_shelf"):
			shelves.append(box)
		if box.is_in_group("new_level_premium"):
			premium.append(box)
		if box.is_in_group("new_level_checkout_guide"):
			checkout_guides.append(box)
	if node.is_in_group("new_level_player_spawn"):
		players.append(node)
	if node.is_in_group("new_level_granny_spawn"):
		grannies.append(node)
	if node.is_in_group("new_level_sale_point"):
		sales.append(node)
	if node.is_in_group("new_level_large_slot"):
		large.append(node)
	if node.is_in_group("new_level_checkout_anchor"):
		checkouts.append(node)
	for child in node.get_children():
		_scan_nodes(child, solids, shelves, premium, players, grannies,
				sales, large, checkouts, checkout_guides)

static func _checkout_specs(root: Node3D) -> Array:
	var specs: Array = []
	for side_name in ["North", "South", "West", "East"]:
		var group := root.find_child("CheckoutGroup_%s" % side_name, true, false) as Node3D
		if group == null:
			continue
		var tx := _scene_transform(group)
		var outward := tx.basis.z.normalized()
		var side_axis := tx.basis.x.normalized()
		for lane_index in 2:
			var local_x := -1.5 if lane_index == 0 else 1.5
			var center := tx * Vector3(local_x, 0.0, 0.0)
			specs.append({
				"name": "%s_%s" % [side_name, "A" if lane_index == 0 else "B"],
				"center": center,
				"outward": outward,
				"side": side_axis,
				"length": 6.0,
				"lane_half_w": 1.3,
				"belt_offset": -1.95 if lane_index == 0 else 1.95,
				"exit_outer": center + outward * 10.0,
			})
	return specs

static func _checkout_geometry(guides: Array[Node], markers: Array[Node]) -> Dictionary:
	var lane_x: Array[float] = []
	var gate_in_z := 11.5
	var gate_out_z := 19.2
	var lane_half_w := 1.55
	if not guides.is_empty():
		guides.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
		gate_in_z = INF
		gate_out_z = -INF
		lane_half_w = INF
		for node in guides:
			var guide := node as CSGBox3D
			var tx := _scene_transform(guide)
			var p := tx.origin
			var half_x := guide.size.x * tx.basis.x.length() * 0.5
			var half_z := guide.size.z * tx.basis.z.length() * 0.5
			lane_x.append(p.x)
			gate_in_z = minf(gate_in_z, p.z - half_z)
			gate_out_z = maxf(gate_out_z, p.z + half_z)
			lane_half_w = minf(lane_half_w, half_x)
	else:
		for pos in _sorted_positions(markers):
			lane_x.append(pos.x)
	var exit_x := 0.0
	for x in lane_x:
		exit_x += x
	if not lane_x.is_empty():
		exit_x /= lane_x.size()
	return {
		"lane_x": lane_x,
		"gate_in_z": gate_in_z,
		"gate_out_z": gate_out_z,
		"lane_half_w": lane_half_w,
		"exit_x": exit_x,
	}

static func _zone_sale_points(shelves: Array[Node], premium: Array[Node],
		fallback_markers: Array[Node]) -> Array[Vector3]:
	var sums := {}
	var counts := {}
	for node in shelves:
		var shelf := node as CSGBox3D
		var zone := str(shelf.get_meta("zone", ""))
		if zone == "":
			continue
		sums[zone] = sums.get(zone, Vector3.ZERO) + _scene_transform(shelf).origin
		counts[zone] = int(counts.get(zone, 0)) + 1
	var out: Array[Vector3] = []
	for zone in Catalog.SHOPPING_ZONES:
		if int(counts.get(zone, 0)) <= 0:
			continue
		var p: Vector3 = sums[zone] / float(counts[zone])
		p.y = 0.1
		out.append(p)
	if not premium.is_empty():
		var premium_center := Vector3.ZERO
		for node in premium:
			premium_center += _scene_transform(node as Node3D).origin
		premium_center /= premium.size()
		premium_center.y = 0.1
		out.append(premium_center)
	if out.is_empty():
		return _sorted_positions(fallback_markers)
	return out

static func _append_shelf_slots(shelf: CSGBox3D, out: Array) -> void:
	var zone := str(shelf.get_meta("zone", ""))
	if zone == "":
		return
	var side_offset := 0.58 if str(shelf.get_meta("fixture", "")) == "cold_case" else 0.51
	var levels := COLD_CASE_LEVELS if str(shelf.get_meta("fixture", "")) == "cold_case" \
			else UPRIGHT_SHELF_LEVELS
	var count := maxi(2, int(floor((shelf.size.x - 0.4) / 0.9)))
	var step := (shelf.size.x - 0.8) / float(maxi(1, count - 1))
	for side in [-1.0, 1.0]:
		for level in levels:
			for i in count:
				var local := Vector3(-shelf.size.x * 0.5 + 0.4 + step * i,
						0.0, side * side_offset)
				var world := _scene_transform(shelf) * local
				world.y = level
				out.append({
					"pos": world,
					"zone": zone,
					# 双面货架两侧商品分别朝向各自过道，绝不让正面朝向货架脊柱。
					"yaw": _scene_transform(shelf).basis.get_euler().y \
							+ (PI if side < 0.0 else 0.0),
				})

static func _append_premium_slots(stand: CSGBox3D, out: Array) -> void:
	# 手工排版把中央展柜从三组精简为一组；单柜用4×3陈列网格承载
	# 12件压轴库存，保持删减后的视觉结构同时不静默吞掉商品。
	for z in [-0.62, 0.0, 0.62]:
		for x in [-0.84, -0.28, 0.28, 0.84]:
			out.append({
				"pos": _scene_transform(stand) * Vector3(x, stand.size.y * 0.5 + 0.02, z),
				"zone": Catalog.ZONE_PREMIUM,
				"yaw": _scene_transform(stand).basis.get_euler().y,
			})

static func _sorted_positions(nodes: Array[Node]) -> Array[Vector3]:
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	var out: Array[Vector3] = []
	for node in nodes:
		if node is Node3D:
			out.append(_scene_transform(node as Node3D).origin)
	return out

static func _scene_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

static func _mark_grid_border(nav: AStarGrid2D) -> void:
	var hi := GRID_MIN + GRID_SIZE
	for x in range(GRID_MIN.x, hi.x):
		nav.set_point_solid(Vector2i(x, GRID_MIN.y), true)
		nav.set_point_solid(Vector2i(x, hi.y - 1), true)
	for z in range(GRID_MIN.y, hi.y):
		nav.set_point_solid(Vector2i(GRID_MIN.x, z), true)
		nav.set_point_solid(Vector2i(hi.x - 1, z), true)
