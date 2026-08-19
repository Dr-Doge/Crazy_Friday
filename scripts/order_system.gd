class_name OrderSystem
## 混合代购订单的纯数据规则。
## 正式对局使用“点名爆款 + 分区类别计数”，教学固定订单仍兼容旧的点名条目结构。

const KIND_EXACT := "exact"
const KIND_CATEGORY := "category"

static func exact(id: String) -> Dictionary:
	return exact_count(id, 1)

static func exact_count(id: String, required: int) -> Dictionary:
	return {
		"kind": KIND_EXACT,
		"id": id,
		"name": Catalog.ITEMS[id]["name"],
		"cat": Catalog.ITEMS[id]["cat"],
		"zone": Catalog.ITEMS[id]["zone"],
		"required": maxi(required, 1),
		"delivered": 0,
		"fulfilled_ids": [],
		"scanned": false,
		"via_sale": false,
		"via_sale_count": 0,
	}

static func category(zone: String, required: int) -> Dictionary:
	return {
		"kind": KIND_CATEGORY,
		"id": "zone:" + zone,
		"name": "%s任选" % Catalog.ZONE_NAMES[zone],
		"cat": KIND_CATEGORY,
		"zone": zone,
		"required": maxi(required, 1),
		"delivered": 0,
		"fulfilled_ids": [],
		"scanned": false,
		"via_sale": false,
		"via_sale_count": 0,
	}

static func kind(entry: Dictionary) -> String:
	return str(entry.get("kind", KIND_EXACT))

static func is_category(entry: Dictionary) -> bool:
	return kind(entry) == KIND_CATEGORY

static func zone(entry: Dictionary) -> String:
	if entry.has("zone"):
		return str(entry["zone"])
	var id := str(entry.get("id", ""))
	return str(Catalog.ITEMS[id]["zone"]) if Catalog.ITEMS.has(id) else ""

static func required(entry: Dictionary) -> int:
	return maxi(int(entry.get("required", 1)), 1)

static func delivered(entry: Dictionary) -> int:
	if entry.has("delivered"):
		return clampi(int(entry["delivered"]), 0, required(entry))
	return 1 if bool(entry.get("scanned", false)) else 0

static func is_complete(entry: Dictionary) -> bool:
	return delivered(entry) >= required(entry)

static func candidate_ids(entry: Dictionary) -> Array[String]:
	if not is_category(entry):
		var exact_id := str(entry.get("id", ""))
		return [exact_id] if Catalog.ITEMS.has(exact_id) else []
	var out: Array[String] = []
	var wanted_zone := zone(entry)
	for id in Catalog.ITEMS:
		if Catalog.ITEMS[id]["zone"] == wanted_zone \
				and Catalog.ITEMS[id]["cat"] != Catalog.CAT_SALE:
			out.append(id)
	return out

static func matches(entry: Dictionary, item_id: String) -> bool:
	if not Catalog.ITEMS.has(item_id) or Catalog.ITEMS[item_id]["cat"] == Catalog.CAT_SALE:
		return false
	if is_category(entry):
		return Catalog.ITEMS[item_id]["zone"] == zone(entry)
	return str(entry.get("id", "")) == item_id

## 一件正常商品最多完成一个订单单位。优先满足点名项目，再满足类别项目。
static func fulfill_item(list: Array, item_id: String) -> bool:
	for entry in list:
		if not is_category(entry) and not is_complete(entry) and matches(entry, item_id):
			_add_delivery(entry, item_id, false)
			return true
	for entry in list:
		if is_category(entry) and not is_complete(entry) and matches(entry, item_id):
			_add_delivery(entry, item_id, false)
			return true
	return false

## 特价箱只顶替一个尚缺的类别单位，不能跳过点名爆款。
static func fulfill_sale(list: Array) -> bool:
	var best: Dictionary = {}
	var best_remaining := 0
	for entry in list:
		if not is_category(entry) or is_complete(entry):
			continue
		var remaining := required(entry) - delivered(entry)
		if remaining > best_remaining:
			best = entry
			best_remaining = remaining
	if best.is_empty():
		return false
	_add_delivery(best, "sale_box", true)
	return true

static func _add_delivery(entry: Dictionary, item_id: String, via_sale: bool) -> void:
	var next := mini(delivered(entry) + 1, required(entry))
	entry["delivered"] = next
	entry["scanned"] = next >= required(entry)
	var ids: Array = entry.get("fulfilled_ids", [])
	ids.append(item_id)
	entry["fulfilled_ids"] = ids
	if via_sale:
		entry["via_sale"] = true
		entry["via_sale_count"] = int(entry.get("via_sale_count", 0)) + 1

static func required_total(list: Array) -> int:
	var total := 0
	for entry in list:
		total += required(entry)
	return total

static func delivered_total(list: Array) -> int:
	var total := 0
	for entry in list:
		total += delivered(entry)
	return total
