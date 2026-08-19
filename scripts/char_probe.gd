class_name CharProbe extends RefCounted
## 角色技能自检(回归资产)。
##
## 为什么必须专门做:无头模拟里没有人按键,`char_skills.gd` 的每一行都不会被执行——
## 也就是说不做这个 harness 的话,三个角色技能在自动化测试里等于**完全没有覆盖**,
## 任何一次重构都可能悄悄把它们改坏而CI 全绿。
##
## 用法:WHITEBOX_CHARTEST=1 配合 --headless,跑完打印 RESULT 并自动退出。
## 判定:所有断言通过 → RESULT=PASS。
##
## 覆盖范围:
##   主动 ×3  贴地冲撞 / 都给我上(双随从追击) / 上链接(精准截货)
##   被动 ×3  压弯 / 班组长(标记追击与体力返还) / 主播手速(偷取耗时与链接提示)

var _m
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _notes: Array[String] = []

var _dummy: Actor          # 靶子(不含 _physics_process,站着不动)
var _atk_dummy: Actor      # 反击测试里的攻方
var _atk_cart: Cart
var _far_cart: Cart        # 李洋技能与近距链接提示的测试车
var _grab_item: Item
var _zhao_imb_before := 0.0
var _dummy_imb_before := 0.0
var _test_buddies: Array[WarehouseBuddy] = []

func _init(m) -> void:
	_m = m

func setup() -> void:
	var p: Player = _m.player
	print("[char] 自检开始,本机角色初值= ", p.char_id)
	# 技能夹具不能复用正式出生区：New_Level 的入口包含购物车围栏，
	# 把目标车放在角色正前方时会与围栏相交，导致“上链接”测到地图而非技能。
	# 固定移到南侧中央空场；只移动测试实体，不改变正式对局出生点。
	if p.attached:
		p.detach_cart()
	p.global_position = Vector3(8.0, 0.1, 14.0)
	p.body_root.rotation = Vector3.ZERO
	if is_instance_valid(p.cart):
		p.cart.global_position = p.global_position + Vector3(-1.6, 0.2, -0.5)
		p.cart.linear_velocity = Vector3.ZERO
		p.cart.angular_velocity = Vector3.ZERO
	_dummy = _make_dummy("靶子", p.global_position + _fwd(p) * 1.6)
	_atk_dummy = _make_dummy("攻方", p.global_position + Vector3(3.0, 0, 3.0))
	_atk_cart = Cart.create(Color(0.7, 0.7, 0.7), "攻方的车")
	_m.add_child(_atk_cart)
	_atk_cart.global_position = _atk_dummy.global_position + Vector3(0, 0.2, -1.0)
	_atk_dummy.cart = _atk_cart
	_atk_dummy.attach_cart()

func _make_dummy(title: String, pos: Vector3) -> Actor:
	var a := Actor.new()
	_m.add_child(a)
	a.build_body(Color(0.8, 0.8, 0.8), title)
	a.global_position = pos
	return a

func _fwd(p: Player) -> Vector3:
	var f := -p.body_root.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD

# ---------------------------------------------------------------- 主循环

## 时间表:每一步在指定时刻执行一次。物理断言都留足了沉降时间。
func tick(delta: float) -> void:
	_t += delta
	var schedule := [
		[1.0, _s_dash_fire], [2.2, _s_dash_check],
		[2.6, _s_carve_setup], [3.4, _s_carve_check],
		[3.8, _s_buddy_fire], [5.5, _s_buddy_check], [7.2, _s_buddy_return_check],
		[7.5, _s_remote_running_check],
		[7.8, _s_link_setup], [8.5, _s_link_fire], [8.8, _s_link_check],
		[9.1, _s_link_hint_setup], [9.5, _s_link_hint_check],
		[10.0, _s_report],
	]
	while _step < schedule.size() and _t >= float(schedule[_step][0]):
		var fn: Callable = schedule[_step][1]
		_step += 1
		fn.call()

func _check(ok: bool, msg: String) -> void:
	if ok:
		_notes.append("  OK   " + msg)
	else:
		_fails.append(msg)
		_notes.append("  FAIL " + msg)

