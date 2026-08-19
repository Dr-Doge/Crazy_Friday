class_name Cart extends RigidBody3D
## 购物车:物理容器。车斗真实堆货,重量影响推力手感,车头撞击按部位结算失衡。
## 朝向约定:车头 -Z,车把 +Z。

const BASE_MASS := 20.0
const MIN_HIT_SPEED := 2.5
const ITEM_GRAVITY_FULL := 6.0      # 车内商品大重力(失衡0时)
const ITEM_GRAVITY_LOOSE := 0.55    # 失衡拉满时车内商品几乎没抓地,一撞就飞
const LATERAL_GRIP := 6.0           # 驾驶时的侧向抓地,产生"车"的循迹感(越大越不漂)

## 撞击结算后给双方的分离冲量(每千克)。追尾与车头对撞时两车会正面顶住,
## 没有这一下就会"焊在一起"谁也推不动。
const SEPARATE_IMPULSE := 2.2
const CONTACT_UNLOCK_TIME := 0.22  # 两车持续接触多久后主动解除互锁
const CONTACT_UNLOCK_IMPULSE := 0.9
const ACTOR_RESCUE_INTERVAL := 0.08
const CART_CCD_RANGE := 4.5

## 车内商品相对车斗的最大速度(米/秒)。
##
## 这是防穿模的**治本一环**:实测显示扁平商品被挤压时能被弹射到 21 m/s,
## 而 60Hz 下这意味着单帧位移 0.36 米——远超车斗任何一块板的厚度,
## 必然穿透。车内货物本就该"跟着车走",给相对速度设上限不影响手感,
## 反而强化"大重力粘在车里"的设计意图。
## 注意:被甩出/肘飞的商品处于豁免期(Item.fling_grace),不受此限制。
const ITEM_REL_SPEED_CAP := 7.0

## 车斗板厚。原为底板0.06/侧壁 0.05,薄到无法拦住高速小物件;
## 加厚后即使偶发高速也有足够的穿透余量。
const FLOOR_T := 0.18
const WALL_T := 0.12

## 车斗内腔(加厚只向外扩,这些值保持不变→装货容积与手感不变)
const FLOOR_TOP := 0.58      # 内底面高度,装货的基准面
const WALL_H := 0.62         # 侧壁高
const INNER_HALF_X := 0.49   # 内半宽
const INNER_HALF_Z := 0.715  # 内半长

