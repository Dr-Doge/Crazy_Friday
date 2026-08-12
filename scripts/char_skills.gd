class_name CharSkills
## 三个角色的主动技能与被动的实现处(设计见《16-角色设计与建模规格》)。
##
## 为什么单独一个文件:main.gd 已经很长(拆过一轮),而角色技能是一组
## 高内聚、低耦合的规则——它们只读写 Player/Cart/Actor 上的少量状态字段。
## 全部做成静态函数,由main.trigger_char_skill() 统一分派,联机侧一律主机权威。
##
## 三个技能的代价统一是"自身失衡",因此天然不可连发(见文档§一·1.3)。

# ---------------- 赵冬梅「铁腿」· 贴地冲撞 ----------------

const DASH_WINDUP := 0.2# 下蹲蓄力(全场可见,给对手反应窗口)
## 突进持续。距离 = 速度 × 时长,所以"距离翻倍"是速度与时长各 ×1.41,
## 而不是速度直接 ×2:后者会让单帧位移过大而穿透货架/车斗薄壁。
const DASH_TIME := 0.64
const DASH_SPEED := 19.8        # 徒步突进速度(0.64秒约12.7m,约6个购物车身位)
const DASH_CART_SPEED := 15.5   # 推车突进的车速(0.64秒约9.9m;并临时放开车的软限速)
const DASH_KNOCKBACK := 9.0     # 撞飞徒步者的水平推速(与突进速度解耦,免得调速把人打飞出地图)
const DASH_SELF_IMB := 20.0     # 代价:无论命中与否
const DASH_STUN := 1.2# 落空硬直
const DASH_HIT_RANGE := 2.2# 徒步突进的命中判定半径
const DASH_HIT_PED := 55.0      # 撞徒步者
const DASH_HIT_DRIVER := 40.0   # 撞推车者
const DASH_SPILL := 0.2# 撞推车者的甩货比例
const DASH_CART_MULT := 1.5     # 推车时车头撞击倍率

# ---------------- 马德胜「老码」· 扎马步 ----------------

const STANCE_TIME := 2.0        # 完全定身,换来免疫与车斗锁死
const STANCE_MIN_IMB := 30.0    # 反击下限(撞速2.5m/s)
const STANCE_MAX_IMB := 50.0    # 反击上限(撞速 8.8m/s)
const STANCE_KICKBACK := 4.5    # 反弹冲量(每千克)

# ---------------- 李洋「上链接」· 全网最低价 ----------------

const PROMO_RADIUS := 6.0
const PROMO_TIME := 8.0
const PROMO_SLOW := 0.55        # 对手保留55%移动能力(即减速45%)
const PROMO_SELF_IMB := 20.0

# ---------------- 被动数值(受《16·一·1.4》红线约束) ----------------

## 赵冬梅「压弯」:只碰机动性与体力耐久
const ZHAO_STEER_MULT := 1.25# 推车转向力
const ZHAO_GRIP_MULT := 1.2     # 侧向抓地(抗漂)
const ZHAO_STEER_FLOOR := 0.20  # 低速转向下限(基准0.12)
const ZHAO_STAMINA_MULT := 0.75 # 冲刺体力消耗 -25%

## 马德胜「余光」:威胁预警
const THREAT_RANGE := 15.0
const THREAT_MAX := 3           # 最多同时提示3个,防止满屏箭头
const THREAT_IMMINENT := 0.4    # 这么久之后将撞上→箭头闪白

## 李洋「爆款嗅觉」/ 其他角色的通用「杀意感知」
const SNIFF_RANGE_OTHERS := 12.0  # 通用版:12米内只亮红壳(《05·三》已同步削弱)

# ================================================================ 主动技能

## 角色技能统一入口(空格 / 联机 char_skill 动作)。
## m: Main, p: Player, dir: 出手方向(镜头朝向;联机为客户端上报的朝向)
static func trigger(m, p: Player, dir: Vector3) -> void:
	if p == null or p.downed or p.finished or m.game_over:
		return
	#硬直/突进/扎马步中不可重复触发
	if p.stun_time > 0.0 or p.dash_windup > 0.0 or p.dash_time > 0.0 or p.stance_time > 0.0:
		return
	if p.char_cd > 0.0:
		if p == m.player:
			Main.float_text(m, p.global_position + Vector3.UP * 2.4,
					"%s 冷却中(%d秒)" % [CharacterDef.skill_name(p.char_id), int(ceil(p.char_cd))],
					Color(0.8, 0.8, 0.8))
		return
	var fwd := dir
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = -p.body_root.global_transform.basis.z
		fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	match CharacterDef.valid_id(p.char_id):
		CharacterDef.ZHAO:
			_start_dash(m, p, fwd)
		CharacterDef.MA:
			_start_stance(m, p)
		CharacterDef.LI:
			_drop_promo_link(m, p)

