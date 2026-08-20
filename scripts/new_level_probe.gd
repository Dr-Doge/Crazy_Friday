class_name NewLevelProbe extends RefCounted
## v6施工图版New_Level专项回归：参考图语义、CSG资产、分区、通行净宽与运行时玩法。

var _m: Main
var _fails: Array[String] = []
var _notes: Array[String] = []

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	var packed := load("res://scenes/New_Level.tscn") as PackedScene
	_check(packed != null, "场景资源：New_Level.tscn可加载")
	if packed == null:
		_report()
		return
	var level := packed.instantiate()
	_check(level.get_script() == load("res://scripts/main.gd") \
			and bool(level.get("embedded_level")),
			"玩法入口：New_Level直接承载main.gd并启用手工关卡模式")
	_check(str(level.get_meta("reference", "")).ends_with("黑五扫货_超市施工指示图_v6_2K.png") \
			and str(level.get_meta("annotation_reference", "")).ends_with("黑五扫货_超市部件标注图_v7_2K.png"),
			"参考约束：v6为几何基准，v7只登记为标注说明")
	_check(float(level.get_meta("min_clear_aisle_m", 0.0)) >= 4.0,
			"布局元数据：最低净过道不小于4米")
	_m.hud.set_sensitivity_panel(true, 1.35)
	_check(_m.team_prep_active and _m.hud.sensitivity_panel_visible() \
			and is_equal_approx(_m.hud.sensitivity_slider.value, 1.35) \
			and is_equal_approx(_m.cam_rig.sensitivity_multiplier(), 1.35),
			"准备设置：ESC面板提供40%–250%鼠标视角灵敏度滑块并即时生效")
	_m.hud.set_sensitivity_panel(false)
	_m.cam_rig.set_sensitivity_multiplier(1.0)
	var architecture := level.find_child("Architecture", true, false) as Node3D
	var shelf_islands := level.find_child("ShelfIslands", true, false) as Node3D
	_check(absf(float(level.get_meta("horizontal_expansion", 1.0)) - 1.25) < 0.001 \
			and architecture != null and absf(architecture.scale.x - 1.25) < 0.001 \
			and absf(float(level.get_meta("longitudinal_expansion", 1.0)) - 1.25) < 0.001 \
			and absf(architecture.scale.z - 1.25) < 0.001 \
			and shelf_islands != null and absf(shelf_islands.scale.x - 1.0) < 0.001 \
			and absf(shelf_islands.scale.z - 1.0) < 0.001,
			"平面扩建：卖场东西/南北均扩至1.25倍，货架容器保持原始模型尺度")

	var csg_shapes: Array[CSGShape3D] = []
	var mesh_count := _collect_models(level, csg_shapes)
	_check(csg_shapes.size() >= 230,
			"白盒资产：至少230个可在编辑器单独调整的CSG节点")
	_check(mesh_count > 0 and level.find_child("BakedArtAssets", true, false) != null,
			"资产约束：正式Mesh/prefab已作为真实场景节点导入，CSG白盒继续保留碰撞与可编辑货位")
	_check(level.find_child("FloorOutline", true, false) is CSGPolygon3D,
			"外轮廓：八边形卖场地板使用可编辑CSGPolygon3D")
	_check(level.find_child("BackOfHouse", true, false) == null,
			"平面清理：不存在v6施工图以外的西北仓库")
	var corners_connected := _segment_connects(level, "Wall_Chamfer_13",
			Vector3(-31.0, 2.2, -22.5), Vector3(-36.0, 2.2, -9.0)) \
			and _segment_connects(level, "Wall_Chamfer_14",
					Vector3(31.0, 2.2, -22.5), Vector3(36.0, 2.2, -9.0)) \
			and _segment_connects(level, "Wall_Chamfer_15",
					Vector3(31.0, 2.2, 22.5), Vector3(36.0, 2.2, 9.0)) \
			and _segment_connects(level, "Wall_Chamfer_16",
					Vector3(-31.0, 2.2, 22.5), Vector3(-36.0, 2.2, 9.0))
	_check(corners_connected,
			"外墙接缝：四角斜墙均按西南模板与相邻直墙重叠连接")
	_check(architecture != null and absf(architecture.scale.y - 1.5) < 0.01,
			"垂直空间：外墙按原高度1.5倍增高至6.6米")

	var zone_floor_count := 0
	var zone_colors := {}
	for child in (level.find_child("ZoneFloors", true, false) as Node).get_children():
		if child is CSGBox3D and str(child.name).begins_with("ZoneFloor_"):
			zone_floor_count += 1
			var material := (child as CSGBox3D).material as StandardMaterial3D
			if material != null:
				zone_colors[material.albedo_color] = true
	_check(zone_floor_count == 8 and zone_colors.size() == 8,
			"分区地板：八个区域均存在且使用八种不同颜色")
	_check(_hanging_signage_ready(level),
			"分区标识：九块厚重CSG方牌均有四面单向正字，旧贴地文字已取消显示")
	var shelf_branch := level.find_child("ShelfIslands", true, false)
	var shelf_color: Color = Color(-1, -1, -1)
	var dark_shelf_count := 0
	var shelf_colors_match := shelf_branch != null
	if shelf_branch != null:
		var shelf_parts: Array[CSGBox3D] = []
		_collect_csg_boxes(shelf_branch, shelf_parts)
		for child in shelf_parts:
			var material := child.material as StandardMaterial3D
			if material == null:
				shelf_colors_match = false
				continue
			if dark_shelf_count == 0:
				shelf_color = material.albedo_color
			else:
				shelf_colors_match = shelf_colors_match \
						and material.albedo_color.is_equal_approx(shelf_color)
			dark_shelf_count += 1
	_check(dark_shelf_count >= 110,
			"货架资产：32组当前手工货架/货柜均保留可编辑CSG父子级")
	_check(_shelf_hierarchy_matches_template(level),
			"货架父子级：普通立式货架复制Snack_01双子件结构，四组矮柜整体半高")
	var appliance_a := _find_box(level, "Shelf_Electronics_01")
	var appliance_b := _find_box(level, "Shelf_Electronics_02")
	_check(appliance_a != null and appliance_b != null \
			and appliance_a.transform.basis.z.length() >= 0.53 \
			and appliance_b.transform.basis.z.length() >= 0.53,
			"家电货架：保留当前手工变换，仅复制Snack_01子结构")
	_check(_shelves_follow_zone_floors(level),
			"分区范围：全部货架均落在各自彩色地板定义的区域内")
	_check(_count_named_prefix(level, "RingRoute_") == 0,
			"中心清理：已沿用手工版本，不重新加入黑五爆款区地板饰条")

	_check(_count_group(level, "new_level_shelf") == 33,
			"货架排布：沿用当前手工版本的33组根货架，不回退用户排版")
	_check(_art_asset_import_ready(),
			"实体美术节点：33组货架/冰柜与34组灯管已写入New_Level场景树；模块首尾连续、冰柜仅001/002，全部prefab均可在左侧节点树找到")
	_check(_count_fixture(level, "cold_case") == 4,
			"生鲜冷冻：四组原立式货架已替换为双层开放货柜")
	_check(_count_group(level, "new_level_premium") == 1,
			"中心陈列：沿用手工删减后的单组黑五低矮促销展台")
	_check(_count_group(level, "team_entrance") == 4 \
			and _count_group(level, "public_exit") == 4,
			"出入口：四个队伍入口与四个公共出口完整")
	_check(_count_group(level, "checkout_visual_group") == 4 \
			and _count_group(level, "checkout_terminal") == 8,
			"收银排布：四边各一组双收银位，共8个CSG终端")
	var checkout_orientation_ok := _count_group(level, "checkout_lane_visual") == 6 \
			and _count_group(level, "checkout_channel_rail") == 16
	for group_name in ["CheckoutGroup_North", "CheckoutGroup_South",
			"CheckoutGroup_West", "CheckoutGroup_East"]:
		var group := level.find_child(group_name, true, false) as Node3D
		if group == null:
			checkout_orientation_ok = false
			continue
		var outward := Vector3(group.position.x, 0.0, group.position.z).normalized()
		checkout_orientation_ok = checkout_orientation_ok \
				and group.transform.basis.z.normalized().dot(outward) > 0.99
		for suffix in ["A", "B"]:
			var counter := level.find_child("Counter_%s_%s" % [
					group_name.trim_prefix("CheckoutGroup_"), suffix], true, false) as CSGBox3D
			checkout_orientation_ok = checkout_orientation_ok and counter != null \
					and counter.size.z > counter.size.x * 3.0
	_check(checkout_orientation_ok,
			"收银车道：四组均以双推车通道为主体，窄台面仅作两侧辅助装饰")
	_check(_count_named_prefix(level, "WallCase_") >= 8 \
			and _count_named_prefix(level, "Vending_") >= 8,
			"周边设施：四角单组壁柜与四台售货机均以CSG部件搭建")
	_check(_count_group(level, "sample_stand") == 4 \
			and _m.get_tree().get_nodes_in_group("sample_stand").size() == 4 \
			and _m.get_tree().get_nodes_in_group("sample_stand").all(func(stand):
				return stand.get_node_or_null("SampleStandLabel") is Label3D),
			"场边设施：四座原展示柜均改为有文字标识且可互动的免费试吃摊")
	_check(_vending_machines_mirrored(level),
			"售货机排布：其余三台按南部出口右侧手工样板四角镜像")
	_check(_corner_cases_mirrored(level),
			"贴墙资产：其余三角壁柜按西南手工排布镜像并重新贴合墙面")

	var gameplay := NewLevelLayout.build(level)
	_check((gameplay["checkout_specs"] as Array).size() == 8,
			"收银功能：四个出口共八条车道均接入结算玩法")
	_check(gameplay["slots"].size() >= 600,
			"货架功能：30组双层CSG货架仍生成充足可拿取陈列位")
	var zones := {}
	var slot_counts := {}
	for slot in gameplay["slots"]:
		zones[slot["zone"]] = true
		slot_counts[slot["zone"]] = int(slot_counts.get(slot["zone"], 0)) + 1
	var all_zone_slots := zones.has(Catalog.ZONE_PREMIUM)
	for zone in Catalog.SHOPPING_ZONES:
		all_zone_slots = all_zone_slots and zones.has(zone)
	_check(all_zone_slots,
			"商品分配：八个独立专区与中央爆款区均有有效货位")
	_check(gameplay["player_spawns"].size() == 8 \
			and gameplay["granny_spawns"].size() == 8,
			"对局出生：8个四队席位与8名NPC均有新版场景锚点")
	_check(_count_group(level, "team_waiting_room") == 4 \
			and _count_group(level, "waiting_room_cart_bay") == 0 \
			and _spawns_inside_waiting_rooms(level, gameplay["player_spawns"]),
			"等待室：沿用手工删除隔离带后的开放缓冲区，8个场景锚点仍位于室内")
	_check(_team_spawns_centered_and_facing(gameplay),
			"队伍出生：每队两席以等待室正中心为中点，人物和购物车均正对本队准备室大门")
	_check((gameplay["zone_bounds"] as Dictionary).size() == 8,
			"玩法范围：八个分类区域直接读取当前彩色地板尺寸")
	_check(_regional_architecture_ready(level),
			"分区建筑：冷冻隔离墙双入口、中央围墙、四门与四根斜角立柱完整")
	_check(_count_group(level, "freezer_curtain_strip") == 10 \
			and _count_group(level, "freezer_curtain_joint") == 10,
			"冷冻门帘：双入口共10片重力软帘，上沿关节固定且可物理推动")
	_check(_actor_world_markers_ready(),
			"角色标识：姓名受场景深度遮挡，玩家脚边箭头持续指向自己的购物车")
	_check(_count_group(level, "team_start_gate") == 4,
			"开局入口：四队均有对应颜色的实体准备门")

	var expected_stock := 0
	for zone in slot_counts:
		expected_stock += Catalog.shelf_stock_target(str(zone), int(slot_counts[zone]))
	for id in Catalog.ITEMS:
		if Catalog.ITEMS[id]["cat"] == Catalog.CAT_LARGE:
			expected_stock += int(Catalog.ITEMS[id]["stock"])
	var region_granny_count := _m.get_tree().get_nodes_in_group("region_grannies").size()
	_check(_m.all_items.size() == expected_stock + 6 \
			and _m.get_tree().get_nodes_in_group("region_kids").size() == 8 \
			and region_granny_count >= 6 and region_granny_count <= 8,
			"实际开局：%d件货架库存＋6件乱蹦生鲜，另有8熊孩子/6–8挡路大妈（实际商品%d/孩子%d/大妈%d）" % [
				expected_stock, _m.all_items.size(),
				_m.get_tree().get_nodes_in_group("region_kids").size(),
				region_granny_count])
	_check(_tiered_stock_ready(expected_stock),
			"三级铺货：平面生鲜/冷冻柜只铺最上层，其余货架按6:3:1分布并显示为车内尺寸2倍")
	var checkouts_ready := _m.checkouts.size() == 8
	for co in _m.checkouts:
		checkouts_ready = checkouts_ready and co.gate != null \
				and co.south_gate != null and co.inner_area != null \
				and co.sign_label != null and co.sign_label.get_parent() == co.gate \
				and not co.sign_label.no_depth_test and absf(co.sign_label.position.y) < 0.05 \
				and co.queue_wait_pos().distance_to(co.scan_stop_pos()) > 2.0 \
				and co._gate_open_pos > co._gate_closed_pos
	_check(checkouts_ready, "实际开局：八条通道均有单车隔离门，开关文字贴在入口挡板且受场景遮挡")
	_check(_all_world_labels_depth_tested(_m),
			"场地文字：角色、告示、字幕与收银状态全部参加深度测试，不穿透场景模型")
	var open_by_side := {}
	for i in _m.checkouts.size():
		if not _m.checkouts[i].lane_open:
			continue
		var side := str(_m.checkouts[i].name).trim_prefix("Checkout_").get_slice("_", 0)
		open_by_side[side] = int(open_by_side.get(side, 0)) + 1
	_check(_m.active_checkout_indices.size() == 4 and open_by_side.size() == 4,
			"随机收银：八条中开放四条，且东南西北每个出口恰有一条可用")
	_check(_count_group(level, "exit_apron") == 4 \
			and _count_group(level, "exit_apron_guard") == 12,
			"出口缓冲：四个出口外均有大型引导平台和三面防坠护栏")
	_check(_m.find_child("Market", false, false) == null,
			"场景隔离：正式对局未叠加旧MarketBuilder卖场")
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) \
			== "res://scenes/New_Level.tscn",
			"模式入口：单机与联机均从当前New_Level场景启动")

	var audit := level.find_child("TopDownAuditCamera", true, false) as Camera3D
	_check(audit != null and audit.projection == Camera3D.PROJECTION_ORTHOGONAL \
			and audit.size >= 100.0 and audit.position.y >= 55.0,
			"排布审查：正上方正交相机覆盖完整卖场")
	var authored_runtime := level.find_child("RuntimeOnly", true, false) as Node3D
	var live_runtime := _m.find_child("RuntimeOnly", true, false) as Node3D
	_check(authored_runtime != null and not authored_runtime.visible \
			and live_runtime != null and live_runtime.visible \
			and live_runtime.find_child("Ceiling", true, false) is CSGPolygon3D \
			and (live_runtime.find_child("Ceiling", true, false) as Node3D).position.y >= 7.3 \
			and _count_named_prefix(live_runtime, "Ceiling_") == 4,
			"运行时顶棚：增高至7.35米，并完整覆盖四个等待室")
	var lights: Array[SpotLight3D] = []
	_collect_spotlights(_m, lights)
	var lighting_valid := _count_group(level, "aisle_light_fixture") == 30 \
			and lights.size() == 30
	for light in lights:
		var aim := -light.transform.basis.z.normalized()
		lighting_valid = lighting_valid and light.shadow_enabled \
				and light.light_energy >= 1.0 and light.light_energy <= 1.1 \
				and light.spot_range >= 11.5 and light.spot_range <= 12.5 \
				and aim.dot(Vector3.DOWN) > 0.99
	_check(lighting_valid and _count_group(level, "waiting_room_downlight") == 4 \
			and _count_imported_render_helpers(_m) == 0,
			"照明：仅保留34盏关卡顶灯，导入资产辅助节点已剔除并加强防过曝照明")
	_check(await _verify_central_opening(),
			"中央事件：每局随机1—3种压轴商品，开局锁定并随四门升起开放")
	_check(await _verify_team_entrance_opening(),
			"开局倒计时：5秒中央大字、准备阶段不耗比赛时间，四队门权威同步")
	_check(await _verify_curtain_physics(),
			"冷冻门帘实测：下沿受推后摆开，并在重力与阻尼作用下回垂闭合")
	_check(_verify_region_effects(gameplay["zone_bounds"]),
			"分区机制：5秒冻僵及A/D挣扎生效，个护区与遮蔽道具共用无硬切淡粉渐进雾")
	_check(_verify_region_npc_behaviors(),
			"生态NPC：较低难受上限生效，活鲜两拳昏迷静止，大妈受击后共享仇恨")
	_check(_verify_vending_coupon(),
			"自动贩卖机：可捶打并夸张闪动，中奖券绑定具体商品且必须在结算时兑现")

	var clearances := {
		"生鲜双货柜": _clearance_z(level, "Shelf_Fresh_01", "Shelf_Fresh_02"),
		"冷冻双货柜": _clearance_z(level, "Shelf_Frozen_01", "Shelf_Frozen_02"),
		"数码双货架": _world_clearance_x(level, "Shelf_Electronics_02", "Shelf_Electronics_01"),
		"日用双货架": _clearance_x(level, "Shelf_Daily_NW", "Shelf_Daily_NE"),
	}
	for label in clearances:
		_check(float(clearances[label]) >= 3.95,
				"双车净宽：%s %.1f米（≥4.0米）" % [label, clearances[label]])
	_check(await _verify_checkout_flow(),
			"收银实测：四条开放通道可逐件扫码，四条关闭通道拒绝结算")
	level.free()
	_m.get_tree().create_timer(0.05).timeout.connect(_report)

