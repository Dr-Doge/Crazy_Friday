class_name PropProbe extends RefCounted
## 全商品投掷专项回归：车斗轮盘、实际物权、差异伤害、落点效果与准星方向。

var _m: Main
var _p: Player
var _dummy: Actor
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []
var _item: Item
var _zone_before := 0
var _block_cart: Cart
var _burst_cart: Cart

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	_p = _m.player
	if _p.attached:
		_p.detach_cart()
	_p.drop_all_held(false)
	_p.cart.right_up()
	_p.cart.global_position = Vector3(0, 0.2, 12)
	_p.cart.linear_velocity = Vector3.ZERO
	_p.cart.angular_velocity = Vector3.ZERO
	_p.attach_cart()
	_dummy = Actor.new()
	_m.add_child(_dummy)
	_dummy.build_body(Color(0.75, 0.75, 0.75), "投掷靶子")
	_dummy.global_position = _p.global_position + Vector3(5.0, 0, 0)
	_check(Catalog.THROW_IMBALANCE.size() == Catalog.ITEMS.size(), "目录：所有商品均配置投掷失衡值")
	_check(Catalog.THROW_EFFECT.size() == Catalog.ITEMS.size(), "目录：所有商品均配置统一效果类别")
	for id in Catalog.ITEMS:
		_check(Catalog.is_prop(id) and Catalog.throw_imbalance(id) > 0.0, "全商品可投掷：%s" % id)
	print("[prop] 全商品投掷自检开始")

func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[0.3, _setup_wheel], [0.7, _check_wheel],
		[0.9, _throw_detergent], [1.1, _hit_detergent], [1.4, _check_detergent],
		[1.6, _throw_thermos], [1.8, _hit_thermos], [2.1, _check_thermos],
		[2.3, _throw_candy], [2.5, _hit_candy], [2.9, _check_candy],
		[3.0, _throw_drone], [3.2, _hit_drone], [3.45, _check_drone],
		[3.7, _check_pedestrian_hits], [3.9, _check_cart_recovery], [4.3, _report],
	]
	while _step < schedule.size() and _t >= float(schedule[_step][0]):
		var fn: Callable = schedule[_step][1]
		_step += 1
		fn.call()

func _put(id: String) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_free_at(_p.cart.to_global(Vector3(randf_range(-0.18, 0.18), 1.28, randf_range(-0.18, 0.18))))
	return it

func _count_zones(type_name: String) -> int:
	var n := 0
	for node in _m.get_children():
		if (type_name == "slow" and node is SlowZone) \
				or (type_name == "scatter" and node is ObscureZone):
			n += 1
	return n

func _setup_wheel() -> void:
	_put("tissue")
	_put("cola")
	_put("tv")

