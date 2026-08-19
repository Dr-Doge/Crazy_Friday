class_name OrderProbe extends RefCounted
## 混合订单专项回归：结构、类别计数、Q候选、结算匹配、特价替代与HUD。

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
	var exacts: Array = list.filter(func(e): return not OrderSystem.is_category(e))
	var categories: Array = list.filter(func(e): return OrderSystem.is_category(e))
	_check(exacts.size() == 2 and categories.size() == 4,
			"订单结构：2条明确指定商品 + 4条分区类别计数")
	_check(OrderSystem.required_total(list) == 12,
			"订单总量：开局共享单要求12件商品，中央压轴开放后再按实存追加")
	var category_units := 0
	var zones := {}
	for entry in categories:
		category_units += OrderSystem.required(entry)
		zones[OrderSystem.zone(entry)] = true
	_check(category_units == 10 and zones.size() == 4,
			"类别结构：从八个独立常规专区错位选四区，按3+3+2+2分配十件")
	var exact_normal := true
	for entry in exacts:
		exact_normal = exact_normal and entry["cat"] == Catalog.CAT_NORMAL
	_check(exact_normal, "点名项目：开局保留少量明确SKU制造交叉竞争")
	_check(_m.team_data.size() == 4 and _m.team_bots.size() == 7 \
			and _m.pdata[0]["list"] == _m.team_data[_m.player.team_id]["list"],
			"四队框架：单人测试空缺的7个席位由AI补齐，真人使用队伍共享订单")

	var count_two: Dictionary = {}
	for entry in categories:
		if OrderSystem.required(entry) == 2:
			count_two = entry
			break
	var candidates := OrderSystem.candidate_ids(count_two)
	_check(candidates.size() >= 2, "类别候选：同一订单允许多种商品完成")
	var usable: Array[String] = []
	for id in candidates:
		var is_exact := exacts.any(func(e): return str(e["id"]) == id)
		if Catalog.ITEMS[id]["cat"] == Catalog.CAT_NORMAL and not is_exact:
			usable.append(id)
		if usable.size() >= 2:
			break
	var held_items: Array[Item] = []
	for id in usable:
		var it := Item.create(id)
		_m.add_child(it)
		_m.all_items.append(it)
		_m.player.take_item(it)
		held_items.append(it)
	var missing_with_two := _m.missing_list_ids(0)
	var category_still_missing := false
	for id in candidates:
		var is_exact := exacts.any(func(e): return str(e["id"]) == id)
		if not is_exact:
			category_still_missing = category_still_missing or missing_with_two.has(id)
	_check(_m._owned_matching_count(_m.player, count_two) == 2 and not category_still_missing,
			"Q雷达：队伍库存达到类别要求后，不再泛亮该区非点名候选")
	_m.player.drop_all_held(false)
	var recommendations := _m._locate_recommendations(0)
	var category_recommendations := 0
	var recommended_ids := {}
	for item_index in recommendations:
		var recommended: Item = _m.all_items[item_index]
		if OrderSystem.matches(count_two, recommended.item_id):
			category_recommendations += 1
			recommended_ids[recommended.item_id] = true
	_check(category_recommendations > 0 \
			and recommended_ids.size() >= mini(2, category_recommendations),
			"Q雷达：类别单优先展示不同SKU，明确点名则保留全部真实库存高亮")

	for id in usable:
		var scanned := Item.create(id)
		_m.add_child(scanned)
		_m._on_item_scanned(scanned, _m.player)
	_check(OrderSystem.is_complete(count_two) and OrderSystem.delivered(count_two) == 2,
			"收银匹配：不同商品可累计完成同一类别计数")

	var exact := exacts[0] as Dictionary
	var wrong_need := ""
	for id in Catalog.ids_of_cat(Catalog.CAT_NEED):
		if id != exact["id"]:
			wrong_need = id
			break
	var wrong := Item.create(wrong_need)
	_m.add_child(wrong)
	_m._on_item_scanned(wrong, _m.player)
	_check(not OrderSystem.is_complete(exact),
			"点名项目：同为爆款的其他商品不能顶替指定商品")

	var before_sale := 0
	for entry in categories:
		before_sale += OrderSystem.delivered(entry)
	var sale := Item.create("sale_box")
	_m.add_child(sale)
	_m._on_item_scanned(sale, _m.player)
	var after_sale := 0
	for entry in categories:
		after_sale += OrderSystem.delivered(entry)
	_check(after_sale == before_sale + 1 \
			and not OrderSystem.is_complete(exact),
			"特价箱：只顶替一个类别单位，不跳过点名爆款")

	var rows := _m._build_rows(0)
	var has_category_progress := false
	for row in rows:
		if not row.get("header", false) and "类别×" in str(row.get("text", "")) \
				and "已交付" in str(row.get("text", "")):
			has_category_progress = true
			break
	_check(has_category_progress, "HUD：类别订单显示需求数量与交付进度")
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
