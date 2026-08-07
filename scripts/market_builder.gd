class_name MarketBuilder
## 灰盒超市生成器:地板、外墙、4分区货架、收银区、地滑区、寻路网格。
## 坐标:x向东,z向南。卖场内圈 x∈[-28,28], z∈[-20,22],南墙开两个入口。

const GRID_MIN := Vector2i(-30, -24)
const GRID_SIZE := Vector2i(60, 48)

## 返回 {slots, tv_slots, sale_points, grid, granny_spawns, stash_points,
##       player_spawn, parked_cart_spawns, lane_x}
static func build(root: Node3D) -> Dictionary:
	var solid_rects: Array[Rect2] = []

	# 地板
	_box(root, Vector3(0, -0.25, 1), Vector3(60, 0.5, 48), Color(0.88, 0.88, 0.86))

	# 外墙(南墙留两个4米门洞:x∈[13,17]与[20,24])
	_wall(root, solid_rects, Vector3(0, 0, -20.5), Vector3(58, 3, 1))     # 北
	_wall(root, solid_rects, Vector3(-28.5, 0, 1), Vector3(1, 3, 44))     # 西
	_wall(root, solid_rects, Vector3(28.5, 0, 1), Vector3(1, 3, 44))      # 东
	# 南-西段在x[-27,-22]开5米"出口"(收银后离场通道),其余照旧
	_wall(root, solid_rects, Vector3(-27.75, 0, 22.5), Vector3(1.5, 3, 1))# 南-西小段
	_wall(root, solid_rects, Vector3(-4.5, 0, 22.5), Vector3(35, 3, 1))   # 南-西段(出口以东)
	_wall(root, solid_rects, Vector3(18.5, 0, 22.5), Vector3(3, 3, 1))    # 南-门间段
	_wall(root, solid_rects, Vector3(26.5, 0, 22.5), Vector3(5, 3, 1))    # 南-东段

	# 出口标识:大字招牌+绿色地贴引导
	_zone_sign(root, Vector3(-24.5, 4.5, 21.5), "↓ 出 口 ↓", Color(0.15, 0.75, 0.3))
	var exit_strip := MeshInstance3D.new()
	var esm := BoxMesh.new()
	esm.size = Vector3(5, 0.04, 4.5)
	var esmat := StandardMaterial3D.new()
	esmat.albedo_color = Color(0.2, 0.8, 0.35, 0.5)
	esmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	esm.material = esmat
	exit_strip.mesh = esm
	exit_strip.position = Vector3(-24.5, 0.02, 20.8)
	root.add_child(exit_strip)

	# 地板边缘围栏:把墙外檐廊围成门厅,防止从门洞走出世界边缘掉进虚空
	_wall(root, solid_rects, Vector3(0, 0, -22.75), Vector3(60, 3, 0.5))
	_wall(root, solid_rects, Vector3(0, 0, 24.75), Vector3(60, 3, 0.5))
	_wall(root, solid_rects, Vector3(-29.75, 0, 1), Vector3(0.5, 3, 47.5))
	_wall(root, solid_rects, Vector3(29.75, 0, 1), Vector3(0.5, 3, 47.5))

	# 分区地贴与名牌
	var zone_rects := {
		Catalog.ZONE_FRESH: Rect2(-26, -18, 24, 15),
		Catalog.ZONE_APPLIANCE: Rect2(2, -18, 24, 15),
		Catalog.ZONE_DAILY: Rect2(-26, 2, 24, 8),
		Catalog.ZONE_SNACK: Rect2(2, 2, 24, 8),
	}
	for zone in zone_rects:
		var r: Rect2 = zone_rects[zone]
		var c: Color = Catalog.ZONE_COLORS[zone]
		var tint := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(r.size.x, 0.04, r.size.y)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(c.r, c.g, c.b, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.material = mat
		tint.mesh = pm
		tint.position = Vector3(r.position.x + r.size.x * 0.5, 0.02, r.position.y + r.size.y * 0.5)
		root.add_child(tint)
		_zone_sign(root, Vector3(r.position.x + r.size.x * 0.5, 3.4, r.position.y + r.size.y * 0.5), Catalog.ZONE_NAMES[zone], c)

	# 货架:行距拉宽到4.2米以上,玩家/NPC/双车会车都不再卡死
	var slots: Array = []   # {pos: Vector3, zone: String}
	var shelf_rows := {
		Catalog.ZONE_FRESH: [Vector3(-14, 0, -15.5), Vector3(-14, 0, -9)],
		Catalog.ZONE_APPLIANCE: [Vector3(14, 0, -15.5), Vector3(14, 0, -9)],
		Catalog.ZONE_DAILY: [Vector3(-14, 0, 3.5), Vector3(-14, 0, 9.5)],
		Catalog.ZONE_SNACK: [Vector3(14, 0, 3.5), Vector3(14, 0, 9.5)],
	}
	for zone in shelf_rows:
		for pos in shelf_rows[zone]:
			_shelf(root, solid_rects, pos, 10.0, zone, slots)
	# 生鲜区:卧式冰柜(顶部开口取货),与货架行保持5米以上间距
	for fx in [-20.0, -14.0, -8.0]:
		_freezer(root, solid_rects, Vector3(fx, 0, -4), 4.0, Catalog.ZONE_FRESH, slots)
	# 促销堆头:全部放到开阔侧翼,不再挤在过道里
	_pallet(root, solid_rects, Vector3(-23, 0, 6.5), Catalog.ZONE_DAILY, slots)
	_pallet(root, solid_rects, Vector3(-5.5, 0, 6.5), Catalog.ZONE_DAILY, slots)
	_pallet(root, solid_rects, Vector3(5.5, 0, 6.5), Catalog.ZONE_SNACK, slots)
	_pallet(root, solid_rects, Vector3(23, 0, 6.5), Catalog.ZONE_SNACK, slots)

	# 中央"黑五爆款专区":高价值高折扣的必需品独立展台,四面开阔远离联排货架
	_premium_stand(root, solid_rects, Vector3(0, 0, -3.5), slots)
	_premium_stand(root, solid_rects, Vector3(0, 0, 2.5), slots)
	_premium_stand(root, solid_rects, Vector3(-3, 0, -0.5), slots)
	_premium_stand(root, solid_rects, Vector3(3, 0, -0.5), slots)
	_zone_sign(root, Vector3(0, 4.6, -0.5), "★ 黑五爆款专区 ★", Catalog.ZONE_COLORS[Catalog.ZONE_PREMIUM])

	# 家电区大件地堆(电视/跑步机各2台),放侧翼开阔带
	var tv_slots: Array = [Vector3(4.5, 0.5, -4.0), Vector3(7.5, 0.5, -4.0), Vector3(20.5, 0.5, -4.0), Vector3(23.5, 0.5, -4.0)]
	for tp in tv_slots:
		_box(root, Vector3(tp.x, 0.2, tp.z), Vector3(1.6, 0.4, 1.2), Color(0.72, 0.6, 0.45))
		solid_rects.append(Rect2(tp.x - 0.8, tp.z - 0.6, 1.6, 1.2))

	# 地滑区改为运行时随机生成(main负责):开局随机3块+保洁阿姨定时拖地+玩家水瓶

	# 特价事件投放点(各分区加宽后的主过道+中央专区)
	var sale_points: Array = [
		Vector3(-14, 0, -12), Vector3(14, 0, -12),
		Vector3(-14, 0, 6.5), Vector3(14, 0, 6.5), Vector3(0, 0, -0.5),
	]

	# 收银区标识
	_zone_sign(root, Vector3(-13, 3.4, 15.5), "收银区", Color(0.9, 0.35, 0.3))

	# 大妈出生点与囤货点
	var granny_spawns: Array = [
		Vector3(-24, 0, -16), Vector3(-4, 0, -16), Vector3(24, 0, -16), Vector3(-24, 0, 0),
		Vector3(24, 0, 0), Vector3(-4, 0, 9), Vector3(6, 0, 9), Vector3(24, 0, 9),
	]
	var stash_points: Array = [
		Vector3(-26, 0, -18), Vector3(26, 0, -18), Vector3(-26, 0, 9), Vector3(26, 0, 19),
	]

	# 无主购物车(偷窃/撞击测试靶)
	var parked_cart_spawns: Array = [Vector3(-10, 0, -7.5), Vector3(10, 0, 6)]

	# 寻路网格
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(GRID_MIN, GRID_SIZE)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	# 边界一圈实心
	for x in range(GRID_MIN.x, GRID_MIN.x + GRID_SIZE.x):
		grid.set_point_solid(Vector2i(x, GRID_MIN.y), true)
		grid.set_point_solid(Vector2i(x, GRID_MIN.y + GRID_SIZE.y - 1), true)
	for y in range(GRID_MIN.y, GRID_MIN.y + GRID_SIZE.y):
		grid.set_point_solid(Vector2i(GRID_MIN.x, y), true)
		grid.set_point_solid(Vector2i(GRID_MIN.x + GRID_SIZE.x - 1, y), true)
	for r in solid_rects:
		_mark_solid(grid, r)

	return {
		"slots": slots,
		"tv_slots": tv_slots,
		"sale_points": sale_points,
		"grid": grid,
		"granny_spawns": granny_spawns,
		"stash_points": stash_points,
		"player_spawn": Vector3(15, 0, 19.5),
		"parked_cart_spawns": parked_cart_spawns,
		"lane_x": [-18.0, -8.0],
	}

# ---------- 内部工具 ----------

static func _box(root: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos + Vector3(0, size.y * 0.5, 0) if pos.y == 0.0 else pos
	root.add_child(body)
	return body

static func _wall(root: Node3D, solids: Array, pos: Vector3, size: Vector3) -> void:
	_box(root, Vector3(pos.x, 0, pos.z), size, Color(0.62, 0.62, 0.64))
	solids.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))

