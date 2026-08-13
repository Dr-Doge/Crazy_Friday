class_name WarehouseBuddy extends Actor
## 马德胜的物流随从。常驻跟随，技能期间由主机权威搜敌、追逐与肘击。

const SEARCH_RANGE := 10.0
const LEASH_RANGE := 14.0
const ACTIVE_TIME := 8.0
const HIT_IMBALANCE := 10.0
const HIT_INTERVAL := 1.1
const MAX_HITS := 4
const BUDDY_MAX_IMBALANCE := 60.0

var leader: Player
var slot := 0
var active := false
var active_time := 0.0
var hit_count := 0
var hit_cd := 0.0
var target: Actor
var return_delay := 0.0
var restored_stamina := false

func setup(p: Player, index: int) -> void:
	leader = p
	slot = index
	build_body(Color(0.28, 0.55, 0.92) if index == 0 else Color(0.92, 0.48, 0.22),
			"大壮" if index == 0 else "二壮", 1.35)
	collision_mask = Catalog.L_WORLD | Catalog.L_CART
	add_to_group("warehouse_buddies")
	_snap_home()
	ignore_player_cart(p.cart)

## 玩家购物车与随从双向忽略，避免刚体车斗把跟随者卡进车身。
func ignore_player_cart(player_cart: Cart) -> void:
	if not is_instance_valid(player_cart):
		return
	add_collision_exception_with(player_cart)
	player_cart.add_collision_exception_with(self)

func deploy() -> void:
	if not is_instance_valid(leader) or downed:
		return
	active = true
	active_time = ACTIVE_TIME
	hit_count = 0
	hit_cd = 0.15 + slot * 0.16
	target = null
	restored_stamina = false
	Main.float_text(self, global_position + Vector3.UP * 1.9,
			"收到!" if slot == 0 else "工伤算谁的?", Color(1, 0.82, 0.35), 50)

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	if not is_instance_valid(leader):
		queue_free()
		return
	if downed:
		return_delay -= delta
		apply_motion(delta, Vector3.ZERO, 0.0)
		if return_delay <= 0.0:
			_recover_buddy()
		return
	if taser_time > 0.0:
		hand_pose = "stunned"
		apply_motion(delta, Vector3.ZERO, 0.0)
		return
	if active:
		_tick_attack(delta)
	else:
		_follow_owner(delta)

func add_imbalance(amount: float, source: Node = null) -> void:
	if downed or immune:
		return
	# 马德胜一方不会误伤自己的随从；随从只接受对手造成的失衡伤害。
	if is_friendly_source(source):
		return
	_last_hit_time = Time.get_ticks_msec() * 0.001
	imbalance = clampf(imbalance + amount, 0.0, BUDDY_MAX_IMBALANCE)
	if imbalance >= BUDDY_MAX_IMBALANCE:
		knockdown()

func is_friendly_source(source: Node) -> bool:
	if source == null or not is_instance_valid(leader):
		return false
	if source == leader:
		return true
	if source is WarehouseBuddy:
		return source.leader == leader
	if source is Cart:
		return source.cart_owner == leader or source.attached_agent == leader
	return false

func knockdown() -> void:
	if downed:
		return
	downed = true
	active = false
	target = null
	return_delay = 1.5
	_down_timer = 1.5
	body_root.rotation.x = -PI * 0.5
	collision_layer = 0
	Main.float_text(self, global_position + Vector3.UP * 1.7,
			"马师傅!工伤怎么算?!", Color(1, 0.45, 0.25), 58)

func _recover_buddy() -> void:
	downed = false
	imbalance = 0.0
	body_root.rotation.x = 0.0
	collision_layer = Catalog.L_CHAR

func _recover() -> void:
	_recover_buddy()

func _snap_home() -> void:
	if not is_instance_valid(leader):
		return
	global_position = leader.global_position + _home_offset()
	reset_physics_interpolation()

func _home_offset() -> Vector3:
	var side := -1.0 if slot == 0 else 1.0
	return leader.body_root.global_transform.basis * Vector3(side * 0.8, 0, 0.85)

func _follow_owner(delta: float) -> void:
	var home := leader.global_position + _home_offset()
	var to := home - global_position
	to.y = 0.0
	var speed := leader.buddy_move_speed()
	# 只做温和的队形追赶，不改变玩家档位，也不再用远距离瞬移追上。
	var catchup := lerpf(1.0, 1.35, clampf((to.length() - 1.2) / 6.0, 0.0, 1.0))
	apply_motion(delta, to.normalized() if to.length() > 0.2 else Vector3.ZERO, speed * catchup)

func _tick_attack(delta: float) -> void:
	active_time -= delta
	hit_cd = maxf(0.0, hit_cd - delta)
	if active_time <= 0.0 or hit_count >= MAX_HITS:
		active = false
		target = null
		return
	if not _valid_target(target):
		target = _find_target()
	if target == null:
		_follow_owner(delta)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > LEASH_RANGE or target.global_position.distance_to(leader.global_position) > LEASH_RANGE:
		target = null
		return
	if d > 1.65:
		var speed := leader.buddy_move_speed() * (1.2 if CharSkills.is_foreman_marked(target, leader) else 1.0)
		apply_motion(delta, to.normalized(), speed)
		return
	apply_motion(delta, Vector3.ZERO, 0.0)
	if hit_cd > 0.0:
		return
	hit_cd = HIT_INTERVAL * (0.85 if CharSkills.is_foreman_marked(target, leader) else 1.0)
	hit_count += 1
	target.add_imbalance(HIT_IMBALANCE, self)
	target.drop_one_held(true)
	target.push_velocity += to.normalized() * 2.2
	Main.float_text(target, target.global_position + Vector3.UP * 2.0,
			"物流式肘击 +10", Color(1, 0.72, 0.2), 58)
	if CharSkills.is_foreman_marked(target, leader) and not restored_stamina:
		restored_stamina = true
		leader.stamina = minf(100.0, leader.stamina + 8.0)

func _valid_target(a: Actor) -> bool:
	return is_instance_valid(a) and a != leader and not a.downed and not a.immune \
			and not (a is WarehouseBuddy and a.leader == leader)

func _find_target() -> Actor:
	var best: Actor = null
	var best_score := -9999.0
	for node in get_tree().get_nodes_in_group("characters"):
		if not (node is Actor):
			continue
		var a: Actor = node
		if not _valid_target(a):
			continue
		var d := leader.global_position.distance_to(a.global_position)
		if d > SEARCH_RANGE * perception_factor():
			continue
		var score := -d + (30.0 if CharSkills.is_foreman_marked(a, leader) else 0.0)
		# 两人尽量分头；没有第二目标时才夹击。
		for buddy in leader.buddies:
			if buddy != self and is_instance_valid(buddy) and buddy.target == a:
				score -= 8.0
		if score > best_score:
			best = a
			best_score = score
	return best