## 切角色前清干净技能状态,避免上一个角色的硬直/定身影响下一段
func _use_char(id: String) -> void:
	var p: Player = _m.player
	p.char_id = id
	p.char_cd = 0.0
	p.stun_time = 0.0
	p.dash_time = 0.0
	p.dash_windup = 0.0
	p.stance_time = 0.0
	p.stance = false
	p.imbalance = 0.0
	p.downed = false
	p.immune = false
	p.finished = false
	p.body_root.rotation.x = 0.0
	if is_instance_valid(p.cart):
		p.cart.hit_mult = 1.0
		p.cart.hit_mult_time = 0.0

# ---------------------------------------------------------------- ① 贴地冲撞

func _s_dash_fire() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.ZHAO)
	_dummy.global_position = p.global_position + _fwd(p) * 1.5
	_dummy.imbalance = 0.0
	_dummy_imb_before = _dummy.imbalance
	_zhao_imb_before = p.imbalance
	_m.trigger_char_skill(p, _fwd(p))
	_check(p.dash_windup > 0.0, "贴地冲撞:按下后进入可见蓄力(dash_windup>0)")
	_check(p.char_cd > 0.0, "贴地冲撞:立即进入冷却(%.0f秒)" % CharacterDef.skill_cd(CharacterDef.ZHAO))

func _s_dash_check() -> void:
	var p: Player = _m.player
	_check(p.imbalance >= _zhao_imb_before + CharSkills.DASH_SELF_IMB - 1.0,
			"贴地冲撞:自身付出+%d 失衡代价(实际 %.0f)" % [int(CharSkills.DASH_SELF_IMB), p.imbalance])
	_check(_dummy.imbalance >= CharSkills.DASH_HIT_PED - 1.0 or _dummy.downed,
			"贴地冲撞:命中徒步者 +%d 失衡(实际 %.0f, downed=%s)" % [
					int(CharSkills.DASH_HIT_PED), _dummy.imbalance, _dummy.downed])
	_check(p.dash_time <= 0.0, "贴地冲撞:突进已结束(命中即中断)")

# ---------------------------------------------------------------- ②压弯(被动)

func _s_carve_setup() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.ZHAO)
	if is_instance_valid(p.cart):
		p.global_position = p.cart.handle_pos()
		p.attach_cart()

func _s_carve_check() -> void:
	var p: Player = _m.player
	_check(p.attached, "压弯:测试前置——已挂上购物车")
	if p.attached and is_instance_valid(p.cart):
		_check(is_equal_approx(p.cart.grip_mult, CharSkills.ZHAO_GRIP_MULT),
				"压弯:侧向抓地×%.2f 已生效(实际 %.2f)" % [CharSkills.ZHAO_GRIP_MULT, p.cart.grip_mult])
	# 换成非赵冬梅后必须复位,否则被动会泄漏给所有角色
	p.char_id = CharacterDef.MA
	_m.player._drive_cart(0.016, Vector2.ZERO, false)
	_check(is_equal_approx(p.cart.grip_mult, 1.0),
			"压弯:换角色后抓地系数复位(实际 %.2f)" % p.cart.grip_mult)
	# 体力口径:压弯只减冲刺消耗,不碰回复与肘击
	_check(CharSkills.ZHAO_STAMINA_MULT < 1.0 and CharSkills.ZHAO_STAMINA_MULT >= 0.75,
			"压弯:冲刺体力消耗系数 %.2f(≤25%% 的红线内)" % CharSkills.ZHAO_STAMINA_MULT)
	p.detach_cart()

# ---------------------------------------------------------------- ③ 都给我上 / 班组长

func _s_buddy_fire() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.MA)
	p.stamina = 70.0
	_dummy.global_position = p.global_position + _fwd(p) * 1.5
	_dummy.imbalance = 0.0
	CharSkills.mark_foreman_target(_dummy, p)
	for i in 2:
		var buddy := WarehouseBuddy.new()
		_m.add_child(buddy)
		buddy.setup(p, i)
		p.buddies.append(buddy)
		_m.warehouse_buddies.append(buddy)
		_test_buddies.append(buddy)
	_check(_test_buddies[0].get_collision_exceptions().has(p.cart),
			"随从:忽略玩家购物车碰撞，避免卡进车身")
	_check(is_equal_approx(p.buddy_move_speed(), Player.WALK_SPEED),
			"随从:基础移动速度绑定玩家步行速度")
	_m.trigger_char_skill(p, _fwd(p))
	_check(_test_buddies.all(func(b): return b.active), "都给我上:两名随从同时出动")
	_check(p.imbalance >= CharSkills.BUDDY_SELF_IMB - 1.0,
			"都给我上:自身付出 +%d 失衡" % int(CharSkills.BUDDY_SELF_IMB))
	_check(p.char_cd > 0.0, "都给我上:进入 30 秒冷却")

