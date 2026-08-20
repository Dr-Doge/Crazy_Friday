class_name Item extends RigidBody3D
## 白盒商品:真实物理刚体。货架上冻结,手持时冻结随人,车斗内自由堆叠。

enum ItemState { SHELVED, HELD, FREE, SCANNED }

## 碰撞体的最小厚度(米)。**视觉网格仍用真实尺寸,只加厚物理代理**。
##
## 为什么必须这样:哈兰德三文鱼(0.12)、冻披萨(0.12)、大米(0.15)这类扁平商品,
## 若碰撞体与外形等厚,在车斗里被重物挤压时接触求解极不稳定,会被弹射到
## 20+ m/s;而 60Hz 下21 m/s 的单帧位移是 0.36 米,足以直接穿过车斗底板
## 飞出地图。加厚物理代理是解决扁平刚体穿模的标准做法,代价只是堆叠时
## 有几厘米视觉间隙(在 1.05 米宽的车斗里看不出来)。
const MIN_COLLIDER_THICKNESS := 0.16

## 质量下限。原为 0.6,导致电视(5.05kg)与三文鱼盒(0.6kg)质量比高达 12:1,
##悬殊质量比是接触求解器把轻物体弹射出去的主因。抬到 1.2 后压到约 4:1。
## 注意:这会让满载车略重(load_factor 约 -9%),手感需实测确认。
const MIN_MASS := 1.2

## 被甩出/肘飞后的物理豁免期(秒)。
## 期间不受购物车"车内大重力 + 限速"托管,否则刚甩出去就被重新吸住。
const FLING_GRACE := 0.6
var item_id := ""
var display_name := ""
var category := ""
var state: ItemState = ItemState.FREE
var box_size := Vector3.ONE
var label: Label3D = null # 白盒商品的首个表面标签；正式美术模型保持为空。
var surface_labels: Array[Label3D] = []
var visual_mesh: MeshInstance3D
var visual_root: Node3D
var _visual_base_color := Color.WHITE
var _live_hit_tween: Tween
var ping_shell: MeshInstance3D   # 找货雷达的绿色高亮壳
var _cart_label_sources := {}    # 正处于哪些车斗感应区；非空时隐藏商品头顶名称
## 中央黑五区开门前使用。锁定商品保持SHELVED，但不可见、不可射线选取、不可被AI锁定。
var event_locked := false
## >0 时表示刚被甩出,购物车不要接管它的重力与速度
var fling_grace := 0.0

static func create(id: String) -> Item:
	var data: Dictionary = Catalog.ITEMS[id]
	var it := Item.new()
	it.name = "Item_" + id
	it.item_id = id
	it.display_name = data["name"]
	it.category = data["cat"]
	it.box_size = data["size"]
	it.mass = maxf(MIN_MASS, it.box_size.x * it.box_size.y * it.box_size.z * 22.0)
	it.collision_layer = Catalog.L_ITEM
	it.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
	it.linear_damp = 0.5
	it.angular_damp = 2.0
	it.can_sleep = true
	# 连续碰撞检测:商品会被撞击/甩货加速到很高速度,离散检测必然漏掉薄板穿透
	it.continuous_cd = true
	# 提高求解迭代:车斗内是多体堆叠,默认迭代数下扁平体容易被挤穿
	it.max_contacts_reported = 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.0
	it.physics_material_override = pm

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = it.box_size          # 视觉:真实尺寸
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data["color"]
	box.material = mat
	mesh.mesh = box
	it.add_child(mesh)
	it.visual_mesh = mesh
	it.visual_root = mesh
	it._visual_base_color = data["color"]
	# 正式商品模型采用等比包围盒内接，最大尺寸不会越过Catalog规定的白盒。
	# 缺少对应资产的专区继续显示白盒，便于美术逐批交付而不破坏玩法。
	var art_visual := ArtAssetFitter.create_product_visual(id, it.box_size)
	if art_visual != null:
		mesh.visible = false
		it.add_child(art_visual)
		it.visual_root = art_visual
		var imported_mesh := ArtAssetFitter.first_mesh(art_visual)
		if imported_mesh != null:
			it.visual_mesh = imported_mesh
	else:
		# 尚未替换正式美术资产的彩色白盒缺少包装辨识度，因此把名称作为
		# 包装印字贴回模型表面。正式模型依靠自身贴图，只保留瞄准注释卡。
		it._build_surface_labels(str(data["name"]), Color(data["color"]).darkened(0.5))

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = it.collider_size()  # 物理:各轴不低于最小厚度
	col.shape = shape
	it.add_child(col)

	# 正式商品名称只在玩家瞄准时由HUD注释卡显示；白盒商品同时保留表面印字。

	# 找货雷达高亮壳:绿色描边,穿墙可见,平时隐藏
	var ping := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = it.box_size * 1.3 + Vector3(0.08, 0.08, 0.08)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 1.0, 0.4, 0.45)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.cull_mode = BaseMaterial3D.CULL_FRONT
	pmat.no_depth_test = true
	pb.material = pmat
	ping.mesh = pb
	ping.visible = false
	it.add_child(ping)
	it.ping_shell = ping

	it.add_to_group("items")
	return it

