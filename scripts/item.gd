class_name Item extends RigidBody3D
## 白盒商品:真实物理刚体。货架上冻结,手持时冻结随人,车斗内自由堆叠。

enum ItemState { SHELVED, HELD, FREE, SCANNED }

var item_id := ""
var display_name := ""
var category := ""
var state: ItemState = ItemState.FREE
var box_size := Vector3.ONE
var label: Label3D
var ping_shell: MeshInstance3D   # 找货雷达的绿色高亮壳

static func create(id: String) -> Item:
	var data: Dictionary = Catalog.ITEMS[id]
	var it := Item.new()
	it.name = "Item_" + id
	it.item_id = id
	it.display_name = data["name"]
	it.category = data["cat"]
	it.box_size = data["size"]
	it.mass = maxf(0.6, it.box_size.x * it.box_size.y * it.box_size.z * 22.0)
	it.collision_layer = Catalog.L_ITEM
	it.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
	it.linear_damp = 0.5
	it.angular_damp = 2.0
	it.can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.0
	it.physics_material_override = pm

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = it.box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data["color"]
	box.material = mat
	mesh.mesh = box
	it.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = it.box_size
	col.shape = shape
	it.add_child(col)

	var lb := Label3D.new()
	lb.text = data["name"]
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