func _s_buddy_check() -> void:
	var p: Player = _m.player
	_check(_dummy.imbalance >= WarehouseBuddy.HIT_IMBALANCE or _dummy.downed,
			"都给我上:随从会追击并肘击目标(实际失衡 %.0f)" % _dummy.imbalance)
	_check(p.stamina > 70.0, "班组长:随从首次命中标记目标返还体力(实际 %.0f)" % p.stamina)
	var buddy := _test_buddies[0]
	var friendly_before := buddy.imbalance
	buddy.add_imbalance(30.0, p)
	buddy.add_imbalance(30.0, _test_buddies[1])
	_check(is_equal_approx(buddy.imbalance, friendly_before),
			"随从:免疫所属马德胜及同队随从造成的所有失衡伤害")
	buddy.add_imbalance(WarehouseBuddy.BUDDY_MAX_IMBALANCE, _dummy)
	_check(buddy.downed, "随从:60 失衡时被击倒并开始返场")

func _s_buddy_return_check() -> void:
	var buddy := _test_buddies[0]
	_check(not buddy.downed and buddy.imbalance == 0.0, "随从:倒地 1.5 秒后回到马德胜身边")

# ---------------------------------------------------------------- ④ 上链接 / 主播手速

func _s_link_setup() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.LI)
	if p.attached:
		p.detach_cart()
	for buddy in _test_buddies:
		buddy.active = false
	# 玩家车必须与链接目标车完全分离，否则两个BasketArea重叠时，
	# missing_list_ids会正确地把目标商品视为“玩家已经拥有”，测试反而无法施放技能。
	if is_instance_valid(p.cart):
		p.cart.freeze = true
		p.cart.global_position = p.global_position - _fwd(p) * 6.0 + Vector3.UP * 0.2
	_atk_cart.linear_velocity = Vector3.ZERO
	_atk_cart.freeze = true
	_dummy.global_position = p.global_position + Vector3(20.0, 0, 20.0)
	_atk_dummy.global_position = p.global_position + Vector3(-20.0, 0, 20.0)
	_far_cart = Cart.create(Color(0.5, 0.5, 0.5), "链接测试车")
	_m.add_child(_far_cart)
	_far_cart.freeze = true
	_far_cart.global_position = p.global_position + _fwd(p) * 2.6 + Vector3.UP * 0.2
	var want_id := str(_m.pdata[0]["list"][0]["id"])
	_grab_item = Item.create(want_id)
	_m.add_child(_grab_item)
	_m.all_items.append(_grab_item)
	_grab_item.set_free_at(_far_cart.to_global(Vector3(0, 0.95, 0)))
	_grab_item.freeze = true

func _s_link_fire() -> void:
	var p: Player = _m.player
	_check(_far_cart.items_in_basket().has(_grab_item), "上链接:测试商品已进入目标车斗")
	_check(not p.downed and p.char_id == CharacterDef.LI and p.char_cd <= 0.0,
			"上链接:施放者状态允许使用技能")
	var fwd := _fwd(p)
	_m.trigger_char_skill(p, fwd)

func _s_link_check() -> void:
	var p: Player = _m.player
	_check(p.held.has(_grab_item) or _grab_item.global_position.distance_to(p.global_position) < 2.0,
			"上链接:从面前购物车截走一件自己需要的商品")
	_check(p.imbalance >= CharSkills.LINK_SELF_IMB - 1.0, "上链接:成功时自身 +20 失衡")
	_check(p.char_cd > 20.0, "上链接:成功后进入完整冷却")
	_check(is_equal_approx(CharSkills.steal_time_for(p), CharSkills.LI_STEAL_TIME),
			"主播手速:拿取耗时缩短至 %.2f 秒" % CharSkills.LI_STEAL_TIME)

func _s_link_hint_setup() -> void:
	var p: Player = _m.player
	# 将测试货放回车内并验证 8 米链接提示及距离边界。
	if p.held.has(_grab_item):
		p.held.erase(_grab_item)
	_far_cart.global_position = p.global_position + Vector3(7.0, 0.2, 0)
	_grab_item.set_free_at(_far_cart.to_global(Vector3(0, 0.95, 0)))
	_grab_item.freeze = true

