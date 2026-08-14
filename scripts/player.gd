class_name Player extends Actor
## 玩家:徒步/推车两态。搜货必须脱车(策划案第五节),E键情境交互。

const WALK_SPEED := 4.2
const SPRINT_MULT := 1.55
const PUSH_FORCE := 620.0
const DRIVE_STEER := 110.0    # 驾驶转向力(过高会原地打转)
const BRAKE_MULT := 1.5       # S刹车强度
const REVERSE_MULT := 1.0     # 倒车推力比例(与前进一致)
const SEARCH_TIME := 0.8   # 货架搜货
const STEAL_TIME := 1.2    # 偷别人车里的货
const ELBOW_STAMINA := 4.0 # 肘击耗体力:一管体力=25次肘击

var stamina := 100.0
var settled_once := false   # 是否已结算
var finished := false       # 本局已完赛(结算/打烊/掉线),停止操控
var avatar_color := Color(0.25, 0.5, 0.9)
var seat_label := "你"      # 头顶名牌(玩家自定义的昵称)
var brace_time := 0.0       # Ctrl:冲击准备剩余时长
var brace_cd := 0.0
var locate_cd := 0.0        # 技能CD按人各算(联机双人)
var prop_cd := 0.0          # 右键场内商品道具冷却
var throw_selection := 0    # 购物车商品轮盘当前索引（本地UI状态）
var throw_aiming := false   # 按住右键进入越肩瞄准，松开时才真正投掷
var buddies: Array = []      # 马德胜常驻的两名物流随从

# ---------- 角色(见 character_def.gd / char_skills.gd) ----------
var char_id := CharacterDef.ORDER[0]
var char_cd := 0.0          # 空格 角色技能冷却

# 赵冬梅「贴地冲撞」状态
var dash_windup := 0.0      #蓄力剩余(全场可见的前摇)
var dash_time := 0.0        # 突进剩余
var dash_dir := Vector3.ZERO
var dash_hit := false       # 本次突进是否已命中(决定落空硬直)
var stun_time := 0.0        # 落空硬直:不能移动/肘击

# 马德胜「扎马步」状态(stance 本身在 Actor 基类上,供撞击结算读取)
var stance_time := 0.0

# 联机:远程玩家由主机模拟,输入来自网络(含客户端镜头朝向)
var remote := false
var net_move := Vector2.ZERO
var net_sprint := false
var net_brace := false
var net_interact := false
var net_cam_yaw := 0.0
var _interact_held := false

func set_net_input(mv: Vector2, sp: bool, br: bool, ih: bool, cam_yaw: float) -> void:
	net_move = mv
	net_sprint = sp
	net_brace = br
	net_interact = ih
	net_cam_yaw = cam_yaw
var main: Main

# 交互引导(由HUD显示)
var prompt_text := ""
var channel_progress := -1.0

# E键长按通道
var _channel_kind := ""       # "search" / "steal"
var _channel_target: Node = null
var _channel_time := 0.0
var _channel_need := 0.0

func _ready() -> void:
	char_id = CharacterDef.valid_id(char_id)
	build_body(avatar_color, seat_label)
	hold_capacity = 2

