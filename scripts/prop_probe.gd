class_name PropProbe extends RefCounted
## 全商品投掷专项回归：车斗/手持轮盘、实际物权、差异伤害、落点效果与准星方向。

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
var _shelf_target: Item
var _ground_target: Item
var _ground_blocked_shelves: Array[Item] = []
var _track_shelf_target := false
var _protected_cart_item: Item
var _overstock_cart_item: Item
var _wheel_extra_items: Array[Item] = []

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
	var no_label_item := Item.create("cola")
	_m.add_child(no_label_item)
	_check(no_label_item.label == null and no_label_item.surface_labels.is_empty(),
			"商品标识：正式美术模型不叠加名称，仅保留玩家瞄准HUD注释卡")
	no_label_item.queue_free()
	var fallback_id := ""
	for id in Catalog.ITEMS:
		if ArtAssetCatalog.item_prefab_path(str(id)) == "":
			fallback_id = str(id)
			break
	var fallback_item := Item.create(fallback_id)
	_m.add_child(fallback_item)
	_check(fallback_id != "" and fallback_item.label != null \
			and fallback_item.surface_labels.size() == 2 \
			and fallback_item.surface_labels.all(func(lb: Label3D):
				return not lb.no_depth_test \
						and lb.billboard == BaseMaterial3D.BILLBOARD_DISABLED),
			"商品标识：未替换模型的白盒商品恢复双面贴附名称且受场景遮挡")
	fallback_item.queue_free()
	var display_scale_item := Item.create("cola")
	_m.add_child(display_scale_item)
	display_scale_item.set_shelved(_p.global_position + Vector3(0.0, 2.0, 0.0))
	var shelf_scale_ok := display_scale_item.scale.is_equal_approx(
			Vector3.ONE * Catalog.SHELF_DISPLAY_SCALE)
	display_scale_item.set_held()
	_check(shelf_scale_ok and display_scale_item.collision_layer == 0 \
			and display_scale_item.scale.is_equal_approx(Vector3.ONE),
			"商品陈列：货架模型放大2倍并关闭碰撞，拿取后恢复车内真实尺寸")
	display_scale_item.queue_free()
	_check(Catalog.THROW_IMBALANCE.size() == Catalog.ITEMS.size(), "目录：所有商品均配置投掷失衡值")
	_check(Catalog.THROW_EFFECT.size() == Catalog.ITEMS.size(), "目录：所有商品均配置统一效果类别")
	for id in Catalog.ITEMS:
		_check(Catalog.is_prop(id) and Catalog.throw_imbalance(id) > 0.0, "全商品可投掷：%s" % id)
	print("[prop] 全商品投掷自检开始")

