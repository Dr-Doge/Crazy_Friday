class_name Cart extends RigidBody3D
## 购物车:物理容器。车斗真实堆货,重量影响推力手感,车头撞击按部位结算失衡。
## 朝向约定:车头 -Z,车把 +Z。

const BASE_MASS := 20.0
const MIN_HIT_SPEED := 2.5
const ITEM_GRAVITY_FULL := 6.0      # 车内商品大重力(失衡0时)
const ITEM_GRAVITY_LOOSE := 0.55    # 失衡拉满时车内商品几乎没抓地,一撞就飞
const LATERAL_GRIP := 6.0           # 驾驶时的侧向抓地,产生"车"的循迹感(越大越不漂)

var cart_owner: Node3D = null       # 车主(null=无主车)
var attached_agent: Actor = null    # 正在推车的人
var sprinting := false
var sprint_level := 0.0             # 0-1,玩家蓄力冲刺进度,决定限速上限
var basket_area: Area3D
var alert_label: Label3D            # 被偷提示"!"
var highlight_mesh: MeshInstance3D  # 红色高亮壳(玩家目标商品在此车中)
var _recent_hits := {}
var _mass_timer := 0.0
var _alert_timer := 0.0
var _grav_timer := 0.0
var _grav_items: Array[Item] = []

static func create(color: Color, title: String) -> Cart:
	var c := Cart.new()
	c.name = "Cart_" + title
	c.mass = BASE_MASS
	c.collision_layer = Catalog.L_CART
	c.collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART | Catalog.L_ITEM
	c.linear_damp = 1.6
	c.angular_damp = 6.5
	c.contact_monitor = true
	c.max_contacts_reported = 8
	c.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	c.center_of_mass = Vector3(0, 0.18, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15
	pm.bounce = 0.05
	c.physics_material_override = pm

	# 车斗:底板+四壁(网格与碰撞一致),加大版
	var parts := [
		[Vector3(0, 0.55, 0), Vector3(1.05, 0.06, 1.5)],       # 底板
		[Vector3(0, 0.86, -0.74), Vector3(1.05, 0.62, 0.05)],  # 前壁
		[Vector3(0, 0.86, 0.74), Vector3(1.05, 0.62, 0.05)],   # 后壁
		[Vector3(-0.515, 0.86, 0), Vector3(0.05, 0.62, 1.5)],  # 左壁
		[Vector3(0.515, 0.86, 0), Vector3(0.05, 0.62, 1.5)],   # 右壁
		[Vector3(0, 1.25, 0.92), Vector3(1.1, 0.07, 0.07)],    # 车把
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.82)
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		bm.material = mat
		mi.mesh = bm
		mi.position = p[0]
		c.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p[1]
		cs.shape = bs
		cs.position = p[0]
		c.add_child(cs)

	# 四个滑轮(低摩擦球碰撞)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.25, 0.25, 0.28)
	for wx in [-0.42, 0.42]:
		for wz in [-0.6, 0.6]:
			var ws := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = 0.14
			ws.shape = sp
			ws.position = Vector3(wx, 0.14, wz)
			c.add_child(ws)
			var wm := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.14
			sm.height = 0.28
			sm.material = wheel_mat
			wm.mesh = sm
			wm.position = Vector3(wx, 0.14, wz)
			c.add_child(wm)

	# 车主旗标
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.18, 0.18, 0.18)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = color
	fm.material = fmat
	flag.mesh = fm
	flag.position = Vector3(0, 1.5, 0.92)
	c.add_child(flag)

	var lb := Label3D.new()
	lb.text = title
	lb.font = Catalog.ui_font()
	lb.font_size = 52
	lb.pixel_size = 0.004
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.outline_size = 10
	lb.outline_modulate = Color(0, 0, 0, 0.8)
	lb.modulate = color.lightened(0.3)
	lb.position = Vector3(0, 1.8, 0.6)
	c.add_child(lb)

	# 被偷提示
	var al := Label3D.new()
	al.text = "!"
	al.font = Catalog.ui_font()
	al.font_size = 110
	al.pixel_size = 0.006
	al.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	al.no_depth_test = true
	al.modulate = Color(1, 0.25, 0.2)
	al.outline_size = 14
	al.position = Vector3(0, 2.25, 0)
	al.visible = false
	c.add_child(al)
	c.alert_label = al

	# 车斗感应区:统计斗内商品
	var area := Area3D.new()
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = Catalog.L_ITEM
	var acs := CollisionShape3D.new()
	var abs_shape := BoxShape3D.new()
	abs_shape.size = Vector3(1.0, 1.0, 1.45)
	acs.shape = abs_shape
	acs.position = Vector3(0, 1.12, 0)
	area.add_child(acs)
	c.add_child(area)
	c.basket_area = area

	# 红色高亮壳:玩家清单商品在这辆车里时点亮(反面剔除→外描边观感)
	var hl := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(1.4, 1.7, 1.9)
	var hlmat := StandardMaterial3D.new()
	hlmat.albedo_color = Color(1, 0.12, 0.08, 0.32)
	hlmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hlmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hlmat.cull_mode = BaseMaterial3D.CULL_FRONT
	hb.material = hlmat
	hl.mesh = hb
	hl.position = Vector3(0, 0.85, 0)
	hl.visible = false
	c.add_child(hl)
	c.highlight_mesh = hl

	c.add_to_group("carts")
	c.body_entered.connect(c._on_body_entered)
	return c