var cart_owner: Node3D = null       # 车主(null=无主车)
var attached_agent: Actor = null    # 正在推车的人
var sprinting := false
var sprint_level := 0.0             # 0-1,玩家蓄力冲刺进度,决定限速上限
var basket_area: Area3D
var alert_label: Label3D            # 被偷提示"!"
var hot_label: Label3D              # 「爆款嗅觉」:车顶浮出的具体商品名(仅李洋可见)
var highlight_mesh: MeshInstance3D  # 红色高亮壳(玩家目标商品在此车中)
## 侧向抓地系数(赵冬梅「压弯」被动×1.2;由推车人每帧设置,松手即复位)
var grip_mult := 1.0
## 车头撞击倍率与其剩余时长(赵冬梅「贴地冲撞」推车突进时 ×1.5)
var hit_mult := 1.0
var hit_mult_time := 0.0
## 限速上限的临时加成(赵冬梅「贴地冲撞」推车突进用)。
## 常规限速 cap=6.0 会把突进速度在几帧内钳回去,必须在窗口内抬高上限。
var speed_cap_bonus := 0.0
var _speed_cap_timer := 0.0
var _recent_hits := {}
var _cart_contact_time := {}
var _mass_timer := 0.0
var _alert_timer := 0.0
var _grav_timer := 0.0
var _grav_items: Array[Item] = []
var _actor_rescue_timer := 0.0
var _ccd_scan_timer := 0.0

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
	# 单车常开CCD会扰动车内商品；仅在邻车接近或技能高速窗口动态开启。
	c.continuous_cd = false
	c.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	c.center_of_mass = Vector3(0, 0.18, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15
	pm.bounce = 0.05
	c.physics_material_override = pm

	# 车斗:底板+四壁(网格与碰撞一致)。
	# 板一律"向外加厚",保持内腔尺寸不变(内底面 FLOOR_TOP、内半宽/半长如下),
	# 这样加厚不会改变装货容积,也不影响 basket_area 的覆盖关系。
	var fz := FLOOR_TOP - FLOOR_T * 0.5              # 底板中心
	var wy := FLOOR_TOP -0.03 + WALL_H * 0.5        # 侧壁中心(略埋进底板,防缝隙)
	var hx := INNER_HALF_X + WALL_T * 0.5            # 左右壁中心
	var hz := INNER_HALF_Z + WALL_T * 0.5            # 前后壁中心
	var outer_x := INNER_HALF_X * 2.0 + WALL_T * 2.0
	var outer_z := INNER_HALF_Z * 2.0 + WALL_T * 2.0
	var parts := [
		[Vector3(0, fz, 0), Vector3(outer_x, FLOOR_T, outer_z)],        # 底板
		[Vector3(0, wy, -hz), Vector3(outer_x, WALL_H, WALL_T)],        # 前壁
		[Vector3(0, wy, hz), Vector3(outer_x, WALL_H, WALL_T)],         # 后壁
		[Vector3(-hx, wy, 0), Vector3(WALL_T, WALL_H, outer_z)],        # 左壁
		[Vector3(hx, wy, 0), Vector3(WALL_T, WALL_H, outer_z)],         # 右壁
		[Vector3(0, 1.25, 0.92), Vector3(1.1, 0.07, 0.07)],             # 车把
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

	# 「爆款嗅觉」(李洋被动):车顶浮出这车里有你要的哪一件
	var hb_lb := Label3D.new()
	hb_lb.text = ""
	hb_lb.font = Catalog.ui_font_bold()
	hb_lb.font_size = 58
	hb_lb.pixel_size = 0.005
	hb_lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hb_lb.no_depth_test = true
	hb_lb.modulate = Color(1, 0.45, 0.62)
	hb_lb.outline_size = 16
	hb_lb.outline_modulate = Color(0.1, 0, 0.05, 0.9)
	hb_lb.position = Vector3(0,2.6, 0)
	hb_lb.visible = false
	c.add_child(hb_lb)
	c.hot_label = hb_lb

	# 车斗感应区:统计斗内商品
	var area := Area3D.new()
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = Catalog.L_ITEM | Catalog.L_CHAR
	var acs := CollisionShape3D.new()
	var abs_shape := BoxShape3D.new()
	abs_shape.size = Vector3(1.0, 1.0, 1.45)
	acs.shape = abs_shape
	acs.position = Vector3(0, 1.12, 0)
	area.add_child(acs)
	c.add_child(area)
	c.basket_area = area
	area.body_entered.connect(c._on_basket_body_entered)
	area.body_exited.connect(c._on_basket_body_exited)

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
	if not on and hot_label != null:
		hot_label.visible = false

## 「爆款嗅觉」:除红壳外再显示具体商品名(只有李洋会收到 name != "")
func set_hot_name(text: String) -> void:
	if hot_label == null:
		return
	hot_label.text = text
	hot_label.visible = text != ""

## 扎马步中:车斗锁死(甩货与肘飞一律失败)
func is_locked() -> bool:
	return attached_agent != null and attached_agent.stance

func handle_pos() -> Vector3:
	return to_global(Vector3(0, 0, 1.28))

func items_in_basket() -> Array[Item]:
	var out: Array[Item] = []
	for b in basket_area.get_overlapping_bodies():
		if b is Item and b.state == Item.ItemState.FREE:
			out.append(b)
	return out

func _on_basket_body_entered(body: Node3D) -> void:
	if body is Item and body.state == Item.ItemState.FREE:
		body.set_cart_label_hidden(self, true)

func _on_basket_body_exited(body: Node3D) -> void:
	if body is Item:
		body.set_cart_label_hidden(self, false)

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
				it.set_cart_label_hidden(self, false)
		for it in current:
			if is_instance_valid(it):
				it.set_cart_label_hidden(self, true)
		_grav_items = current
	var imb := attached_agent.imbalance if attached_agent != null else 0.0
	var gscale := lerpf(ITEM_GRAVITY_FULL, ITEM_GRAVITY_LOOSE, clampf(imb / 100.0, 0.0, 1.0))
	for it in _grav_items:
		if not is_instance_valid(it) or it.state != Item.ItemState.FREE:
			continue
		# 刚被甩出/肘飞的货处于豁免期:别把它重新吸回车里
		if it.fling_grace > 0.0:
			continue
		it.gravity_scale = gscale
		# 限制相对车斗的速度。挤压弹射能把扁平商品加速到 20+ m/s,
		# 那样单帧位移会远超板厚而直接穿模飞出地图(v0.14实测缺陷)。
		var rel := it.linear_velocity - linear_velocity
		if rel.length() > ITEM_REL_SPEED_CAP:
			it.linear_velocity = linear_velocity + rel.normalized() * ITEM_REL_SPEED_CAP

	# 驾驶中给侧向抓地,让推车有"车"的循迹感而不是溜冰
	# grip_mult:赵冬梅「压弯」被动 ×1.2(抗漂),由player.gd 每帧设置
	if hit_mult_time > 0.0:
		hit_mult_time -= delta
		if hit_mult_time <= 0.0:
			hit_mult = 1.0
	if _speed_cap_timer > 0.0:
		_speed_cap_timer -= delta
		if _speed_cap_timer <= 0.0:
			speed_cap_bonus = 0.0
	_ccd_scan_timer -= delta
	if _ccd_scan_timer <= 0.0:
		_ccd_scan_timer = 0.1
		_refresh_cart_ccd()
	# 持续接触复查:body_entered 只在接触起始帧触发,追尾/对撞贴住时会漏判
	_sweep_contacts(delta)
	_actor_rescue_timer -= delta
	if _actor_rescue_timer <= 0.0:
		_actor_rescue_timer = ACTOR_RESCUE_INTERVAL
		_rescue_trapped_actors()
	if attached_agent != null:
		var side := global_transform.basis.x
		side.y = 0.0
		if side.length() > 0.01:
			side = side.normalized()
			var lat := side.dot(linear_velocity)
			apply_central_force(-side * lat * mass * LATERAL_GRIP * grip_mult)
	else:
		sprint_level = move_toward(sprint_level, 0.0, 2.0 * delta)
		grip_mult = 1.0

	# 限速:软限制,避免硬钳制造成的高速抖动
	# speed_cap_bonus:突进窗口内临时放开(见 lift_speed_cap)
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var movement_mult := attached_agent.movement_factor() if attached_agent != null else 1.0
	var cap := (6.0 + 2.8 * sprint_level + speed_cap_bonus) * movement_mult
	if hv.length() > cap:
		hv = hv.lerp(hv.normalized() * cap, 0.35)
		linear_velocity.x = hv.x
		linear_velocity.z = hv.z
	# 兜底:跌出世界拉回入口
	if global_position.y < -5.0:
		global_position = Main.instance.layout_respawn_pos(0.5) \
				if Main.instance != null else MapLayout.respawn_pos(0.5)
		global_rotation = Vector3.ZERO
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		reset_physics_interpolation()

## 载重越大越难加速/转向的系数(1=空车)
func load_factor() -> float:
	return BASE_MASS / mass

## 临时抬高限速上限(赵冬梅「贴地冲撞」推车突进)。
## 不这么做的话,突进给的车速会被 _physics_process 里的软限速在几帧内清回 6m/s。
func lift_speed_cap(bonus: float, dur: float) -> void:
	speed_cap_bonus = maxf(speed_cap_bonus, bonus)
	_speed_cap_timer = maxf(_speed_cap_timer, dur)

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
	# 扎马步:车斗锁死,一件都肘不出来
	if is_locked():
		return null
	var items := items_in_basket()
	if items.is_empty():
		return null
	var it: Item = items.pick_random()
	it.mark_flung()
	var dir := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	it.apply_central_impulse((dir.normalized() * 2.5 + Vector3.UP * 4.2) * it.mass)
	Main.float_text(self, it.global_position + Vector3.UP * 0.6, "肘飞了 " + it.display_name + "!", Color(1, 0.6, 0.3))
	return it

## 倒地/翻车时甩货
func spill(fraction: float) -> void:
	# 扎马步:车斗锁死,撞不散
	if is_locked():
		return
	for it in items_in_basket():
		if randf() < fraction:
			# 豁免期 + 恢复常规重力,保证甩出去的货不被车斗重新吸住
			it.mark_flung()
			it.apply_central_impulse(Vector3(randf_range(-2.5, 2.5), randf_range(3.0, 5.0), randf_range(-2.5, 2.5)) * it.mass)
	apply_torque_impulse(Vector3(randf_range(-14, 14), randf_range(-8, 8), randf_range(-14, 14)))

## 撞击结算入口(body_entered 信号)。
##
## 只靠这个信号是不够的:它**只在接触开始的那一帧**触发。追尾与车头对撞时
## 两车常常贴住不再分开,于是不会有新的 entered 事件,表现就是"撞上了没判定、
## 人还被卡住"。因此 _physics_process 里另有一路每帧复查(见 _sweep_contacts)。
func _on_body_entered(body: Node) -> void:
	_try_hit(body)

## 每帧复查持续接触:补上 body_entered 漏掉的"贴住不分开"情形,并给卡住的车解套
func _sweep_contacts(delta: float) -> void:
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var touching := {}
	for body in get_colliding_bodies():
		if body is Cart:
			touching[body.get_instance_id()] = true
			_resolve_cart_contact(body, delta)
		if (body is Cart or body is Actor) and hv.length() >= MIN_HIT_SPEED:
			_try_hit(body)
	for key in _cart_contact_time.keys():
		if not touching.has(key):
			_cart_contact_time.erase(key)

## 持续接触不依赖撞击速度：先消掉彼此相向的速度，再周期性施加分离冲量。
## 这样两名驾驶者同时顶住油门时也不会把两辆车“焊”成一个刚体团。
func _resolve_cart_contact(other: Cart, delta: float) -> void:
	if not is_instance_valid(other) or get_instance_id() > other.get_instance_id():
		return
	var away := global_position - other.global_position
	away.y = 0.0
	if away.length() < 0.02:
		away = global_transform.basis.x
		away.y = 0.0
	if away.length() < 0.02:
		away = Vector3.RIGHT
	away = away.normalized()
	# 清除继续压向对方的速度分量，保留侧向滑开空间。
	var mine_inward := linear_velocity.dot(away)
	if mine_inward < 0.0:
		linear_velocity -= away * mine_inward
	var other_inward := other.linear_velocity.dot(-away)
	if other_inward < 0.0:
		other.linear_velocity += away * other_inward
	var key := other.get_instance_id()
	var held := float(_cart_contact_time.get(key, 0.0)) + delta
	_cart_contact_time[key] = held
	if held < CONTACT_UNLOCK_TIME:
		return
	_cart_contact_time[key] = 0.0
	# 先直接建立一个很小的分离速度，避免下一物理步的驾驶力再次把冲量抵消。
	linear_velocity += away * 0.7
	other.linear_velocity -= away * 0.7
	apply_central_impulse(away * CONTACT_UNLOCK_IMPULSE * mass)
	other.apply_central_impulse(-away * CONTACT_UNLOCK_IMPULSE * other.mass)
	angular_velocity *= 0.72
	other.angular_velocity *= 0.72

func _rescue_trapped_actors() -> void:
	if basket_area == null:
		return
	for body in basket_area.get_overlapping_bodies():
		if not (body is Actor) or body == attached_agent:
			continue
		var local := to_local(body.global_position)
		if local.y >= FLOOR_TOP - 0.18 and absf(local.x) < INNER_HALF_X + 0.15 \
				and absf(local.z) < INNER_HALF_Z + 0.15:
			body.escape_from_cart(self)

## 两车进入可能高速相遇的范围后提前打开CCD；脱离后恢复常规求解，保护车内货物。
func _refresh_cart_ccd() -> void:
	var near_cart := false
	for node in get_tree().get_nodes_in_group("carts"):
		if node != self and is_instance_valid(node) \
				and global_position.distance_squared_to(node.global_position) <= CART_CCD_RANGE * CART_CCD_RANGE:
			near_cart = true
			break
	continuous_cd = near_cart or _speed_cap_timer > 0.0

## 单次撞击结算(策划案第六节表格)。返回是否真的结算了一次撞击。
func _try_hit(body: Node) -> bool:
	if body is Item or not is_instance_valid(body):
		return false
	var now := Time.get_ticks_msec() * 0.001
	var key := body.get_instance_id()
	if now - float(_recent_hits.get(key, -10.0)) < 0.8:
		return false

	var myv := linear_velocity
	myv.y = 0.0
	var speed := myv.length()
	if speed < MIN_HIT_SPEED:
		return false
	var toward: Vector3 = body.global_position - global_position
	toward.y = 0.0
	if toward.length() < 0.01 or myv.normalized().dot(toward.normalized()) < 0.3:
		return false

	# 去重登记必须放在**所有校验通过之后**:否则一次没打中的轻碰(速度不足/方向
	# 不对)就会占掉 0.8 秒的去重窗口,把紧接着的真正高速撞击一并吃掉——
	# 这是"撞到了却没判定"的另一半原因。
	_recent_hits[key] = now

	if body is Cart:
		var victim: Actor = body.attached_agent
		# 一次碰撞只结算一次,抑制对方处理器重复触发
		body._recent_hits[get_instance_id()] = now
		# 扎马步(马德胜):受方免疫且反弹失衡给攻方,本次撞击不再走常规结算
		if victim != null and victim.stance:
			CharSkills.stance_counter(victim, self)
			return true
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
		# 贴地冲撞(赵冬梅)推车突进窗口内:车头撞击×1.5
		if hit_mult > 1.0:
			amount *= hit_mult
			kind = "冲撞" + kind
		# 撞击双方都按部位吃失衡:攻方吃"车头撞击"+15,守方按被撞部位
		# 注意:add_imbalance可能当场击倒攻方并导致人车分离,先留住局部引用
		var atk: Actor = attached_agent
		if atk != null:
			atk.add_imbalance(15.0, body)
			Main.float_text(atk, atk.global_position + Vector3.UP * 2.2, "%s 车头+15" % Main.bam(), Color(1, 0.6, 0.25), 68)
		if victim != null:
			victim.add_imbalance(amount, self)
			Main.float_text(victim, victim.global_position + Vector3.UP * 2.2, "%s %s+%d" % [Main.bam(), kind, int(amount)], Color(1, 0.5, 0.2), 80)
			victim.on_cart_hit(self)
		# 撞完把两车弹开:追尾/对撞时车头车尾会互相顶住,不给分离冲量就会"焊在一起"
		_separate_from(body)
		# 涉及玩家的撞击→震对应玩家所在机器的相机(用局部引用,攻方可能已被击倒分离)
		if Main.instance != null:
			var sv := clampf(speed / 10.0, 0.3, 0.8)
			if atk is Player:
				Main.instance.shake_for(atk, sv)
			if victim is Player:
				Main.instance.shake_for(victim, sv)
		return true
	elif body is Actor:
		body.hit_by_cart(self)
		return true
	return false

## 撞击后的分离冲量:治"两车顶住互相卡死推不动"
func _separate_from(other: Node3D) -> void:
	var away: Vector3 = global_position - other.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = global_transform.basis.z
		away.y = 0.0
	if away.length() < 0.01:
		return
	away = away.normalized()
	apply_central_impulse(away * SEPARATE_IMPULSE * mass)
	if other is Cart:
		other.apply_central_impulse(-away * SEPARATE_IMPULSE * other.mass)