func _check_wheel() -> void:
	var items := _m.cart_throw_items(_p)
	_check(items.size() >= 3, "轮盘：读取购物车内全部商品")
	var before := _m.selected_cart_item_id(_p)
	_m.cycle_cart_item(_p, 1)
	var after := _m.selected_cart_item_id(_p)
	_check(before != after, "轮盘：滚轮循环切换选中商品")
	var aim := _m.cam_rig.aim_direction()
	_check(aim.is_finite() and absf(aim.length() - 1.0) < 0.02, "准星：屏幕中心生成单位三维投掷方向")
	var converged := _p._aim_dir()
	_check(converged.is_finite() and absf(converged.length() - 1.0) < 0.02,
			"准星：越肩相机从角色投掷点向屏幕中心目标会聚")
	_check(_m.cam_rig.spring.position.x > 0.5,
			"镜头：采用右肩偏移，角色不再遮挡屏幕中心准星")
	_check(_m.cam_rig.spring.position.y >= 0.5 and CameraRig.MIN_WORLD_AIM_DISTANCE >= 8.0,
			"准星：角色构图下移且近景会聚距离受限，不再贴近角色脚边")
	_check(CameraRig.DIST < 5.0 and CameraRig.NEAR_LOD_HIDE_DISTANCE > 0.0,
			"镜头：近距离越肩构图与场景近景LOD参数已启用")
	_check(not _m.get_tree().get_nodes_in_group("camera_near_lod").is_empty(),
			"镜头LOD：货架、墙体与场景灯牌视觉已登记近景隐藏")
	_check(_m.hud.item_wheel.anchor_left == 1.0 and _m.hud.item_wheel.anchor_top == 1.0 \
			and _m.hud.item_wheel.offset_right == 0.0 and _m.hud.item_wheel.offset_bottom == 0.0,
			"轮盘：整圆圆心固定在游戏界面最右下角")
	_check(Hud.ITEM_SELECTOR_ANGLE > -PI and Hud.ITEM_SELECTOR_ANGLE < -PI * 0.5,
			"轮盘：固定框选位位于可见的左上四分之一圆环")
	_check(is_equal_approx(Hud.ITEM_RING_OUTER_RADIUS, Hud.ITEM_RING_OLD_OUTER_RADIUS * 1.5) \
			and is_equal_approx(Hud.ITEM_RING_INNER_RADIUS, 270.0),
			"轮盘：外圈直径扩大1.5倍且内圈直径保持不变")
	_check(is_equal_approx(Hud.ITEM_NODE_RADIUS * 2.0 + 24.0, Hud.ITEM_RING_GAP),
			"轮盘：商品尺寸随环带空隙同步缩放并嵌入其中")
	var type_counts := {}
	for id in Catalog.ITEMS:
		var kind := Catalog.prop_kind(id)
		type_counts[kind] = int(type_counts.get(kind, 0)) + 1
		_check(Catalog.prop_effect_short(id) != "" and Catalog.prop_effect_color(id).a > 0.9,
				"轮盘类型提示：%s 配置短标签、颜色与图标类别" % id)
	_check(type_counts.size() == 4 and type_counts[Catalog.PROP_BURST] == 7 \
			and type_counts[Catalog.PROP_WET] == 7 and type_counts[Catalog.PROP_SCATTER] == 7 \
			and type_counts[Catalog.PROP_TASER] == 6,
			"统一分类：27件商品按7/7/7/6分入四类")
	var guard_item := Item.create("tissue")
	_m.add_child(guard_item)
	_m._throw_item_body(guard_item, _p, Vector3(0.0, -1.0, 0.05))
	var guard_origin: Vector3 = guard_item.get_meta("throw_origin")
	var guard_spawn: Vector3 = guard_item.get_meta("throw_spawn_position")
	_check(Vector2(guard_spawn.x - guard_origin.x, guard_spawn.z - guard_origin.z).length() >= 1.1 \
			and guard_item.linear_velocity.y >= 0.0,
			"低视角投掷：出手点始终向前离开角色，不会向脚下发射")
	_check((guard_item.collision_mask & Catalog.L_WORLD) == 0,
			"离手保护：短暂关闭场景碰撞，避免出生包围盒与脚边地面重叠")
	_m._thrown_item_hit(guard_item, _p, _p)
	_m._thrown_item_hit(guard_item, _p.cart, _p)
	_check(bool(guard_item.get_meta("throw_active", false)),
			"自撞保护：投掷者和本人购物车均不会触发落点效果")
	guard_item.global_position = guard_item.get_meta("throw_origin") + Vector3(0.2, -1.0, 0.0)
	_m._thrown_item_hit(guard_item, _m, _p)
	_check(bool(guard_item.get_meta("throw_active", false)),
			"投掷落点：离手瞬间的脚边世界碰撞不会提前触发效果")
	guard_item.set_meta("throw_active", false)
	_check(Hud.OBSCURE_SCREEN_ALPHA >= 0.35 and Hud.OBSCURE_BLOB_ALPHA >= 0.65,
			"散落遮挡：屏幕暗幕与碎屑块达到强遮蔽基线")

func _clear_cart() -> void:
	for it in _m.cart_throw_items(_p):
		it.queue_free()

func _throw_detergent() -> void:
	_clear_cart()
	_item = _put("detergent")
	_zone_before = _count_zones("slow")
	_dummy.slow_time = 0.0
	_dummy.slow_factor = 1.0
	_p.prop_cd = 0.0