func _s_link_hint_check() -> void:
	var p: Player = _m.player
	_m._apply_highlights_local()
	_check(_far_cart.highlight_mesh.visible, "主播手速:8 米内需求车亮红壳")
	_check(_far_cart.hot_label != null and _far_cart.hot_label.text == "🔗", "主播手速:仅显示链接图标而非商品名")
	_far_cart.global_position = p.global_position + Vector3(9.0, 0.2, 0)
	_m._apply_highlights_local()
	_check(not _far_cart.highlight_mesh.visible, "主播手速:超过 8 米不再提示")

# ---------------------------------------------------------------- ③ 扎马步

func _s_stance_fire() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.MA)
	# 车斗"锁死"的前提是他正在推这辆车:松了手的车是无主车,被撞散是合理的,
	# 所以这里必须先挂上车再扎马步(否则测的是一个不存在的语义)
	p.global_position = p.cart.handle_pos()
	p.attach_cart()
	# 车斗里塞一件货,用来验证"锁死"
	_grab_item = Item.create("chips")
	_m.add_child(_grab_item)
	_m.all_items.append(_grab_item)
	_grab_item.set_free_at(p.cart.to_global(Vector3(0, 0.95, 0)))
	_m.trigger_char_skill(p, _fwd(p))
	_check(p.stance and p.stance_time > 0.0, "扎马步:进入姿态(stance=true)")
	_check(p.cart.is_locked(), "扎马步:推车时车斗进入锁死状态")

func _s_stance_check() -> void:
	var p: Player = _m.player
	# 免疫:撞击与肘击都不该涨失衡
	var before := p.imbalance
	p.add_imbalance(45.0, _atk_cart)
	_check(is_equal_approx(p.imbalance, before), "扎马步:撞击失衡被免疫(%.0f→%.0f)" % [before, p.imbalance])
	# 车斗锁死:甩货与肘飞都该失败
	var n_before := p.cart.items_in_basket().size()
	p.cart.spill(1.0)
	var ejected := p.cart.eject_random_item()
	_check(p.cart.items_in_basket().size() == n_before and ejected == null,
			"扎马步:车斗锁死,%d 件货一件没掉" % n_before)
	# 反击:攻方吃30-50 失衡并被弹开
	_atk_dummy.imbalance = 0.0
	_atk_cart.linear_velocity = (p.global_position - _atk_cart.global_position).normalized() * 6.0
	var countered := CharSkills.stance_counter(p, _atk_cart)
	_check(countered, "扎马步:反击成功触发")
	_check(_atk_dummy.imbalance >= CharSkills.STANCE_MIN_IMB - 1.0,
			"扎马步:攻方吃 %d-%d 失衡(实际 %.0f)" % [
					int(CharSkills.STANCE_MIN_IMB), int(CharSkills.STANCE_MAX_IMB), _atk_dummy.imbalance])
	# 弱点自检:扎马步**不防偷**,这是他的指定反制手段
	var stolen := p.cart.take_top_item()
	_check(stolen != null, "扎马步:仍然可以被偷(take_top_item 不受影响)——设计如此")
	p.detach_cart()

# ---------------------------------------------------------------- ④ 余光(被动)

## 设置与断言合在一步:threats_for只读速度字段,
## 若隔几帧再断言,linear_damp 会把车速衰减到阈值以下,测出来的是阻尼而不是技能
func _s_sense_setup() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.MA)
	# 让攻方的车朝玩家高速冲来:这正是「余光」该报警的工况
	_atk_cart.global_position = p.global_position + Vector3(6.0, 0.2, 0)
	_atk_dummy.global_position = _atk_cart.handle_pos()
	var to_me := (p.global_position - _atk_cart.global_position).normalized()
	_atk_cart.linear_velocity = to_me * 6.5
	var threats := CharSkills.threats_for(_m, p)
	_check(threats.size() > 0, "余光:侦测到朝我冲来的威胁(%d 个)" % threats.size())
	if threats.size() > 0:
		var t: Dictionary = threats[0]
		_check(float(t["dist"]) <= CharSkills.THREAT_RANGE,
				"余光:威胁在 %.1f 米内(上限 %.0f)" % [float(t["dist"]), CharSkills.THREAT_RANGE])
	# 背对着走开的人不该报警(否则满屏箭头)
	_atk_cart.linear_velocity = -to_me * 6.5
	_check(CharSkills.threats_for(_m, p).is_empty(), "余光:没朝我来的人不报警")
	_atk_cart.linear_velocity = to_me * 6.5
	p.char_id = CharacterDef.LI
	_check(CharSkills.threats_for(_m, p).is_empty(), "余光:非马德胜不获得预警(角色专属)")

