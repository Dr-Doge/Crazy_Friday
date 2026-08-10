class_name Actor extends CharacterBody3D
## 玩家与NPC共享基类:失衡值、倒地(白盒布娃娃)、被车撞、手持物品

const MAX_IMBALANCE := 100.0
const DOWN_TIME := 3.0
const IMBALANCE_DECAY := 10.0   # 脱战3秒后每秒衰减
const DECAY_DELAY := 3.0

var imbalance := 0.0
var last_overflow := 0.0    # 击倒瞬间超出100的溢出量,决定甩货比例
var held: Array[Item] = []
var hold_capacity := 2          # 小件2件,大件占满
var downed := false
var immune := false             # 收银通道内免战
var braced := false             # 冲击准备:被车撞不涨失衡(玩家空格技能)
var stance := false             # 扎马步(马德胜Ctrl):免疫撞击与肘击失衡+车斗锁死+反击
var push_velocity := Vector3.ZERO
var gravity := 9.8

# 购物车挂接(玩家与大妈共用)
var cart: Cart = null
var attached := false
var _saved_layer := 0
var _saved_mask := 0

var body_root: Node3D           # 可倾倒的视觉根
var name_label: Label3D         # 头顶名牌(玩家自定义昵称,染本人配色)
var mark_shell: MeshInstance3D  # 被「上链接」抢货后的追踪标记壳(只在受害者本机点亮)
var hand_l: MeshInstance3D      # 双手小球
var hand_r: MeshInstance3D
var hand_pose := "idle"         # idle / push / channel / carry,由子类每帧设置
var _hand_time := 0.0
var _elbow_anim := 0.0
var _down_timer := 0.0
var _last_hit_time := -999.0

## 白盒身体:胶囊+名牌。子类在 _ready 里调用。
func build_body(color: Color, title: String, height := 1.7) -> void:
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	collision_layer = Catalog.L_CHAR
	collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART

	body_root = Node3D.new()
	add_child(body_root)

	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = height
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	cap.material = mat
	mesh.mesh = cap
	mesh.position = Vector3(0, height * 0.5, 0)
	body_root.add_child(mesh)

	# 朝向指示(鼻子)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.12, 0.12, 0.24)
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = color.darkened(0.35)
	nb.material = nmat
	nose.mesh = nb
	nose.position = Vector3(0, height * 0.72, -0.36)
	body_root.add_child(nose)

	# 双手:两个小球,随找货/拿货/推车/肘击动作移动
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = color.lightened(0.3)
	var hs := SphereMesh.new()
	hs.radius = 0.1
	hs.height = 0.2
	hs.material = hmat
	hand_l = MeshInstance3D.new()
	hand_l.mesh = hs
	hand_l.position = Vector3(-0.42, 0.92, 0.0)
	body_root.add_child(hand_l)
	hand_r = MeshInstance3D.new()
	hand_r.mesh = hs
	hand_r.position = Vector3(0.42, 0.92, 0.0)
	body_root.add_child(hand_r)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = height
	col.shape = shape
	col.position = Vector3(0, height * 0.5, 0)
	add_child(col)

	# 头顶名牌:染成本人配色,联机时一眼分清谁是谁
	name_label = Label3D.new()
	name_label.name = "NameTag"
	name_label.text = title
	name_label.font = Catalog.ui_font_bold()
	name_label.font_size = 72
	name_label.pixel_size = 0.004
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.modulate = color.lightened(0.45)
	name_label.outline_size = 14
	name_label.outline_modulate = Color(0, 0, 0, 0.85)
	name_label.position = Vector3(0, height + 0.45, 0)
	add_child(name_label)

	# 追踪标记壳:被李洋「上链接」抢货后,受害者能穿墙看到他4秒。
	# 可见性**只由观察者本机决定**(Main._update_track_mark):
	# 同一个人在受害者屏幕上亮红壳,在其他人屏幕上什么都没有。
	var ms := MeshInstance3D.new()
	var mb := SphereMesh.new()
	mb.radius = 0.62
	mb.height = 1.9
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(1, 0.35, 0.6, 0.34)
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.cull_mode = BaseMaterial3D.CULL_FRONT
	mmat.no_depth_test = true
	mb.material = mmat
	ms.mesh = mb
	ms.position = Vector3(0, height * 0.55, 0)
	ms.visible = false
	add_child(ms)
	mark_shell = ms

	add_to_group("characters")

