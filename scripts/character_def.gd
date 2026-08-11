class_name CharacterDef
## 可选角色的唯一定义处(详见《策划方案集/16-角色设计与建模规格》)。
##
## 改这里之前必读三条红线:
## 1. 主动技能**零基础数值差异**:三人的移速、失衡阈值、载重、手持容量完全一致
## 2. 被动若提供数值,只允许碰"机动性"与"资源耐久",单项 ≤25%,综合贡献 ≤8%
##    (禁止碰:移速上限、失衡阈值、载重容量、失衡输出、搜货与偷窃时长)
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
		"role": "防御反击",
		"quote": "货不是塞进去就算完,得码。撞我?我这腰板三十年了。",
		"skill": "扎马步",
		"skill_cd": 22.0,
		"skill_line": "按一下,扎住不动,谁撞我谁倒",
		"skill_desc": [
			"2 秒内免疫撞击与肘击造成的失衡",
			"车斗锁死:一件货都甩不出去",
			"反击:撞上来的车,攻方按撞速吃 30-50 失衡并被弹开",
			"代价:2 秒完全定身",
			"注意:技能期间**照样能被偷**(按住E 偷车不受影响)",
		],
		"passive": "余光",
		"passive_line": "谁在冲你,屏幕边缘会告诉你",
		"passive_desc": [
			"15 米内有冲刺且朝你来的人,屏幕边缘浮出方向箭头",
			"对方0.4 秒后将撞到你时,箭头闪白告警",
			"与「扎马步」构成 combo:箭头闪白 → 按空格 → 对方自己倒",
			"只给信息不给数值:按不按、什么时候按全靠自己判断",
		],
		"accent": Color(0.35, 0.55, 0.95),
	},
	LI: {
		"name": "李洋",
		"nick": "上链接",
		"job": "三线带货主播(直播间黄了)",
		"role": "直接夺取",
		"quote": "三、二、一——上链接!哎这位大哥手里那个,那是我们家的库存。",
		"skill": "上链接",
		"skill_cd": 25.0,
		"skill_line": "按一下,自动钩最近的对手,一钩子把货抢过来",
		"skill_desc": [
			"自拍杆前钩 3.5 米、自动瞄准最近目标",
			"命中手上有货的人:抢走手中随机 1 件",
			"命中空手推车的人:抢走其车斗最上层 1 件",
			"代价:自身 +25 失衡",
			"代价:被抢方获得 4 秒穿墙追踪标记(他能看见你在哪)",
		],
		"passive": "爆款嗅觉",
		"passive_line": "你要的货在谁车里,全场一目了然",
		"passive_desc": [
			"任何车装有你清单上还缺的商品:全场无距离限制亮红壳",
			"车顶额外浮出具体商品名(其他角色只有 12 米内的红壳)",
			"与「上链接」构成闭环:看见货在谁车里 → 追上去钩过来",
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
