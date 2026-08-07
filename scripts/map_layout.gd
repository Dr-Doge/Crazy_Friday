class_name MapLayout
## 卖场布局的唯一坐标来源。
##
## 改地图尺寸/加宽过道只需改这里,MarketBuilder / Checkout / Granny /
## Tutorial / CameraRig 等都从本表取值,不再各自硬编码。
##
## 坐标系:x 向东为正,z 向南为正,y 向上为正。
##
## z 轴自北向南的功能分带:
##   北墙 -30┃ 生鲜/家电区 -28..-8 ┃ 爆款专区 -4..4 ┃ 日用/零食区 7..16
##   ┃ 集结缓冲带 16..24 ┃ 收银通道 24..32 ┃ 入口门厅 32..36 ┃ 南墙 36
##
## 「集结缓冲带」是 v0.14 新增的反拥堵设计:货架区南缘到收银闸机之间留出
## 8 米纵深的完全空旷带,让打烊冲刺时挤向收银口的人车有地方铺开、会车、掉头。
## 旧版这里只有 1.9 米,是拥堵的主因。

# ----------------------------------------------------------------卖场边界

const WALL_W := -40.0     # 西墙内表面 x
const WALL_E := 40.0      # 东墙内表面 x
const WALL_N := -30.0     # 北墙内表面 z
const WALL_S := 36.0      # 南墙内表面 z
const WALL_H := 3.5       # 墙高
const WALL_T := 1.0       # 墙厚

## 地板(比卖场大一圈,墙外留门厅檐廊)
const FLOOR_Y := -0.25
const FLOOR_THICK := 0.5
const FLOOR_PAD := 3.0

## 寻路网格:比地板再外扩一格,边界一圈标实心
const GRID_MIN := Vector2i(-44, -34)
const GRID_SIZE := Vector2i(88, 74)

# ---------------------------------------------------------------- 功能分带 z

const ZONE_NORTH_MIN := -28.0   # 生鲜/家电区北缘
const ZONE_NORTH_MAX := -8.0    # 生鲜/家电区南缘
const PREMIUM_Z := 0.0          # 中央爆款专区中心
const ZONE_SOUTH_MIN := 7.0# 日用/零食区北缘
const ZONE_SOUTH_MAX := 16.0    # 日用/零食区南缘

## 集结缓冲带:[BUFFER_N, GATE_IN_Z],纵深 8 米,禁止摆放任何货架/堆头
const BUFFER_N := 16.0

# ---------------------------------------------------------------- 收银区

## 两条自助收银通道的 x。间隔 14 米,两条队伍互不干扰
const LANE_XS: Array[float] = [-26.0, -12.0]
const GATE_IN_Z := 24.0# 北口闸机(入口)
const GATE_OUT_Z := 32.0        # 南口闸机(出口)
const LANE_HALF_W := 1.4        # 通道半宽(围栏内侧)
const BELT_DX := -2.1# 收银带相对通道中线的 x 偏移(放西侧不挡主走廊)

static func lane_mid_z() -> float:
	return (GATE_IN_Z + GATE_OUT_Z) * 0.5

static func lane_len() -> float:
	return GATE_OUT_Z - GATE_IN_Z

## 缓冲带纵深:货架南缘到收银闸机
static func buffer_depth() -> float:
	return GATE_IN_Z - BUFFER_N

# ------------------------------------------------- 收银动线关键点(大妈NPC 用)

## 排队等候点:北口闸机外一米
static func queue_wait_z() -> float:
	return GATE_IN_Z - 1.0

## 通道内扫码停车位
static func scan_stop_z() -> float:
	return lane_mid_z() - 0.3

## 出通道后的集散点(南口闸机外)
static func lane_out_z() -> float:
	return GATE_OUT_Z + 1.8

## 出口内侧集结点
static func exit_inner_z() -> float:
	return WALL_S - 1.5

## 出口外:走到这里就离场消失
static func exit_outer_z() -> float:
	return WALL_S + 1.5

# ---------------------------------------------------------------- 出入口

## 南墙入口门洞(东侧两个,各 5 米宽)
const DOOR_1:= Vector2(16.0, 21.0)   # x 区间
const DOOR_2 := Vector2(25.0, 30.0)

## 收银后离场出口(西南角豁口)
const EXIT_X := -35.0
const EXIT_GAP := Vector2(-38.0, -32.0)

## 玩家出生:南门内侧、东侧,远离收银通道
const PLAYER_SPAWN := Vector3(23.0, 0.0, 33.0)

## 掉出世界时的复位点(玩家/购物车/散货共用)
static func respawn_pos(y: float) -> Vector3:
	return Vector3(PLAYER_SPAWN.x, y, PLAYER_SPAWN.z - 1.0)

# ---------------------------------------------------------------- 分区矩形