func is_running() -> bool:
	# 主机模拟远程玩家时不能读取房主本机的 Shift。湿滑地面等权威逻辑
	# 会调用此函数，必须使用该远程玩家最新上报的持续输入。
	if remote:
		return net_sprint and stamina > 1.0
	return Input.is_action_pressed("sprint") and stamina > 1.0

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	prompt_text = ""
	channel_progress = -1.0
	if downed or finished or (main != null and main.game_over):
		_reset_char_states()
		apply_motion(delta, Vector3.ZERO, 0.0)
		return

	var input := net_move if remote else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_interact_held = net_interact if remote else Input.is_action_pressed("interact")
	var sprint_key := net_sprint if remote else Input.is_action_pressed("sprint")
	var brace_key := net_brace if remote else Input.is_action_pressed("brace")

	locate_cd = maxf(0.0, locate_cd - delta)
	prop_cd = maxf(0.0, prop_cd - delta)
	char_cd = maxf(0.0, char_cd - delta)
	# 开发者模式:所有技能无冷却。统一在这里清零,覆盖全部赋值点。
	# 注意只清 CD,不清 dash_windup/stun_time/stance_time——那些是技能的
	# 表现与代价,清掉会让状态机可重入。
	if Main.dev_no_cd:
		locate_cd = 0.0
		prop_cd = 0.0
		char_cd = 0.0
		brace_cd = 0.0
	_tick_char_skill(delta)

	# 突进/硬直/扎马步/电击期间接管移动，均不接受方向输入。
	if dash_time > 0.0 or dash_windup > 0.0 or stun_time > 0.0 or stance_time > 0.0 or taser_time > 0.0:
		_drive_char_state(delta)
		_update_interactions()
		return

	# 冲刺:按下Shift立即提速,耗体力
	var moving := attached or input.length() > 0.1
	var sprint := sprint_key and stamina > 1.0 and moving
	if sprint:
		# 赵冬梅「压弯」:冲刺体力消耗 -25%(只碰资源耐久,不碰移速)
		var burn := 22.0 * (CharSkills.ZHAO_STAMINA_MULT if CharSkills.has_carve(self) else 1.0)
		stamina = maxf(0.0, stamina - burn * delta)
	else:
		stamina = minf(100.0, stamina + 15.0 * delta)

	# Ctrl:冲击准备1秒——期间被车撞不涨失衡(内置2.5秒冷却防常驻)
	brace_cd = maxf(0.0, brace_cd - delta)
	if brace_time > 0.0:
		brace_time -= delta
		if brace_time <= 0.0:
			braced = false
	if brace_key and brace_cd <= 0.0:
		braced = true
		brace_time = 1.0
		brace_cd = 2.5

	if attached and is_instance_valid(cart):
		_drive_cart(delta, input, sprint)
	else:
		# 徒步:移动方向跟随镜头(第三人称);远程玩家用客户端发来的镜头朝向解算
		var wish := Vector3.ZERO
		if input.length() > 0.05:
			var yaw := net_cam_yaw if remote else (main.cam_yaw if main != null else 0.0)
			var yaw_basis := Basis(Vector3.UP, yaw)
			wish = (yaw_basis * Vector3(input.x, 0, input.y)).normalized()
		var speed := WALK_SPEED * (SPRINT_MULT if sprint else 1.0) * speed_factor()
		if braced:
			speed *= 0.45
		apply_motion(delta, wish, speed)

	# 手部姿态
	if braced:
		hand_pose = "brace"
	elif attached:
		hand_pose = "push"
	elif _channel_kind != "":
		hand_pose = "channel"
	elif not held.is_empty():
		hand_pose = "carry"
	else:
		hand_pose = "idle"

	_update_channel(delta, input)
	_update_interactions()

# ---------- 角色技能状态机(见 char_skills.gd) ----------

## 角色技能计时:贴地冲撞的蓄力→突进→硬直，以及扎马步
func _tick_char_skill(delta: float) -> void:
	if stance_time > 0.0:
		stance_time -= delta
		if stance_time <= 0.0:
			stance_time = 0.0
			stance = false
	if stun_time > 0.0:
		stun_time = maxf(0.0, stun_time - delta)
	if dash_windup > 0.0:
		dash_windup -= delta
		if dash_windup <= 0.0:
			dash_windup = 0.0
			CharSkills.dash_launch(main, self)
		return
	if dash_time > 0.0:
		# 推车突进的命中由 cart 的碰撞回调结算,徒步突进在这里判定
		if not attached:
			CharSkills.dash_check_hit(main, self)
		dash_time = maxf(0.0, dash_time - delta)
		if dash_time <= 0.0:
			CharSkills.dash_finish(main, self)

## 技能占用期间的移动:三种状态都不接受方向输入
func _drive_char_state(delta: float) -> void:
	if taser_time > 0.0:
		hand_pose = "stunned"
		_cancel_channel()
		if attached and is_instance_valid(cart):
			cart.linear_velocity *= 0.55
			cart.angular_velocity *= 0.4
			_hold_cart_handle()
		else:
			apply_motion(delta, Vector3.ZERO, 0.0)
		return
	if stance_time > 0.0:
		hand_pose = "brace"
		if attached and is_instance_valid(cart):
			# 定身:不施力,并主动压住残余速度(人车一体扎住)
			cart.linear_velocity = cart.linear_velocity * 0.6
			cart.angular_velocity = cart.angular_velocity * 0.3
			global_position = cart.handle_pos()
			body_root.global_rotation = Vector3(0, cart.global_rotation.y, 0)
			velocity = Vector3.ZERO
		else:
			apply_motion(delta, Vector3.ZERO, 0.0)
		return
	if dash_time > 0.0 and not attached:
		hand_pose = "speed"
		# 必须走 apply_motion(move_and_slide):move_and_collide 不会滑动,
		# 一旦向下的分量碰到地板就会整体中止位移,横向也就跟着没了。
		apply_motion(delta, dash_dir, CharSkills.DASH_SPEED)
		return
	# 蓄力 / 硬直 / 推车突进:原地或维持车上姿态
	hand_pose = "speed" if dash_windup > 0.0 or dash_time > 0.0 else "idle"
	if attached and is_instance_valid(cart):
		_hold_cart_handle()
	else:
		apply_motion(delta, Vector3.ZERO, 0.0)