func _verify_checkout_flow() -> bool:
	if _m.checkouts.size() != 8:
		return false
	var settled_flags := {}
	var spawned: Array[Node] = []
	for i in _m.checkouts.size():
		var co := _m.checkouts[i]
		if not co.lane_open:
			continue
		var lane_id := i
		co.lane_settled.connect(func(_by: Player) -> void:
			settled_flags[lane_id] = true, CONNECT_ONE_SHOT)
		var dummy := Player.new()
		dummy.main = _m
		dummy.remote = true
		_m.add_child(dummy)
		var cart := Cart.create(Color(0.7, 0.7, 0.7), "收银测试车%d" % i)
		_m.add_child(cart)
		dummy.cart = cart
		cart.cart_owner = dummy
		cart.global_position = co.scan_stop_pos()
		dummy.global_position = cart.global_position
		dummy.attach_cart()
		var item := Item.create("cola")
		_m.add_child(item)
		dummy.take_item(item)
		spawned.append(dummy)
		spawned.append(cart)
		spawned.append(item)
	await _m.get_tree().create_timer(2.35).timeout
	var ok := settled_flags.size() == 4
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	await _m.get_tree().process_frame
	# NPC结算离场必须立即释放通道，而不是残留在出口或等Area下一轮刷新。
	var npc_lane: Checkout = null
	for co in _m.checkouts:
		if co.lane_open:
			npc_lane = co
			break
	if npc_lane == null:
		return false
	var bot := Granny.new()
	bot.main = _m
	bot.is_team_bot = true
	_m.add_child(bot)
	var npc_cart := Cart.create(Color(0.5, 0.7, 0.95), "结算离场测试车")
	npc_cart.cart_owner = bot
	_m.add_child(npc_cart)
	bot.cart = npc_cart
	bot.attach_cart()
	bot.target_checkout = npc_lane
	_m.grannies.append(bot)
	_m.team_bots.append(bot)
	npc_lane._active_cart = npc_cart
	var outside := npc_lane.exit_outer_pos()
	_m.teleport_checkout_agent_outside(bot, npc_lane)
	ok = ok and npc_cart.global_position.distance_to(outside + Vector3.UP * 0.22) < 0.1 \
			and npc_lane._active_cart == null
	# 再占用一次以验证NPC销毁路径也会立即释放。
	npc_lane._active_cart = npc_cart
	bot._despawn_and_leave()
	await _m.get_tree().process_frame
	ok = ok and not is_instance_valid(bot) and not is_instance_valid(npc_cart) \
			and npc_lane._active_cart == null and npc_lane.lane_open
	return ok

