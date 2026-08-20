class_name Catalog
## 商品目录与全局常量:分类、分区、计分、价格与黑五折扣、物理层位

# 游戏版本号:改版时同步更新 export_presets.cfg 里的导出文件名
const GAME_VERSION := "v0.19.0"

# 商品分类(计分见策划案第十节)
const CAT_NEED := "need"      # 必需品 15分,库存<需求,必然争抢
const CAT_NORMAL := "normal"  # 常规品 10分
const CAT_LARGE := "large"    # 大件 25分,占双手,速度减半
const CAT_SALE := "sale"      # 特价 5分+通配一项常规品

const POINTS := {CAT_NEED: 15, CAT_NORMAL: 10, CAT_LARGE: 25, CAT_SALE: 10}
const SALE_BONUS := 5

const TEAM_NAMES := ["蓝队 A", "橙队 B", "绿队 C", "紫队 D"]
const TEAM_SHORT_NAMES := ["A队", "B队", "C队", "D队"]
const TEAM_COLORS := [
	Color(0.24, 0.58, 0.92),
	Color(0.94, 0.52, 0.16),
	Color(0.28, 0.72, 0.38),
	Color(0.67, 0.38, 0.86),
]

static func team_color(team_id: int) -> Color:
	return TEAM_COLORS[clampi(team_id, 0, TEAM_COLORS.size() - 1)]

static func team_name(team_id: int, short := false) -> String:
	var names := TEAM_SHORT_NAMES if short else TEAM_NAMES
	return names[clampi(team_id, 0, names.size() - 1)]

# 分区(premium=地图中央的黑五爆款专区,高价值高折扣必需品集中于此)
const ZONE_FRESH := "fresh"
const ZONE_FROZEN := "frozen"
const ZONE_APPLIANCE := "appliance"
const ZONE_DAILY := "daily"
const ZONE_SNACK := "snack"
const ZONE_TOY := "toy"
const ZONE_BEAUTY := "beauty"
const ZONE_CLOTHING := "clothing"
const ZONE_PREMIUM := "premium"

## 生鲜生态商品只以地面活物形式生成，不进入普通货柜铺货池。
const LIVE_FRESH_IDS := ["king_crab", "xianyu_fish"]

const SHOPPING_ZONES := [
	ZONE_FRESH, ZONE_FROZEN, ZONE_SNACK, ZONE_TOY,
	ZONE_APPLIANCE, ZONE_DAILY, ZONE_BEAUTY, ZONE_CLOTHING,
]

# 货架铺货按十件一组循环：低/中/高档严格维持6:3:1；每个普通专区最多50件。
const TIER_LOW := 1
const TIER_MID := 2
const TIER_HIGH := 3
const TIER_PATTERN := [1, 1, 1, 1, 1, 1, 2, 2, 2, 3]
const SHELF_STOCK_PER_ZONE := 50
const PREMIUM_STOCK := 10
const SHELF_DISPLAY_SCALE := 2.0

const ZONE_NAMES := {
	ZONE_FRESH: "生鲜区",
	ZONE_FROZEN: "冷冻区",
	ZONE_APPLIANCE: "数码家电区",
	ZONE_DAILY: "日用品区",
	ZONE_SNACK: "饮料零食区",
	ZONE_TOY: "玩具区",
	ZONE_BEAUTY: "个护美妆区",
	ZONE_CLOTHING: "服饰区",
	ZONE_PREMIUM: "黑五爆款专区",
}

const ZONE_COLORS := {
	ZONE_FRESH: Color(0.55, 0.78, 0.92),
	ZONE_FROZEN: Color(0.48, 0.76, 0.9),
	ZONE_APPLIANCE: Color(0.72, 0.72, 0.85),
	ZONE_DAILY: Color(0.72, 0.87, 0.62),
	ZONE_SNACK: Color(0.95, 0.82, 0.55),
	ZONE_TOY: Color(0.95, 0.62, 0.72),
	ZONE_BEAUTY: Color(0.82, 0.68, 0.9),
	ZONE_CLOTHING: Color(0.84, 0.68, 0.52),
	ZONE_PREMIUM: Color(1.0, 0.78, 0.2),
}