## 人挂在车把上(不施力)
func _hold_cart_handle() -> void:
	global_position = cart.handle_pos()
	body_root.global_rotation = Vector3(0, cart.global_rotation.y, 0)
	velocity = Vector3.ZERO

## 倒地/完赛时清掉技能状态,避免"定身/硬直"跨状态残留
func _reset_char_states() -> void:
	throw_aiming = false
	dash_windup = 0.0
	dash_time = 0.0
	stun_time = 0.0
	stance_time = 0.0
	stance = false
	if is_instance_valid(cart):
		cart.grip_mult = 1.0

## 大件减速:抱着电视速度减半
func speed_factor() -> float:
	for it in held:
		if it.category == Catalog.CAT_LARGE:
			return 0.5
	return 1.0

## 随从以玩家当前的移动档位为基准：抱大件、冲刺、推车速度都会同步影响。
func buddy_move_speed() -> float:
	var speed := WALK_SPEED * speed_factor()
	if is_running():
		speed *= SPRINT_MULT
	if attached and is_instance_valid(cart):
		var cart_speed := Vector2(cart.linear_velocity.x, cart.linear_velocity.z).length()
		speed = maxf(speed, cart_speed)
	if braced:
		speed *= 0.45
	return speed

# ---------- 推车 ----------

## 汽车式驾驶:W沿车头前进,A/D转向,S刹车/倒车
func _drive_cart(delta: float, input: Vector2, sprint: bool) -> void:
	# 车被撞翻(侧倾过大)时强制人车分离,避免人被"焊"在翻倒的车把上
	if cart.global_transform.basis.y.dot(Vector3.UP) < 0.35:
		detach_cart()
		return
	var throttle := -input.y   # W=+1 前进,S=-1
	var steer := input.x# A=-1 D=+1
	cart.sprinting = sprint and throttle > 0.1
	cart.sprint_level = 1.0 if cart.sprinting else move_toward(cart.sprint_level, 0.0, delta * 3.0)
	# 赵冬梅「压弯」:侧向抓地×1.2(更不漂),每帧设置以便松手/换人后自动复位
	var carve := CharSkills.has_carve(self)
	cart.grip_mult = (CharSkills.ZHAO_GRIP_MULT if carve else 1.0) * traction_factor()
	var lf := cart.load_factor()   # 满载→推力体感下降、转向变笨
	var fwd := -cart.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var fwd_speed := fwd.dot(cart.linear_velocity)
	var movement_mult := movement_factor()

	if throttle > 0.05:
		cart.apply_central_force(fwd * PUSH_FORCE * throttle * (1.7 if sprint else 1.0) * movement_mult)
	elif throttle < -0.05:
		if fwd_speed > 0.6:
			# 刹车
			cart.apply_central_force(-fwd * PUSH_FORCE * BRAKE_MULT * absf(throttle))
		else:
			# 倒车(慢速)
			cart.apply_central_force(fwd * PUSH_FORCE * REVERSE_MULT * throttle)
	if absf(steer) > 0.05:
		# 转向力与车速强挂钩:静止时几乎不转(修"原地漂移"),越快越听方向
		# 倒车时转向反打:按A行进轨迹仍向屏幕左弯(倒库直觉)
		# 「压弯」:转向力×1.25,且低速转向下限抬到0.20(慢速也掰得动车头)
		var floor_eff := CharSkills.ZHAO_STEER_FLOOR if carve else 0.12
		var steer_eff := clampf(absf(fwd_speed) / 3.5, floor_eff, 1.0)
		var steer_sign := -1.0 if fwd_speed < -0.2 else 1.0
		var steer_force := DRIVE_STEER * (CharSkills.ZHAO_STEER_MULT if carve else 1.0) * movement_mult
		cart.apply_torque(Vector3(0, -steer * steer_sign * steer_force * cart.mass * 0.12 * steer_eff * (0.4 + 0.6 * lf), 0))

	# 人挂在车把上
	global_position = cart.handle_pos()
	body_root.global_rotation = Vector3(0, cart.global_rotation.y, 0)
	velocity = Vector3.ZERO

func _on_knockdown() -> void:
	# 推车时被撞满失衡:人车分离+翻车甩货,按失衡溢出量30%起(策划案第六节)
	if attached and is_instance_valid(cart):
		detach_cart()
		cart.spill(clampf(0.3 + last_overflow / 100.0, 0.3, 1.0))
	stamina = maxf(stamina, 30.0)

# ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if remote or downed or main == null or main.game_over:
		return
	if event.is_action_pressed("interact"):
		_on_interact_pressed()
	elif event.is_action_released("interact"):
		_cancel_channel()
	elif event.is_action_pressed("drive"):
		# F:抓住/放开购物车(侧翻的车抓住时自动扶正)
		if attached:
			detach_cart()
		elif cart != null and is_instance_valid(cart) \
				and global_position.distance_to(cart.global_position) < 2.6:
			attach_cart()
	elif event.is_action_pressed("load_cart"):
		_drop_held()
	elif event.is_action_pressed("locate"):
		main.trigger_locate_skill()
	elif event.is_action_pressed("char_skill"):
		# 空格:角色专属技能(赵冬梅冲撞 / 马德胜扎马步 / 李洋促销圈)
		main.trigger_char_skill(self, _aim_dir())
	elif event.is_action_pressed("elbow"):
		# 肘击自动朝镜头面朝的方向
		do_elbow(_aim_dir())

## 出手方向:投掷读取屏幕中心准星射线；肘击只使用其中的水平分量。
func _aim_dir() -> Vector3:
	if main != null:
		var exclusions: Array[RID] = [get_rid()]
		if is_instance_valid(cart):
			exclusions.append(cart.get_rid())
		return main.cam_rig.aim_direction_from(global_position + Vector3.UP * Main.THROW_ORIGIN_HEIGHT, exclusions)
	return Vector3.ZERO

## 肘击统一入口(本地/联机远程共用):结算体力,不够抡不动
func do_elbow(dir: Vector3) -> void:
	if downed or finished:
		return
	# 突进/蓄力/硬直/扎马步期间抡不动(技能占用双手)
	if dash_windup > 0.0 or dash_time > 0.0 or stun_time > 0.0 or stance_time > 0.0 or taser_time > 0.0:
		return
	if stamina < ELBOW_STAMINA:
		Main.float_text(self, global_position + Vector3.UP * 2.2, "胳膊抡不动了...(体力不足)", Color(0.8, 0.8, 0.8))
		return
	if not attached:
		# 转身面向出肘方向(本地=镜头方向,远程=客户端镜头方向)
		if dir.length() > 0.1:
			body_root.global_rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
		elif main != null:
			body_root.global_rotation = Vector3(0, main.cam_yaw, 0)
	if try_elbow(dir):
		stamina = maxf(0.0, stamina - ELBOW_STAMINA)

func _on_interact_pressed() -> void:
	if attached:
		return
	var pick := _best_interaction()
	match pick.get("kind", ""):
		"pickup":
			var it: Item = pick["target"]
			if can_hold(it):
				it.set_held()
				take_item(it)
				Main.float_text(self, global_position + Vector3.UP * 2.0, "拾取 " + it.display_name, Color(0.6, 0.9, 0.6))
		"search":
			_start_channel("search", pick["target"], SEARCH_TIME)
		"steal":
			_start_channel("steal", pick["target"], CharSkills.steal_time_for(self))
		"load":
			_load_held_into_cart()

func _start_channel(kind: String, target: Node, need: float) -> void:
	_channel_kind = kind
	_channel_target = target
	_channel_time = 0.0
	_channel_need = need

func _cancel_channel() -> void:
	_channel_kind = ""
	_channel_target = null

func _update_channel(delta: float, input: Vector2) -> void:
	if _channel_kind == "":
		return
	# 移动、被撞离目标或目标失效则打断
	if input.length() > 0.1 or not is_instance_valid(_channel_target) or downed or attached:
		_cancel_channel()
		return
	if _channel_target is Node3D and global_position.distance_to(_channel_target.global_position) > 2.8:
		_cancel_channel()
		return
	# 搜货期间必须持续用屏幕中心准星锁住开始选择的那件商品。
	if _channel_kind == "search" and (main == null \
			or main.cam_rig.aimed_shelf_item() != _channel_target):
		_cancel_channel()
		return
	if not _interact_held:
		_cancel_channel()
		return
	_channel_time += delta
	channel_progress = _channel_time / _channel_need
	if _channel_time < _channel_need:
		if _channel_kind == "search":
			prompt_text = "搜货中……(松开取消)"
		else:
			prompt_text = "翻别人车斗中……(松开取消)"
		return
	# 完成
	match _channel_kind:
		"search":
			var it: Item = _channel_target
			if it.state == Item.ItemState.SHELVED and can_hold(it):
				it.set_held()
				take_item(it)
				main.on_player_took_from_shelf(it)
		"steal":
			var target_cart: Cart = _channel_target
			var it2 := target_cart.take_top_item()
			if it2 != null and can_hold(it2):
				it2.set_held()
				take_item(it2)
				target_cart.show_steal_alert()
				main.on_player_stole(self, target_cart, it2)
	_cancel_channel()