func _hit_detergent() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "detergent")
	_check(bool(_item.get_meta("throw_active", false)), "洗衣液：从车斗取出真实商品并进入投掷态")
	_item.global_position = _dummy.global_position
	_m._thrown_item_hit(_item, _m, _p)

func _check_detergent() -> void:
	_check(is_instance_valid(_item) and _item.state == Item.ItemState.FREE, "投掷商品：命中后留在场内而非消失")
	var effect_pos: Vector3 = _item.get_meta("throw_effect_position", Vector3.ZERO)
	_check(effect_pos.distance_to(Vector3(_dummy.global_position.x, 0.0, _dummy.global_position.z)) < 0.25 \
			and effect_pos.distance_to(Vector3(_p.global_position.x, 0.0, _p.global_position.z)) > 2.0,
			"投掷落点：效果中心锁定首次有效落点，不生成在投掷者脚下")
	_check(_count_zones("slow") == _zone_before + 1, "湿滑类：落点生成统一8秒减速地面")
	_check(_dummy.movement_factor() <= Catalog.WET_MOVE_FACTOR + 0.01,
			"湿滑类：区域内统一保留65%移动能力")
	_check(_dummy.traction_factor() <= Catalog.WET_TRACTION_FACTOR + 0.01,
			"湿滑类：推车抓地统一下降，经过时更容易漂移")

func _throw_thermos() -> void:
	_clear_cart()
	_item = _put("thermos")
	_dummy.imbalance = 0.0
	_dummy.push_velocity = Vector3.ZERO
	_burst_cart = Cart.create(Color(0.55, 0.55, 0.6), "爆裂推离测试车")
	_m.add_child(_burst_cart)
	_burst_cart.global_position = _dummy.global_position + Vector3.RIGHT * 1.2
	_burst_cart.linear_velocity = Vector3.ZERO
	_p.prop_cd = 0.0

func _hit_thermos() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "thermos")
	_item.global_position = _dummy.global_position
	_m._thrown_item_hit(_item, _dummy, _p)

func _check_thermos() -> void:
	_check(absf(_dummy.imbalance - Catalog.throw_imbalance("thermos") \
			* Catalog.THROW_ACTOR_DAMAGE_MULTIPLIER) < 0.5,
			"保温杯：直击角色造成1.5倍失衡(实际%.0f)" % _dummy.imbalance)
	var direct_push_length := _dummy.push_velocity.length()
	_dummy.imbalance = 0.0
	_burst_cart.attached_agent = _dummy
	var cart_hit_item := Item.create("thermos")
	_m.add_child(cart_hit_item)
	_m._throw_item_body(cart_hit_item, _p, Vector3.FORWARD)
	cart_hit_item.global_position = _burst_cart.global_position
	_m._thrown_item_hit(cart_hit_item, _burst_cart, _p)
	_check(absf(_dummy.imbalance - Catalog.throw_imbalance("thermos") \
			* Catalog.THROW_CART_DAMAGE_MULTIPLIER) < 0.5,
			"保温杯：砸中对手购物车造成1.0倍失衡(实际%.0f)" % _dummy.imbalance)
	_burst_cart.attached_agent = null
	_check(direct_push_length >= Catalog.BURST_ACTOR_PUSH,
			"爆裂类：范围内角色受到统一推离且不追加失衡")
	_check(_burst_cart.linear_velocity.length() > 0.5,
			"爆裂类：范围内购物车同样受到推离")
	_check(_burst_cart.linear_velocity.y > 3.0,
			"爆裂类：购物车获得足以离地的向上冲量(当前%.1fm/s)" % _burst_cart.linear_velocity.y)
	_check(_burst_cart.angular_velocity.length() > 0.5,
			"爆裂类：购物车获得翻转扭矩，产生掀车效果")

func _throw_candy() -> void:
	_clear_cart()
	_item = _put("candy")
	_zone_before = _count_zones("scatter")
	_dummy.obscure_time = 0.0
	_dummy.obscure_factor = 1.0
	_p.prop_cd = 0.0