# 商品表：tier=1/2/3低中高档；stock保留给旧场景回退，新关卡按专区6:3:1动态铺货。
# size是拿取/车内真实尺寸；货架陈列由Item统一放大到2倍。
const ITEMS := {
	# ---- 中央黑五：现实中会等大促购买的高价货 ----
	"mini_led_98": {"name":"98寸MiniLED巨幕电视", "cat":CAT_NEED, "zone":ZONE_PREMIUM, "tier":3, "stock":1, "size":Vector3(1.4,0.9,0.2), "color":Color(0.18,0.28,0.62), "price":8999, "disc":0.45},
	"gaming_laptop": {"name":"旗舰显卡游戏本", "cat":CAT_NEED, "zone":ZONE_PREMIUM, "tier":2, "stock":3, "size":Vector3(0.55,0.1,0.4), "color":Color(0.18,0.2,0.25), "price":6999, "disc":0.4},
	"premium_robot_vac": {"name":"全屋激光扫拖机器人", "cat":CAT_NEED, "zone":ZONE_PREMIUM, "tier":1, "stock":6, "size":Vector3(0.52,0.2,0.52), "color":Color(0.82,0.82,0.86), "price":3299, "disc":0.5},
	"espresso_machine": {"name":"双锅炉意式咖啡机", "cat":CAT_NEED, "zone":ZONE_PREMIUM, "tier":2, "stock":3, "size":Vector3(0.48,0.5,0.4), "color":Color(0.55,0.28,0.18), "price":4599, "disc":0.42},
	"durian_phone": {"name":"榴莲手机", "cat":CAT_NEED, "zone":ZONE_PREMIUM, "tier":3, "stock":1, "size":Vector3(0.22,0.36,0.08), "color":Color(0.62,0.82,0.22), "price":4999, "disc":0.35},

	# ---- 生鲜区 ----
	"king_crab": {"name":"皮皮虾", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":2, "stock":3, "size":Vector3(0.55,0.3,0.45), "color":Color(0.85,0.22,0.2), "price":99, "disc":0.3},
	"wagyu": {"name":"老吴和牛礼盒", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":3, "stock":1, "size":Vector3(0.5,0.22,0.35), "color":Color(0.7,0.15,0.22), "price":599, "disc":0.45},
	"salmon": {"name":"哈兰德三文鱼", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":2, "stock":3, "size":Vector3(0.4,0.12,0.3), "color":Color(0.98,0.55,0.45), "price":89, "disc":0.35},
	"yogurt_pack": {"name":"MC希腊酸奶", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":1, "stock":6, "size":Vector3(0.38,0.28,0.3), "color":Color(0.84,0.9,0.98), "price":55, "disc":0.35},
	"xianyu_fish": {"name":"闲鱼黄胖鱼", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":1, "stock":6, "size":Vector3(0.45,0.22,0.28), "color":Color(0.95,0.78,0.18), "price":29, "disc":0.2},
	"moose_milk": {"name":"枫叶麋鹿鲜奶", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":1, "stock":6, "size":Vector3(0.3,0.45,0.25), "color":Color(0.92,0.95,1.0), "price":35, "disc":0.25},
	"costcow_eggs": {"name":"Trader John牧场鸡蛋", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":2, "stock":3, "size":Vector3(0.5,0.18,0.32), "color":Color(0.84,0.7,0.48), "price":69, "disc":0.3},
	"whole_paycheck_avocado": {"name":"Half foods牛油果", "cat":CAT_NORMAL, "zone":ZONE_FRESH, "tier":3, "stock":1, "size":Vector3(0.4,0.24,0.32), "color":Color(0.28,0.62,0.3), "price":129, "disc":0.35},

	# ---- 冷冻区 ----
	"pizza": {"name":"夏威夷披萨", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":1, "stock":6, "size":Vector3(0.42,0.12,0.42), "color":Color(0.92,0.6,0.35), "price":39, "disc":0.3},
	"ice_cream": {"name":"八羊冰淇淋", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":1, "stock":6, "size":Vector3(0.3,0.3,0.3), "color":Color(0.95,0.75,0.85), "price":49, "disc":0.4},
	"dumplings": {"name":"速冻炒肝水饺", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":1, "stock":6, "size":Vector3(0.35,0.2,0.28), "color":Color(0.85,0.9,0.95), "price":25, "disc":0.25},
	"five_dudes_burger": {"name":"Five-Dudes五个老哥汉堡", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":2, "stock":3, "size":Vector3(0.4,0.22,0.35), "color":Color(0.85,0.32,0.18), "price":59, "disc":0.35},
	"salted_sword": {"name":"尚方宝剑咸鱼", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":2, "stock":3, "size":Vector3(0.62,0.12,0.18), "color":Color(0.58,0.72,0.78), "price":79, "disc":0.4},
	"frozen_pear": {"name":"东北黑金砖冻梨", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":1, "stock":6, "size":Vector3(0.32,0.3,0.28), "color":Color(0.2,0.17,0.2), "price":19, "disc":0.2},
	"one_fifty_hotdog": {"name":"CostCow热狗", "cat":CAT_NORMAL, "zone":ZONE_FROZEN, "tier":3, "stock":1, "size":Vector3(0.45,0.16,0.22), "color":Color(0.9,0.65,0.28), "price":15, "disc":0.67},

	# ---- 饮料零食区 ----
	"chips": {"name":"喜事桶装薯片", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":1, "stock":6, "size":Vector3(0.3,0.4,0.24), "color":Color(0.95,0.85,0.3), "price":29, "disc":0.25},
	"cola": {"name":"口渴可乐整箱", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":1, "stock":6, "size":Vector3(0.4,0.25,0.3), "color":Color(0.7,0.2,0.25), "price":45, "disc":0.3},
	"candy": {"name":"小小泡泡糖", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":1, "stock":6, "size":Vector3(0.28,0.3,0.28), "color":Color(0.95,0.6,0.75), "price":19, "disc":0.2},
	"sparkling_water": {"name":"怨气树林气泡水", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":1, "stock":6, "size":Vector3(0.38,0.24,0.28), "color":Color(0.48,0.78,0.88), "price":39, "disc":0.3},
	"paper_towels": {"name":"阿诺牌蛋白粉", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":2, "stock":3, "size":Vector3(0.38,0.22,0.28), "color":Color(0.92,0.91,0.82), "price":69, "disc":0.3},
	"tactical_spicy_strips": {"name":"威龙战术辣条", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":1, "stock":6, "size":Vector3(0.34,0.08,0.45), "color":Color(0.82,0.12,0.08), "price":12, "disc":0.2},
	"grandpa_coconut": {"name":"爷树牌椰汁", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":2, "stock":3, "size":Vector3(0.28,0.38,0.22), "color":Color(0.25,0.25,0.22), "price":39, "disc":0.35},
	"sidequest_energy": {"name":"地球人电解质饮料", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":3, "stock":1, "size":Vector3(0.28,0.42,0.22), "color":Color(0.35,0.75,1.0), "price":89, "disc":0.45},
	"freedom_corn_chips": {"name":"自由鹰超辣玉米片", "cat":CAT_NORMAL, "zone":ZONE_SNACK, "tier":2, "stock":3, "size":Vector3(0.36,0.42,0.18), "color":Color(0.22,0.42,0.82), "price":49, "disc":0.3},

	# ---- 玩具区 ----
	"teddy": {"name":"拉肚肚", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":2, "stock":3, "size":Vector3(0.4,0.45,0.35), "color":Color(0.8,0.6,0.4), "price":99, "disc":0.45},
	"lego": {"name":"激动武士矮达", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":2, "stock":3, "size":Vector3(0.5,0.35,0.3), "color":Color(0.4,0.75,0.5), "price":199, "disc":0.35},
	"tongtongsahu": {"name":"TongTongSahu木偶摆件", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":1, "stock":6, "size":Vector3(0.32,0.46,0.28), "color":Color(0.72,0.46,0.22), "price":39, "disc":0.25},
	"ohio_final_boss": {"name":"Ohio最终Boss手办", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":3, "stock":1, "size":Vector3(0.4,0.5,0.32), "color":Color(0.48,0.18,0.68), "price":299, "disc":0.5},
	"skibuddy_toilet": {"name":"Skibuddy马桶盲盒", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":1, "stock":6, "size":Vector3(0.32,0.36,0.32), "color":Color(0.88,0.9,0.95), "price":59, "disc":0.35},
	"gta7_disc": {"name":"GTA7游戏实体光盘", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":3, "stock":1, "size":Vector3(0.34,0.04,0.34), "color":Color(0.12,0.18,0.22), "price":599, "disc":0.35},
	"pocketmon_cards": {"name":"Pocketmon集换卡", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":2, "stock":3, "size":Vector3(0.25,0.05,0.36), "color":Color(0.98,0.72,0.12), "price":159, "disc":0.4},
	"logo_bricks": {"name":"LOGO拼装玩具", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":1, "stock":6, "size":Vector3(0.4,0.3,0.28), "color":Color(0.92,0.18,0.16), "price":69, "disc":0.3},
	"biba_doll": {"name":"碧芭娃娃", "cat":CAT_NORMAL, "zone":ZONE_TOY, "tier":1, "stock":6, "size":Vector3(0.28,0.48,0.24), "color":Color(0.98,0.52,0.76), "price":79, "disc":0.35},

	# ---- 数码家电区 ----
	"air_fryer": {"name":"秒速空气炸锅", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":1, "stock":6, "size":Vector3(0.45,0.45,0.45), "color":Color(0.9,0.32,0.25), "price":299, "disc":0.6},
	"robot_vac": {"name":"爱丽丝扫地机", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":2, "stock":3, "size":Vector3(0.5,0.2,0.5), "color":Color(0.8,0.25,0.38), "price":899, "disc":0.5},
	"game_console": {"name":"任地狱游戏机", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":3, "stock":1, "size":Vector3(0.45,0.35,0.3), "color":Color(0.9,0.2,0.3), "price":1999, "disc":0.35},
	"microwave": {"name":"核动力微波炉", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":1, "stock":6, "size":Vector3(0.55,0.35,0.42), "color":Color(0.6,0.62,0.7), "price":199, "disc":0.3},
	"kettle": {"name":"九阴电热水壶", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":1, "stock":6, "size":Vector3(0.25,0.3,0.25), "color":Color(0.7,0.85,0.9), "price":89, "disc":0.35},
	"hair_dryer": {"name":"戴林吹风机", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":1, "stock":6, "size":Vector3(0.3,0.25,0.15), "color":Color(0.85,0.6,0.75), "price":129, "disc":0.4},
	"electric_iron": {"name":"肉包智能助手", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":2, "stock":3, "size":Vector3(0.32,0.2,0.18), "color":Color(0.55,0.72,0.82), "price":109, "disc":0.4},
	"drone": {"name":"小江航拍无人机", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":2, "stock":3, "size":Vector3(0.35,0.18,0.35), "color":Color(0.5,0.55,0.6), "price":299, "disc":0.4},
	"nvidiai_gpu": {"name":"NVIDI-AI显卡", "cat":CAT_NORMAL, "zone":ZONE_APPLIANCE, "tier":3, "stock":1, "size":Vector3(0.48,0.18,0.3), "color":Color(0.28,0.72,0.16), "price":6999, "disc":0.3},
	"treadmill": {"name":"爱驴折叠电动车", "cat":CAT_LARGE, "zone":ZONE_APPLIANCE, "tier":3, "stock":1, "size":Vector3(1.1,0.5,0.6), "color":Color(0.35,0.4,0.5), "price":1599, "disc":0.45},

	# ---- 日用品区 ----
	"tissue": {"name":"抽个爽卫生纸", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.5,0.28,0.3), "color":Color(0.95,0.95,0.92), "price":35, "disc":0.3},
	"detergent": {"name":"绿太阳洗衣液", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.28,0.4,0.22), "color":Color(0.45,0.5,0.9), "price":49, "disc":0.35},
	"thermos": {"name":"自带枸杞保温杯", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":2, "stock":3, "size":Vector3(0.18,0.35,0.18), "color":Color(0.75,0.55,0.85), "price":79, "disc":0.4},
	"rice_bag": {"name":"东北六常大米", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.45,0.15,0.6), "color":Color(0.9,0.85,0.7), "price":69, "disc":0.2},
	"procrastination_mop": {"name":"一拖再拖拖把", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.5,0.16,0.3), "color":Color(0.3,0.72,0.75), "price":39, "disc":0.3},
	"ancestral_pan": {"name":"祖传不粘锅（什么都粘）", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":2, "stock":3, "size":Vector3(0.52,0.12,0.4), "color":Color(0.22,0.22,0.24), "price":129, "disc":0.4},
	"route67_lube": {"name":"67号万能润滑油", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.2,0.38,0.18), "color":Color(0.2,0.36,0.82), "price":27, "disc":0.25},
	"stanley_tumbler": {"name":"斯坦尼巨型吸管杯", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":3, "stock":1, "size":Vector3(0.3,0.5,0.3), "color":Color(0.92,0.48,0.66), "price":399, "disc":0.5},
	"home_despot_tape": {"name":"Home Despot万能胶带", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":2, "stock":3, "size":Vector3(0.3,0.22,0.3), "color":Color(0.9,0.38,0.08), "price":59, "disc":0.3},
	"freedom_trash_bags": {"name":"自由尺寸垃圾袋", "cat":CAT_NORMAL, "zone":ZONE_DAILY, "tier":1, "stock":6, "size":Vector3(0.34,0.3,0.22), "color":Color(0.18,0.22,0.28), "price":29, "disc":0.2},

	# ---- 个护美妆区 ----
	"shampoo": {"name":"虞姬防脱洗发水", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":1, "stock":6, "size":Vector3(0.22,0.32,0.18), "color":Color(0.4,0.7,0.55), "price":59, "disc":0.3},
	"sos_honey": {"name":"小宝SOS蜜", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":1, "stock":6, "size":Vector3(0.25,0.22,0.25), "color":Color(0.95,0.65,0.22), "price":49, "disc":0.35},
	"manchester_lip": {"name":"曼彻斯特润唇膏", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":1, "stock":6, "size":Vector3(0.15,0.32,0.15), "color":Color(0.2,0.42,0.75), "price":39, "disc":0.3},
	"ceramaybe_cream": {"name":"CeraMaybe神经酰胺霜", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":2, "stock":3, "size":Vector3(0.25,0.25,0.25), "color":Color(0.88,0.95,1.0), "price":119, "disc":0.4},
	"doctor_square_soap": {"name":"博士方块皂", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":1, "stock":6, "size":Vector3(0.3,0.18,0.24), "color":Color(0.35,0.68,0.42), "price":45, "disc":0.25},
	"sigma_hairspray": {"name":"Sigma定型喷雾", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":2, "stock":3, "size":Vector3(0.18,0.42,0.18), "color":Color(0.45,0.2,0.65), "price":89, "disc":0.35},
	"sephora_kid_kit": {"name":"十岁丝芙拉抗老套装", "cat":CAT_NORMAL, "zone":ZONE_BEAUTY, "tier":3, "stock":1, "size":Vector3(0.42,0.26,0.32), "color":Color(0.95,0.65,0.8), "price":499, "disc":0.5},

	# ---- 服饰区 ----
	"prosperity_tracksuit": {"name":"旺仔战衣", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":1, "stock":6, "size":Vector3(0.45,0.12,0.5), "color":Color(0.9,0.08,0.08), "price":99, "disc":0.35},
	"dance_champion_shoes": {"name":"广场舞冠军战靴", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":2, "stock":3, "size":Vector3(0.45,0.2,0.3), "color":Color(0.92,0.68,0.12), "price":199, "disc":0.45},
	"maple_goose_jacket": {"name":"枫叶鹅极寒羽绒服", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":3, "stock":1, "size":Vector3(0.48,0.16,0.55), "color":Color(0.72,0.12,0.18), "price":1999, "disc":0.55},
	"south_face_jacket": {"name":"The South Face冲锋衣", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":2, "stock":3, "size":Vector3(0.46,0.14,0.52), "color":Color(0.18,0.42,0.75), "price":699, "disc":0.45},
	"costcow_socks": {"name":"Costcow三十双家庭袜", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":1, "stock":6, "size":Vector3(0.42,0.22,0.32), "color":Color(0.75,0.72,0.68), "price":59, "disc":0.3},
	"ohio_tshirt": {"name":"我爱纽约但人在Ohio恤", "cat":CAT_NORMAL, "zone":ZONE_CLOTHING, "tier":1, "stock":6, "size":Vector3(0.4,0.12,0.45), "color":Color(0.95,0.95,0.92), "price":39, "disc":0.25},

	# ---- 特价神秘箱(限时特价事件掉落) ----
	"sale_box": {"name":"特价神秘箱", "cat":CAT_SALE, "zone":"", "tier":1, "stock":0, "size":Vector3(0.38,0.38,0.38), "color":Color(0.98,0.8,0.15), "price":99, "disc":0.8},
}

# 物理层位
const L_WORLD := 1
const L_CHAR := 2
const L_CART := 4
const L_ITEM := 8
# 冷冻软门帘只从自身一侧感知角色/购物车并接受推力；角色和车辆的碰撞掩码
# 不包含此层，因此穿行时不会被布条卡住。
const L_CURTAIN := 16

static var _font: SystemFont
static var _font_bold: SystemFont

# 全商品投掷基础失衡。数值按包装重量、硬度和体积手工分层；每件商品均有独立值。
const THROW_IMBALANCE := {
	"mini_led_98":55.0, "gaming_laptop":35.0, "premium_robot_vac":42.0, "espresso_machine":40.0,
	"king_crab":28.0, "wagyu":20.0, "salmon":10.0, "yogurt_pack":18.0,
	"xianyu_fish":14.0, "moose_milk":19.0, "costcow_eggs":12.0, "whole_paycheck_avocado":17.0,
	"pizza":12.0, "ice_cream":16.0, "dumplings":14.0, "five_dudes_burger":18.0,
	"salted_sword":26.0, "frozen_pear":20.0, "one_fifty_hotdog":11.0,
	"chips":13.0, "cola":26.0, "candy":15.0, "sparkling_water":24.0, "paper_towels":17.0,
	"tactical_spicy_strips":10.0, "grandpa_coconut":18.0, "sidequest_energy":25.0, "freedom_corn_chips":14.0,
	"teddy":8.0, "lego":21.0, "tongtongsahu":12.0, "ohio_final_boss":25.0,
	"skibuddy_toilet":13.0, "gta7_disc":18.0, "pocketmon_cards":9.0,
	"logo_bricks":20.0, "biba_doll":11.0,
	"air_fryer":38.0, "robot_vac":42.0, "game_console":34.0,
	"microwave":46.0, "kettle":22.0, "hair_dryer":18.0, "electric_iron":23.0,
	"drone":19.0, "durian_phone":28.0, "nvidiai_gpu":31.0, "treadmill":65.0,
	"tissue":6.0, "detergent":24.0, "thermos":30.0, "rice_bag":40.0,
	"procrastination_mop":18.0, "ancestral_pan":34.0, "route67_lube":16.0,
	"stanley_tumbler":29.0, "home_despot_tape":15.0, "freedom_trash_bags":9.0,
	"shampoo":17.0, "sos_honey":14.0, "manchester_lip":8.0, "ceramaybe_cream":12.0,
	"doctor_square_soap":18.0, "sigma_hairspray":15.0, "sephora_kid_kit":20.0,
	"prosperity_tracksuit":10.0, "dance_champion_shoes":24.0, "maple_goose_jacket":18.0,
	"south_face_jacket":17.0, "costcow_socks":9.0, "ohio_tshirt":8.0,
	"sale_box":25.0,
}

# 投掷效果只保留四个统一类别。同类商品的范围、时长、控制和表现完全一致，
# 单件商品之间只由 THROW_IMBALANCE 保留直击失衡差异。
const PROP_BURST := "burst"
const PROP_WET := "wet"
const PROP_SCATTER := "scatter"
const PROP_TASER := "taser"

const THROW_EFFECT := {
	# 原有商品
	"thermos": PROP_BURST, "cola": PROP_BURST, "air_fryer": PROP_BURST,
	"microwave": PROP_BURST,
	"king_crab": PROP_BURST, "wagyu": PROP_BURST,
	"sparkling_water": PROP_BURST,
	# 湿滑地面（7）
	"ice_cream": PROP_WET, "detergent": PROP_WET, "shampoo": PROP_WET,
	"salmon": PROP_WET, "dumplings": PROP_WET,
	"pizza": PROP_WET, "yogurt_pack": PROP_WET,
	# 散落遮挡（7）
	"tissue": PROP_SCATTER, "rice_bag": PROP_SCATTER, "chips": PROP_SCATTER,
	"sale_box": PROP_SCATTER, "candy": PROP_SCATTER, "paper_towels": PROP_SCATTER,
	# 电击定身（6）
	"robot_vac": PROP_TASER, "game_console": PROP_TASER,
	"hair_dryer": PROP_TASER, "drone": PROP_TASER,
	"treadmill": PROP_TASER, "electric_iron": PROP_TASER,
	# 扩展商品：四类数量继续保持近似均衡，降低玩家记忆成本。
	"mini_led_98":PROP_TASER, "gaming_laptop":PROP_TASER,
	"premium_robot_vac":PROP_TASER, "espresso_machine":PROP_TASER,
	"xianyu_fish":PROP_WET, "moose_milk":PROP_WET,
	"costcow_eggs":PROP_SCATTER, "whole_paycheck_avocado":PROP_BURST,
	"five_dudes_burger":PROP_SCATTER, "salted_sword":PROP_BURST,
	"frozen_pear":PROP_BURST, "one_fifty_hotdog":PROP_WET,
	"tactical_spicy_strips":PROP_SCATTER, "grandpa_coconut":PROP_WET,
	"sidequest_energy":PROP_WET, "freedom_corn_chips":PROP_SCATTER,
	"tongtongsahu":PROP_SCATTER, "ohio_final_boss":PROP_BURST,
	"skibuddy_toilet":PROP_SCATTER, "gta7_disc":PROP_TASER,
	"pocketmon_cards":PROP_SCATTER, "logo_bricks":PROP_SCATTER,
	"biba_doll":PROP_BURST, "teddy":PROP_TASER, "lego":PROP_TASER,
	"durian_phone":PROP_TASER, "nvidiai_gpu":PROP_TASER, "kettle":PROP_TASER,
	"procrastination_mop":PROP_WET, "ancestral_pan":PROP_BURST,
	"route67_lube":PROP_WET, "stanley_tumbler":PROP_BURST,
	"home_despot_tape":PROP_SCATTER, "freedom_trash_bags":PROP_SCATTER,
	"sos_honey":PROP_WET, "manchester_lip":PROP_WET,
	"ceramaybe_cream":PROP_WET, "doctor_square_soap":PROP_BURST,
	"sigma_hairspray":PROP_SCATTER, "sephora_kid_kit":PROP_TASER,
	"prosperity_tracksuit":PROP_SCATTER, "dance_champion_shoes":PROP_BURST,
	"maple_goose_jacket":PROP_BURST, "south_face_jacket":PROP_BURST,
	"costcow_socks":PROP_WET, "ohio_tshirt":PROP_TASER,
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
const TASER_TIME := 5.0
const TASER_IMMUNITY := 4.0
const THROW_DIRECT_PUSH := 2.4
const THROW_WORLD_ARM_TIME := 0.12
const THROW_WORLD_ARM_DISTANCE := 1.6
const THROW_CART_DAMAGE_MULTIPLIER := 1.0
const THROW_ACTOR_DAMAGE_MULTIPLIER := 1.5

static func prop_kind(id: String) -> String:
	return str(THROW_EFFECT.get(id, PROP_SCATTER))

static func is_fragile(id: String) -> bool:
	return ITEMS.has(id) and str(ITEMS[id]["zone"]) == ZONE_APPLIANCE

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

static func tier_of(item_id: String) -> int:
	return clampi(int(ITEMS[item_id].get("tier", TIER_LOW)), TIER_LOW, TIER_HIGH) \
			if ITEMS.has(item_id) else TIER_LOW

static func ids_of_zone_tier(zone: String, tier: int, include_large := false) -> Array[String]:
	var out: Array[String] = []
	for id in ITEMS:
		var data: Dictionary = ITEMS[id]
		if str(data["zone"]) != zone or tier_of(id) != tier \
				or data["cat"] == CAT_SALE:
			continue
		if not include_large and data["cat"] == CAT_LARGE:
			continue
		out.append(id)
	return out

static func shelf_stock_target(zone: String, slot_count: int) -> int:
	var wanted := PREMIUM_STOCK if zone == ZONE_PREMIUM else SHELF_STOCK_PER_ZONE
	return mini(maxi(slot_count, 0), wanted)