## 地贴与名牌用。Rect2(x, z, w, h)
static func zone_rects() -> Dictionary:
	return {
		Catalog.ZONE_FRESH: Rect2(WALL_W + 3.0, ZONE_NORTH_MIN, 34.0, 20.0),
		Catalog.ZONE_APPLIANCE: Rect2(3.0, ZONE_NORTH_MIN, 34.0, 20.0),
		Catalog.ZONE_DAILY: Rect2(WALL_W + 3.0, ZONE_SOUTH_MIN, 34.0, 9.0),
		Catalog.ZONE_SNACK: Rect2(3.0, ZONE_SOUTH_MIN, 34.0, 9.0),
	}

# ---------------------------------------------------------------- 货架与陈列

const SHELF_LEN := 14.0
const SHELF_W := 1.2
const SHELF_H := 1.9

## 联排货架:每区两行。行距 ≥7米,双车会车 + 人群穿行都不卡
static func shelf_rows() -> Dictionary:
	return {
		Catalog.ZONE_FRESH: [Vector3(-19, 0, -24), Vector3(-19, 0, -16)],
		Catalog.ZONE_APPLIANCE: [Vector3(19, 0, -24), Vector3(19, 0, -16)],
		Catalog.ZONE_DAILY: [Vector3(-19, 0, 8.5), Vector3(-19, 0, 15.0)],
		Catalog.ZONE_SNACK: [Vector3(19, 0, 8.5), Vector3(19, 0, 15.0)],
	}

## 生鲜区卧式冰柜(顶面取货),摆在货架行以南的开阔带
const FREEZER_Z := -9.0
const FREEZER_LEN := 5.0
static func freezer_xs() -> Array[float]:
	return [-30.0, -22.0, -14.0]

## 促销堆头:全部在开阔侧翼,不进过道
static func pallets() -> Array:
	return [
		{"pos": Vector3(-33, 0, 11.5), "zone": Catalog.ZONE_DAILY},
		{"pos": Vector3(-7, 0, 11.5), "zone": Catalog.ZONE_DAILY},
		{"pos": Vector3(7, 0, 11.5), "zone": Catalog.ZONE_SNACK},
		{"pos": Vector3(33, 0, 11.5), "zone": Catalog.ZONE_SNACK},
	]

## 中央爆款专区:4 座金色展台,四面开阔,必然争抢发生在最适合冲撞的地方
static func premium_stands() -> Array[Vector3]:
	return [
		Vector3(0, 0, PREMIUM_Z - 4.0),
		Vector3(0, 0, PREMIUM_Z + 4.0),
		Vector3(-4.5, 0, PREMIUM_Z),
		Vector3(4.5, 0, PREMIUM_Z),
	]

## 家电区大件地堆(电视/跑步机),放侧翼开阔带
static func large_pads() -> Array[Vector3]:
	return [
		Vector3(7.0, 0.5, FREEZER_Z), Vector3(11.0, 0.5, FREEZER_Z),
		Vector3(29.0, 0.5, FREEZER_Z), Vector3(33.0, 0.5, FREEZER_Z),
	]

# ---------------------------------------------------------------- 事件与 NPC

## 限时特价投放点:各区主过道 + 中央专区
static func sale_points() -> Array[Vector3]:
	return [
		Vector3(-19, 0, -20), Vector3(19, 0, -20),
		Vector3(-19, 0, 11.5), Vector3(19, 0, 11.5),
		Vector3(0, 0, PREMIUM_Z),
	]

static func granny_spawns() -> Array[Vector3]:
	return [
		Vector3(-32, 0, -25), Vector3(-6, 0, -25), Vector3(32, 0, -25),
		Vector3(-32, 0, -2), Vector3(32, 0, -2),
		Vector3(-6, 0, 12), Vector3(8, 0, 12), Vector3(32, 0, 12),
	]

## 大妈囤货点(墙角,可以去抄家)
static func stash_points() -> Array[Vector3]:
	return [
		Vector3(-37, 0, -27), Vector3(37, 0, -27),
		Vector3(-37, 0, 13), Vector3(37, 0, 30),
	]

## 无主购物车(偷窃/撞击练手靶)
static func parked_cart_spawns() -> Array[Vector3]:
	return [Vector3(-13, 0, -12), Vector3(13, 0, 12)]

## 大妈无目标时的游荡范围
static func wander_x() -> Vector2:
	return Vector2(WALL_W + 5.0, WALL_E - 5.0)

static func wander_z() -> Vector2:
	return Vector2(WALL_N + 5.0, ZONE_SOUTH_MAX)

## 湿滑地面的随机生成范围(避开收银区与门厅)
static func slippery_x() -> Vector2:
	return Vector2(WALL_W + 6.0, WALL_E - 6.0)

static func slippery_z() -> Vector2:
	return Vector2(WALL_N + 6.0, ZONE_SOUTH_MAX)
