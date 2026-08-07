class_name ListRows
## HUD 购物清单的行数据生成:按超市分区分组,已入车/已结算标绿划线。
## 参数 m 是 Main(此处不写类型注解,避免与 Main 形成 class_name 循环引用)。

## 分区显示顺序:爆款专区置顶
const ZONE_ORDER := [
	Catalog.ZONE_PREMIUM,
	Catalog.ZONE_FRESH,
	Catalog.ZONE_APPLIANCE,
	Catalog.ZONE_DAILY,
	Catalog.ZONE_SNACK,
]

static func build(m, idx: int) -> Array:
	var p: Player = m.players[idx]
	var list: Array = m.pdata[idx]["list"]
	var cart_ids := {}
	if is_instance_valid(p.cart):
		for it in p.cart.items_in_basket():
			cart_ids[it.item_id] = true
	var rows: Array = []
	for zone in ZONE_ORDER:
		var group: Array = []
		for entry in list:
			if Catalog.ITEMS[entry["id"]]["zone"] == zone:
				group.append(entry)
		if group.is_empty():
			continue
		rows.append({
			"header": true,
			"text": "【%s】" % Catalog.ZONE_NAMES[zone],
			"color": Catalog.ZONE_COLORS[zone],
		})
		for entry in group:
			rows.append(_row(m, entry, p, cart_ids))
	return rows

static func _row(m, entry: Dictionary, p: Player, cart_ids: Dictionary) -> Dictionary:
	var done: bool = entry["scanned"]
	var status: String
	if done:
		status = "已结算✓" + ("(特价抵扣)" if entry["via_sale"] else "")
	else:
		status = whereabouts(m, entry["id"], p)
	var cat_tag: String = "必需" if entry["cat"] == Catalog.CAT_NEED \
			else ("大件" if entry["cat"] == Catalog.CAT_LARGE else "常规")
	return {
		"text": "  · %s [%s] — %s" % [entry["name"], cat_tag, status],
		"green": done or cart_ids.has(entry["id"]),
	}

## 这件商品现在在哪:手中 > 车内 > 货架剩N件 > 库存告急
static func whereabouts(m, id: String, p: Player) -> String:
	var shelf_left := 0
	for it in m.all_items:
		if not is_instance_valid(it) or it.item_id != id:
			continue
		if p.held.has(it):
			return "手中"
		if it.state == Item.ItemState.FREE and is_instance_valid(p.cart) \
				and p.cart.basket_area.overlaps_body(it):
			return "车内"
		if it.state == Item.ItemState.SHELVED:
			shelf_left += 1
	if shelf_left > 0:
		return "货架剩%d件" % shelf_left
	return "场上库存告急!"