func _s_sense_check() -> void:
	pass

## 联机遥控玩家不能读取主机键盘状态，否则湿滑区抓地等依赖“是否冲刺”的逻辑会串台。
func _s_remote_running_check() -> void:
	var p: Player = _m.player
	var old_remote := p.remote
	var old_sprint := p.net_sprint
	var old_stamina := p.stamina
	p.remote = true
	p.stamina = 100.0
	p.net_sprint = true
	_check(p.is_running(), "联机输入:遥控玩家按网络冲刺状态判定为奔跑")
	p.net_sprint = false
	_check(not p.is_running(), "联机输入:遥控玩家不受主机键盘冲刺键串扰")
	p.remote = old_remote
	p.net_sprint = old_sprint
	p.stamina = old_stamina

# ---------------------------------------------------------------- ⑤ 全网最低价

func _s_promo_setup() -> void:
	var p: Player = _m.player
	_use_char(CharacterDef.LI)
	p.slow_time = 0.0
	p.slow_factor = 1.0
	_dummy.slow_time = 0.0
	_dummy.slow_factor = 1.0
	_dummy.global_position = p.global_position + Vector3(3.0, 0, 0)

func _s_promo_fire() -> void:
	var p: Player = _m.player
	p.imbalance = 0.0
	_m.trigger_char_skill(p, _fwd(p))

func _s_promo_check() -> void:
	var p: Player = _m.player
	var zones: Array = _m.get_children().filter(func(n): return n is SlowZone)
	_check(not zones.is_empty(), "全网最低价:原地生成直播促销减速区")
	_check(is_equal_approx(p.movement_factor(), 1.0), "全网最低价:李洋本人免疫自己的减速区")
	_check(_dummy.movement_factor() <= CharSkills.PROMO_SLOW + 0.01,
			"全网最低价:范围内对手保留约%d%%移动能力" % int(CharSkills.PROMO_SLOW * 100.0))
	_check(p.imbalance >= CharSkills.PROMO_SELF_IMB - 1.0,
			"全网最低价:自身付出 +%d 失衡代价(实际 %.0f)" % [int(CharSkills.PROMO_SELF_IMB), p.imbalance])
	_check(p.char_cd > 0.0, "全网最低价:进入冷却")

# ---------------------------------------------------------------- ⑥ 爆款嗅觉(被动)

func _s_sniff_setup() -> void:
	var p: Player = _m.player
	# 20 米外(远超通用版的 12 米门槛)放一辆装着"我还缺的货"的车
	_far_cart = Cart.create(Color(0.5, 0.5, 0.5), "远处的车")
	_m.add_child(_far_cart)
	_far_cart.global_position = p.global_position + Vector3(0, 0.2, -20.0)
	var want_id := str(_m.pdata[0]["list"][0]["id"])
	var it := Item.create(want_id)
	_m.add_child(it)
	_m.all_items.append(it)
	it.set_free_at(_far_cart.to_global(Vector3(0, 0.95, 0)))

func _s_sniff_check() -> void:
	var p: Player = _m.player
	p.char_id = CharacterDef.LI
	_m._apply_highlights_local()
	var lit_for_li: bool = _far_cart.highlight_mesh.visible
	var named: bool = _far_cart.hot_label != null and _far_cart.hot_label.visible
	p.char_id = CharacterDef.MA
	_m._apply_highlights_local()
	var lit_for_ma: bool = _far_cart.highlight_mesh.visible
	_check(lit_for_li, "爆款嗅觉:20 米外的车也亮红壳(李洋无距离限制)")
	_check(named, "爆款嗅觉:车顶浮出具体商品名")
	_check(not lit_for_ma, "爆款嗅觉:非李洋在 %.0f 米外看不到红壳(通用版已削弱)" % CharSkills.SNIFF_RANGE_OTHERS)

# ---------------------------------------------------------------- 报告

func _s_report() -> void:
	print("[char] ---------------- 角色技能自检 ----------------")
	for line in _notes:
		print("[char] ", line)
	print("[char] 断言 %d 条,失败 %d 条" % [_notes.size(), _fails.size()])
	if _fails.is_empty():
		print("[char] RESULT=PASS")
	else:
		print("[char] RESULT=FAIL")
		for f in _fails:
			print("[char] 失败项: ", f)
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
