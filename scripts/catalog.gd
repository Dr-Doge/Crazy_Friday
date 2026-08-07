class_name Catalog
## 商品目录与全局常量:分类、分区、计分、价格与黑五折扣、物理层位

# 游戏版本号:改版时同步更新 export_presets.cfg 里的导出文件名
const GAME_VERSION := "v0.14"

# 商品分类(计分见策划案第十节)
const CAT_NEED := "need"      # 必需品 15分,库存<需求,必然争抢
const CAT_NORMAL := "normal"  # 常规品 10分
const CAT_LARGE := "large"    # 大件 25分,占双手,速度减半
const CAT_SALE := "sale"      # 特价 5分+通配一项常规品

const POINTS := {CAT_NEED: 15, CAT_NORMAL: 10, CAT_LARGE: 25, CAT_SALE: 10}
const SALE_BONUS := 5

# 分区(premium=地图中央的黑五爆款专区,高价值高折扣必需品集中于此)
const ZONE_FRESH := "fresh"
const ZONE_APPLIANCE := "appliance"
const ZONE_DAILY := "daily"
const ZONE_SNACK := "snack"
const ZONE_PREMIUM := "premium"

const ZONE_NAMES := {
	ZONE_FRESH: "生鲜冷冻区",
	ZONE_APPLIANCE: "家电区",
	ZONE_DAILY: "日用百货区",
	ZONE_SNACK: "零食玩具区",
	ZONE_PREMIUM: "黑五爆款专区",
}

const ZONE_COLORS := {
	ZONE_FRESH: Color(0.55, 0.78, 0.92),
	ZONE_APPLIANCE: Color(0.72, 0.72, 0.85),
	ZONE_DAILY: Color(0.72, 0.87, 0.62),
	ZONE_SNACK: Color(0.95, 0.82, 0.55),
	ZONE_PREMIUM: Color(1.0, 0.78, 0.2),
}

