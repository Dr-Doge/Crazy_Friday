class_name MarketBuilder
##卖场生成器:地板、外墙、4分区货架、中央爆款专区、收银区标识、寻路网格。
##
## 【白盒资产策略】每个实心构件由 StaticBody3D + BoxShape3D 凸体碰撞代理
## 承载，CSGBox3D 只负责白盒视觉。运行时生成的节点不能在编辑器里永久替换；
## 正式美术应在本生成器里按语义节点名实例化 PackedScene，并保留现有碰撞代理。
##
## 所有坐标取自 MapLayout,本文件不出现魔法数字。
##
## 生成的场景树(命名规整,便于按名字批量替换):
##   Market
##   ├── Floor/{Collider,Visual}
##   ├── Walls/Wall_*外墙与防坠围栏
##   ├── Decals/Decal_*       分区地贴、出口引导(无碰撞)
##   ├── Signs/Sign_*         灯牌底板 + Label3D
##   ├── Shelves/Shelf_<区>_<序号>/{Body, Ledge_*}
##   ├── Freezers/Freezer_*
##   ├── Pallets/Pallet_*
##   ├── PremiumStands/Stand_*
##   └── LargePads/Pad_*

## 返回 {slots, tv_slots, sale_points, grid, granny_spawns, stash_points,
##       player_spawn, parked_cart_spawns, lane_x}
static func build(root: Node3D) -> Dictionary:
	var solid_rects: Array[Rect2] = []
	var market := _group(root, "Market")

	_build_floor(market)
	_build_walls(market, solid_rects)
	_build_decals(market)
	_build_signs(market)

	var slots: Array = []          # {pos: Vector3, zone: String}
	_build_shelves(market, solid_rects, slots)
	_build_freezers(market, solid_rects, slots)
	_build_pallets(market, solid_rects, slots)
	_build_premium(market, solid_rects, slots)
	var tv_slots := _build_large_pads(market, solid_rects)

	# 地滑区由 main 在运行时随机生成(开局3块 + 保洁定时拖地 + 洗衣液道具)

	return {
		"slots": slots,
		"tv_slots": tv_slots,
		"sale_points": MapLayout.sale_points(),
		"grid": _build_grid(solid_rects),
		"granny_spawns": MapLayout.granny_spawns(),
		"stash_points": MapLayout.stash_points(),
		"player_spawn": MapLayout.PLAYER_SPAWN,
		"parked_cart_spawns": MapLayout.parked_cart_spawns(),
		"lane_x": MapLayout.LANE_XS,
	}

# ---------------------------------------------------------------- 地板与外墙

static func _build_floor(market: Node3D) -> void:
	var pad := MapLayout.FLOOR_PAD
	var w := (MapLayout.WALL_E - MapLayout.WALL_W) + pad * 2.0
	var d := (MapLayout.WALL_S - MapLayout.WALL_N) + pad * 2.0
	var cz := (MapLayout.WALL_N + MapLayout.WALL_S) * 0.5
	_csg_box(market, "Floor",
			Vector3(0, MapLayout.FLOOR_Y, cz),
			Vector3(w, MapLayout.FLOOR_THICK, d),
			Color(0.88, 0.88, 0.86))

static func _build_walls(market: Node3D, solids: Array[Rect2]) -> void:
	var walls := _group(market, "Walls")
	var t := MapLayout.WALL_T
	var w_span := MapLayout.WALL_E - MapLayout.WALL_W + t
	var d_span := MapLayout.WALL_S - MapLayout.WALL_N + t
	var cz := (MapLayout.WALL_N + MapLayout.WALL_S) * 0.5

	_wall(walls, solids, "Wall_N", Vector3(0, 0, MapLayout.WALL_N - t * 0.5), Vector3(w_span, MapLayout.WALL_H, t))
	_wall(walls, solids, "Wall_W", Vector3(MapLayout.WALL_W - t * 0.5, 0, cz), Vector3(t, MapLayout.WALL_H, d_span))
	_wall(walls, solids, "Wall_E", Vector3(MapLayout.WALL_E + t * 0.5, 0, cz), Vector3(t, MapLayout.WALL_H, d_span))

	# 南墙:被2 个入口门洞和 1 个出口豁口切成 4 段
	var sz := MapLayout.WALL_S + t * 0.5
	var cuts: Array[Vector2] = [MapLayout.EXIT_GAP, MapLayout.DOOR_1, MapLayout.DOOR_2]
	var x := MapLayout.WALL_W - t * 0.5
	var seg := 0
	for cut in cuts:
		if cut.x > x:
			seg += 1
			_wall(walls, solids, "Wall_S_%d" % seg,
					Vector3((x + cut.x) * 0.5, 0, sz),
					Vector3(cut.x - x, MapLayout.WALL_H, t))
		x = maxf(x, cut.y)
	if x < MapLayout.WALL_E + t * 0.5:
		seg += 1
		_wall(walls, solids, "Wall_S_%d" % seg,
				Vector3((x + MapLayout.WALL_E + t * 0.5) * 0.5, 0, sz),
				Vector3(MapLayout.WALL_E + t * 0.5 - x, MapLayout.WALL_H, t))

	# 门厅外圈围栏:防止从门洞走出地板边缘掉进虚空
	var pad := MapLayout.FLOOR_PAD
	var fw := w_span + pad * 2.0
	var fd := d_span + pad * 2.0
	_wall(walls, solids, "Fence_N", Vector3(0, 0, MapLayout.WALL_N - pad), Vector3(fw, MapLayout.WALL_H, 0.5))
	_wall(walls, solids, "Fence_S", Vector3(0, 0, MapLayout.WALL_S + pad), Vector3(fw, MapLayout.WALL_H, 0.5))
	_wall(walls, solids, "Fence_W", Vector3(MapLayout.WALL_W - pad, 0, cz), Vector3(0.5, MapLayout.WALL_H, fd))
	_wall(walls, solids, "Fence_E", Vector3(MapLayout.WALL_E + pad, 0, cz), Vector3(0.5, MapLayout.WALL_H, fd))