## 赵冬梅:进入蓄力,0.2秒后真正突进(蓄力期全场可见,是对手的反应窗口)
static func _start_dash(m, p: Player, fwd: Vector3) -> void:
	p.char_cd = CharacterDef.skill_cd(p.char_id)
	p.dash_windup = DASH_WINDUP
	p.dash_dir = fwd
	p.dash_hit = false
	Main.float_text(m, p.global_position + Vector3.UP * 2.4, "蹲!", Color(1, 0.65, 0.2), 70)

## 蓄力结束→真正起步(由 player.gd 每帧推进调用)
static func dash_launch(m, p: Player) -> void:
	p.dash_time = DASH_TIME
	# 代价先付:无论命中与否都吃20失衡
	p.add_imbalance(DASH_SELF_IMB, null)
	if p.attached and is_instance_valid(p.cart):
		# 连人带车突进。这里**不能用冲量**:车有 linear_damp=1.6,且 cart.gd
		# 的 _physics_process 里有一道 cap=6.0+2.8*sprint_level 的软限速,
		# 冲量给出的速度会在几帧内被钳回常规上限——这正是"按了技能只往前
		# 蠕动一小段、且改 DASH_SPEED 完全没反应"的根因(推车分支压根不读 DASH_SPEED)。
		# 所以:直接给定速度 + 在突进窗口内临时抬高限速上限。
		var c: Cart = p.cart
		# 「内切」:先把车头掰到突进方向,否则 LATERAL_GRIP 的侧向抓地会把这一冲抹平
		c.global_rotation = Vector3(0, atan2(-p.dash_dir.x, -p.dash_dir.z), 0)
		c.angular_velocity = Vector3.ZERO
		c.linear_velocity = p.dash_dir * DASH_CART_SPEED + Vector3(0, c.linear_velocity.y, 0)
		c.lift_speed_cap(DASH_CART_SPEED, DASH_TIME + 0.3)
		# 15.5m/s 下单帧位移约 0.26m,已接近车斗壁厚,开连续碰撞检测防穿透
		c.continuous_cd = true
		c.reset_physics_interpolation()
		c.hit_mult_time = DASH_TIME + 0.5
		c.hit_mult = DASH_CART_MULT
		p.dash_hit = true   # 推车突进的结算交给cart 的碰撞回调,不判定落空硬直
	Main.float_text(m, p.global_position + Vector3.UP * 2.2, "内切!!", Color(1, 0.5, 0.15), 76)

## 徒步突进期间的命中判定(每帧调用)。命中即结束突进。
static func dash_check_hit(m, p: Player) -> void:
	var best: Actor = null
	var best_d := DASH_HIT_RANGE
	for node in p.get_tree().get_nodes_in_group("characters"):
		if node == p or not (node is Actor):
			continue
		var a: Actor = node
		if a.immune or a.downed:
			continue
		var to: Vector3 = a.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.01 and p.dash_dir.dot(to.normalized()) > 0.2:
			best = a
			best_d = d
	if best == null:
		return
	p.dash_hit = true
	p.dash_time = 0.0
	var target_cart: Cart = best.get_pushed_cart()
	if target_cart != null:
		best.add_imbalance(DASH_HIT_DRIVER, p.cart if is_instance_valid(p.cart) else null)
		target_cart.spill(DASH_SPILL)
		Main.float_text(best, best.global_position + Vector3.UP * 2.2,
				"%s 贴地冲撞+%d!" % [Main.bam(), int(DASH_HIT_DRIVER)], Color(1, 0.45, 0.15), 80)
	else:
		best.push_velocity += p.dash_dir * DASH_KNOCKBACK + Vector3.UP * 2.2
		best.add_imbalance(DASH_HIT_PED, null)
		Main.float_text(best, best.global_position + Vector3.UP * 2.2,
				"%s 贴地冲撞+%d %s" % [Main.bam(), int(DASH_HIT_PED), Main.BAM_PED.pick_random()],
				Color(1, 0.4, 0.2), 84)
	if m != null:
		m.shake_for(p, 0.55)
		m.shake_for(best, 0.75)

## 突进结束:落空则进硬直(这是对手的处刑窗口)
static func dash_finish(m, p: Player) -> void:
	if p.dash_hit:
		return
	p.stun_time = DASH_STUN
	Main.float_text(m, p.global_position + Vector3.UP * 2.2, "收不住脚!!", Color(0.8, 0.8, 0.85), 70)

## 马德胜:扎马步
static func _start_stance(m, p: Player) -> void:
	p.char_cd = CharacterDef.skill_cd(p.char_id)
	p.stance_time = STANCE_TIME
	p.stance = true
	if p.attached and is_instance_valid(p.cart):
		# 定身:把车的动量按住,配合 player.gd 里的"技能期间不施力"
		p.cart.linear_velocity *= 0.15
		p.cart.angular_velocity = Vector3.ZERO
	Main.float_text(m, p.global_position + Vector3.UP * 2.4, "扎稳了!", Color(0.45, 0.75, 1.0), 76)