## 改名(大厅改档案后即时生效)
func set_display_name(t: String) -> void:
	if name_label != null:
		name_label.text = t

func is_running() -> bool:
	return false

## 每帧公共逻辑:衰减、倒地计时、手持跟随、双手动画
func actor_tick(delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not downed and now - _last_hit_time > DECAY_DELAY:
		imbalance = maxf(0.0, imbalance - IMBALANCE_DECAY * delta)
	if downed:
		_down_timer -= delta
		if _down_timer <= 0.0:
			_recover()
	_update_held_positions()
	_update_hands(delta)

func _update_hands(delta: float) -> void:
	if hand_l == null:
		return
	var speed := Vector3(velocity.x, 0, velocity.z).length()
	if attached and is_instance_valid(cart):
		speed = Vector3(cart.linear_velocity.x, 0, cart.linear_velocity.z).length()
	_hand_time += delta * clampf(3.0 + speed * 1.6, 3.0, 12.0)
	_elbow_anim = maxf(0.0, _elbow_anim - delta * 3.5)
	var lp: Vector3
	var rp: Vector3
	match hand_pose:
		"push":     # 双手扶车把
			lp = Vector3(-0.3, 1.12, -0.5)
			rp = Vector3(0.3, 1.12, -0.5)
		"channel":  # 翻找货架/车斗:双手前伸交替扒拉
			var s := sin(_hand_time * 2.5) * 0.16
			lp = Vector3(-0.17, 1.05, -0.5 + s)
			rp = Vector3(0.17, 1.05, -0.5 - s)
		"carry":    # 托着手里的货
			lp = Vector3(-0.2, 1.32, -0.34)
			rp = Vector3(0.2, 1.32, -0.34)
		"brace":    # 冲击准备:双臂交叉护胸
			lp = Vector3(0.14, 1.12, -0.42)
			rp = Vector3(-0.14, 1.2, -0.4)
		"speed":    # 贴地冲撞:速滑姿态,双手背在身后
			lp = Vector3(-0.34, 0.72, 0.46)
			rp = Vector3(0.34, 0.72, 0.46)
		"grab":     # 上链接:自拍杆式前钩,右手远伸
			var g := sin(_hand_time * 3.0) * 0.1
			lp = Vector3(-0.26, 1.0, -0.2)
			rp = Vector3(0.2, 1.42, -1.15 + g)
		_:          # 垂在身侧,走路时前后摆
			var sw := sin(_hand_time) * (0.22 if speed > 0.6 else 0.03)
			lp = Vector3(-0.42, 0.92, sw)
			rp = Vector3(0.42, 0.92, -sw)
	var k := 1.0 - exp(-14.0 * delta)
	if _elbow_anim > 0.0:
		# 夸张肘击:先大幅后拉蓄力,再全力前捅,右手瞬间变大
		var w := clampf(_elbow_anim, 0.0, 1.0)
		if _elbow_anim > 0.95:
			rp = rp.lerp(Vector3(0.6, 1.05, 0.55), w)          # 后拉蓄力
		else:
			rp = rp.lerp(Vector3(0.42, 1.32, -1.35), w)        # 猛捅出去
		lp = lp.lerp(Vector3(-0.6, 1.0, 0.45), w * 0.8)        # 左手反向抡开
		hand_r.scale = Vector3.ONE * (1.0 + 1.0 * w)
		k = 1.0 - exp(-30.0 * delta)                            # 出拳阶段手部动作更快
	else:
		hand_r.scale = hand_r.scale.lerp(Vector3.ONE, k)
	hand_l.position = hand_l.position.lerp(lp, k)
	hand_r.position = hand_r.position.lerp(rp, k)

# ---------- 购物车挂接 ----------

func attach_cart() -> void:
	if attached or cart == null or not is_instance_valid(cart) or cart.attached_agent != null:
		return
	# 车翻了?抓住的同时自动扶正
	if cart.global_transform.basis.y.dot(Vector3.UP) < 0.8:
		cart.right_up()
	attached = true
	cart.attached_agent = self
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	global_position = cart.handle_pos()
	reset_physics_interpolation()

func detach_cart() -> void:
	if not attached:
		return
	attached = false
	if is_instance_valid(cart):
		cart.attached_agent = null
		cart.sprinting = false
		global_position = cart.handle_pos() + Vector3(0, 0.1, 0)
	collision_layer = _saved_layer if _saved_layer != 0 else Catalog.L_CHAR
	collision_mask = _saved_mask if _saved_mask != 0 else (Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART)

## 正在推的车(肘击"肘掉车内商品"用)
func get_pushed_cart() -> Cart:
	if attached and is_instance_valid(cart):
		return cart
	return null

## 联机客户端傀儡:不模拟,仅驱动手部动画等表现
func puppet_update(delta: float) -> void:
	_update_hands(delta)

## 子类通用移动:wish为水平方向单位向量
func apply_motion(delta: float, wish: Vector3, speed: float) -> void:
	var horiz := wish * speed + push_velocity
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	# 兜底:任何原因跌出世界都拉回入口
	if global_position.y < -5.0:
		global_position = MapLayout.respawn_pos(0.5)
		velocity = Vector3.ZERO
		push_velocity = Vector3.ZERO
		reset_physics_interpolation()
	push_velocity = push_velocity.move_toward(Vector3.ZERO, 8.0 * delta)
	# 徒步推动松散购物车(增加一点闹剧感)
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Cart and other.attached_agent == null:
			other.apply_central_impulse(-col.get_normal() * 60.0 * delta)
	if not downed and wish.length() > 0.1:
		var target_yaw := atan2(-wish.x, -wish.z)
		body_root.rotation.y = lerp_angle(body_root.rotation.y, target_yaw, 10.0 * delta)

func add_imbalance(amount: float, _source: Node = null) -> void:
	if downed or immune:
		return
	# 扎马步(马德胜):撞击与肘击一律不涨失衡。免疫优先于braced,
	# 且不限来源类型——它比通用「稳住」更强,代价是2秒完全定身。
	if stance and amount > 0.0:
		return
	# 冲击准备:撞击(购物车来源)不涨失衡
	if braced and _source is Cart:
		Main.float_text(self, global_position + Vector3.UP * 2.2, "稳如老狗!!", Color(0.4, 0.9, 1.0), 76)
		return
	_last_hit_time = Time.get_ticks_msec() * 0.001
	var raw := imbalance + amount
	imbalance = clampf(raw, 0.0, MAX_IMBALANCE)
	if imbalance >= MAX_IMBALANCE:
		last_overflow = raw - MAX_IMBALANCE
		knockdown()

## 被购物车撞:徒步+50并被撞飞
func hit_by_cart(hit_cart: Cart) -> void:
	if downed or immune:
		return
	# 扎马步:徒步状态下被撞也免疫并反击(技能是"人"的姿态,不依赖有没有推车)
	if stance:
		CharSkills.stance_counter(self, hit_cart)
		return
	var v := hit_cart.linear_velocity
	v.y = 0.0
	push_velocity = v * 1.1 + Vector3.UP * 2.0
	add_imbalance(50.0, hit_cart)
	Main.float_text(self, global_position + Vector3.UP * 2.0, "%s +50 %s" % [Main.bam(), Main.BAM_PED.pick_random()], Color(1, 0.4, 0.2), 80)
	on_cart_hit(hit_cart)
	if Main.instance != null:
		Main.instance.shake_for(self, 0.65)
		if hit_cart.attached_agent != null:
			Main.instance.shake_for(hit_cart.attached_agent, 0.5)

## 反应钩子:被车撞/被肘击(大妈子类里触发对话气泡)
func on_cart_hit(_by: Cart) -> void:
	pass

func on_elbowed(_by: Actor) -> void:
	pass

func knockdown() -> void:
	if downed:
		return
	downed = true
	_down_timer = DOWN_TIME
	imbalance = MAX_IMBALANCE
	drop_all_held(true)
	var tw := create_tween()
	tw.tween_property(body_root, "rotation:x", -PI * 0.5, 0.25).set_trans(Tween.TRANS_BOUNCE)
	_on_knockdown()
	if Main.instance != null:
		Main.instance.on_actor_downed(self)

func _recover() -> void:
	downed = false
	imbalance = 30.0
	_last_hit_time = Time.get_ticks_msec() * 0.001
	var tw := create_tween()
	tw.tween_property(body_root, "rotation:x", 0.0, 0.3)
	_on_recover()

func _on_knockdown() -> void:
	pass

func _on_recover() -> void:
	pass

# ---------- 手持物品 ----------

func held_slots_used() -> int:
	var n := 0
	for it in held:
		n += 2 if it.category == Catalog.CAT_LARGE else 1
	return n

func can_hold(it: Item) -> bool:
	var need := 2 if it.category == Catalog.CAT_LARGE else 1
	return held_slots_used() + need <= hold_capacity

func take_item(it: Item) -> void:
	it.set_held()
	held.append(it)

## 掉落手中随机一件(肘击/倒地)
func drop_one_held(scatter := true) -> Item:
	if held.is_empty():
		return null
	var it: Item = held.pick_random()
	held.erase(it)
	var imp := Vector3.ZERO
	if scatter:
		imp = Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 3.5), randf_range(-1.5, 1.5)) * it.mass
	it.set_free_at(global_position + Vector3(0, 1.4, 0), imp)
	return it