# ---------------------------------------------------------------- 地贴与灯牌

static func _build_decals(market: Node3D) -> void:
	var decals := _group(market, "Decals")
	for zone in MapLayout.zone_rects():
		var r: Rect2 = MapLayout.zone_rects()[zone]
		var c: Color = Catalog.ZONE_COLORS[zone]
		_decal(decals, "Decal_%s" % zone,
				Vector3(r.position.x + r.size.x * 0.5, 0.02, r.position.y + r.size.y * 0.5),
				Vector3(r.size.x, 0.04, r.size.y),
				Color(c.r, c.g, c.b, 0.35))
	# 出口绿色引导地贴
	var gap := MapLayout.EXIT_GAP
	_decal(decals, "Decal_Exit",
			Vector3(MapLayout.EXIT_X, 0.02, MapLayout.WALL_S - 1.6),
			Vector3(gap.y - gap.x, 0.04, 4.5),
			Color(0.2, 0.8, 0.35, 0.5))
	# 集结缓冲带地贴:提示这里是空旷集结区(反拥堵设计的可视化)
	var bz := (MapLayout.BUFFER_N + MapLayout.GATE_IN_Z) * 0.5
	_decal(decals, "Decal_Buffer",
			Vector3(0, 0.015, bz),
			Vector3(MapLayout.WALL_E - MapLayout.WALL_W - 4.0, 0.03, MapLayout.buffer_depth()),
			Color(0.95, 0.95, 0.98, 0.18))

static func _build_signs(market: Node3D) -> void:
	var signs := _group(market, "Signs")
	for zone in MapLayout.zone_rects():
		var r: Rect2 = MapLayout.zone_rects()[zone]
		_sign(signs, "Sign_%s" % zone,
				Vector3(r.position.x + r.size.x * 0.5, 3.4, r.position.y + r.size.y * 0.5),
				Catalog.ZONE_NAMES[zone], Catalog.ZONE_COLORS[zone])
	_sign(signs, "Sign_Premium", Vector3(0, 4.6, MapLayout.PREMIUM_Z),
			"★ %s ★" % Catalog.ZONE_NAMES[Catalog.ZONE_PREMIUM],
			Catalog.ZONE_COLORS[Catalog.ZONE_PREMIUM])
	_sign(signs, "Sign_Checkout",
			Vector3((MapLayout.LANE_XS[0] + MapLayout.LANE_XS[1]) * 0.5, 3.4, MapLayout.GATE_IN_Z - 2.5),
			"收银区", Color(0.9, 0.35, 0.3))
	_sign(signs, "Sign_Exit", Vector3(MapLayout.EXIT_X, 4.5, MapLayout.WALL_S - 1.0),
			"↓ 出 口 ↓", Color(0.15, 0.75, 0.3))

# ---------------------------------------------------------------- 陈列设施

static func _build_shelves(market: Node3D, solids: Array[Rect2], slots: Array) -> void:
	var parent := _group(market, "Shelves")
	var rows := MapLayout.shelf_rows()
	for zone in rows:
		var i := 0
		for pos in rows[zone]:
			_shelf(parent, solids, "Shelf_%s_%d" % [zone, i], pos, MapLayout.SHELF_LEN, zone, slots)
			i += 1

static func _build_freezers(market: Node3D, solids: Array[Rect2], slots: Array) -> void:
	var parent := _group(market, "Freezers")
	var i := 0
	for fx in MapLayout.freezer_xs():
		_freezer(parent, solids, "Freezer_%d" % i,
				Vector3(fx, 0, MapLayout.FREEZER_Z), MapLayout.FREEZER_LEN,
				Catalog.ZONE_FRESH, slots)
		i += 1