func _collect_models(node: Node, csg: Array[CSGShape3D]) -> int:
	var meshes := 1 if node is MeshInstance3D else 0
	if node is CSGShape3D:
		csg.append(node as CSGShape3D)
	for child in node.get_children():
		meshes += _collect_models(child, csg)
	return meshes

func _all_world_labels_depth_tested(root: Node) -> bool:
	if root is Label3D:
		var parent := root.get_parent()
		while parent != null:
			# 第一人称手持物复制体属于相机内HUD，不是“场地上的文本框”。
			if parent is Camera3D:
				return true
			parent = parent.get_parent()
		if (root as Label3D).no_depth_test:
			return false
	for child in root.get_children():
		if not _all_world_labels_depth_tested(child):
			return false
	return true

func _collect_csg_boxes(node: Node, out: Array[CSGBox3D]) -> void:
	if node is CSGBox3D:
		out.append(node as CSGBox3D)
	for child in node.get_children():
		_collect_csg_boxes(child, out)

func _shelf_hierarchy_matches_template(root: Node) -> bool:
	var shelves: Array[Node] = []
	_collect_group_nodes(root, "new_level_shelf", shelves)
	if shelves.size() != 33:
		return false
	for node in shelves:
		var shelf := node as CSGBox3D
		if shelf == null:
			return false
		var parts: Array[CSGBox3D] = []
		for child in shelf.get_children():
			if child is CSGBox3D:
				parts.append(child as CSGBox3D)
		var cold_case := str(shelf.get_meta("fixture", "")) == "cold_case"
		if cold_case:
			if str(shelf.get_meta("template", "")) != "Shelf_Fresh_01":
				return false
			if parts.size() != 7 \
					or shelf.find_child("*_Lip_North", false, false) == null \
					or shelf.find_child("*_Lip_South", false, false) == null:
				return false
			var cold_spine := shelf.find_child("*_Spine", false, false) as CSGBox3D
			var cold_middle := shelf.find_child("*_Board_Middle", false, false) as CSGBox3D
			var cold_lower := shelf.find_child("*_Board_Lower", false, false) as CSGBox3D
			if cold_spine == null or absf(cold_spine.size.y - 1.0) > 0.01 \
					or cold_middle == null or absf(cold_middle.position.y - 0.81) > 0.01 \
					or cold_lower == null or absf(cold_lower.size.z - 1.5) > 0.01:
				return false
			continue
		if parts.size() != 2:
			return false
		if str(shelf.get_meta("template", "")) != "Shelf_Snacks_01":
			return false
		var ys: Array[float] = []
		for part in parts:
			if absf(part.position.x) > 0.01 or absf(part.position.z) > 0.01:
				return false
			ys.append(snappedf(part.position.y, 0.01))
		ys.sort()
		if not is_equal_approx(ys[0], 0.95) or not is_equal_approx(ys[1], 1.03):
			return false
		var spine := shelf.find_child("*_Spine", false, false) as CSGBox3D
		var lower := shelf.find_child("*_Board_Lower", false, false) as CSGBox3D
		if spine == null or spine.size.y < 1.95 or absf(spine.size.z - 0.12) > 0.01 \
				or lower == null or absf(lower.size.z - 0.82) > 0.01 \
				or absf(lower.size.x - shelf.size.x) > 0.01:
			return false
	return true