## 货架:沿x向,货位在南北两侧×两层
static func _shelf(root: Node3D, solids: Array, pos: Vector3, length: float, zone: String, slots: Array) -> void:
	_box(root, pos, Vector3(length, 1.9, 1.2), Color(0.55, 0.57, 0.6))
	solids.append(Rect2(pos.x - length * 0.5, pos.z - 0.6, length, 1.2))
	# 两层置物板(视觉)
	for side in [-1.0, 1.0]:
		for level_y in [0.62, 1.22]:
			_ledge(root, Vector3(pos.x, level_y, pos.z + side * 0.75), Vector3(length, 0.05, 0.35))
			var n := int(length / 1.25)
			for i in n:
				var sx := pos.x - length * 0.5 + 1.25 * (i + 0.5)
				slots.append({
					# 置物板顶面高度;商品半高由摆货时补,底面正好贴板
					"pos": Vector3(sx, level_y + 0.025, pos.z + side * 0.78),
					"zone": zone,
				})

## 卧式冰柜:低矮开口柜,货位在顶面
static func _freezer(root: Node3D, solids: Array, pos: Vector3, length: float, zone: String, slots: Array) -> void:
	_box(root, pos, Vector3(length, 0.85, 1.3), Color(0.82, 0.9, 0.95))
	solids.append(Rect2(pos.x - length * 0.5, pos.z - 0.65, length, 1.3))
	var n := int(length / 0.9)
	for i in n:
		slots.append({
			"pos": Vector3(pos.x - length * 0.5 + 0.9 * (i + 0.5), 0.87, pos.z),
			"zone": zone,
		})