func _hit_candy() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "candy")
	_item.global_position = _dummy.global_position
	_m._thrown_item_hit(_item, _m, _p)

func _check_candy() -> void:
	_check(_count_zones("scatter") == _zone_before + 1, "散落类：落点生成统一4秒遮挡区")
	_check(_dummy.perception_factor() <= Catalog.SCATTER_PERCEPTION_FACTOR + 0.01,
			"散落类：区域内NPC感知距离统一降至35%")

func _throw_drone() -> void:
	_clear_cart()
	_item = _put("drone")
	_dummy.taser_time = 0.0
	_dummy.taser_immunity_time = 0.0
	_p.prop_cd = 0.0

func _hit_drone() -> void:
	_m.trigger_throw_cart_item(_p, Vector3.FORWARD, "drone")
	_m._thrown_item_hit(_item, _dummy, _p)

func _check_drone() -> void:
	_check(_dummy.taser_time > 0.0 and _dummy.taser_time <= Catalog.TASER_TIME,
			"电击类：直接命中角色后统一定身1.2秒")
	var before := _dummy.taser_time
	var reapplied := _dummy.apply_taser(Catalog.TASER_TIME, Catalog.TASER_IMMUNITY, _p)
	_check(not reapplied and _dummy.taser_time <= before,
			"电击类：目标进入4秒免疫，不能被连续无限定身")

func _check_pedestrian_hits() -> void:
	_dummy.imbalance = 0.0
	_dummy.downed = false
	_p.cart.sprinting = false
	_p.cart.sprint_level = 0.0
	_p.cart.hit_mult = 1.0
	_dummy.hit_by_cart(_p.cart)
	_check(absf(_dummy.imbalance - 50.0) < 0.5, "徒步受撞：普通购物车造成基础值2倍，即50失衡")
	_dummy.imbalance = 0.0
	_dummy.downed = false
	_p.cart.sprinting = true
	_p.cart.sprint_level = 1.0
	_dummy.hit_by_cart(_p.cart)
	_check(_dummy.downed and _dummy.imbalance >= 100.0, "徒步受撞：加速购物车直接满失衡并撞倒")

func _check_cart_recovery() -> void:
	_block_cart = Cart.create(Color.GRAY, "解锁测试车")
	_m.add_child(_block_cart)
	_p.cart.global_position = Vector3(0, 0.2, 12)
	_block_cart.global_position = _p.cart.global_position + Vector3.RIGHT * 0.8
	_p.cart.linear_velocity = Vector3.RIGHT * 2.0
	_block_cart.linear_velocity = Vector3.LEFT * 2.0
	_p.cart._resolve_cart_contact(_block_cart, Cart.CONTACT_UNLOCK_TIME + 0.01)
	var away := (_p.cart.global_position - _block_cart.global_position).normalized()
	var separating := (_p.cart.linear_velocity - _block_cart.linear_velocity).dot(away)
	_check(separating > 0.0, "购物车防卡死：持续接触会清除对顶速度并主动分离")
	_p.cart._refresh_cart_ccd()
	_block_cart._refresh_cart_ccd()
	_check(_p.cart.continuous_cd and _block_cart.continuous_cd,
			"购物车防穿模：邻车进入风险范围后提前开启连续碰撞检测")
	_dummy.downed = false
	_dummy.global_position = _p.cart.to_global(Vector3(0, Cart.FLOOR_TOP + 0.05, 0))
	_dummy.escape_from_cart(_p.cart)
	_check(_dummy.get_collision_exceptions().has(_p.cart) and _dummy.push_velocity.length() > 5.0,
			"角色车斗逃生：短暂忽略困住自己的车并沿最近侧边推出")

func _check(ok: bool, msg: String) -> void:
	_notes.append(("  OK   " if ok else "  FAIL ") + msg)
	if not ok:
		_fails.append(msg)

func _report() -> void:
	for line in _notes:
		print("[prop]", line)
	print("[prop] RESULT=%s assertions=%d" % ["PASS" if _fails.is_empty() else "FAIL", _notes.size()])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