func set_highlight(on: bool) -> void:
	if highlight_mesh:
		highlight_mesh.visible = on

func handle_pos() -> Vector3:
	return to_global(Vector3(0, 0, 1.28))

func items_in_basket() -> Array[Item]:
	var out: Array[Item] = []
	for b in basket_area.get_overlapping_bodies():
		if b is Item and b.state == Item.ItemState.FREE:
			out.append(b)
	return out

func _physics_process(delta: float) -> void:
	_mass_timer -= delta
	if _mass_timer <= 0.0:
		_mass_timer = 0.5
		var m := BASE_MASS
		for it in items_in_basket():
			m += it.mass
		mass = m
	if _alert_timer > 0.0:
		_alert_timer -= delta
		if _alert_timer <= 0.0 and alert_label:
			alert_label.visible = false

	# 车内商品动态重力:失衡0=大重力粘在车里,失衡满=轻飘飘一撞就飞
	_grav_timer -= delta
	if _grav_timer <= 0.0:
		_grav_timer = 0.25
		var current := items_in_basket()
		for it in _grav_items:
			if is_instance_valid(it) and not current.has(it):
				it.gravity_scale = 1.0
		_grav_items = current
	var imb := attached_agent.imbalance if attached_agent != null else 0.0
	var gscale := lerpf(ITEM_GRAVITY_FULL, ITEM_GRAVITY_LOOSE, clampf(imb / 100.0, 0.0, 1.0))
	for it in _grav_items:
		if is_instance_valid(it) and it.state == Item.ItemState.FREE:
			it.gravity_scale = gscale

	# 驾驶中给侧向抓地,让推车有"车"的循迹感而不是溜冰
	if attached_agent != null:
		var side := global_transform.basis.x
		side.y = 0.0
		if side.length() > 0.01:
			side = side.normalized()
			var lat := side.dot(linear_velocity)
			apply_central_force(-side * lat * mass * LATERAL_GRIP)
	else:
		sprint_level = move_toward(sprint_level, 0.0, 2.0 * delta)

	# 限速:软限制,避免硬钳制造成的高速抖动
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var cap := 6.0 + 2.8 * sprint_level
	if hv.length() > cap:
		hv = hv.lerp(hv.normalized() * cap, 0.35)
		linear_velocity.x = hv.x
		linear_velocity.z = hv.z
	# 兜底:跌出世界拉回入口
	if global_position.y < -5.0:
		global_position = MapLayout.respawn_pos(0.5)
		global_rotation = Vector3.ZERO
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		reset_physics_interpolation()

## 载重越大越难加速/转向的系数(1=空车)
func load_factor() -> float:
	return BASE_MASS / mass

## 从车斗抽走最上面一件(偷窃/扫码共用)
func take_top_item() -> Item:
	var items := items_in_basket()
	if items.is_empty():
		return null
	var top: Item = items[0]
	for it in items:
		if it.global_position.y > top.global_position.y:
			top = it
	return top

