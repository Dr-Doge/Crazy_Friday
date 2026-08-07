class_name SlipperyZone extends Area3D
## 小心地滑:踩入瞬间+12失衡,区域内行走+15/秒,奔跑+30/秒,
## 推车按载重最高再乘3倍——玩家和NPC都非常容易在水渍上滑倒。
## 所有水渍都会自然干掉:life<=0时取45-75秒随机寿命(开局水渍),
## 保洁拖地/玩家水瓶传入固定寿命;消失前3秒逐渐缩小蒸发。

const ENTRY_BURST := 12.0   # 踩上去脚下一滑
const WALK_RATE := 15.0
const RUN_RATE := 30.0
const CART_LOAD_MULT_MAX := 3.0
const FADE_TIME := 3.0      # 蒸发动画时长

var lifetime := 0.0
var _entry_cd := {}         # 实例id -> 上次入场触发时间,防抖
var water_mesh: MeshInstance3D
var sign_mesh: MeshInstance3D
var sign_label: Label3D

static func create(root: Node3D, pos: Vector3, size: Vector3, life := 0.0) -> SlipperyZone:
	var z := SlipperyZone.new()
	z.lifetime = life if life > 0.0 else randf_range(45.0, 75.0)
	z.monitoring = true
	z.monitorable = false
	z.collision_layer = 0
	z.collision_mask = Catalog.L_CHAR | Catalog.L_CART
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, 2.0, size.z)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	z.add_child(cs)

	# 水渍视觉
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.03, size.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.7, 0.95, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(0, 0.03, 0)
	z.add_child(mi)
	z.water_mesh = mi

	# 醒目大立牌(自发光亮黄)
	var sign := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.7, 1.1, 0.14)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.98, 0.82, 0.08)
	smat.emission_enabled = true
	smat.emission = Color(0.95, 0.75, 0.05)
	smat.emission_energy_multiplier = 0.9
	sb.material = smat
	sign.mesh = sb
	sign.position = Vector3(0, 0.58, 0)
	z.add_child(sign)
	z.sign_mesh = sign

	var lb := Label3D.new()
	lb.text = "!! 小心地滑 !!"
	lb.font = Catalog.ui_font_bold()
	lb.font_size = 84
	lb.pixel_size = 0.004
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.modulate = Color(0.15, 0.12, 0.05)
	lb.outline_size = 16
	lb.outline_modulate = Color(0.98, 0.85, 0.1)
	lb.position = Vector3(0, 1.55, 0)
	z.add_child(lb)
	z.sign_label = lb

	z.position = pos
	root.add_child(z)
	z.body_entered.connect(z._on_body_entered)
	return z

## 踩入瞬间脚下一滑
func _on_body_entered(body: Node) -> void:
	var target := _resolve_actor(body)
	if target == null or target.downed:
		return
	var now := Time.get_ticks_msec() * 0.001
	var key := body.get_instance_id()
	if now - float(_entry_cd.get(key, -10.0)) < 1.5:
		return
	_entry_cd[key] = now
	target.add_imbalance(ENTRY_BURST, self)
	Main.float_text(target, target.global_position + Vector3.UP * 2.0, "哧溜!!", Color(0.4, 0.8, 1.0), 68)

func _resolve_actor(body: Node) -> Actor:
	if body is Actor:
		return body
	if body is Cart and body.attached_agent != null:
		return body.attached_agent
	return null

func _physics_process(delta: float) -> void:
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			# 联机客户端不本地弹字(主机的飘字会转发过来,避免重复)
			if Main.instance == null or not Main.instance.net_client:
				Main.float_text(self, global_position + Vector3.UP * 0.8, "水渍干了~", Color(0.6, 0.85, 1.0), 48)
			queue_free()
			return
		# 消失前逐渐缩小蒸发
		if lifetime < FADE_TIME:
			var f := clampf(lifetime / FADE_TIME, 0.05, 1.0)
			water_mesh.scale = Vector3(f, 1, f)
			sign_mesh.scale = Vector3.ONE * f
			sign_label.modulate.a = f
	# 联机客户端:纯视觉,失衡由主机结算
	if Main.instance != null and Main.instance.net_client:
		return
	for body in get_overlapping_bodies():
		var target := _resolve_actor(body)
		var load_mult := 1.0
		if body is Cart and body.attached_agent != null:
			# 推车经由车结算;满载车倍率更高(策划案:满载车进地滑区≈灾难)
			load_mult = clampf(1.0 / body.load_factor(), 1.0, CART_LOAD_MULT_MAX)
		if target != null and not target.downed:
			var rate := RUN_RATE if target.is_running() else WALK_RATE
			target.add_imbalance(rate * load_mult * delta, self)