func drop_all_held(scatter := true) -> void:
	while not held.is_empty():
		drop_one_held(scatter)

func _update_held_positions() -> void:
	var base := global_position + Vector3.UP * 1.55
	var fwd := -body_root.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
	var y := 0.0
	for it in held:
		if it.category == Catalog.CAT_LARGE:
			# 抱大件:挡在胸前
			it.global_position = global_position + Vector3.UP * 1.1 + fwd * 0.62
		else:
			it.global_position = base + fwd * 0.42 + Vector3.UP * y
			y += it.collider_half_height() * 2.0 + 0.05
		it.global_rotation = Vector3(0, body_root.global_rotation.y, 0)

## 肘击:无冷却(手速就是攻速),命中+15失衡,击落对方手中随机1件,并从对方车斗肘飞随机1件
## dir_override:出肘方向(玩家传镜头朝向);零向量则用身体朝向
func try_elbow(dir_override := Vector3.ZERO) -> bool:
	if downed:
		return false
	_elbow_anim = 1.3
	var fwd := dir_override
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = -body_root.global_transform.basis.z
		fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Actor = null
	var best_d := 2.6 if attached else 2.0   # 推车时手臂借车身前伸,够得更远
	for node in get_tree().get_nodes_in_group("characters"):
		if node == self or not (node is Actor):
			continue
		if node.immune:   # 收银通道免战区内不可被肘击
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.01 and fwd.dot(to.normalized()) > 0.35:
			best = node
			best_d = d
	if best:
		# 扎马步:免疫肘击的失衡与掉货(手上、车里都护住)
		if best.stance:
			Main.float_text(best, best.global_position + Vector3.UP * 2.0, "码得住!!(肘不动)", Color(0.5, 0.85, 1.0), 72)
			best.on_elbowed(self)
			return true
		best.add_imbalance(15.0, self)
		best.drop_one_held(true)
		best.push_velocity += fwd * 3.0
		var vcart := best.get_pushed_cart()
		if vcart != null:
			vcart.eject_random_item()
		Main.float_text(best, best.global_position + Vector3.UP * 2.0, "%s 肘击+15" % Main.BAM_ELBOW.pick_random(), Color(1, 0.7, 0.2), 76)
		best.on_elbowed(self)
		if Main.instance != null:
			Main.instance.shake_for(self, 0.25)
			Main.instance.shake_for(best, 0.5)
	return true