func _tiered_stock_ready(expected_total: int) -> bool:
	if _m.all_items.size() != expected_total + 6:
		return false
	var counts := {}
	var shelf_nodes: Array[Node] = []
	_collect_group_nodes(_m, "new_level_shelf", shelf_nodes)
	for it in _m.all_items:
		if bool(it.get_meta("live_fresh_good", false)):
			continue
		if not is_instance_valid(it) or it.state != Item.ItemState.SHELVED \
				or Catalog.LIVE_FRESH_IDS.has(it.item_id) \
				or not it.scale.is_equal_approx(Vector3.ONE * Catalog.SHELF_DISPLAY_SCALE) \
				or it.collision_layer != 0 or it.collision_mask != 0:
			return false
		var has_art := is_instance_valid(it.visual_root) \
				and it.visual_root.has_meta("art_item_id")
		if (has_art and (it.label != null or not it.surface_labels.is_empty())) \
				or (not has_art and (it.label == null or it.surface_labels.size() != 2)):
			return false
		# 已替换正式资产的商品约定本地+Z为包装正面；双面货架必须分别朝外。
		if has_art:
			var nearest: Node3D = null
			var nearest_dist := INF
			for shelf_node in shelf_nodes:
				var shelf := shelf_node as Node3D
				var dist := Vector2(it.global_position.x - shelf.global_position.x,
						it.global_position.z - shelf.global_position.z).length()
				if dist < nearest_dist:
					nearest_dist = dist
					nearest = shelf
			if nearest != null and nearest_dist < 2.0:
				var outward := it.global_position - nearest.global_position
				outward.y = 0.0
				var shelf_normal := nearest.global_transform.basis.z
				shelf_normal.y = 0.0
				var expected_front := shelf_normal.normalized() \
						* (-1.0 if outward.dot(shelf_normal) < 0.0 else 1.0)
				var front := it.global_transform.basis.z
				front.y = 0.0
				if outward.length_squared() > 0.01 and front.length_squared() > 0.01 \
						and front.normalized().dot(expected_front) < 0.9:
					_notes.append("  INFO 商品朝向失败:%s dot=%.3f item=%s shelf=%s" % [
							it.item_id, front.normalized().dot(expected_front),
							str(it.global_position), str(nearest.global_position)])
					return false
		var data: Dictionary = Catalog.ITEMS[it.item_id]
		if str(data["zone"]) in [Catalog.ZONE_FRESH, Catalog.ZONE_FROZEN] \
				and it.global_position.y - it.shelf_display_half_height() < 0.88:
			return false
		if data["cat"] == Catalog.CAT_LARGE:
			continue
		var zone := str(data["zone"])
		var tier := Catalog.tier_of(it.item_id)
		var key := "%s:%d" % [zone, tier]
		counts[key] = int(counts.get(key, 0)) + 1
	for zone in Catalog.SHOPPING_ZONES + [Catalog.ZONE_PREMIUM]:
		var total := 0
		for tier in [Catalog.TIER_LOW, Catalog.TIER_MID, Catalog.TIER_HIGH]:
			total += int(counts.get("%s:%d" % [zone, tier], 0))
		if total <= 0:
			return false
		var expected_tiers := {Catalog.TIER_LOW: 0, Catalog.TIER_MID: 0, Catalog.TIER_HIGH: 0}
		for i in total:
			var expected_tier: int = Catalog.TIER_PATTERN[i % Catalog.TIER_PATTERN.size()]
			expected_tiers[expected_tier] += 1
		if int(counts.get("%s:1" % zone, 0)) != int(expected_tiers[Catalog.TIER_LOW]) \
				or int(counts.get("%s:2" % zone, 0)) != int(expected_tiers[Catalog.TIER_MID]) \
				or int(counts.get("%s:3" % zone, 0)) != int(expected_tiers[Catalog.TIER_HIGH]):
			return false
	return true

func _hanging_signage_ready(root: Node) -> bool:
	var legacy := root.find_child("LevelSignage", true, false) as Node3D
	var boards: Array[Node] = []
	var texts: Array[Node] = []
	_collect_group_nodes(root, "zone_hanging_sign", boards)
	_collect_group_nodes(root, "zone_hanging_sign_text", texts)
	if legacy != null or boards.size() != 9 or texts.size() != 36:
		return false
	var face_counts := {}
	var face_sets := {}
	for node in boards:
		if not (node is CSGBox3D):
			return false
		var board := node as CSGBox3D
		if board.position.y < 5.0 or board.size.x < 4.5 or board.size.z < 4.5 \
				or board.size.y < 1.4 or absf(board.size.x - board.size.z) > 0.05:
			return false
	for node in texts:
		if not (node is Label3D):
			return false
		var label := node as Label3D
		if label.billboard != BaseMaterial3D.BILLBOARD_DISABLED or label.double_sided \
				or label.transform.basis.determinant() < 0.99:
			return false
		var parts := str(label.name).trim_prefix("Text_").split("_")
		if parts.size() != 2 or not parts[1] in ["South", "North", "East", "West"]:
			return false
		var sign_id := str(parts[0])
		face_counts[sign_id] = int(face_counts.get(sign_id, 0)) + 1
		if not face_sets.has(sign_id):
			face_sets[sign_id] = {}
		face_sets[sign_id][str(parts[1])] = true
	for sign_id in face_counts:
		if int(face_counts[sign_id]) != 4 or (face_sets[sign_id] as Dictionary).size() != 4:
			return false
	return face_counts.size() == 9

func _collect_group_nodes(node: Node, group: StringName, out: Array[Node]) -> void:
	if node.is_in_group(group):
		out.append(node)
	for child in node.get_children():
		_collect_group_nodes(child, group, out)