## 爆款展台:金色自发光底座,顶面四格货位(中央专区专用)
static func _premium_stand(root: Node3D, solids: Array, pos: Vector3, slots: Array) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 0.45, 1.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.1)
	mat.emission_energy_multiplier = 0.8
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 0.45, 1.7)
	cs.shape = bs
	body.add_child(cs)
	body.position = pos + Vector3(0, 0.225, 0)
	root.add_child(body)
	solids.append(Rect2(pos.x - 0.85, pos.z - 0.85, 1.7, 1.7))
	for ox in [-0.42, 0.42]:
		for oz in [-0.42, 0.42]:
			slots.append({
				"pos": Vector3(pos.x + ox, 0.48, pos.z + oz),
				"zone": Catalog.ZONE_PREMIUM,
			})

## 促销堆头:矮托盘,顶面四格货位
static func _pallet(root: Node3D, solids: Array, pos: Vector3, zone: String, slots: Array) -> void:
	_box(root, pos, Vector3(1.7, 0.3, 1.7), Color(0.72, 0.6, 0.45))
	solids.append(Rect2(pos.x - 0.85, pos.z - 0.85, 1.7, 1.7))
	for ox in [-0.42, 0.42]:
		for oz in [-0.42, 0.42]:
			slots.append({
				"pos": Vector3(pos.x + ox, 0.32, pos.z + oz),
				"zone": zone,
			})

static func _ledge(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Catalog.L_WORLD
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.7, 0.72)
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	root.add_child(body)

static func _zone_sign(root: Node3D, pos: Vector3, text: String, color: Color) -> void:
	# 自发光灯牌底板,配大号白字——远处一眼可见
	var plate := MeshInstance3D.new()
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(7.5, 1.7, 0.25)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = color.darkened(0.15)
	pmat.emission_enabled = true
	pmat.emission = color
	pmat.emission_energy_multiplier = 1.3
	pmesh.material = pmat
	plate.mesh = pmesh
	plate.position = pos
	root.add_child(plate)

	var lb := Label3D.new()
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
	root.add_child(lb)

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