## 物理碰撞体尺寸:各轴不低于 MIN_COLLIDER_THICKNESS(视觉网格不受影响)
func collider_size() -> Vector3:
	return Vector3(
			maxf(box_size.x, MIN_COLLIDER_THICKNESS),
			maxf(box_size.y, MIN_COLLIDER_THICKNESS),
			maxf(box_size.z, MIN_COLLIDER_THICKNESS))

## 物理代理的半高(购物车摆位与判定用真实的物理高度,而非视觉高度)
func collider_half_height() -> float:
	return maxf(box_size.y, MIN_COLLIDER_THICKNESS) * 0.5

## 货架白盒阶段用2倍展示尺寸填满层板；离架后立即恢复真实物理尺寸。
func shelf_display_half_height() -> float:
	# 扁平包装上架时绕X轴立起，陈列高度因此取Y/Z中的较大值。
	return maxf(box_size.y, box_size.z) * 0.5 * Catalog.SHELF_DISPLAY_SCALE

func _build_surface_labels(text: String, color: Color) -> void:
	var axis := 0
	if box_size.y <= box_size.x and box_size.y <= box_size.z:
		axis = 1
	elif box_size.z <= box_size.x and box_size.z <= box_size.y:
		axis = 2
	for sign_value in [-1.0, 1.0]:
		var lb := Label3D.new()
		lb.text = text
		lb.font = Catalog.ui_font_bold()
		lb.font_size = 54
		var face_width := box_size.x if axis != 0 else box_size.z
		lb.pixel_size = minf(0.0032, face_width / maxf(120.0, text.length() * 33.0))
		lb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lb.no_depth_test = false
		lb.modulate = color
		lb.outline_size = 10
		lb.outline_modulate = Color(1, 1, 1, 0.92)
		match axis:
			0:
				lb.position.x = sign_value * (box_size.x * 0.5 + 0.006)
				lb.rotation.y = sign_value * PI * 0.5
			1:
				lb.position.y = sign_value * (box_size.y * 0.5 + 0.006)
				lb.rotation.x = -sign_value * PI * 0.5
			2:
				lb.position.z = sign_value * (box_size.z * 0.5 + 0.006)
				lb.rotation.y = 0.0 if sign_value > 0.0 else PI
		add_child(lb)
		surface_labels.append(lb)
	label = surface_labels[0]

func apply_state_scale() -> void:
	scale = Vector3.ONE * (Catalog.SHELF_DISPLAY_SCALE \
			if state == ItemState.SHELVED else 1.0)

## 标记"刚被甩出",在豁免期内不被购物车接管重力与限速
func mark_flung() -> void:
	fling_grace = FLING_GRACE
	gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	if fling_grace > 0.0:
		fling_grace -= delta
	_refresh_label_visibility()

## 车内商品只保留实体外观和轮盘提示，不再用一叠穿透文字遮挡驾驶视野。
## 用来源集合处理两辆购物车感应区短暂重叠的情况，任意车斗仍包含它就继续隐藏。
func set_cart_label_hidden(source: Object, hidden: bool) -> void:
	if source == null:
		return
	var key := source.get_instance_id()
	if hidden:
		_cart_label_sources[key] = true
	else:
		_cart_label_sources.erase(key)
	_refresh_label_visibility()

