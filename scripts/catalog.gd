class_name Catalog
## 商品目录与全局常量:分类、分区、计分、价格与黑五折扣、物理层位

# 游戏版本号:改版时同步更新 export_presets.cfg 里的导出文件名
const GAME_VERSION := "v0.18.1"

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

# 全商品投掷基础失衡。数值按包装重量、硬度和体积手工分层；每件商品均有独立值。
const THROW_IMBALANCE := {
	"king_crab": 28.0, "wagyu": 20.0, "air_fryer": 38.0, "rice_cooker": 36.0,
	"robot_vac": 42.0, "game_console": 34.0, "pizza": 12.0, "ice_cream": 16.0,
	"salmon": 10.0, "dumplings": 14.0, "microwave": 46.0, "kettle": 22.0,
	"hair_dryer": 18.0, "tissue": 6.0, "detergent": 24.0, "thermos": 30.0,
	"shampoo": 17.0, "rice_bag": 40.0, "chips": 13.0, "cola": 26.0,
	"candy": 15.0, "teddy": 8.0, "lego": 21.0, "drone": 19.0,
	"tv": 55.0, "treadmill": 65.0, "sale_box": 25.0,
}

# 投掷效果只保留四个统一类别。同类商品的范围、时长、控制和表现完全一致，
# 单件商品之间只由 THROW_IMBALANCE 保留直击失衡差异。
const PROP_BURST := "burst"
const PROP_WET := "wet"
const PROP_SCATTER := "scatter"
const PROP_TASER := "taser"

const THROW_EFFECT := {
	# 爆裂推离（7）
	"thermos": PROP_BURST, "cola": PROP_BURST, "air_fryer": PROP_BURST,
	"rice_cooker": PROP_BURST, "microwave": PROP_BURST,
	"king_crab": PROP_BURST, "wagyu": PROP_BURST,
	# 湿滑地面（7）
	"ice_cream": PROP_WET, "detergent": PROP_WET, "shampoo": PROP_WET,
	"kettle": PROP_WET, "salmon": PROP_WET, "dumplings": PROP_WET,
	"pizza": PROP_WET,
	# 散落遮挡（7）
	"tissue": PROP_SCATTER, "rice_bag": PROP_SCATTER, "chips": PROP_SCATTER,
	"lego": PROP_SCATTER, "sale_box": PROP_SCATTER, "candy": PROP_SCATTER,
	"teddy": PROP_SCATTER,
	# 电击定身（6）
	"robot_vac": PROP_TASER, "game_console": PROP_TASER,
	"hair_dryer": PROP_TASER, "drone": PROP_TASER, "tv": PROP_TASER,
	"treadmill": PROP_TASER,
}

const BURST_RADIUS := 3.2
const BURST_ACTOR_PUSH := 7.5
const BURST_CART_PUSH := 7.2
const BURST_CART_LIFT := 11.5
const BURST_CART_TORQUE := 5.4
const WET_RADIUS := 2.8
const WET_LIFE := 8.0
const WET_MOVE_FACTOR := 0.65
const WET_TRACTION_FACTOR := 0.55
const SCATTER_RADIUS := 3.5
const SCATTER_LIFE := 4.0
const SCATTER_PERCEPTION_FACTOR := 0.35
const TASER_TIME := 1.2
const TASER_IMMUNITY := 4.0
const THROW_DIRECT_PUSH := 2.4
const THROW_WORLD_ARM_TIME := 0.12
const THROW_WORLD_ARM_DISTANCE := 1.6
const THROW_CART_DAMAGE_MULTIPLIER := 1.0
const THROW_ACTOR_DAMAGE_MULTIPLIER := 1.5

static func prop_kind(id: String) -> String:
	return str(THROW_EFFECT.get(id, PROP_SCATTER))

static func is_prop(id: String) -> bool:
	return ITEMS.has(id)

static func prop_cd(_id: String) -> float:
	return 0.65

static func throw_imbalance(id: String) -> float:
	return float(THROW_IMBALANCE.get(id, 15.0))

static func prop_effect_name(id: String) -> String:
	match prop_kind(id):
		PROP_BURST: return "爆裂推离"
		PROP_WET: return "湿滑地面"
		PROP_SCATTER: return "散落遮挡"
		PROP_TASER: return "电击定身"
	return "散落遮挡"

static func prop_effect_short(id: String) -> String:
	match prop_kind(id):
		PROP_BURST: return "推离"
		PROP_WET: return "湿滑"
		PROP_SCATTER: return "遮挡"
		PROP_TASER: return "定身"
	return "遮挡"

static func prop_effect_color(id: String) -> Color:
	match prop_kind(id):
		PROP_BURST: return Color(1.0, 0.34, 0.08)
		PROP_WET: return Color(0.28, 0.62, 1.0)
		PROP_SCATTER: return Color(0.94, 0.84, 0.58)
		PROP_TASER: return Color(0.35, 0.9, 1.0)
	return Color.WHITE

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
