class_name OrderProbe extends RefCounted
## 队伍点名订单专项回归：25件/四专区结构、共享引用、库存可完成性与折叠UI。

var _m: Main
var _fails: Array[String] = []
var _notes: Array[String] = []

func _init(m: Main) -> void:
	_m = m

func setup() -> void:
	var expected_names := ["Half foods牛油果", "Trader John牧场鸡蛋", "CostCow热狗",
			"小小泡泡糖", "地球人电解质饮料", "GTA7游戏实体光盘",
			"Pocketmon集换卡", "LOGO拼装玩具", "碧芭娃娃", "榴莲手机"]
	var actual_names: Array = Catalog.ITEMS.values().map(func(info): return str(info["name"]))
	_check(expected_names.all(func(display_name): return actual_names.has(display_name)),
			"商品目录：本轮改名、新玩具与黑五榴莲手机已全部进入数据源")
	_check(Catalog.ITEMS.size() == 72 and Catalog.ITEMS.has("five_dudes_burger") \
			and Catalog.ITEMS.has("route67_lube") and Catalog.ITEMS.has("tongtongsahu") \
			and not Catalog.ITEMS.has("tv") and not Catalog.ITEMS.has("npc_stream_button") \
			and Catalog.ITEMS.values().all(func(info): return int(info.get("tier", 0)) in [1, 2, 3]),
			"商品扩充：71种可采购SKU＋特价箱全部归区分级，删除项未残留")
	var complete_catalog := true
	for id in Catalog.ITEMS:
		var info: Dictionary = Catalog.ITEMS[id]
		complete_catalog = complete_catalog and info.has("name") and info.has("cat") \
				and info.has("zone") and info.has("tier") and info.has("stock") \
				and info.has("size") and info.has("color") and info.has("price") \
				and info.has("disc") and Catalog.THROW_IMBALANCE.has(id) \
				and Catalog.THROW_EFFECT.has(id)
	_check(complete_catalog,
			"商品数据：每个SKU均有专区、三级、尺寸、价格、折扣、失衡和投掷映射")
	_check(Catalog.is_fragile("microwave") and Catalog.is_fragile("treadmill") \
			and not Catalog.is_fragile("cola"),
			"分区特性：家电区普通与大件商品均标记易碎，其他分区不误伤")
	var list: Array = _m.pdata[0]["list"]
	_check(not list.is_empty() and list.all(func(e): return not OrderSystem.is_category(e)),
			"订单结构：正式局只包含指定商品名称，不再生成类别任选项目")
	_check(OrderSystem.required_total(list) == Main.TEAM_ORDER_TOTAL,
			"订单总量：每队共享单从真实上架库存随机抽取固定25件，允许同品重复")
	var all_teams_valid := _m.team_data.size() == 4
	var zone_sets: Array = []
	for team_id in _m.team_data.size():
		var team: Dictionary = _m.team_data[team_id]
		var team_list: Array = team["list"]
		var order_zones: Array = team.get("order_zones", [])
		var actual_zones := {}
		for entry in team_list:
			actual_zones[OrderSystem.zone(entry)] = true
		zone_sets.append(actual_zones.keys())
		all_teams_valid = all_teams_valid and OrderSystem.required_total(team_list) == 25 \
				and team_list.all(func(e): return not OrderSystem.is_category(e)) \
				and order_zones.size() == 4 and actual_zones.size() == 4 \
				and order_zones.has(Main.TEAM_ENTRY_ORDER_ZONES[team_id])
	_check(all_teams_valid,
			"四队订单：每队25件只来自4个专区，且保底包含本队入口首区")
	var overlap_valid := true
	for team_id in 4:
		var overlap_count := 0
		for zone in zone_sets[team_id]:
			for other_id in 4:
				if other_id != team_id and (zone_sets[other_id] as Array).has(zone):
					overlap_count += 1
					break
		overlap_valid = overlap_valid and overlap_count >= 2
	_check(overlap_valid, "专区竞争：每队至少有2个订单专区与其他队重合")
	_check(_m.team_bots.size() == 7 and is_same(_m.pdata[0]["list"],
			_m.team_data[_m.player.team_id]["list"]),
			"队内共享：真人与AI队友读取同一份订单对象和实时交付进度")
	var bot_split_valid := true
	for team_id in 4:
		var slot_zero := _m._team_bot_targets(team_id, 0)
		var slot_one := _m._team_bot_targets(team_id, 1)
		var combined := slot_zero + slot_one
		bot_split_valid = bot_split_valid and combined.size() == Main.TEAM_ORDER_TOTAL
		for entry in _m.team_data[team_id]["list"]:
			bot_split_valid = bot_split_valid \
					and combined.count(str(entry["id"])) == OrderSystem.required(entry)
	_check(bot_split_valid,
			"AI协作：同一商品的多件需求按队内两个席位拆分，合计覆盖完整25件")
	var checkout_slots: Array = _m.team_data[0].get("checkout_ready_slots", [])
	var first_waits := not _m._mark_team_checkout_ready(0, 0)
	var second_finishes := _m._mark_team_checkout_ready(0, 1)
	_check(checkout_slots.size() == 2 and first_waits and second_finishes,
			"队伍结算：首名队员只登记等待，两个席位都进入收银台后才完成")
	_m.team_data[0]["checkout_ready_slots"] = [false, false]

	var shelf_stock := {}
	for item in _m.all_items:
		if is_instance_valid(item) and item.state == Item.ItemState.SHELVED:
			shelf_stock[item.item_id] = int(shelf_stock.get(item.item_id, 0)) + 1
	var globally_required := {}
	for team in _m.team_data:
		for entry in team["list"]:
			var id := str(entry["id"])
			globally_required[id] = int(globally_required.get(id, 0)) + OrderSystem.required(entry)
	var stock_safe := true
	for id in globally_required:
		stock_safe = stock_safe and int(globally_required[id]) <= int(shelf_stock.get(id, 0))
	_check(stock_safe, "库存校验：四队全部100件需求合计不超过本局真实上架库存")

	var exact := list[0] as Dictionary
	var missing := _m.missing_list_ids(0)
	var recommendations := _m._locate_recommendations(0)
	var q_found_exact := recommendations.any(func(item_index: int) -> bool:
		return _m.all_items[item_index].item_id == str(exact["id"]))
	_check(missing.has(str(exact["id"])) and q_found_exact,
			"Q雷达：缺货集合与高亮候选都直接指向清单上的指定SKU")

	var ordered_ids := list.map(func(e): return str(e["id"]))
	var wrong_id := ""
	for id in Catalog.ITEMS:
		if id != "sale_box" and not ordered_ids.has(id):
			wrong_id = id
			break
	var target_before := OrderSystem.delivered(exact)
	var wrong := Item.create(wrong_id)
	_m.add_child(wrong)
	_m._on_item_scanned(wrong, _m.player)
	_check(OrderSystem.delivered(exact) == target_before,
			"点名匹配：任何其他商品都不能顶替当前指定SKU")
	for i in OrderSystem.required(exact):
		var scanned := Item.create(str(exact["id"]))
		_m.add_child(scanned)
		_m._on_item_scanned(scanned, _m.player)
	_check(OrderSystem.is_complete(exact), "共享结算：同名商品按数量累计直至该行完成")

	var before_sale := OrderSystem.delivered_total(list)
	var sale := Item.create("sale_box")
	_m.add_child(sale)
	_m._on_item_scanned(sale, _m.player)
	_check(OrderSystem.delivered_total(list) == before_sale,
			"点名订单：特价箱和非清单货只能计价，不能替代指定需求")

	var rows := _m._build_rows(0)
	var has_named_progress := false
	for row in rows:
		if not row.get("header", false) and str(exact["name"]) in str(row.get("text", "")):
			has_named_progress = true
			break
	_check(has_named_progress, "HUD：共享清单逐行显示指定商品名称和数量进度")
	var compact_rows := ListRows.present(rows, "", false)
	var player_team := int(_m.pdata[0].get("team_id", 0))
	var current_zone := str((_m.team_data[player_team]["order_zones"] as Array)[0])
	var local_rows := ListRows.present(rows, current_zone, false)
	var expanded_rows := ListRows.present(rows, "", true)
	_check(compact_rows.size() == 4 \
			and compact_rows.all(func(row): return row.get("header", false) \
					and row.get("collapsed", false) and "仍需" in str(row.get("text", ""))) \
			and local_rows.size() > compact_rows.size() and local_rows.size() < expanded_rows.size(),
			"HUD折叠：仅脚下专区展开，其余三区压缩为专区名与剩余需求件数")
	_check(expanded_rows.size() == rows.size() and InputMap.has_action("show_orders"),
			"Tab总览：按住Tab时恢复全部专区订单明细，松开后可重新折叠")
	_check(ListRows.is_cart_secured(false, {"hand": 0, "cart": 1}) \
			and not ListRows.is_cart_secured(false, {"hand": 2, "cart": 0}),
			"HUD勾选：队内任意购物车出现1件需求品即打勾划线，单纯手持不触发")
	_m.get_tree().create_timer(0.15).timeout.connect(_report)

func _check(ok: bool, msg: String) -> void:
	_notes.append("  %s %s" % [("OK  " if ok else "FAIL"), msg])
	if not ok:
		_fails.append(msg)

func _report() -> void:
	for line in _notes:
		print("[order]", line)
	print("[order] RESULT=%s assertions=%d" % [
			"PASS" if _fails.is_empty() else "FAIL", _notes.size()])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