static func _build_pallets(market: Node3D, solids: Array[Rect2], slots: Array) -> void:
	var parent := _group(market, "Pallets")
	var i := 0
	for p in MapLayout.pallets():
		_pallet(parent, solids, "Pallet_%d" % i, p["pos"], p["zone"], slots)
		i += 1

static func _build_premium(market: Node3D, solids: Array[Rect2], slots: Array) -> void:
	var parent := _group(market, "PremiumStands")
	var i := 0
	for pos in MapLayout.premium_stands():
		_premium_stand(parent, solids, "Stand_%d" % i, pos, slots)
		i += 1

static func _build_large_pads(market: Node3D, solids: Array[Rect2]) -> Array[Vector3]:
	var parent := _group(market, "LargePads")
	var pads := MapLayout.large_pads()
	var i := 0
	for tp in pads:
		_csg_box(parent, "Pad_%d" % i, Vector3(tp.x, 0.2, tp.z),
				Vector3(1.6, 0.4, 1.2), Color(0.72, 0.6, 0.45))
		solids.append(Rect2(tp.x - 0.8, tp.z - 0.6, 1.6, 1.2))
		i += 1
	return pads

# ---------------------------------------------------------------- 寻路网格

static func _build_grid(solid_rects: Array[Rect2]) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(MapLayout.GRID_MIN, MapLayout.GRID_SIZE)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var lo := MapLayout.GRID_MIN
	var hi := MapLayout.GRID_MIN + MapLayout.GRID_SIZE
	for x in range(lo.x, hi.x):
		grid.set_point_solid(Vector2i(x, lo.y), true)
		grid.set_point_solid(Vector2i(x, hi.y - 1), true)
	for y in range(lo.y, hi.y):
		grid.set_point_solid(Vector2i(lo.x, y), true)
		grid.set_point_solid(Vector2i(hi.x - 1, y), true)
	for r in solid_rects:
		_mark_solid(grid, r)
	return grid

static func _mark_solid(grid: AStarGrid2D, r: Rect2) -> void:
	var x0 := int(floor(r.position.x))
	var x1 := int(ceil(r.position.x + r.size.x))
	var y0 := int(floor(r.position.y))
	var y1 := int(ceil(r.position.y + r.size.y))
	for x in range(x0, x1):
		for y in range(y0, y1):
			var id := Vector2i(x, y)
			if grid.is_in_boundsv(id):
				grid.set_point_solid(id, true)

# ---------------------------------------------------------------- CSG基元

static func _group(parent: Node3D, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n

## 实心构件:CSG 负责**视觉**,碰撞另挂 StaticBody3D + BoxShape3D(凸体)。
##
## 【为什么不用 CSGShape3D.use_collision】
## 它生成的是 ConcavePolygonShape3D(三角网格)。trimesh 是无厚度的单面碰撞体,
## 动态刚体高速运动或被挤压时极易穿透——v0.14 实测中商品会直接穿过地板
## 掉到 y=-7 以下飞出地图。BoxShape3D 是凸体,有完整的内外判定与穿透恢复,
## 对刚体堆叠(本作车斗与货架的核心场景)可靠得多。
##
## 换正式模型时:把Visual 子节点替换掉即可,Collider 保留(或改成模型自带碰撞)。
## pos.y == 0 表示"贴地摆放",自动抬升半个高度。
static func _csg_box(parent: Node3D, name: String, pos: Vector3, size: Vector3,
		color: Color) -> CSGBox3D:
	var at := pos + Vector3(0, size.y * 0.5, 0) if pos.y == 0.0 else pos
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	body.position = at
	parent.add_child(body)

	var cs := CollisionShape3D.new()
	cs.name = "Collider"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)

	var b := CSGBox3D.new()
	b.name = "Visual"
	b.size = size
	b.material = _mat(color)
	b.use_collision = false     # 碰撞由父级 StaticBody3D 提供
	body.add_child(b)
	_register_camera_lod(b, size)
	return b

## 无碰撞的薄地贴/透明装饰
static func _decal(parent: Node3D, name: String, pos: Vector3, size: Vector3, color: Color) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = name
	b.size = size
	b.material = _mat(color, true)
	b.use_collision = false
	b.position = pos
	parent.add_child(b)
	return b

## 只登记视觉节点：镜头贴得过近时隐藏网格，但父级碰撞体继续阻挡角色和购物车。
static func _register_camera_lod(node: Node3D, size: Vector3) -> void:
	node.add_to_group("camera_near_lod")
	node.set_meta("camera_lod_half_extents", size * 0.5)