func _load_held_into_cart() -> void:
	if attached or held.is_empty() or cart == null or not is_instance_valid(cart):
		return
	if global_position.distance_to(cart.global_position) > 2.6:
		return
	while not held.is_empty():
		var it: Item = held.pop_back()
		var drop_pos := cart.to_global(Vector3(randf_range(-0.15, 0.15), 1.5, randf_range(-0.25, 0.25)))
		it.set_free_at(drop_pos, Vector3(0, -1.0, 0))
	Main.float_text(self, global_position + Vector3.UP * 2.0, "装车!", Color(0.6, 0.9, 0.6))

## R:把手里的东西放在脚边
func _drop_held() -> void:
	if attached or held.is_empty():
		return
	var fwd := -body_root.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	while not held.is_empty():
		var it: Item = held.pop_back()
		it.set_free_at(global_position + fwd * 0.7 + Vector3.UP * 0.9)
	Main.float_text(self, global_position + Vector3.UP * 2.0, "放下了物品", Color(0.8, 0.8, 0.8))

# ---------- 交互扫描 ----------

func _best_interaction() -> Dictionary:
	var best := {}
	var best_d := 999.0
	# 地上的散货(不含别人车斗里的)
	for node in get_tree().get_nodes_in_group("items"):
		var it: Item = node
		if not is_instance_valid(it):
			continue
		var d := global_position.distance_to(it.global_position)
		if it.state == Item.ItemState.FREE and d < 1.8 and d < best_d and not _item_in_any_basket(it):
			if can_hold(it):
				best = {"kind": "pickup", "target": it, "label": "E 拾取 " + it.display_name}
				best_d = d
	# 别人的车(无人推、有货)
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if c == cart or not is_instance_valid(c):
			continue
		var d2 := global_position.distance_to(c.global_position)
		if d2 < 2.1 and d2 < best_d and c.attached_agent == null and not c.items_in_basket().is_empty():
			if held_slots_used() < hold_capacity:
				var steal_time := CharSkills.steal_time_for(self)
				best = {"kind": "steal", "target": c, "label": "按住E 偷取车内商品(%.2f秒)" % steal_time}
				best_d = d2
	# 手里有货且在自己车旁:E 放入购物车
	if not held.is_empty() and cart != null and is_instance_valid(cart):
		var d3 := global_position.distance_to(cart.global_position)
		if d3 < 2.6 and d3 < best_d:
			best = {"kind": "load", "target": cart, "label": "E 放入购物车"}
			best_d = d3
	# 货架货不再按“离谁最近”自动选择，只允许准星射线明确命中的那一件覆盖候选。
	var aimed_item: Item = main.cam_rig.aimed_shelf_item() if main != null else null
	var aimed_horizontal_distance := INF
	if is_instance_valid(aimed_item):
		aimed_horizontal_distance = Vector2(global_position.x, global_position.z).distance_to(
				Vector2(aimed_item.global_position.x, aimed_item.global_position.z))
	if is_instance_valid(aimed_item) and aimed_horizontal_distance < 1.9:
		if can_hold(aimed_item):
			best = {"kind": "search", "target": aimed_item,
					"label": "按住E 拿取准星商品:" + aimed_item.display_name}
		else:
			best = {"kind": "search_full", "target": aimed_item,
					"label": "手上拿不下了(R先装车)"}
	return best

func _item_in_any_basket(it: Item) -> bool:
	for node in get_tree().get_nodes_in_group("carts"):
		var c: Cart = node
		if is_instance_valid(c) and c.basket_area.overlaps_body(it):
			return true
	return false

func _update_interactions() -> void:
	if channel_progress >= 0.0:
		return
	if attached:
		prompt_text = "W前进 A/D转向 S刹车 · Shift冲刺 · F放开 · 左键肘击"
		return
	var parts: Array = []
	var pick := _best_interaction()
	if pick.has("label"):
		parts.append(str(pick["label"]))
	if cart != null and is_instance_valid(cart) and global_position.distance_to(cart.global_position) < 2.6:
		parts.append("F 扶正并推车" if cart.global_transform.basis.y.dot(Vector3.UP) < 0.8 else "F 推车")
	if not held.is_empty():
		parts.append("R 放下")
	prompt_text = " · ".join(parts)