func clear_cart_label_hides() -> void:
	_cart_label_sources.clear()
	_refresh_label_visibility()

func _refresh_label_visibility() -> void:
	for lb in surface_labels:
		if is_instance_valid(lb):
			lb.visible = not event_locked

## 地面活鲜被肘击时做极端压扁+回弹并闪成白粉色，反馈只作用视觉网格，
## 不缩放刚体根节点和碰撞体，避免物理求解因瞬时缩放发散。
func play_live_hit_feedback() -> void:
	if not bool(get_meta("live_fresh_good", false)) or not is_instance_valid(visual_root):
		return
	if _live_hit_tween != null and _live_hit_tween.is_valid():
		_live_hit_tween.kill()
	# 白盒BoxMesh可以安全改色；导入模型的ArrayMesh材质可能跨实例共享，
	# 这里只做形变反馈，避免一次击打把同款商品全部染色。
	var mat: StandardMaterial3D = null
	if visual_root == visual_mesh and is_instance_valid(visual_mesh) \
			and visual_mesh.mesh != null and visual_mesh.mesh.get_surface_count() > 0:
		mat = visual_mesh.get_active_material(0) as StandardMaterial3D
	visual_root.scale = Vector3(1.75, 0.28, 1.45)
	if mat != null:
		mat.albedo_color = Color(1.0, 0.72, 0.88)
	_live_hit_tween = create_tween().set_parallel(true)
	_live_hit_tween.tween_property(visual_root, "scale", Vector3.ONE, 0.42) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if mat != null:
		_live_hit_tween.tween_property(mat, "albedo_color", _visual_base_color, 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 冻结摆上货架
func set_shelved(pos: Vector3, shelf_yaw := 0.0) -> void:
	clear_cart_label_hides()
	state = ItemState.SHELVED
	apply_state_scale()
	freeze = true
	gravity_scale = 1.0
	# 陈列商品只保留视觉与准星交互，不参与刚体碰撞，避免包装突出货架卡住过道。
	collision_layer = 0
	collision_mask = 0
	global_position = pos
	# 扁平包装仍立起陈列；所有模型统一约定本地+Z为包装正面。
	var label_face_is_horizontal := visual_root == visual_mesh \
			and box_size.y <= box_size.x and box_size.y <= box_size.z
	var stand_pitch := -PI * 0.5 if label_face_is_horizontal else 0.0
	global_rotation = Vector3(stand_pitch, shelf_yaw, 0.0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## 压轴区商品的显隐/交互锁。它不是新的商品状态，开门后仍可沿用普通货架拿取流程。
func set_event_locked(locked: bool) -> void:
	event_locked = locked
	visible = not locked
	if locked:
		collision_layer = 0
		collision_mask = 0
	elif state == ItemState.SHELVED:
		collision_layer = 0
		collision_mask = 0

## 被拿到手上:冻结、关碰撞,由持有者每帧摆位
func set_held() -> void:
	clear_cart_label_hides()
	state = ItemState.HELD
	apply_state_scale()
	freeze = true
	gravity_scale = 1.0
	collision_layer = 0
	collision_mask = 0

## 释放为自由物理体(落地/入车/被打飞)
func set_free_at(pos: Vector3, impulse := Vector3.ZERO) -> void:
	clear_cart_label_hides()
	state = ItemState.FREE
	apply_state_scale()
	global_position = pos
	gravity_scale = 1.0
	collision_layer = Catalog.L_ITEM
	collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if impulse != Vector3.ZERO:
		apply_central_impulse(impulse)

## 已扫码:冻结在收银带上,不可偷不可撞散
func set_scanned_at(pos: Vector3) -> void:
	clear_cart_label_hides()
	state = ItemState.SCANNED
	apply_state_scale()
	freeze = true
	collision_layer = 0
	collision_mask = 0
	global_position = pos
	global_rotation = Vector3.ZERO
