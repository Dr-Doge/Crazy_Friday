class_name TutorialGuide extends RefCounted
## 九步教学关:移动→抓车→驾驶→冲刺→搜货→装车→偷窃→三技能→收银毕业。
## 每步只做"读玩家状态 → 满足即推进",不干预对局逻辑。
## 参数 m 是 Main(不写类型注解以避免 class_name 循环引用)。

## 练手无主车的摆放点(入口区旁,玩家出生点西侧)
const DUMMY_CART_POS := Vector3(MapLayout.PLAYER_SPAWN.x - 6.0, 0.2, MapLayout.PLAYER_SPAWN.z - 3.0)
const MOVE_DIST := 5.0        # ①走够多远
const DRIVE_DIST := 10.0      # ③推着走够多远
const SPRINT_TIME := 1.0      # ④冲刺持续多久

var step := 0
## 无法从玩家状态直接读出的一次性事件标记(如"偷过一件"),由 Main 事件回调写入
var marks := {}

var _m
var _origin := Vector3.ZERO
var _dist := 0.0
var _last_cart := Vector3.ZERO
var _sprint := 0.0

func _init(m) -> void:
	_m = m

## 布置练手道具:一辆无主车+ 车里两件散货(供第⑦步偷)
func setup() -> void:
	var c := Cart.create(Color(0.6, 0.6, 0.6), "无主购物车(练手)")
	_m.add_child(c)
	c.global_position = DUMMY_CART_POS
	var normals := Catalog.ids_of_cat(Catalog.CAT_NORMAL)
	for i in 2:
		var it := Item.create(normals.pick_random())
		_m.add_child(it)
		it.set_free_at(DUMMY_CART_POS + Vector3(0, 1.0 + i * 0.5, 0))
		_m.all_items.append(it)
	step = 0
	_origin = _m.player.global_position

func tick(delta: float) -> void:
	var p: Player = _m.player
	match step:
		0:
			_say("① 移动:WASD 走两步,动动鼠标转转视角")
			if p.global_position.distance_to(_origin) > MOVE_DIST:
				step = 1
		1:
			_say("② 靠近你的购物车,按 F 抓住车把")
			if p.attached and is_instance_valid(p.cart):
				step = 2
				_last_cart = p.cart.global_position
				_dist = 0.0
		2:
			_say("③ 驾驶:W 前进 · A/D 转向 · S 刹车/倒车(推着逛10米)")
			if p.attached:
				_dist += p.cart.global_position.distance_to(_last_cart)
				_last_cart = p.cart.global_position
				if _dist > DRIVE_DIST:
					step = 3
		3:
			_say("④ 按住 Shift 冲刺1秒——撞翻对手全靠它")
			if p.attached and is_instance_valid(p.cart) and p.cart.sprinting:
				_sprint += delta
				if _sprint > SPRINT_TIME:
					step = 4
		4:
			_say("⑤ 按 F 停车,走到货架前,按住 E 搜出一件商品(0.8秒)")
			if not p.held.is_empty():
				step = 5
		5:
			_say("⑥ 走回自己车旁,按 E 把商品放入购物车(R 可随时放下)")
			if is_instance_valid(p.cart) and not p.cart.items_in_basket().is_empty():
				step = 6
		6:
			_say("⑦ 入口旁停着辆无主购物车:按住 E 偷一件(1.2秒)")
			if marks.get("stole", false):
				step = 7
		7:
			_tick_skills(p)
		8:
			_say("⑨ 最后:推车开进收银通道,停稳自动扫码——扫完即毕业!")

## ⑧三技能各用一次:用CD 是否被触发来判定"用过了"
func _tick_skills(p: Player) -> void:
	if p.locate_cd > 0.0:
		marks["q"] = true
	if p.bottle_cd > 0.0:
		marks["rmb"] = true
	if p.braced:
		marks["space"] = true
	_say("⑧ 试用技能:Q 找货雷达%s · 右键 掷水瓶%s · 空格 稳住%s" % [
			_mark("q"), _mark("rmb"), _mark("space")])
	if marks.get("q", false) and marks.get("rmb", false) and marks.get("space", false):
		step = 8

func _mark(key: String) -> String:
	return "✓" if marks.get(key, false) else "…"

func _say(text: String) -> void:
	_m.hud.set_tutorial_text(text)