func _shelves_follow_zone_floors(root: Node) -> bool:
	var shelves: Array[Node] = []
	_collect_group_nodes(root, "new_level_shelf", shelves)
	for node in shelves:
		var shelf := node as CSGBox3D
		var tokens := str(shelf.name).split("_")
		if tokens.size() < 2:
			return false
		var floor := _find_box(root, "ZoneFloor_%s" % tokens[1])
		if floor == null:
			return false
		var shelf_tx := _world_transform(shelf)
		var floor_tx := _world_transform(floor)
		var shelf_hx := (absf(shelf_tx.basis.x.x) * shelf.size.x \
				+ absf(shelf_tx.basis.z.x) * shelf.size.z) * 0.5
		var shelf_hz := (absf(shelf_tx.basis.x.z) * shelf.size.x \
				+ absf(shelf_tx.basis.z.z) * shelf.size.z) * 0.5
		var floor_hx := floor.size.x * floor_tx.basis.x.length() * 0.5
		var floor_hz := floor.size.z * floor_tx.basis.z.length() * 0.5
		if absf(shelf_tx.origin.x - floor_tx.origin.x) + shelf_hx > floor_hx + 0.05 \
				or absf(shelf_tx.origin.z - floor_tx.origin.z) + shelf_hz > floor_hz + 0.05:
			return false
	return true

func _spawns_inside_waiting_rooms(root: Node, spawns: Array) -> bool:
	if spawns.size() != 8:
		return false
	var room_rects: Array[Rect2] = []
	for suffix in ["A", "B", "C", "D"]:
		var room := root.find_child("WaitingRoom_%s" % suffix, true, false) as Node3D
		var floor := room.find_child("Floor", false, false) as CSGBox3D if room != null else null
		if floor == null:
			return false
		var tx := _world_transform(floor)
		var half_x := floor.size.x * tx.basis.x.length() * 0.5
		var half_z := floor.size.z * tx.basis.z.length() * 0.5
		room_rects.append(Rect2(tx.origin.x - half_x, tx.origin.z - half_z,
				half_x * 2.0, half_z * 2.0))
	for value in spawns:
		var p := value as Vector3
		var inside := false
		for rect in room_rects:
			inside = inside or rect.has_point(Vector2(p.x, p.z))
		if not inside:
			return false
	return true

func _actor_world_markers_ready() -> bool:
	var found_player := false
	for node in _m.get_tree().get_nodes_in_group("characters"):
		if not (node is Actor):
			continue
		var actor := node as Actor
		if actor.name_label == null or actor.name_label.no_depth_test:
			return false
		if not (actor is Player):
			continue
		var p := actor as Player
		if not is_instance_valid(p.cart) or not is_instance_valid(p.cart_pointer):
			return false
		if p == _m.player and p.name_label.visible:
			return false
		p._update_cart_pointer()
		var cart_dir := p.cart.global_position - p.global_position
		cart_dir.y = 0.0
		var pointer_dir := p.cart_pointer.global_position - p.global_position
		pointer_dir.y = 0.0
		var shaft := p.cart_pointer.get_child(0) as MeshInstance3D
		var shaft_mesh := shaft.mesh as BoxMesh if shaft != null else null
		if not p.cart_pointer.visible or cart_dir.length_squared() < 0.01 \
				or pointer_dir.normalized().dot(cart_dir.normalized()) < 0.99 \
				or pointer_dir.length() < 1.4 or shaft_mesh == null or shaft_mesh.size.z < 0.75:
			return false
		found_player = true
	return found_player

func _world_transform(node: Node3D) -> Transform3D:
	var tx := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		tx = (parent as Node3D).transform * tx
		parent = parent.get_parent()
	return tx

func _collect_spotlights(node: Node, out: Array[SpotLight3D]) -> void:
	if node is SpotLight3D and node.is_in_group("aisle_downlight"):
		out.append(node as SpotLight3D)
	for child in node.get_children():
		_collect_spotlights(child, out)

func _count_imported_render_helpers(node: Node, inside_art_prefab := false) -> int:
	var in_prefab := inside_art_prefab or node.has_meta("art_prefab")
	var count := 1 if in_prefab and (node is Camera3D or node is Light3D \
			or node is WorldEnvironment) else 0
	for child in node.get_children():
		count += _count_imported_render_helpers(child, in_prefab)
	return count

func _count_group(node: Node, group: StringName) -> int:
	var count := 1 if node.is_in_group(group) else 0
	for child in node.get_children():
		count += _count_group(child, group)
	return count

func _count_named_prefix(node: Node, prefix: String) -> int:
	var count := 1 if str(node.name).begins_with(prefix) else 0
	for child in node.get_children():
		count += _count_named_prefix(child, prefix)
	return count

func _find_box(root: Node, node_name: String) -> CSGBox3D:
	return root.find_child(node_name, true, false) as CSGBox3D

func _segment_connects(root: Node, node_name: String,
		expected_a: Vector3, expected_b: Vector3) -> bool:
	var box := _find_box(root, node_name)
	if box == null:
		return false
	var half := box.size.x * 0.5
	var a := box.transform * Vector3(-half, 0.0, 0.0)
	var b := box.transform * Vector3(half, 0.0, 0.0)
	var direct := maxf(a.distance_to(expected_a), b.distance_to(expected_b))
	var reversed := maxf(a.distance_to(expected_b), b.distance_to(expected_a))
	# 西南模板在接点处刻意留有几厘米重叠，0.12米容差足以识别连接但抓得住可见裂缝。
	return minf(direct, reversed) <= 0.12

func _corner_cases_mirrored(root: Node) -> bool:
	var sw2 := _find_box(root, "WallCase_W_South_02")
	if sw2 == null:
		return false
	var expected := {
		"WallCase_W_North_02": Vector3(sw2.position.x, sw2.position.y, -sw2.position.z),
		"WallCase_E_South_02": Vector3(-sw2.position.x, sw2.position.y, sw2.position.z),
		"WallCase_E_North_02": Vector3(-sw2.position.x, sw2.position.y, -sw2.position.z),
	}
	for node_name in expected:
		var box := _find_box(root, node_name)
		if box == null or box.position.distance_to(expected[node_name]) > 0.02:
			return false
	for prefix in ["W_North_02", "W_South_02", "E_North_02", "E_South_02"]:
		var body := _find_box(root, "WallCase_%s" % prefix)
		var glass := _find_box(root, "WallCase_%s_Glass" % prefix)
		if body == null or glass == null \
				or absf(body.position.distance_to(glass.position) - 0.63) > 0.03:
			return false
	return true

func _vending_machines_mirrored(root: Node) -> bool:
	var se := _find_box(root, "Vending_SE")
	if se == null:
		return false
	var expected := {
		"Vending_SW": Vector3(-se.position.x, se.position.y, se.position.z),
		"Vending_NE": Vector3(se.position.x, se.position.y, -se.position.z),
		"Vending_NW": Vector3(-se.position.x, se.position.y, -se.position.z),
	}
	for node_name in expected:
		var body := _find_box(root, node_name)
		var screen := _find_box(root, "%s_Screen" % node_name)
		if body == null or screen == null \
				or body.position.distance_to(expected[node_name]) > 0.02:
			return false
		var toward_center := Vector3(0.0, 0.0, -signf(body.position.z))
		var screen_dir := Vector3(screen.position.x - body.position.x, 0.0,
				screen.position.z - body.position.z).normalized()
		if screen_dir.dot(toward_center) < 0.98:
			return false
	return true

func _count_fixture(node: Node, fixture: String) -> int:
	var count := 1 if str(node.get_meta("fixture", "")) == fixture else 0
	for child in node.get_children():
		count += _count_fixture(child, fixture)
	return count