func tick(delta: float) -> void:
	_t += delta
	if _track_shelf_target and is_instance_valid(_shelf_target):
		_place_shelf_on_crosshair()
	var schedule := [
		[0.3, _setup_wheel], [0.7, _check_wheel],
		[0.78, _setup_shelf_target], [0.88, _check_shelf_target],
		[0.98, _move_shelf_off_crosshair], [1.08, _check_shelf_miss],
		[1.10, _setup_ground_target], [1.14, _check_ground_target],
		[1.17, _move_ground_off_crosshair], [1.19, _check_ground_miss],
		[1.2, _throw_detergent], [1.4, _hit_detergent], [1.7, _check_detergent],
		[1.9, _throw_thermos], [2.1, _hit_thermos], [2.4, _check_thermos],
		[2.6, _throw_candy], [2.8, _hit_candy], [3.2, _check_candy],
		[3.3, _throw_drone], [3.5, _hit_drone], [3.75, _check_drone],
		[4.0, _check_pedestrian_hits], [4.2, _check_cart_recovery], [4.6, _report],
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
		if (type_name == "slow" and node is SlipperyZone) \
				or (type_name == "scatter" and node is ObscureZone):
			n += 1
	return n

func _setup_wheel() -> void:
	var order: Array = _m._order_for_player(_p)
	var first_entry: Dictionary = order[0]
	_protected_cart_item = _put(str(first_entry["id"]))
	# 车内同SKU数量比尚缺订单多1件；最低实例ID的需求件受保护，最后一件应成为弹药。
	for i in OrderSystem.required(first_entry):
		_overstock_cart_item = _put(str(first_entry["id"]))
	var ordered_ids: Array = order.map(func(entry): return str(entry["id"]))
	for id in Catalog.ITEMS:
		if id == "sale_box" or ordered_ids.has(id):
			continue
		_wheel_extra_items.append(_put(str(id)))
		if _wheel_extra_items.size() >= 3:
			break

func _check_wheel() -> void:
	var items := _m.cart_throw_items(_p)
	_check(items.size() == 4 and _wheel_extra_items.all(func(it: Item): return items.has(it)) \
			and not items.has(_protected_cart_item) and items.has(_overstock_cart_item),
			"驾车轮盘：保护队伍尚缺数量，同SKU超出订单的部分可作为道具")
	var before := _p.throw_selection
	_m.cycle_cart_item(_p, 1)
	var after := _p.throw_selection
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
	_check(is_equal_approx(CameraRig.DIST, 3.0) and CameraRig.SHOULDER_OFFSET >= 0.9 \
			and is_equal_approx(CameraRig.THROW_AIM_DIST, 2.0) \
			and CameraRig.THROW_AIM_SHOULDER > CameraRig.SHOULDER_OFFSET,
			"镜头：常态3米左下构图与2米右肩瞄准参数已启用")
	_check(Player.DRIVE_STEER <= 82.0,
			"驾驶手感：转向力由110降至82，高速转向不再过度甩头")
	var sign_lod_nodes := _m.get_tree().get_nodes_in_group("third_person_sign_lod")
	# New_Level只保留贴地分区字，不再有会遮挡镜头的悬浮牌；旧地图仍验证悬浮牌LOD。
	var no_overhead_signs_needed := _m.embedded_level and sign_lod_nodes.is_empty()
	_check(no_overhead_signs_needed or not sign_lod_nodes.is_empty(),
			"镜头LOD：悬浮分区牌已登记规避，或新版场景仅使用无需隐藏的贴地标识")
	var early_sign_lod := no_overhead_signs_needed
	var sign_only_lod := true
	for node in sign_lod_nodes:
		sign_only_lod = sign_only_lod and str(node.get_meta("camera_lod_kind", "")) == "overhead_sign"
		if float(node.get_meta("camera_lod_hide_distance", 0.0)) >= 2.0:
			early_sign_lod = true
	_check(early_sign_lod and sign_only_lod,
			"镜头LOD：仅分区告示牌使用2米隐藏距离，货架与墙体不参与")
	var cart_labels_match_asset_state := true
	for it in items:
		var has_art := is_instance_valid(it.visual_root) \
				and it.visual_root.has_meta("art_item_id")
		cart_labels_match_asset_state = cart_labels_match_asset_state \
				and ((has_art and it.label == null and it.surface_labels.is_empty()) \
				or (not has_art and it.label != null and it.surface_labels.size() == 2))
	_check(cart_labels_match_asset_state,
			"商品标识：正式模型无叠加字，仍处于白盒阶段的商品保留表面名称")
	# 后续逐类投掷效果测试不属于订单筛选测试，清空测试玩家的临时清单以免随机订单屏蔽指定道具。
	_m.team_data[_p.team_id]["list"] = []
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	_p.detach_cart()
	_m._update_skill_hud()
	var held_view_test := Item.create("thermos")
	_m.add_child(held_view_test)
	_m.all_items.append(held_view_test)
	_p.take_item(held_view_test)
	var held_view_test_2 := Item.create("tissue")
	_m.add_child(held_view_test_2)
	_m.all_items.append(held_view_test_2)
	_p.take_item(held_view_test_2)
	_m._update_skill_hud()
	_check(_m.player_throw_items(_p).size() == 2 and _m.hud.item_wheel.visible,
			"徒步轮盘：双手满载时读取全部手持商品并显示轮盘")
	_m._unhandled_input(press)
	_m._update_camera(0.2)
	_check(not _m.cam_rig.is_first_person() and _p.body_root.visible \
			and not _m.cam_rig.first_person_hands_visible() \
			and _m.cam_rig.spring.spring_length < CameraRig.DIST \
			and _m.cam_rig.spring.position.x > CameraRig.SHOULDER_OFFSET \
			and _m.cam_rig.camera.fov < CameraRig.FOV,
			"脱车视角：常态保持第三人称，按住右键平滑切入2米右肩越肩镜头")
	_check(held_view_test.visible and held_view_test_2.visible \
			and _m.cam_rig.first_person_held_item_count() == 0,
			"第三人称手持：保留角色双手间的真实商品模型，不生成第一人称重复模型")
	_check(_p.throw_aiming and not _m.cam_rig.throw_preview_visible() \
			and _m.hud.item_wheel.visible and not _m.cam_rig.is_first_person(),
			"徒步右键：使用第三人称越肩瞄准和手持轮盘，不显示驾车抛物线")
	_m._unhandled_input(release)
	_m._update_camera(0.1)
	_check(not _m.cam_rig.is_first_person() and not _p.throw_aiming and _p.prop_cd > 0.0 \
			and _p.held.size() == 1,
			"徒步投掷：松开右键投出轮盘选中手持商品，保持第三人称视角")
	var pedestrian_throw_active := false
	for it in [held_view_test, held_view_test_2]:
		pedestrian_throw_active = pedestrian_throw_active \
				or is_instance_valid(it) and bool(it.get_meta("throw_active", false))
	_check(pedestrian_throw_active, "徒步投掷：真实手持商品离手并进入投掷态")
	_p.prop_cd = 0.0
	_p.drop_all_held(false)
	_p.attach_cart()
	_m._update_skill_hud()
	_m._unhandled_input(press)
	_m._update_camera(0.2)
	_check(not _m.cam_rig.is_first_person() and _p.body_root.visible and held_view_test.visible \
			and _p.throw_aiming and _m.cam_rig.throw_preview_visible(),
			"右键瞄准：上车恢复世界商品可见性，进入右肩镜头并显示半透明抛物线")
	_m._unhandled_input(release)
	_check(not _p.throw_aiming and _p.prop_cd > 0.0,
			"右键瞄准：松开后才消耗商品并进入投掷冷却")
	_p.prop_cd = 0.0
	for it in _m.all_items:
		if is_instance_valid(it) and bool(it.get_meta("throw_active", false)):
			it.set_meta("throw_active", false)
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
	var min_type := Catalog.ITEMS.size()
	var max_type := 0
	for kind in type_counts:
		min_type = mini(min_type, int(type_counts[kind]))
		max_type = maxi(max_type, int(type_counts[kind]))
	_check(type_counts.size() == 4 and max_type - min_type <= 1,
			"统一分类：72个目录条目按18/18/18/18严格均分为四类")
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
	_check(not _m.hud.crosshair.visible and not _m.hud.controls_hint.visible \
			and _m.hud.minimap.visible and _m.hud.cd_wheel.size.x >= 140.0,
			"HUD重排：白点与右上键位表删除，小地图和状态条右侧技能冷却槽启用")
	_check(is_equal_approx(Player.SHELF_INTERACT_DISTANCE, 8.0) \
			and is_equal_approx(Player.FREE_INTERACT_DISTANCE, 2.2),
			"拿取范围：商品视觉标注与E键互动共用同一套货架/散货距离")

func _setup_shelf_target() -> void:
	if _p.attached:
		_p.detach_cart()
	# 第三人称上下车保持平滑跟随；测试先让镜头收敛到徒步目标，再沿真实准星放置货物。
	_m._update_camera(1.0)
	_shelf_target = Item.create("thermos")
	_m.add_child(_shelf_target)
	_m.all_items.append(_shelf_target)
	_track_shelf_target = true
	_place_shelf_on_crosshair()

func _place_shelf_on_crosshair() -> void:
	var ray_origin := _p.global_position + Vector3.UP * Main.THROW_ORIGIN_HEIGHT
	var exclusions: Array[RID] = [_p.get_rid()]
	if is_instance_valid(_p.cart):
		exclusions.append(_p.cart.get_rid())
	# 实际选货判定从角色头部沿相机准星会聚方向发射，不是从第三人称相机本体发射。
	var ray_dir := _m.cam_rig.aim_direction_from(ray_origin, exclusions)
	var flat_length := maxf(Vector2(ray_dir.x, ray_dir.z).length(), 0.01)
	var t := 1.35 / flat_length
	_shelf_target.set_shelved(ray_origin + ray_dir * t)

func _check_shelf_target() -> void:
	var pick := _p._best_interaction()
	_check(pick.get("kind", "") == "search" and pick.get("target") == _shelf_target,
			"货架拿取：只有屏幕中心准星命中的具体商品成为搜货目标")
	_track_shelf_target = false

func _move_shelf_off_crosshair() -> void:
	_shelf_target.global_position += _m.cam_rig.camera.global_basis.x * 1.0

func _check_shelf_miss() -> void:
	var pick := _p._best_interaction()
	_check(pick.get("target") != _shelf_target,
			"货架拿取：商品离开准星后不再能靠距离自动拿取")
	_shelf_target.queue_free()
	_p.cart.global_position = _p.global_position + Vector3(0, 0.2, -1.2)
	_p.attach_cart()

func _setup_ground_target() -> void:
	if _p.attached:
		_p.detach_cart()
	# 把自己的车移出准星射线，验证的目标必须是真正落在地面的自由商品。
	_p.cart.global_position = _p.global_position + Vector3.RIGHT * 3.0 + Vector3.UP * 0.2
	_m._update_camera(1.0)
	# 不同队伍等待室的准星远端可能恰好对着真实货架；散货专项只验证近处FREE
	# 候选，因此临时锁住原本可选的货架商品，结束后完整恢复。
	_ground_blocked_shelves.clear()
	for it in _m.all_items:
		if is_instance_valid(it) and it.state == Item.ItemState.SHELVED and not it.event_locked:
			_ground_blocked_shelves.append(it)
			it.set_event_locked(true)
	_ground_target = Item.create("cola")
	_m.add_child(_ground_target)
	_m.all_items.append(_ground_target)
	var ray_origin := _p.global_position + Vector3.UP * Main.THROW_ORIGIN_HEIGHT
	var exclusions: Array[RID] = [_p.get_rid(), _p.cart.get_rid()]
	var ray_dir := _m.cam_rig.aim_direction_from(ray_origin, exclusions)
	_ground_target.set_free_at(ray_origin + ray_dir * 1.45)
	_ground_target.freeze = true

func _check_ground_target() -> void:
	var pick := _p._best_interaction()
	_check(pick.get("kind", "") == "pickup" and pick.get("target") == _ground_target,
			"徒步散货：只有屏幕中央准星瞄准时才出现拾取判定（当前%s/%s）" % [
					str(pick.get("kind", "none")),
					str((pick.get("target") as Item).item_id) if pick.get("target") is Item else "none"])

func _move_ground_off_crosshair() -> void:
	_ground_target.global_position += _m.cam_rig.camera.global_basis.x * 1.0

func _check_ground_miss() -> void:
	var pick := _p._best_interaction()
	_check(pick.get("target") != _ground_target,
			"徒步散货：商品仍在脚边但离开准星后不能自动拾取")
	_ground_target.queue_free()
	for it in _ground_blocked_shelves:
		if is_instance_valid(it):
			it.set_event_locked(false)
	_ground_blocked_shelves.clear()
	_p.cart.global_position = _p.global_position + Vector3(0, 0.2, -1.2)
	_p.attach_cart()

func _clear_cart() -> void:
	for it in _p.cart.items_in_basket():
		# 专项探针必须在同一物理帧内清空旧弹药；queue_free 会让旧货继续占据
		# 一帧的轮盘候选，导致后续效果测试错误选中上一个商品。
		it.free()

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
	_check(_count_zones("slow") == _zone_before + 1, "湿滑类：落点生成高亮湿滑地面")
	var zones := _m.get_children().filter(func(node): return node is SlipperyZone)
	if not zones.is_empty() and not _dummy.downed:
		(zones.back() as SlipperyZone)._on_body_entered(_dummy)
	_check(_dummy.downed and _dummy.imbalance >= _dummy.max_imbalance_value(),
			"湿滑类：首次踏入直接满失衡滑倒，不再逐步累计失衡")

func _throw_thermos() -> void:
	_clear_cart()
	_item = _put("thermos")
	if _dummy.downed:
		_dummy._recover()
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
	var scatter_fog := _m.find_child("ScatterBeautyFog", true, false) as FogVolume
	var scatter_mat := scatter_fog.material as FogMaterial if scatter_fog != null else null
	_check(scatter_mat != null and scatter_mat.albedo.r >= 0.99 and scatter_mat.albedo.g >= 0.8,
			"散落类：外观与个护区统一为高明度淡粉体积雾")
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
			"电击类：直接命中角色后统一定身5秒")
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
	var leaked_item := Item.create("cola")
	_m.add_child(leaked_item)
	leaked_item.set_free_at(_p.cart.to_global(Vector3(0.0, Cart.FLOOR_TOP + 0.25, 0.0)))
	_p.cart._on_basket_body_entered(leaked_item)
	leaked_item.global_position = _p.cart.to_global(Vector3(0.0, Cart.FLOOR_TOP - 0.35, 0.0))
	_p.cart._rescue_items_below_basket()
	var rescued_local := _p.cart.to_local(leaked_item.global_position)
	_check(rescued_local.y > Cart.FLOOR_TOP and _p.cart._basket_known.has(leaked_item.get_instance_id()),
			"购物车防漏货：曾进入车斗且向下穿底的商品会被送回内底面")
	leaked_item.queue_free()
	_p.detach_cart()
	var carried_item := Item.create("thermos")
	_m.add_child(carried_item)
	_p.take_item(carried_item)
	_p.attach_cart()
	var loaded_local := _p.cart.to_local(carried_item.global_position)
	_check(_p.held.is_empty() and carried_item.state == Item.ItemState.FREE \
			and absf(loaded_local.x) < Cart.INNER_HALF_X \
			and absf(loaded_local.z) < Cart.INNER_HALF_Z,
			"上车装货：手持商品会自动落入车斗，不再保持手持状态")
	carried_item.queue_free()
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