func show_steal_alert() -> void:
	if alert_label:
		alert_label.visible = true
	_alert_timer = 2.0

## 侧翻回正:被重新抓住时自动扶正(保留朝向,竖直归零)
func right_up() -> void:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = global_transform.basis.y
		f.y = 0.0
	if f.length() < 0.1:
		f = Vector3.FORWARD
	var yaw := atan2(-f.x, -f.z)
	global_position.y += 0.15
	global_rotation = Vector3(0, yaw, 0)
	linear_velocity = Vector3(linear_velocity.x * 0.2, 0, linear_velocity.z * 0.2)
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()

## 被肘击时从车斗里肘飞随机一件
func eject_random_item() -> Item:
	var items := items_in_basket()
	if items.is_empty():
		return null
	var it: Item = items.pick_random()
	it.gravity_scale = 1.0
	var dir := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	it.apply_central_impulse((dir.normalized() * 2.5 + Vector3.UP * 4.2) * it.mass)
	Main.float_text(self, it.global_position + Vector3.UP * 0.6, "肘飞了 " + it.display_name + "!", Color(1, 0.6, 0.3))
	return it

## 倒地/翻车时甩货
func spill(fraction: float) -> void:
	for it in items_in_basket():
		if randf() < fraction:
			it.gravity_scale = 1.0   # 飞出瞬间恢复常规重力,保证能飞出车斗
			it.apply_central_impulse(Vector3(randf_range(-2.5, 2.5), randf_range(3.0, 5.0), randf_range(-2.5, 2.5)) * it.mass)
	apply_torque_impulse(Vector3(randf_range(-14, 14), randf_range(-8, 8), randf_range(-14, 14)))

## 撞击结算(策划案第六节表格)
func _on_body_entered(body: Node) -> void:
	if body is Item:
		return
	var now := Time.get_ticks_msec() * 0.001
	var key := body.get_instance_id()
	if now - float(_recent_hits.get(key, -10.0)) < 0.8:
		return
	_recent_hits[key] = now

	var myv := linear_velocity
	myv.y = 0.0
	var speed := myv.length()
	if speed < MIN_HIT_SPEED:
		return
	var toward: Vector3 = body.global_position - global_position
	toward.y = 0.0
	if toward.length() < 0.01 or myv.normalized().dot(toward.normalized()) < 0.3:
		return

	if body is Cart:
		var victim: Actor = body.attached_agent
		var local: Vector3 = body.to_local(global_position)
		var amount := 0.0
		var kind := ""
		if absf(local.x) > absf(local.z):
			amount = 60.0 if sprinting else 45.0
			kind = "侧撞"
		elif local.z > 0.0:
			amount = 25.0
			kind = "追尾"
		else:
			amount = 15.0
			kind = "对撞"
		# 撞击双方都按部位吃失衡:攻方吃"车头撞击"+15,守方按被撞部位
		# 注意:add_imbalance可能当场击倒攻方并导致人车分离,先留住局部引用
		var atk: Actor = attached_agent
		if atk != null:
			atk.add_imbalance(15.0, body)
			Main.float_text(atk, atk.global_position + Vector3.UP * 2.2, "%s 车头+15" % Main.bam(), Color(1, 0.6, 0.25), 68)
		# 一次碰撞只结算一次,抑制对方处理器重复触发
		body._recent_hits[get_instance_id()] = now
		if victim != null:
			victim.add_imbalance(amount, self)
			Main.float_text(victim, victim.global_position + Vector3.UP * 2.2, "%s %s+%d" % [Main.bam(), kind, int(amount)], Color(1, 0.5, 0.2), 80)
			victim.on_cart_hit(self)
		# 涉及玩家的撞击→震对应玩家所在机器的相机(用局部引用,攻方可能已被击倒分离)
		if Main.instance != null:
			var sv := clampf(speed / 10.0, 0.3, 0.8)
			if atk is Player:
				Main.instance.shake_for(atk, sv)
			if victim is Player:
				Main.instance.shake_for(victim, sv)
	elif body is Actor:
		body.hit_by_cart(self)