func _regional_architecture_ready(root: Node) -> bool:
	var frozen := root.find_child("FrozenIsolation", true, false)
	var central := root.find_child("CentralBlackFridayEnclosure", true, false)
	if frozen == null or central == null:
		return false
	var west_header := _find_box(root, "FrozenEntry_West_Header")
	var south_header := _find_box(root, "FrozenEntry_South_Header")
	return west_header != null and west_header.size.z >= 5.0 \
			and south_header != null and south_header.size.x >= 5.0 \
			and _count_group(root, "central_black_friday_gate") == 4 \
			and _count_named_prefix(central, "CentralPillar_") == 4 \
			and _count_named_prefix(central, "CentralWall_") == 12

func _verify_central_opening() -> bool:
	var gates := _m.get_tree().get_nodes_in_group("central_black_friday_gate")
	if gates.size() != 4 or _m.central_locked_items.is_empty() \
			or _m.central_feature_ids.size() < 1 or _m.central_feature_ids.size() > 3:
		return false
	for node in gates:
		if not (node is CSGBox3D) or not (node as CSGBox3D).use_collision \
				or (node as Node3D).position.y > 1.6:
			return false
	for it in _m.central_locked_items:
		if not is_instance_valid(it) or not it.event_locked or it.visible:
			return false
	var starts: Array[float] = []
	for node in gates:
		starts.append((node as Node3D).position.y)
	_m.open_central_black_friday()
	await _m.get_tree().create_timer(0.35).timeout
	for i in gates.size():
		var mid_gate := gates[i] as CSGBox3D
		var target := float(mid_gate.get_meta("slide_open_target_y", -1.0))
		if not is_instance_valid(mid_gate) or not mid_gate.use_collision \
				or not bool(mid_gate.get_meta("slide_open_animating", false)) \
				or mid_gate.position.y <= starts[i] + 0.05 or mid_gate.position.y >= target - 0.05:
			return false
	await _m.get_tree().create_timer(0.7).timeout
	for node in gates:
		if not is_instance_valid(node) or (node as Node3D).position.y < 5.1 \
				or (node as CSGBox3D).use_collision \
				or bool(node.get_meta("slide_open_animating", true)):
			return false
	var selected_alive := 0
	for it in _m.central_locked_items:
		if not is_instance_valid(it):
			continue
		if not _m.central_feature_ids.has(it.item_id) or it.event_locked or not it.visible:
			return false
		selected_alive += 1
	if selected_alive < 4 or selected_alive > 5:
		return false
	return true

func _verify_team_entrance_opening() -> bool:
	var gates := _m.get_tree().get_nodes_in_group("team_start_gate")
	if gates.size() != 4 or not _m.team_prep_active or _m.team_prep_left <= 0.0:
		return false
	if _m.elapsed > 0.05 or not is_equal_approx(Main.TEAM_PREP_DURATION, 5.0) \
			or _m.hud.prep_countdown_label == null \
			or _m.hud.prep_countdown_label.get_theme_font_size("font_size") < 150 \
			or not _m.hud.prep_countdown_label.visible:
		return false
	for node in gates:
		if not (node is CSGBox3D) or not (node as CSGBox3D).use_collision \
				or absf((node as Node3D).position.y - 1.65) > 0.05:
			return false
	for bot in _m.grannies:
		if not is_instance_valid(bot) or not bot.prep_locked or not bot.is_physics_processing():
			return false
	var bot_cart_starts := {}
	for bot in _m.grannies:
		if is_instance_valid(bot) and is_instance_valid(bot.cart):
			bot_cart_starts[bot.get_instance_id()] = bot.cart.global_position
	var starts: Array[float] = []
	for node in gates:
		starts.append((node as Node3D).position.y)
	_m.open_team_entrances()
	if _m.hud.prep_countdown_label.visible:
		return false
	for bot in _m.grannies:
		if not is_instance_valid(bot) or bot.prep_locked or not bot.is_physics_processing() \
				or bot.state != Granny.GState.IDLE:
			return false
	await _m.get_tree().create_timer(0.35).timeout
	for i in gates.size():
		var mid_gate := gates[i] as CSGBox3D
		var target := float(mid_gate.get_meta("slide_open_target_y", -1.0))
		if not is_instance_valid(mid_gate) or not mid_gate.use_collision \
				or not bool(mid_gate.get_meta("slide_open_animating", false)) \
				or mid_gate.position.y <= starts[i] + 0.05 or mid_gate.position.y >= target - 0.05:
			return false
	await _m.get_tree().create_timer(0.7).timeout
	for node in gates:
		if not is_instance_valid(node) or (node as Node3D).position.y < 5.25 \
				or (node as CSGBox3D).use_collision \
				or bool(node.get_meta("slide_open_animating", true)):
			return false
	# 门完全打开后，每支非玩家队伍的AI都应已经进入决策/移动状态，
	# 不能等待玩家碰撞或交互才被动唤醒。
	for bot in _m.grannies:
		if not is_instance_valid(bot) or not is_instance_valid(bot.cart):
			return false
		var start_pos: Vector3 = bot_cart_starts.get(bot.get_instance_id(), bot.cart.global_position)
		if bot.state == Granny.GState.IDLE \
				and bot.cart.global_position.distance_to(start_pos) < 0.03:
			return false
	return true

func _verify_curtain_physics() -> bool:
	var strips := _m.get_tree().get_nodes_in_group("freezer_curtain_strip")
	if strips.is_empty() or not (strips[0] is RigidBody3D):
		return false
	var strip := strips[0] as RigidBody3D
	if strip.freeze or strip.mass > 0.5 or strip.angular_damp < 3.0 \
			or strip.collision_layer != Catalog.L_CURTAIN \
			or strip.collision_mask != (Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART):
		return false
	var rest := strip.global_position
	strip.apply_impulse(Vector3(2.2, 0.0, 0.0), Vector3(0.0, -1.0, 0.0))
	await _m.get_tree().create_timer(0.4).timeout
	var pushed_distance := strip.global_position.distance_to(rest)
	await _m.get_tree().create_timer(2.4).timeout
	var returned_distance := strip.global_position.distance_to(rest)
	return pushed_distance > 0.08 and returned_distance < pushed_distance * 0.8

func _verify_region_effects(bounds: Dictionary) -> bool:
	if _m.region_director == null or not bounds.has("Frozen") or not bounds.has("Beauty"):
		return false
	var p: Player = _m.player
	var old_pos := p.global_position
	var frozen_rect: Rect2 = bounds["Frozen"]
	p.global_position = Vector3(frozen_rect.get_center().x, 0.1, frozen_rect.get_center().y)
	_m.region_director.tick(RegionDirector.FREEZE_FILL_TIME + 0.1)
	var cold_ok := p.cold_meter >= 0.99 and p.frozen_time >= 4.9
	# 用远程输入路径模拟客户端交替敲击A/D，验证主机权威挣扎同样能提前解冻。
	var old_remote := p.remote
	var old_net_move := p.net_move
	p.remote = true
	for i in 10:
		p.net_move = Vector2(-1.0 if i % 2 == 0 else 1.0, 0.0)
		p._tick_freeze_struggle()
		p.net_move = Vector2.ZERO
		p._tick_freeze_struggle()
	cold_ok = cold_ok and p.frozen_time <= 0.0 and p.cold_adapt_time >= 7.9
	p.remote = old_remote
	p.net_move = old_net_move
	var beauty_rect: Rect2 = bounds["Beauty"]
	var default_far := _m.cam_rig.camera.far
	p.global_position = Vector3(beauty_rect.get_center().x, 0.1, beauty_rect.get_center().y)
	p.obscure_time = 0.0
	_m.region_director.tick(0.1)
	for i in 16:
		_m.region_director.tick(0.1)
	var fog_volume := _m.find_child("BeautyVolumetricFog", true, false) as FogVolume
	var fog_material: FogMaterial = fog_volume.material as FogMaterial if fog_volume != null else null
	var beauty_ok := p.obscure_time <= 0.0 and fog_volume != null \
			and fog_material != null and fog_material.density >= 0.55 \
			and fog_material.albedo.r >= 0.99 and fog_material.albedo.g >= 0.8 \
			and fog_material.emission.r > 0.25 \
			and fog_volume.position.distance_to(Vector3(beauty_rect.get_center().x,
					2.9, beauty_rect.get_center().y)) < 0.05 \
			and Vector2(fog_volume.size.x, fog_volume.size.z).distance_to(beauty_rect.size) < 0.05 \
			and absf(_m.cam_rig.camera.far - default_far) < 0.1 \
			and _m.region_director._beauty_gradient_shells.size() >= 6 \
			and _m.region_director._beauty_gradient_shells.all(func(shell): return shell.visible)
	p.global_position = old_pos
	for i in 17:
		_m.region_director.tick(0.1)
	beauty_ok = beauty_ok and absf(_m.cam_rig.camera.far - default_far) < 0.1
	p.cold_meter = 0.0
	p.frozen_time = 0.0
	p.obscure_time = 0.0
	return cold_ok and beauty_ok

