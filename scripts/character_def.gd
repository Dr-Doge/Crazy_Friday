class_name CharacterDef
## 可选角色的唯一定义处(详见《策划方案集/16-角色设计与建模规格》)。
##
## 改这里之前必读三条红线:
## 1. 主动技能**零基础数值差异**:三人的移速、失衡阈值、载重、手持容量完全一致
## 2. 被动必须服务角色主循环；数值差异应有清晰边界和可见反制。
## 3. 主动技能的代价统一用**自身失衡**支付,保证技能不可连发
##
## 技能的实际数值与实现在 char_skills.gd;本文件只负责"是什么"与"怎么显示"。

const ZHAO := "zhao"
const MA := "ma"
const LI := "li"

## 选人界面的排列顺序
const ORDER: Array[String] = [ZHAO, MA, LI]

const DEFS := {
	ZHAO: {
		"name": "赵冬梅",
		"nick": "铁腿",
		"job": "退役短道速滑运动员",
		"role": "主动进攻",
		"quote": "超市过道就是弯道。内切、贴边、卡位——规则我比谁都熟。",
		"skill": "贴地冲撞",
		"skill_cd": 20.0,
		"skill_line": "按一下,朝镜头方向飞出去撞人",
		"skill_desc": [
			"0.2秒蓄力(全场可见)后突进约 6 个购物车身位(约12.7米)",
			"撞徒步者:+55 失衡并撞飞",
			"撞推车者:+40 失衡,其车斗甩货 20%",
			"推车时使用:车头掰向突进方向,连人带车高速内切,车头撞击 ×1.5",
			"代价:自身 +20 失衡;落空则 1.2 秒硬直",
		],
		"passive": "压弯",
		"passive_line": "转弯不用减速,而且一直冲得起",
		"passive_desc": [
			"推车转向力 ×1.25,侧向抓地 ×1.2",
			"慢速也掰得动车头(低速转向下限 0.12→0.20)",
			"冲刺体力消耗 -25%(22→16.5 每秒)",
			"不含任何移速、失衡与载重增益",
		],
		"accent": Color(0.98, 0.55, 0.15),
	},
	MA: {
		"name": "马德胜",
		"nick": "老码",
		"job": "前物流仓库保管员(返聘)",
		"role": "随从压场",
		"quote": "大壮二壮！别愣着，给我把这条过道卸干净！",
		"skill": "都给我上",
		"skill_cd": 30.0,
		"skill_line": "吹哨派出两名物流徒弟,追着附近对手肘",
		"skill_desc": [
			"大壮、二壮出击8秒,搜索10米内玩家与NPC",
			"两人优先分头追击;每人最多肘4次,每肘+10失衡并打落手持货",
			"随从失衡上限60;被撞倒后喊工伤并返回马德胜身边",
			"加速购物车可直接撞倒随从,收银免战区不会被追入",
			"代价:吹哨时自身+15失衡;冷却30秒",
		],
		"passive": "班组长",
		"passive_line": "亲手命中的目标会成为徒弟们的重点卸货对象",
		"passive_desc": [
			"马德胜肘击或用商品砸中目标,标记为重点卸货6秒",
			"随从优先追标记目标,追击速度+20%,肘击间隔-15%",
			"每名随从首次命中标记目标,为马德胜恢复8体力",
			"一轮最多恢复16体力;需要马德胜先亲自开团",
		],
		"accent": Color(0.35, 0.55, 0.95),
	},
	LI: {
		"name": "李洋",
		"nick": "上链接",
		"job": "三线带货主播(直播间黄了)",
		"role": "精准截胡",
		"quote": "家人们看准了——别人车里那件，三、二、一，上链接！",
		"skill": "上链接",
		"skill_cd": 24.0,
		"skill_line": "从准星面前的购物车截走一件自己尚缺的货",
		"skill_desc": [
			"检查准星前方±35°、3.5米内最近的购物车",
			"从车内随机抓走一件自己清单上尚缺的商品",
			"双手已满时商品落在脚边;收银免战区内不可抢",
			"没找到需求货只进入4秒失误冷却",
			"成功代价:自身+20失衡;完整冷却24秒",
		],
		"passive": "主播手速",
		"passive_line": "翻别人无人看管的购物车只要0.75秒",
		"passive_desc": [
			"无人看管购物车偷取时间1.2秒→0.75秒",
			"8米内的车若含自己尚缺商品,显示链接图标但不显示具体品名",
			"搜货、装车速度不变;被撞或移动仍会打断偷取",
		],
		"accent": Color(0.95, 0.35, 0.55),
	},
}

## 非法/空 id 一律回落到首个角色,避免存档损坏导致开局崩溃
static func valid_id(id: String) -> String:
	return id if DEFS.has(id) else ORDER[0]

static func get_def(id: String) -> Dictionary:
	return DEFS[valid_id(id)]

static func index_of(id: String) -> int:
	var i := ORDER.find(valid_id(id))
	return maxi(i, 0)

static func id_at(i: int) -> String:
	return ORDER[clampi(i, 0, ORDER.size() - 1)]

## "赵冬梅「铁腿」"
static func full_name(id: String) -> String:
	var d := get_def(id)
	return "%s「%s」" % [d["name"], d["nick"]]

static func skill_name(id: String) -> String:
	return str(get_def(id)["skill"])

static func skill_cd(id: String) -> float:
	return float(get_def(id)["skill_cd"])

static func accent(id: String) -> Color:
	return get_def(id)["accent"]
