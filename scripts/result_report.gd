class_name ResultReport
## 结算画面文案生成:纯数据 → 字符串数组,不碰节点,便于单测与改文案。
## 输入的 pdata 结构见 Main.pdata:{list, score, counts, orig, saved, settled, done}

const CAT_NAMES := {
	Catalog.CAT_NEED: "必需品",
	Catalog.CAT_NORMAL: "常规品",
	Catalog.CAT_LARGE: "大件",
	Catalog.CAT_SALE: "特价",
}

## idx:本次结算的玩家下标 · settled:true=过闸机结算,false=打烊硬结算
## names:各座位昵称(联机排名用),空则回落到"玩家N"
static func build(pdata: Array, idx: int, settled: bool, net_mp: bool, names: Array = []) -> Array:
	var pd: Dictionary = pdata[idx]
	var done := 0
	for entry in pd["list"]:
		if entry["scanned"]:
			done += 1
	var lines: Array = []
	lines.append("🛒 结算完成!" if settled else "🛒 打烊结算")
	lines.append("")
	lines.append("最终得分:%d" % pd["score"])
	if net_mp and pdata.size() > 1:
		lines.append_array(_ranking(pdata, idx, names))
	lines.append("清单完成:%d / %d" % [done, pd["list"].size()])
	for entry in pd["list"]:
		var mark: String = "✓" if entry["scanned"] else "✗"
		lines.append("  %s %s%s" % [mark, entry["name"], "(特价抵扣)" if entry["via_sale"] else ""])
	for cat in pd["counts"]:
		lines.append("%s ×%d" % [CAT_NAMES.get(cat, cat), pd["counts"][cat]])
	lines.append("")
	lines.append("商品原价合计:¥%d · 黑五折后实付:¥%d" % [pd["orig"], pd["orig"] - pd["saved"]])
	lines.append("疯抢星期五,您总计省下了 ¥%d !" % pd["saved"])
	lines.append("")
	lines.append(_verdict(pd, done, settled))
	lines.append("")
	lines.append("按 回车 " + ("断开并返回开始界面" if net_mp else "重开一局"))
	return lines

## 全场排名(以此刻分数排序)
static func _ranking(pdata: Array, idx: int, names: Array) -> Array:
	var ranking: Array = []
	for i in pdata.size():
		ranking.append([pdata[i]["score"], i])
	ranking.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var lines: Array = ["— 本局排名 —"]
	for r in ranking.size():
		var seat: int = ranking[r][1]
		var who: String = str(names[seat]) if seat < names.size() else "玩家%d" % (seat + 1)
		if seat == idx:
			who = "%s(你)" % who
		lines.append("  第%d名 %s:%d分" % [r + 1, who, ranking[r][0]])
	return lines

## 结语:四象限(是否过闸机 × 是否清单全清)
static func _verdict(pd: Dictionary, done: int, settled: bool) -> String:
	var all_done: bool = done == pd["list"].size()
	if settled and all_done:
		return "清单全清,赶在打烊前扬长而去——黑五赢家!"
	if settled:
		return "落袋为安。没凑齐的,明年黑五再战。"
	if all_done:
		return "清单全清,满载而归!文明,打烊之前有效。"
	if pd["score"] > 0:
		return "保住了底,下次早点去排队。"
	return "……您是来观光的吗?未过闸机的商品已全部作废。"