func _verify_region_npc_behaviors() -> bool:
	var kids := _m.get_tree().get_nodes_in_group("region_kids")
	var grannies := _m.get_tree().get_nodes_in_group("region_grannies")
	if kids.is_empty() or grannies.is_empty():
		return false
	var p: Player = _m.player
	var old_pos := p.global_position
	var kid := kids[0] as RegionNpc
	p.global_position = kid.global_position + Vector3(2.0, 0.0, 0.0)
	kid._mischief_timer = 0.0
	kid._missed_mischief_attempts = 3
	kid._tick_kid_intent(0.1)
	var rest_scale := kid._kid_base_scale
	kid._animate_kid_hop(0.1, Vector3.FORWARD)
	var kid_ok := is_instance_valid(kid._charge_target) and kid._charge_time > 0.0 \
			and RegionNpc.KID_CHARGE_CHANCE < 0.5 \
			and RegionNpc.KID_IMPACT_IMBALANCE >= 24.0 \
			and not kid.body_root.scale.is_equal_approx(rest_scale) \
			and absf(kid.body_root.rotation.z) > 0.001
	var live_hit_ok := false
	for it in _m.all_items:
		if not is_instance_valid(it) or not bool(it.get_meta("live_fresh_good", false)):
			continue
		p.global_position = it.global_position + Vector3(0.0, 0.0, 1.0)
		var first_hit := _m.region_director.try_hit_live_good(p, Vector3.FORWARD, 2.0)
		var second_hit := _m.region_director.try_hit_live_good(p, Vector3.FORWARD, 2.0)
		_m.region_director.tick(0.1)
		live_hit_ok = first_hit and second_hit and it.freeze \
				and bool(it.get_meta("live_stunned", false)) \
				and it.collision_layer == 0 and it.collision_mask == 0 \
				and is_instance_valid(it.visual_root) \
				and not it.visual_root.scale.is_equal_approx(Vector3.ONE)
		break
	var first_granny := grannies[0] as RegionNpc
	first_granny.add_imbalance(1.0, p)
	var aggro_ok := true
	for node in grannies:
		var granny := node as RegionNpc
		aggro_ok = aggro_ok and granny._aggro_target == p \
				and granny._aggro_time >= RegionNpc.GRANNY_AGGRO_TIME - 0.01
		granny._aggro_target = null
		granny._aggro_time = 0.0
	kid._charge_target = null
	p.global_position = old_pos
	return kid_ok and aggro_ok and live_hit_ok \
			and kid.max_imbalance_value() == RegionNpc.KID_MAX_IMBALANCE \
			and first_granny.max_imbalance_value() == RegionNpc.GRANNY_MAX_IMBALANCE

func _verify_vending_coupon() -> bool:
	var machine := _m.find_child("Vending_SE", true, false) as CSGBox3D
	if machine == null or _m.team_data.is_empty():
		return false
	var p: Player = _m.player
	var old_pos := p.global_position
	var direction := Vector3(0.0, 0.0, 1.0)
	p.global_position = machine.global_position - direction * 1.4
	_m.region_director._vending_hit_count[str(machine.name)] = 3
	_m.region_director._vending_prizes_left[str(machine.name)] = 1
	machine.set_meta("vending_next_hit_ms", 0)
	var before := (_m.team_data[p.team_id].get("vouchers", []) as Array).size()
	var hit := _m.region_director.try_hit_vending_machine(p, direction, 2.0)
	var vouchers: Array = _m.team_data[p.team_id].get("vouchers", [])
	var visual := _m.find_child("VendingHitFlash", true, false)
	p.global_position = old_pos
	if not hit or vouchers.size() != before + 1 or visual == null:
		return false
	var voucher: Dictionary = vouchers.back()
	var item_id := str(voucher.get("item_id", ""))
	if not Catalog.ITEMS.has(item_id):
		return false
	var price := Catalog.price_of(item_id)
	var base_saved := int(round(price * Catalog.discount_of(item_id)))
	var expected_extra := price - base_saved if str(voucher.get("kind", "")) == "free" \
			else int(round((price - base_saved) * 0.5))
	var redeemed := _m._redeem_vending_voucher(p.team_id, item_id, price, base_saved,
			machine.global_position)
	return redeemed == expected_extra \
			and (_m.team_data[p.team_id].get("vouchers", []) as Array).size() == before

func _team_spawns_centered_and_facing(gameplay: Dictionary) -> bool:
	var specs: Array = gameplay.get("team_spawn_specs", [])
	if specs.size() != 4:
		return false
	for tid in 4:
		var actors := _m.team_inventory_actors(tid)
		if actors.size() != 2:
			return false
		var center: Vector3 = (specs[tid] as Dictionary)["center"]
		var facing: Vector3 = (specs[tid] as Dictionary)["facing"]
		var mean := (actors[0].global_position + actors[1].global_position) * 0.5
		if mean.distance_to(center) > 0.35:
			return false
		for actor in actors:
			var actor_forward := -actor.body_root.global_transform.basis.z
			if actor_forward.dot(facing) < 0.97 or not is_instance_valid(actor.cart):
				return false
			var cart_forward := -actor.cart.global_transform.basis.z
			if cart_forward.dot(facing) < 0.97:
				return false
	return true

func _clearance_x(root: Node, left_name: String, right_name: String) -> float:
	var left := _find_box(root, left_name)
	var right := _find_box(root, right_name)
	if left == null or right == null:
		return -1.0
	return right.position.x - right.size.x * 0.5 \
			- (left.position.x + left.size.x * 0.5)

func _clearance_z(root: Node, north_name: String, south_name: String) -> float:
	var north := _find_box(root, north_name)
	var south := _find_box(root, south_name)
	if north == null or south == null:
		return -1.0
	return south.position.z - south.size.z * 0.5 \
			- (north.position.z + north.size.z * 0.5)

func _world_clearance_x(root: Node, left_name: String, right_name: String) -> float:
	var left := _find_box(root, left_name)
	var right := _find_box(root, right_name)
	if left == null or right == null:
		return -1.0
	var ltx := _world_transform(left)
	var rtx := _world_transform(right)
	var lh := (absf(ltx.basis.x.x) * left.size.x + absf(ltx.basis.z.x) * left.size.z) * 0.5
	var rh := (absf(rtx.basis.x.x) * right.size.x + absf(rtx.basis.z.x) * right.size.z) * 0.5
	return rtx.origin.x - rh - (ltx.origin.x + lh)

