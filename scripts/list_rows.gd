class_name ListRows
## HUD 代购清单的行数据生成:按超市分区分组,已入车/已交付标绿划线。
## 参数 m 是 Main(此处不写类型注解,避免与 Main 形成 class_name 循环引用)。

## 分区显示顺序:爆款专区置顶
const ZONE_ORDER := [
	Catalog.ZONE_PREMIUM,
	Catalog.ZONE_FRESH,
	Catalog.ZONE_FROZEN,
	Catalog.ZONE_SNACK,
	Catalog.ZONE_TOY,
	Catalog.ZONE_APPLIANCE,
	Catalog.ZONE_DAILY,
	Catalog.ZONE_BEAUTY,
	Catalog.ZONE_CLOTHING,
]

static func build(m, idx: int) -> Array:
	var p: Player = m.players[idx]
	var actors: Array = m.team_inventory_actors(p.team_id)
	var list: Array = m.pdata[idx]["list"]
	var rows: Array = []
	for zone in ZONE_ORDER:
		var group: Array = []
		for entry in list:
			if OrderSystem.zone(entry) == zone:
				group.append(entry)
		if group.is_empty():
			continue
		rows.append({
			"header": true,
			"text": "【%s】" % Catalog.ZONE_NAMES[zone],
			"color": Catalog.ZONE_COLORS[zone],
		})
		for entry in group:
			rows.append(_row(m, entry, p, actors))
	return rows

static func _row(m, entry: Dictionary, p: Player, actors: Array) -> Dictionary:
	var done := OrderSystem.is_complete(entry)
	var owned := _owned_counts(actors, entry)
	var status: String
	if done:
		status = "已结算✓" + _sale_suffix(entry)
	elif OrderSystem.is_category(entry):
		var delivered := OrderSystem.delivered(entry)
		var required := OrderSystem.required(entry)
		var pending: int = owned["hand"] + owned["cart"]
		status = "已交付%d/%d" % [delivered, required]
		if owned["hand"] > 0:
			status += " · 手中%d" % owned["hand"]
		if owned["cart"] > 0:
			status += " · 车内%d" % owned["cart"]
		status += " · 还需%d" % maxi(required - delivered - pending, 0)
	else:
		status = whereabouts(m, entry["id"], p, actors)
	var cat_tag: String
	var label: String
	if OrderSystem.is_category(entry):
		cat_tag = "类别×%d" % OrderSystem.required(entry)
		label = "本区任意商品"
	else:
		cat_tag = "必买" if entry["cat"] == Catalog.CAT_NEED \
				else ("大件" if entry["cat"] == Catalog.CAT_LARGE else "指定")
		label = entry["name"]
	return {
		"text": "  · %s [%s] — %s" % [label, cat_tag, status],
		"green": done or OrderSystem.delivered(entry) + owned["hand"] + owned["cart"] \
				>= OrderSystem.required(entry),
	}

static func _owned_counts(actors: Array, entry: Dictionary) -> Dictionary:
	var hand := 0
	var cart := 0
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		for it in actor.held:
			if is_instance_valid(it) and OrderSystem.matches(entry, it.item_id):
				hand += 1
		if is_instance_valid(actor.cart):
			for it in actor.cart.items_in_basket():
				if is_instance_valid(it) and OrderSystem.matches(entry, it.item_id):
					cart += 1
	return {"hand": hand, "cart": cart}

static func _sale_suffix(entry: Dictionary) -> String:
	var count := int(entry.get("via_sale_count", 1 if entry.get("via_sale", false) else 0))
	return "(特价抵扣×%d)" % count if count > 0 else ""

## 这件商品现在在哪:手中 > 车内 > 货架剩N件 > 库存告急
static func whereabouts(m, id: String, p: Player, actors: Array) -> String:
	var shelf_left := 0
	for it in m.all_items:
		if not is_instance_valid(it) or it.item_id != id:
			continue
		for actor in actors:
			if not is_instance_valid(actor):
				continue
			if actor.held.has(it):
				return "手中" if actor == p else "队友手中"
			if it.state == Item.ItemState.FREE and is_instance_valid(actor.cart) \
					and actor.cart.basket_area.overlaps_body(it):
				return "车内" if actor == p else "队友车内"
		if it.state == Item.ItemState.SHELVED:
			shelf_left += 1
	if shelf_left > 0:
		return "货架剩%d件" % shelf_left
	return "场上库存告急!"
