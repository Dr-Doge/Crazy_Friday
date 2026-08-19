class_name ResultReport
## 出货结算文案生成:纯数据 → 字符串数组,不碰节点,便于单测与改文案。
##
##玩家是投机者:清单不是"自己要买的东西",而是"客户下的代购单"。
## 局内以黑五折扣价低价买入,带出局后高价出手,赚的是差价(局外结算见《01·三》)。
## 输入的 pdata 结构见 Main.pdata:{list, score, counts, orig, saved, settled, done}

const CAT_NAMES := {
	Catalog.CAT_NEED: "硬需求单",
	Catalog.CAT_NORMAL: "常规单",
	Catalog.CAT_LARGE: "大件单",
	Catalog.CAT_SALE: "特价捡漏",
}

## idx:本次结算的玩家下标 · settled:true=过闸机结算,false=打烊硬结算
## names:各座位昵称(联机排名用),空则回落到"玩家N"
static func build(pdata: Array, idx: int, settled: bool, net_mp: bool, names: Array = []) -> Array:
	var pd: Dictionary = pdata[idx]
	var done := OrderSystem.delivered_total(pd["list"])
	var required := OrderSystem.required_total(pd["list"])
	var lines: Array = []
	lines.append("💰 出货结算!" if settled else "💰 打烊清算")
	lines.append("")
	lines.append("到手货值:%d" % pd["score"])
	if net_mp and pdata.size() > 1:
		lines.append_array(_ranking(pdata, idx, names))
	lines.append("代购单交付:%d / %d" % [done, required])
	for entry in pd["list"]:
		var delivered := OrderSystem.delivered(entry)
		var mark := "✓" if OrderSystem.is_complete(entry) else ("△" if delivered > 0 else "✗")
		if OrderSystem.is_category(entry):
			var goods: Array[String] = []
			for id in entry.get("fulfilled_ids", []):
				goods.append("特价箱" if id == "sale_box" else str(Catalog.ITEMS[id]["name"]))
			var detail := "（%s）" % "、".join(goods) if not goods.is_empty() else ""
			lines.append("  %s %s %d/%d%s" % [mark, entry["name"], delivered,
					OrderSystem.required(entry), detail])
		else:
			lines.append("  %s %s%s" % [mark, entry["name"], "(特价顶单)" if entry.get("via_sale", false) else ""])
	for cat in pd["counts"]:
		lines.append("%s ×%d" % [CAT_NAMES.get(cat, cat), pd["counts"][cat]])
	lines.append("")
	lines.append("客户报价合计:¥%d · 你的黑五进货价:¥%d" % [pd["orig"], pd["orig"] - pd["saved"]])
	lines.append("低价扫进,加价倒出——本趟净赚差价 ¥%d !" % pd["saved"])
	lines.append("")
	lines.append(_verdict(pd, done, required, settled))
	lines.append("")
	lines.append("按 回车 " + ("断开并返回开始界面" if net_mp else "再跑一趟"))
	return lines

## 全场排名(以此刻到手货值排序)
static func _ranking(pdata: Array, idx: int, names: Array) -> Array:
	var ranking: Array = []
	for i in pdata.size():
		ranking.append([pdata[i]["score"], i])
	ranking.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var lines: Array = ["— 本趟同行排名 —"]
	for r in ranking.size():
		var seat: int = ranking[r][1]
		var who: String = str(names[seat]) if seat < names.size() else "玩家%d" % (seat + 1)
		if seat == idx:
			who = "%s(你)" % who
		lines.append("  第%d名 %s:%d" % [r + 1, who, ranking[r][0]])
	return lines

## 结语:四象限(是否过闸机 × 代购单是否全清)
static func _verdict(pd: Dictionary, done: int, required: int, settled: bool) -> String:
	var all_done: bool = done == required
	if settled and all_done:
		return "整单交付,赶在打烊前扬长而去——这一行你算是入门了。"
	if settled:
		return "落袋为安。没凑齐的那几单,自己跟客户解释去吧。"
	if all_done:
		return "货是齐了,可你没能出手——卡在店里的存货,一分不值。"
	if pd["score"] > 0:
		return "勉强回本。下次早点来蹲门口。"
	return "……空手而归。未过闸机的货全部作废,客户已在群里点你名了。"