func _art_asset_import_ready() -> bool:
	var baked_root := _m.find_child("BakedArtAssets", true, false) as Node3D
	var reference_root := _m.find_child("ImportedAssetPrefabs", true, false) as Node3D
	var cargo_root := _m.find_child("ShelfTopSightBlockers", true, false) as Node3D
	if baked_root == null or reference_root == null or cargo_root == null \
			or _m.find_child("ArtAssetInstaller", true, false) != null:
		return false
	var shelf_holders := 0
	var light_holders := 0
	var uniform_tiling_ok := true
	var cold_case_3_used := false
	var led_textured := false
	var textured_fixture_kinds := {}
	for node in _m.get_tree().get_nodes_in_group("installed_art_fixture"):
		if not (node is Node3D) or not baked_root.is_ancestor_of(node):
			continue
		var holder := node as Node3D
		var kind := str(holder.get_meta("fixture_kind", ""))
		var fixture_mesh := ArtAssetFitter.first_mesh(holder)
		if fixture_mesh != null and fixture_mesh.mesh != null:
			for surface in fixture_mesh.mesh.get_surface_count():
				var fixture_mat := fixture_mesh.get_active_material(surface) as StandardMaterial3D
				if fixture_mat != null and fixture_mat.albedo_texture != null:
					textured_fixture_kinds[kind] = true
		if kind == "led_tube":
			light_holders += 1
			var led_mesh := ArtAssetFitter.first_mesh(holder)
			if led_mesh != null and led_mesh.mesh != null \
					and led_mesh.mesh.get_surface_count() > 0:
				var led_mat := led_mesh.get_active_material(0) as StandardMaterial3D
				led_textured = led_textured or (led_mat != null \
						and led_mat.albedo_texture != null and led_mat.normal_texture != null)
		else:
			shelf_holders += 1
			cold_case_3_used = cold_case_3_used or kind == "cold_case_3"
		uniform_tiling_ok = uniform_tiling_ok \
				and holder.has_meta("art_uniform_scale") \
				and bool(holder.get_meta("art_no_axis_deform", false)) \
				and int(holder.get_meta("art_module_count", 0)) == holder.get_child_count()

	var available_ids := ArtAssetCatalog.available_item_ids()
	var instantiated := {}
	var textured_ids := {}
	for it in _m.all_items:
		if not is_instance_valid(it) or it.item_id not in available_ids \
				or not is_instance_valid(it.visual_root):
			continue
		if str(it.visual_root.get_meta("art_item_id", "")) != it.item_id:
			continue
		instantiated[it.item_id] = true
		for mesh in ArtAssetFitter.mesh_instances(it.visual_root):
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(surface) as StandardMaterial3D
				if mat != null and mat.albedo_texture != null:
					textured_ids[it.item_id] = true
	var missing_textures: Array[String] = []
	for item_id in available_ids:
		if not textured_ids.has(item_id):
			missing_textures.append(item_id)
	var prefab_files_ok := ResourceLoader.exists("res://scenes/Art_Asset_Library.tscn")
	for kind in ArtAssetCatalog.fixture_kinds():
		prefab_files_ok = prefab_files_ok and ArtAssetCatalog.fixture_prefab_path(kind) != ""
	var gameplay_source_paths := {}
	for item_id in ArtAssetCatalog.source_item_ids():
		gameplay_source_paths[ArtAssetCatalog.item_source_model_path(item_id)] = true
	for kind in ArtAssetCatalog.fixture_kinds():
		gameplay_source_paths[ArtAssetCatalog.fixture_source_model_path(kind)] = true
	var other_prefab_count := 0
	for source_path in ArtAssetCatalog.all_source_model_paths():
		if not gameplay_source_paths.has(source_path) \
				and ResourceLoader.exists(ArtAssetCatalog.library_prefab_path(source_path)):
			other_prefab_count += 1
	var expected_item_count := ArtAssetCatalog.source_item_ids().size()
	var expected_source_count := ArtAssetCatalog.all_source_model_paths().size()
	var expected_other_count := expected_source_count - expected_item_count \
			- ArtAssetCatalog.fixture_kinds().size()
	prefab_files_ok = prefab_files_ok and other_prefab_count == expected_other_count
	prefab_files_ok = prefab_files_ok and reference_root.get_child_count() == expected_source_count \
			and cargo_root.get_child_count() >= 200 \
			and cargo_root.get_children().all(func(node):
				return node is CSGBox3D and node.is_in_group("shelf_top_cargo") \
						and str(node.get_meta("cargo_kind", "")) == "light_gray") \
			and _cargo_clear_of_hanging_signs(cargo_root)
	_notes.append("  INFO 美术prefab：货架/冰柜=%d，灯管=%d，商品模型=%d/%d，带颜色贴图=%d/%d，总览场景=%s，缺贴图=%s" % [
			shelf_holders, light_holders, instantiated.size(), expected_item_count,
			textured_ids.size(), expected_item_count,
			str(prefab_files_ok), str(missing_textures)])
	return shelf_holders == 33 and light_holders >= 30 and uniform_tiling_ok \
			and not cold_case_3_used and prefab_files_ok \
			and textured_fixture_kinds.has("upright_shelf") \
			and textured_fixture_kinds.has("cold_case_1") \
			and textured_fixture_kinds.has("cold_case_2") \
			and textured_fixture_kinds.has("led_tube") \
			and led_textured and available_ids.size() == expected_item_count \
			and instantiated.size() == expected_item_count \
			and textured_ids.size() == expected_item_count

func _cargo_clear_of_hanging_signs(cargo_root: Node3D) -> bool:
	var sign_rects: Array[Rect2] = []
	for node in _m.get_tree().get_nodes_in_group("zone_hanging_sign"):
		if not (node is CSGBox3D):
			continue
		var sign := node as CSGBox3D
		var tx := _world_transform(sign)
		var half_x := (absf(tx.basis.x.x) * sign.size.x \
				+ absf(tx.basis.z.x) * sign.size.z) * 0.5
		var half_z := (absf(tx.basis.x.z) * sign.size.x \
				+ absf(tx.basis.z.z) * sign.size.z) * 0.5
		sign_rects.append(Rect2(tx.origin.x - half_x, tx.origin.z - half_z,
				half_x * 2.0, half_z * 2.0))
	for node in cargo_root.get_children():
		if not (node is CSGBox3D):
			return false
		var cargo := node as CSGBox3D
		var tx := _world_transform(cargo)
		var half_x := (absf(tx.basis.x.x) * cargo.size.x \
				+ absf(tx.basis.z.x) * cargo.size.z) * 0.5
		var half_z := (absf(tx.basis.x.z) * cargo.size.x \
				+ absf(tx.basis.z.z) * cargo.size.z) * 0.5
		var cargo_rect := Rect2(tx.origin.x - half_x, tx.origin.z - half_z,
				half_x * 2.0, half_z * 2.0)
		for sign_rect in sign_rects:
			if cargo_rect.intersects(sign_rect):
				return false
	return true

func _check(ok: bool, msg: String) -> void:
	_notes.append("  %s %s" % [("OK  " if ok else "FAIL"), msg])
	if not ok:
		_fails.append(msg)

func _report() -> void:
	for line in _notes:
		print("[level]", line)
	print("[level] RESULT=%s assertions=%d" % [
			"PASS" if _fails.is_empty() else "FAIL", _notes.size()])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
