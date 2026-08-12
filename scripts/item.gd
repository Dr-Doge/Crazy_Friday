class_name Item extends RigidBody3D
## 白盒商品:真实物理刚体。货架上冻结,手持时冻结随人,车斗内自由堆叠。

enum ItemState { SHELVED, HELD, FREE, SCANNED }

## 碰撞体的最小厚度(米)。**视觉网格仍用真实尺寸,只加厚物理代理**。
##
## 为什么必须这样:三文鱼刺身盒(0.12)、冻披萨(0.12)、大米(0.15)这类扁平商品,
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
var label: Label3D
var ping_shell: MeshInstance3D   # 找货雷达的绿色高亮壳
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

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = it.collider_size()  # 物理:各轴不低于最小厚度
	col.shape = shape
	it.add_child(col)

	var lb := Label3D.new()
	lb.text = str(data["name"])
	lb.font = Catalog.ui_font()
	lb.font_size = 54
	lb.pixel_size = 0.004
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	# 名称用商品本体色,一眼分辨
	lb.modulate = Color(data["color"]).darkened(0.45)
	lb.outline_size = 12
	lb.outline_modulate = Color(1, 1, 1, 0.9)
	lb.position = Vector3(0, it.box_size.y * 0.5 + 0.22, 0)
	it.add_child(lb)
	it.label = lb

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

## 标记"刚被甩出",在豁免期内不被购物车接管重力与限速
func mark_flung() -> void:
	fling_grace = FLING_GRACE
	gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	if fling_grace > 0.0:
		fling_grace -= delta

## 冻结摆上货架
func set_shelved(pos: Vector3) -> void:
	state = ItemState.SHELVED
	freeze = true
	gravity_scale = 1.0
	collision_layer = Catalog.L_ITEM
	collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
	global_position = pos
	global_rotation = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## 被拿到手上:冻结、关碰撞,由持有者每帧摆位
func set_held() -> void:
	state = ItemState.HELD
	freeze = true
	gravity_scale = 1.0
	collision_layer = 0
	collision_mask = 0

## 释放为自由物理体(落地/入车/被打飞)
func set_free_at(pos: Vector3, impulse := Vector3.ZERO) -> void:
	state = ItemState.FREE
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
	state = ItemState.SCANNED
	freeze = true
	collision_layer = 0
	collision_mask = 0
	global_position = pos
	global_rotation = Vector3.ZERO
	if label:
		label.modulate = Color(0.1, 0.55, 0.2)
		label.text = display_name + " ✓"