## 反击:被撞时由 cart.gd / actor_base.gd 调用。返回是否成功反击
static func stance_counter(victim: Actor, attacker_cart: Cart) -> bool:
	if victim == null or not victim.stance or attacker_cart == null or not is_instance_valid(attacker_cart):
		return false
	var v := attacker_cart.linear_velocity
	v.y = 0.0
	var speed := v.length()
	# 撞得越猛,自己弹得越惨(2.5m/s→30,8.8m/s→50)
	var t := clampf((speed - Cart.MIN_HIT_SPEED) / (8.8 - Cart.MIN_HIT_SPEED), 0.0, 1.0)
	var amount := lerpf(STANCE_MIN_IMB, STANCE_MAX_IMB, t)
	var away := attacker_cart.global_position - victim.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = -v
	if away.length() > 0.01:
		attacker_cart.apply_central_impulse(away.normalized() * STANCE_KICKBACK * attacker_cart.mass)
	var atk: Actor = attacker_cart.attached_agent
	if atk != null:
		atk.add_imbalance(amount, null)
		Main.float_text(atk, atk.global_position + Vector3.UP * 2.2,
				"码得住!! 反击+%d" % int(amount), Color(0.5, 0.85, 1.0), 80)
	else:
		Main.float_text(victim, victim.global_position + Vector3.UP * 2.2, "码得住!!", Color(0.5, 0.85, 1.0), 76)
	if Main.instance != null:
		Main.instance.shake_for(victim, 0.35)
		if atk != null:
			Main.instance.shake_for(atk, 0.7)
	return true

## 李洋:全网最低价。原地生成直播促销区，施法者本人免疫。
static func _drop_promo_link(m, p: Player) -> void:
	p.char_cd = CharacterDef.skill_cd(p.char_id)
	p.add_imbalance(PROMO_SELF_IMB, null)
	var pos := p.global_position
	if p.attached and is_instance_valid(p.cart):
		pos = p.cart.global_position
	m.spawn_slow_zone(pos, PROMO_RADIUS, PROMO_TIME, PROMO_SLOW, p,
			"🔥 直播间专享链接 🔥\n全网最低价!", Color(1.0, 0.18, 0.55))
	Main.float_text(m, p.global_position + Vector3.UP * 2.5,
			"家人们!全网最低价!!", Color(1.0, 0.35, 0.65), 40)
	if m != null:
		m.hud.broadcast("直播间提示:%s 发布了限时促销链接——围观可以,别想走太快~" % m.seat_name(m.players.find(p)))

# ================================================================ 被动

## 赵冬梅「压弯」是否生效
static func has_carve(p: Player) -> bool:
	return CharacterDef.valid_id(p.char_id) == CharacterDef.ZHAO

## 马德胜「余光」是否生效
static func has_sixth_sense(p: Player) -> bool:
	return CharacterDef.valid_id(p.char_id) == CharacterDef.MA

## 李洋「爆款嗅觉」是否生效
static func has_sniff(p: Player) -> bool:
	return CharacterDef.valid_id(p.char_id) == CharacterDef.LI

## 「余光」:算出朝本机玩家冲来的威胁。
## 返回 [{yaw: 世界朝向弧度, dist: 距离, imminent: bool}],最多 THREAT_MAX 个。
## 判定口径与《05》撞击判定一致(速度阈值 + 朝向点积),不引入新规则。
static func threats_for(m, p: Player) -> Array:
	var out: Array = []
	if p == null or not has_sixth_sense(p) or p.downed:
		return out
	for node in p.get_tree().get_nodes_in_group("characters"):
		if node == p or not (node is Actor):
			continue
		var a: Actor = node
		if a.downed:
			continue
		var to: Vector3 = p.global_position - a.global_position
		to.y = 0.0
		var d := to.length()
		if d > THREAT_RANGE or d < 0.2:
			continue
		# 速度取"人或其车"的较大者:推车冲过来才是真威胁
		var vel := a.velocity
		var c: Cart = a.get_pushed_cart()
		if c != null:
			vel = c.linear_velocity
		vel.y = 0.0
		var speed := vel.length()
		if speed< Cart.MIN_HIT_SPEED:
			continue
		var dir := to.normalized()
		if vel.normalized().dot(dir) < 0.55:   # 没朝你来就不报警
			continue
		out.append({
			"yaw": atan2(-dir.x, -dir.z),
			"dist": d,
			"imminent": d / maxf(speed, 0.01) <= THREAT_IMMINENT,
		})
	out.sort_custom(func(x, y): return float(x["dist"]) < float(y["dist"]))
	if out.size() > THREAT_MAX:
		out = out.slice(0, THREAT_MAX)
	return out