# 商品表:name 显示名(带品牌特征) / cat 分类 / zone 分区 / stock 本局库存
#         size 包装盒尺寸 / color 白盒颜色 / price 原价 / disc 黑五折扣力度(省下的比例)
const ITEMS := {
	# ---- 必需品(库存2,全场需求>库存;高价高折扣,集中陈列在中央爆款专区) ----
	"king_crab":    {"name": "阿拉斯加帝王蟹", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.55, 0.3, 0.45), "color": Color(0.85, 0.22, 0.2), "price": 399, "disc": 0.5},
	"wagyu":        {"name": "A5和牛礼盒", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.5, 0.22, 0.35), "color": Color(0.7, 0.15, 0.22), "price": 599, "disc": 0.45},
	"air_fryer":    {"name": "网红空气炸锅", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.45, 0.45, 0.45), "color": Color(0.9, 0.32, 0.25), "price": 299, "disc": 0.6},
	"rice_cooker":  {"name": "IH智能电饭煲", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.42, 0.38, 0.42), "color": Color(0.85, 0.42, 0.3), "price": 259, "disc": 0.55},
	"robot_vac":    {"name": "扫地机器人", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.5, 0.2, 0.5), "color": Color(0.8, 0.25, 0.38), "price": 899, "disc": 0.5},
	"game_console": {"name": "次世代游戏主机", "cat": CAT_NEED, "zone": ZONE_PREMIUM, "stock": 2, "size": Vector3(0.45, 0.35, 0.3), "color": Color(0.9, 0.2, 0.3), "price": 1999, "disc": 0.35},
	# ---- 常规品:生鲜冷冻(库存刻意小于全场需求,供不应求) ----
	"pizza":     {"name": "石窑冻披萨", "cat": CAT_NORMAL, "zone": ZONE_FRESH, "stock": 3, "size": Vector3(0.42, 0.12, 0.42), "color": Color(0.92, 0.6, 0.35), "price": 39, "disc": 0.3},
	"ice_cream": {"name": "家庭装冰淇淋", "cat": CAT_NORMAL, "zone": ZONE_FRESH, "stock": 3, "size": Vector3(0.3, 0.3, 0.3), "color": Color(0.95, 0.75, 0.85), "price": 49, "disc": 0.4},
	"salmon":    {"name": "三文鱼刺身盒", "cat": CAT_NORMAL, "zone": ZONE_FRESH, "stock": 3, "size": Vector3(0.4, 0.12, 0.3), "color": Color(0.98, 0.55, 0.45), "price": 89, "disc": 0.35},
	"dumplings": {"name": "速冻虾仁水饺", "cat": CAT_NORMAL, "zone": ZONE_FRESH, "stock": 3, "size": Vector3(0.35, 0.2, 0.28), "color": Color(0.85, 0.9, 0.95), "price": 25, "disc": 0.25},
	# ---- 常规品:家电 ----
	"microwave":  {"name": "平板微波炉", "cat": CAT_NORMAL, "zone": ZONE_APPLIANCE, "stock": 3, "size": Vector3(0.55, 0.35, 0.42), "color": Color(0.6, 0.62, 0.7), "price": 199, "disc": 0.3},
	"kettle":     {"name": "玻璃电热水壶", "cat": CAT_NORMAL, "zone": ZONE_APPLIANCE, "stock": 3, "size": Vector3(0.25, 0.3, 0.25), "color": Color(0.7, 0.85, 0.9), "price": 89, "disc": 0.35},
	"hair_dryer": {"name": "负离子吹风机", "cat": CAT_NORMAL, "zone": ZONE_APPLIANCE, "stock": 3, "size": Vector3(0.3, 0.25, 0.15), "color": Color(0.85, 0.6, 0.75), "price": 129, "disc": 0.4},
	# ---- 常规品:日用百货 ----
	"tissue":    {"name": "十卷装卫生纸", "cat": CAT_NORMAL, "zone": ZONE_DAILY, "stock": 4, "size": Vector3(0.5, 0.28, 0.3), "color": Color(0.95, 0.95, 0.92), "price": 35, "disc": 0.3},
	"detergent": {"name": "薰衣草洗衣液", "cat": CAT_NORMAL, "zone": ZONE_DAILY, "stock": 3, "size": Vector3(0.28, 0.4, 0.22), "color": Color(0.45, 0.5, 0.9), "price": 49, "disc": 0.35},
	"thermos":   {"name": "焖烧保温杯", "cat": CAT_NORMAL, "zone": ZONE_DAILY, "stock": 3, "size": Vector3(0.18, 0.35, 0.18), "color": Color(0.75, 0.55, 0.85), "price": 79, "disc": 0.4},
	"shampoo":   {"name": "生姜防脱洗发水", "cat": CAT_NORMAL, "zone": ZONE_DAILY, "stock": 3, "size": Vector3(0.22, 0.32, 0.18), "color": Color(0.4, 0.7, 0.55), "price": 59, "disc": 0.3},
	"rice_bag":  {"name": "十斤装东北大米", "cat": CAT_NORMAL, "zone": ZONE_DAILY, "stock": 3, "size": Vector3(0.45, 0.15, 0.6), "color": Color(0.9, 0.85, 0.7), "price": 69, "disc": 0.2},
	# ---- 常规品:零食玩具 ----
	"chips": {"name": "巨型桶装薯片", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 4, "size": Vector3(0.3, 0.4, 0.24), "color": Color(0.95, 0.85, 0.3), "price": 29, "disc": 0.25},
	"cola":  {"name": "可乐24罐整箱", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 4, "size": Vector3(0.4, 0.25, 0.3), "color": Color(0.7, 0.2, 0.25), "price": 45, "disc": 0.3},
	"candy": {"name": "什锦软糖桶", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 3, "size": Vector3(0.28, 0.3, 0.28), "color": Color(0.95, 0.6, 0.75), "price": 19, "disc": 0.2},
	"teddy": {"name": "限量款玩具熊", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 2, "size": Vector3(0.4, 0.45, 0.35), "color": Color(0.8, 0.6, 0.4), "price": 99, "disc": 0.45},
	"lego":  {"name": "积木天空城堡", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 2, "size": Vector3(0.5, 0.35, 0.3), "color": Color(0.4, 0.75, 0.5), "price": 199, "disc": 0.35},
	"drone": {"name": "迷你航拍无人机", "cat": CAT_NORMAL, "zone": ZONE_SNACK, "stock": 2, "size": Vector3(0.35, 0.18, 0.35), "color": Color(0.5, 0.55, 0.6), "price": 299, "disc": 0.4},
	# ---- 大件(占双手,徒步减速) ----
	"tv":        {"name": "65寸巨幕电视", "cat": CAT_LARGE, "zone": ZONE_APPLIANCE, "stock": 2, "size": Vector3(1.35, 0.85, 0.2), "color": Color(0.25, 0.35, 0.75), "price": 2999, "disc": 0.4},
	"treadmill": {"name": "折叠跑步机", "cat": CAT_LARGE, "zone": ZONE_APPLIANCE, "stock": 2, "size": Vector3(1.1, 0.5, 0.6), "color": Color(0.35, 0.4, 0.5), "price": 1599, "disc": 0.45},
	# ---- 特价神秘箱(限时特价事件掉落) ----
	"sale_box": {"name": "特价神秘箱", "cat": CAT_SALE, "zone": "", "stock": 0, "size": Vector3(0.38, 0.38, 0.38), "color": Color(0.98, 0.8, 0.15), "price": 99, "disc": 0.8},
}

# 物理层位
const L_WORLD := 1
const L_CHAR := 2
const L_CART := 4
const L_ITEM := 8

static var _font: SystemFont
static var _font_bold: SystemFont

# 中文UI字体:Godot默认字体无CJK,回落到系统字体
static func ui_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Arial"])
	return _font

static func ui_font_bold() -> SystemFont:
	if _font_bold == null:
		_font_bold = SystemFont.new()
		_font_bold.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Arial"])
		_font_bold.font_weight = 700
	return _font_bold

static func points_for(item_id: String) -> int:
	var cat: String = ITEMS[item_id]["cat"]
	return POINTS.get(cat, 0)

static func price_of(item_id: String) -> int:
	return int(ITEMS[item_id].get("price", 0))

static func discount_of(item_id: String) -> float:
	return float(ITEMS[item_id].get("disc", 0.0))

static func ids_of_cat(cat: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id]["cat"] == cat:
			out.append(id)
	return out