static func _wall(parent: Node3D, solids: Array[Rect2], name: String, pos: Vector3, size: Vector3) -> void:
	if size.x <= 0.01 or size.z <= 0.01:
		return
	_csg_box(parent, name, Vector3(pos.x, 0, pos.z), size, Color(0.62, 0.62, 0.64))
	solids.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))

## 联排货架:沿 x 向,货位在南北两侧 × 两层
static func _shelf(parent: Node3D, solids: Array[Rect2], name: String, pos: Vector3,
		length: float, zone: String, slots: Array) -> void:
	var g := _group(parent, name)
	_csg_box(g, "Body", pos, Vector3(length, MapLayout.SHELF_H, MapLayout.SHELF_W), Color(0.55, 0.57, 0.6))
	solids.append(Rect2(pos.x - length * 0.5, pos.z - MapLayout.SHELF_W * 0.5, length, MapLayout.SHELF_W))
	var li := 0
	for side in [-1.0, 1.0]:
		for level_y in [0.62, 1.22]:
			_csg_box(g, "Ledge_%d" % li,
					Vector3(pos.x, level_y, pos.z + side * 0.75),
					Vector3(length, 0.05, 0.35), Color(0.68, 0.7, 0.72))
			li += 1
			var n := int(length / 1.25)
			for i in n:
				var sx := pos.x - length * 0.5 + 1.25 * (i + 0.5)
				slots.append({
					# 置物板顶面高度;商品半高由摆货时补,底面正好贴板
					"pos": Vector3(sx, level_y + 0.025, pos.z + side * 0.78),
					"zone": zone,
				})

## 卧式冰柜:低矮开口柜,货位在顶面
static func _freezer(parent: Node3D, solids: Array[Rect2], name: String, pos: Vector3,
		length: float, zone: String, slots: Array) -> void:
	_csg_box(parent, name, pos, Vector3(length, 0.85, 1.3), Color(0.82, 0.9, 0.95))
	solids.append(Rect2(pos.x - length * 0.5, pos.z - 0.65, length, 1.3))
	var n := int(length / 0.9)
	for i in n:
		slots.append({
			"pos": Vector3(pos.x - length * 0.5 + 0.9 * (i + 0.5), 0.87, pos.z),
			"zone": zone,
		})

## 爆款展台:金色自发光底座,顶面四格货位
static func _premium_stand(parent: Node3D, solids: Array[Rect2], name: String,
		pos: Vector3, slots: Array) -> void:
	var b := _csg_box(parent, name, pos, Vector3(1.7, 0.45, 1.7), Color(0.85, 0.65, 0.15))
	var mat: StandardMaterial3D = b.material
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.1)
	mat.emission_energy_multiplier = 0.8
	solids.append(Rect2(pos.x - 0.85, pos.z - 0.85, 1.7, 1.7))
	for ox in [-0.42, 0.42]:
		for oz in [-0.42, 0.42]:
			slots.append({
				"pos": Vector3(pos.x + ox, 0.48, pos.z + oz),
				"zone": Catalog.ZONE_PREMIUM,
			})

## 促销堆头:矮托盘,顶面四格货位
static func _pallet(parent: Node3D, solids: Array[Rect2], name: String, pos: Vector3,
		zone: String, slots: Array) -> void:
	_csg_box(parent, name, pos, Vector3(1.7, 0.3, 1.7), Color(0.72, 0.6, 0.45))
	solids.append(Rect2(pos.x - 0.85, pos.z - 0.85, 1.7, 1.7))
	for ox in [-0.42, 0.42]:
		for oz in [-0.42, 0.42]:
			slots.append({
				"pos": Vector3(pos.x + ox, 0.32, pos.z + oz),
				"zone": zone,
			})

## 分区灯牌:自发光底板 + 大号白字,远处一眼可见
static func _sign(parent: Node3D, name: String, pos: Vector3, text: String, color: Color) -> void:
	var g := _group(parent, name)
	var plate := CSGBox3D.new()
	plate.name = "Plate"
	plate.size = Vector3(7.5, 1.7, 0.25)
	var pmat := _mat(color.darkened(0.15))
	pmat.emission_enabled = true
	pmat.emission = color
	pmat.emission_energy_multiplier = 1.3
	plate.material = pmat
	plate.use_collision = false
	plate.position = pos
	g.add_child(plate)
	_register_camera_lod(plate, plate.size)

	var lb := Label3D.new()
	lb.name = "Text"
	lb.text = text
	lb.font = Catalog.ui_font_bold()
	lb.font_size = 200
	lb.pixel_size = 0.008
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.modulate = Color(1, 1, 1)
	lb.outline_size = 24
	lb.outline_modulate = color.darkened(0.55)
	lb.position = pos
	g.add_child(lb)
	_register_camera_lod(lb, Vector3(7.5, 1.7, 0.3))

static func _mat(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
