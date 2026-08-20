class_name TutorialGuide extends RefCounted
## 五房串联教学导演：真实玩法负责操作结果，本类只布置、监听、开门与复位。

const MOVE_DIST := 5.0
const DRIVE_DIST := 10.0
const SPRINT_TIME := 1.0
const TARGET_IDS := ["tissue", "thermos", "drone"]

var marks := {}
var room := 0
var stage := 0

var _m
var _data: Dictionary
var _gates: Array = []
var _points: Dictionary
var _waiting_exit := false
var _origin := Vector3.ZERO
var _last_cart := Vector3.ZERO
var _drive_dist := 0.0
var _sprint_time := 0.0
var _room_time := 0.0
var _stage_time := 0.0
var _scan_time := 0.0
var _selection_start := 0
var _combat_retaliate_cd := 0.0

var _goods_a: Item
var _goods_b: Item
var _goods_decoy: Item
var _steal_cart: Cart
var _combat_item: Item
var _combat_dummy: TutorialOpponent
var _brace_cart: Cart
var _lab_dummy: TutorialOpponent
var _lab_cart: Cart
var _final_cart: Cart
var _final_dummy: TutorialOpponent

func _init(m) -> void:
	_m = m

func setup() -> void:
	_data = _m.tutorial_data
	_gates = _data.get("gates", [])
	_points = _data.get("points", {})
	for gate in _gates:
		TutorialRoomBuilder.set_gate_open(gate, false)
	room = 0
	stage = 0
	_origin = _m.player.global_position
	_last_cart = _m.player.cart.global_position
	_prepare_goods_room()
	_prepare_combat_room()
	_prepare_lab_room()
	_enter_room(0)
	var preview := OS.get_environment("WHITEBOX_TUTORIAL_PREVIEW")
	if preview != "":
		_preview_room(clampi(int(preview), 0, 4))

func tick(delta: float) -> void:
	if not is_instance_valid(_m.player):
		return
	_room_time += delta
	_stage_time += delta
	_combat_retaliate_cd = maxf(0.0, _combat_retaliate_cd - delta)
	if _waiting_exit:
		_tick_waiting_for_exit()
		return
	match room:
		0: _tick_drive(delta)
		1: _tick_goods()
		2: _tick_combat()
		3: _tick_lab()
		4: _tick_final(delta)

func _tick_waiting_for_exit() -> void:
	var gate_z: float = TutorialRoomBuilder.GATE_ZS[room]
	_say("房间完成 ✓  推车穿过绿色门，进入下一项训练")
	if _m.player.global_position.z < gate_z - 1.0:
		room += 1
		stage = 0
		_waiting_exit = false
		_enter_room(room)

func _enter_room(index: int) -> void:
	_room_time = 0.0
	_stage_time = 0.0
	marks.clear()
	_m.hud.set_tutorial_room(index)
	match index:
		0:
			_origin = _m.player.global_position
		1:
			_reset_goods_items()
		2:
			_reset_combat()
		3:
			_prepare_lab_inventory()
			_selection_start = _m.player.throw_selection
		4:
			_prepare_final()

func _preview_room(index: int) -> void:
	for i in mini(index, _gates.size()):
		TutorialRoomBuilder.set_gate_open(_gates[i], true)
	room = index
	stage = 0
	_waiting_exit = false
	var center_z: float = float(TutorialRoomBuilder.ROOM_CENTERS[index]) + 8.0
	_m.player.global_position = Vector3(0, 0.05, center_z)
	_m.player.cart.global_position = Vector3(-2.0, 0.2, center_z - 1.0)
	_enter_room(index)

func reset_current_room() -> void:
	var p: Player = _m.player
	if p.attached:
		p.detach_cart()
	p.drop_all_held(false)
	p.imbalance = 0.0
	p.stamina = 100.0
	p.char_cd = 0.0
	p.locate_cd = 0.0
	p.prop_cd = 0.0
	p.braced = false
	var center_z: float = float(TutorialRoomBuilder.ROOM_CENTERS[room]) + 8.0
	p.global_position = Vector3(0, 0.05, center_z)
	p.velocity = Vector3.ZERO
	p.cart.right_up()
	p.cart.global_position = Vector3(-2.0, 0.2, center_z - 1.0)
	p.cart.linear_velocity = Vector3.ZERO
	p.cart.angular_velocity = Vector3.ZERO
	if room < _gates.size():
		TutorialRoomBuilder.set_gate_open(_gates[room], false)
	_waiting_exit = false
	stage = 0
	_enter_room(room)
	Main.float_text(_m, p.global_position + Vector3.UP * 2.4,
			"当前房间已重置", Color(0.4, 0.8, 1.0), 62)

func _advance() -> void:
	stage += 1
	_stage_time = 0.0

func _complete_room() -> void:
	if room >= _gates.size():
		return
	TutorialRoomBuilder.set_gate_open(_gates[room], true)
	_waiting_exit = true
	Main.float_text(_m, _m.player.global_position + Vector3.UP * 2.5,
			"房间 %02d 完成!" % (room + 1), Color(0.35, 1.0, 0.5), 72)

# ---------------------------------------------------------------- 房间01

func _tick_drive(delta: float) -> void:
	var p: Player = _m.player
	match stage:
		0:
			_say("01-1  徒步使用第三人称 · WASD移动 · 鼠标观察  %s" % _progress(p.global_position.distance_to(_origin), MOVE_DIST))
			if p.global_position.distance_to(_origin) >= MOVE_DIST:
				_advance()
		1:
			_say("01-2  靠近自己的购物车，按 F 抓住车把")
			if p.attached:
				_last_cart = p.cart.global_position
				_drive_dist = 0.0
				_advance()
		2:
			_say("01-3  W前进 · A/D转向 · S刹车/倒车  %s" % _progress(_drive_dist, DRIVE_DIST))
			if p.attached:
				_drive_dist += p.cart.global_position.distance_to(_last_cart)
				_last_cart = p.cart.global_position
				if _drive_dist >= DRIVE_DIST:
					_advance()
		3:
			_say("01-4  按住 Shift 冲刺1秒，再把车开到前方门口  %s" % _progress(_sprint_time, SPRINT_TIME))
			if p.attached and p.cart.sprinting:
				_sprint_time += delta
			if _sprint_time >= SPRINT_TIME:
				_complete_room()

# ---------------------------------------------------------------- 房间02

func _prepare_goods_room() -> void:
	_goods_a = _spawn_item("tissue", _points["goods_a"], true)
	_goods_b = _spawn_item("thermos", _points["goods_b"], true)
	_goods_decoy = _spawn_item("treadmill", _points["goods_decoy"], true)

func _reset_goods_items() -> void:
	if not is_instance_valid(_goods_a):
		_goods_a = _spawn_item("tissue", _points["goods_a"], true)
	else:
		_goods_a.set_shelved(_points["goods_a"])
	if not is_instance_valid(_goods_b):
		_goods_b = _spawn_item("thermos", _points["goods_b"], true)
	else:
		_goods_b.set_shelved(_points["goods_b"])
	if not is_instance_valid(_goods_decoy):
		_goods_decoy = _spawn_item("treadmill", _points["goods_decoy"], true)
	else:
		_goods_decoy.set_shelved(_points["goods_decoy"])

func _tick_goods() -> void:
	var p: Player = _m.player
	match stage:
		0:
			_say("02-1  按F放车保持第三人称 · 白点对准卫生纸后长按E（右键可切换越肩观察）")
			if marks.get("shelf:tissue", false):
				_advance()
		1:
			_say("02-2  按常规做法：回到自己的车旁按 E，把卫生纸装进真实车斗")
			if _cart_has(p.cart, "tissue"):
				_advance()
		2:
			_say("02-3  故意拿起红色区域里的非目标折叠电动车，体验大件占满双手")
			if p.held.has(_goods_decoy):
				_advance()
		3:
			_say("02-4  拿错大件时不必折返购物车：按 R 原地放下折叠电动车，立刻腾出双手")
			# 玩家若仍按习惯把红叉练习品装车，立即退回手中并给出明确反馈，
			# 避免教程无响应；只有R丢下才算学会快速腾手。
			if marks.get("dropped_decoy", false):
				_advance()
			elif _item_inside_cart(p.cart, _goods_decoy):
				p.take_item(_goods_decoy)
				marks["decoy_cart_redirect"] = true
				Main.float_text(_m, p.global_position + Vector3.UP * 2.2,
						"这是故意拿错的练习品，请按 R 丢下", Color(1.0, 0.45, 0.2), 62)
		4:
			_say("02-5  按 Q 使用找货雷达，寻找被遮住的第二件商品")
			if p.locate_cd > 0.0:
				_advance()
		5:
			_say("02-6  搜取被高亮的保温杯并装入自己的购物车")
			if _cart_has(p.cart, "thermos"):
				_complete_room()

# ---------------------------------------------------------------- 房间03

func _prepare_combat_room() -> void:
	_steal_cart = Cart.create(Color(0.55, 0.55, 0.58), "无人训练车")
	_m.add_child(_steal_cart)
	_steal_cart.global_position = _points["steal_cart"]
	_combat_item = _add_item_to_cart(_steal_cart, "thermos")
	_combat_dummy = TutorialOpponent.new()
	_m.add_child(_combat_dummy)
	_combat_dummy.setup("训练黄牛")
	_combat_dummy.global_position = _points["combat_dummy"]
	_brace_cart = Cart.create(Color(0.9, 0.42, 0.15), "撞击训练车")
	_m.add_child(_brace_cart)
	_brace_cart.global_position = _points["brace_cart"]

func _reset_combat() -> void:
	if is_instance_valid(_steal_cart):
		_steal_cart.right_up()
		_steal_cart.global_position = _points["steal_cart"]
		_steal_cart.linear_velocity = Vector3.ZERO
	if is_instance_valid(_combat_dummy):
		_combat_dummy.cancel_cart_theft()
		_combat_dummy.protect_held_until_downed = false
		_combat_dummy.drop_all_held(false)
		_combat_dummy.downed = false
		_combat_dummy.body_root.rotation.x = 0.0
		_combat_dummy.global_position = _points["combat_dummy"]
		_combat_dummy.imbalance = 40.0
		_combat_dummy.protect_held_until_downed = true
	if is_instance_valid(_brace_cart):
		_brace_cart.right_up()
		_brace_cart.global_position = _points["brace_cart"]
		_brace_cart.linear_velocity = Vector3.ZERO
	if not is_instance_valid(_combat_item):
		_combat_item = _add_item_to_cart(_steal_cart, "thermos")
	else:
		_place_item_in_cart(_combat_item, _steal_cart, Vector2.ZERO)

func _tick_combat() -> void:
	var p: Player = _m.player
	match stage:
		0:
			_say("03-1  靠近灰色无人车，长按 E 顺走保温杯")
			if marks.get("stole", false):
				_advance()
		1:
			_say("03-2  把刚偷到的保温杯放进自己的车。注意：其他人也能偷取你车里的商品")
			if _cart_has_item(p.cart, _combat_item):
				_combat_dummy.start_cart_theft(p.cart, _combat_item)
				_advance()
		2:
			_say("03-3  观察训练黄牛走到你的购物车偷货，再带回原位；离车搜货时要留意车斗")
			if is_instance_valid(_combat_dummy) and _combat_dummy.theft_completed:
				if is_instance_valid(_combat_dummy.stolen_item):
					_combat_item = _combat_dummy.stolen_item
				_advance()
		3:
			_say("03-4  黄牛偷走了你的商品：白点对准他，按左键肘击以累计失衡")
			if is_instance_valid(_combat_dummy) and _combat_dummy.imbalance > 40.5:
				_advance()
		4:
			_say("03-5  继续肘击，把失衡槽打满；被偷商品只有对方倒地后才能夺回")
			if is_instance_valid(_combat_dummy) and _combat_dummy.imbalance >= 60.0 \
					and _combat_retaliate_cd <= 0.0 and not _combat_dummy.downed \
					and _combat_dummy.global_position.distance_to(p.global_position) < 2.4:
				_combat_dummy.try_elbow((p.global_position - _combat_dummy.global_position).normalized())
				_combat_retaliate_cd = 1.1
			if marks.get("combat_downed", false):
				_advance()
		5:
			_say("03-6  捡起掉落的保温杯，回到自己的车旁按 E 装车")
			if _cart_has(p.cart, "thermos"):
				_advance()
		6:
			_say("03-7  按住 Ctrl 稳住，抵挡一次训练车撞击")
			if p.braced:
				var before := p.imbalance
				_brace_cart.global_position = p.global_position + Vector3.RIGHT * 2.0
				_brace_cart.linear_velocity = Vector3.LEFT * 5.0
				p.hit_by_cart(_brace_cart)
				if p.imbalance <= before + 0.01:
					_complete_room()

# ---------------------------------------------------------------- 房间04

func _prepare_lab_room() -> void:
	_lab_dummy = TutorialOpponent.new()
	_m.add_child(_lab_dummy)
	_lab_dummy.setup("效果测试员")
	_lab_dummy.protect_held_until_downed = false
	_lab_dummy.global_position = _points["lab_dummy"]
	_lab_cart = Cart.create(Color(0.25, 0.72, 0.9), "有人训练车")
	_m.add_child(_lab_cart)
	_lab_cart.global_position = _points["lab_cart"]
	_lab_cart.attached_agent = _lab_dummy

func _prepare_lab_inventory() -> void:
	# 卫生纸是订单货，不进入弹药轮盘；其余都是额外商品，供连续四步投掷训练。
	for id in ["tissue", "cola", "detergent", "candy", "kettle", "drone"]:
		_add_to_player_cart(id)
	# 李洋技能需要目标车内有一件自己仍缺的商品。
	_add_item_to_cart(_lab_cart, "drone")
	_selection_start = _m.player.throw_selection

func _tick_lab() -> void:
	var p: Player = _m.player
	match stage:
		0:
			_say("04-1  按F驾驶并滚动滚轮：轮盘只显示车内不在购物清单上的额外商品")
			if p.attached and (p.throw_selection != _selection_start or marks.get("wheel", false)):
				_advance()
		1:
			_say("04-2  选择任意商品，按住右键用白点和抛物线瞄准测试员，松开直击角色（×1.5）")
			if marks.get("throw_actor", false):
				_advance()
		2:
			_say("04-3  再投一件商品砸中蓝色购物车车体（×1.0）")
			if marks.get("throw_cart", false):
				_advance()
		3:
			_say("04-4  选择洗衣液或卫生纸，投向地面观察首次落点范围效果")
			if marks.get("ground_effect", false):
				_advance()
		4:
			_say("04-5  选择无人机直击测试员，触发电击定身")
			if marks.get("taser", false):
				_prepare_role_skill()
				_advance()
		5:
			_say(_role_skill_prompt(p))
			if marks.get("role_skill", false):
				_complete_room()

func _prepare_role_skill() -> void:
	var p: Player = _m.player
	p.char_cd = 0.0
	if p.char_id != CharacterDef.LI:
		return
	# 李洋只能截自己尚缺的货：清掉本人车内教学无人机，保留蓝色目标车内那件。
	for it in p.cart.items_in_basket():
		if is_instance_valid(it) and it.item_id == "drone":
			it.set_free_at(Vector3(10.0, 1.0, -84.0))
	for i in range(p.held.size() - 1, -1, -1):
		if p.held[i].item_id == "drone":
			var held_drone: Item = p.held.pop_at(i)
			held_drone.set_free_at(Vector3(10.0, 1.0, -84.0))

func _role_skill_prompt(p: Player) -> String:
	match p.char_id:
		CharacterDef.ZHAO:
			return "04-6  用白点对准测试员，按空格施放贴地冲撞"
		CharacterDef.MA:
			return "04-6  靠近测试员，按空格派出大壮/二壮"
		CharacterDef.LI:
			return "04-6  面向3.5米内蓝色训练车，按空格成功上链接"
	return "04-6  按空格使用角色技能"

func on_char_skill_used(p: Player) -> void:
	if room == 3 and stage == 5 and p.char_cd >= CharacterDef.skill_cd(p.char_id) - 0.1:
		marks["role_skill"] = true

func on_throw_hit(it: Item, body: Node, _pos: Vector3) -> void:
	if room != 3:
		return
	var kind := Catalog.prop_kind(it.item_id)
	if body is Actor and body != _m.player:
		marks["throw_actor"] = true
		if kind == Catalog.PROP_TASER:
			marks["taser"] = true
	elif body is Cart and body != _m.player.cart:
		marks["throw_cart"] = true
	else:
		if kind == Catalog.PROP_WET or kind == Catalog.PROP_SCATTER:
			marks["ground_effect"] = true
	# 训练物资无限补充，失手不会锁死流程。
	if stage < 4:
		_m.get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(_m.player) and room == 3:
				_add_to_player_cart(it.item_id))

# ---------------------------------------------------------------- 房间05

func _prepare_final() -> void:
	_remove_target_items()
	_spawn_item("tissue", _points["final_shelf"], true)
	_final_cart = Cart.create(Color(0.55, 0.55, 0.58), "结业无人车")
	_m.add_child(_final_cart)
	_final_cart.global_position = _points["final_cart"]
	_add_item_to_cart(_final_cart, "thermos")
	_final_dummy = TutorialOpponent.new()
	_m.add_child(_final_dummy)
	_final_dummy.setup("结业竞争者")
	_final_dummy.global_position = _points["final_dummy"]
	_final_dummy.imbalance = 40.0
	var drone := _spawn_item("drone", _points["final_dummy"] + Vector3.UP, false)
	drone.set_held()
	_final_dummy.take_item(drone)
	_scan_time = 0.0

func _tick_final(delta: float) -> void:
	var p: Player = _m.player
	var count := 0
	for id in TARGET_IDS:
		if _cart_has(p.cart, id):
			count += 1
	if count < TARGET_IDS.size():
		_say("05  自由完成：搜货架卫生纸 · 偷无人车保温杯 · 肘倒竞争者夺无人机  [%d/3]" % count)
		_scan_time = 0.0
		return
	var checkout: Vector3 = _points["checkout"]
	_say("05  三件齐了!抓住自己的车，驶入绿色结业收银区  %s" % _progress(_scan_time, 2.0))
	if p.attached and p.cart.global_position.distance_to(checkout) < 3.2:
		_scan_time += delta
		if _scan_time >= 2.0:
			_m.complete_tutorial()
	else:
		_scan_time = 0.0

# ---------------------------------------------------------------- 事件与工具

func on_shelf_item(it: Item) -> void:
	marks["shelf:%s" % it.item_id] = true

func on_player_dropped_item(it: Item) -> void:
	if room == 1 and stage == 3 and it == _goods_decoy:
		marks["dropped_decoy"] = true
		# 教程目的已经达成，固定这件大型练习品，避免它滚回车下持续推动玩家车，
		# 进而让下一房的偷窃假人追着移动中的购物车跑不完流程。
		it.freeze = true
		it.linear_velocity = Vector3.ZERO
		it.angular_velocity = Vector3.ZERO

func on_player_stole(_cart: Cart, item: Item) -> void:
	if room == 2 and item == _combat_item:
		marks["stole"] = true

func on_actor_downed(actor: Actor) -> void:
	if actor == _combat_dummy:
		marks["combat_downed"] = true

func on_wheel_cycled() -> void:
	if room == 3:
		marks["wheel"] = true

func _spawn_item(id: String, pos: Vector3, shelved: bool) -> Item:
	var it := Item.create(id)
	_m.add_child(it)
	if shelved:
		it.set_shelved(pos)
	else:
		it.set_free_at(pos)
	_m.all_items.append(it)
	return it

func _add_to_player_cart(id: String) -> Item:
	return _add_item_to_cart(_m.player.cart, id)

func _add_item_to_cart(cart: Cart, id: String) -> Item:
	# 教学车内的固定陈列位既方便辨认，也避免多件商品的名称完全叠在一起。
	var display_slots := {
		"thermos": Vector2(-0.22, -0.18),
		"detergent": Vector2(0.22, -0.18),
		"tissue": Vector2(-0.22, 0.18),
		"drone": Vector2(0.22, 0.18),
	}
	var slot: Vector2 = display_slots.get(id, Vector2.ZERO)
	var it := _spawn_item(id, cart.global_position + Vector3.UP, false)
	_place_item_in_cart(it, cart, slot)
	return it

## 从车斗内底面按商品真实半高摆放，避免旧版统一从1.35米高处落下时
## 小型无人机撞上其他商品后弹出车外。初速度继承购物车，减少移动中补货的相对冲击。
func _place_item_in_cart(it: Item, cart: Cart, slot: Vector2) -> void:
	if not is_instance_valid(it) or not is_instance_valid(cart):
		return
	var local_y := Cart.FLOOR_TOP + it.collider_half_height() + 0.035
	it.set_free_at(cart.to_global(Vector3(slot.x, local_y, slot.y)))
	it.linear_velocity = cart.linear_velocity
	it.angular_velocity = Vector3.ZERO
	it.continuous_cd = true
	it.reset_physics_interpolation()

func _cart_has(cart: Cart, id: String) -> bool:
	if not is_instance_valid(cart):
		return false
	for it in cart.items_in_basket():
		if is_instance_valid(it) and it.item_id == id:
			return true
	return false

func _cart_has_item(cart: Cart, target: Item) -> bool:
	return is_instance_valid(cart) and is_instance_valid(target) \
			and cart.items_in_basket().has(target)

## Area3D 的重叠列表会晚一个物理步刷新；教学纠错同时检查车斗局部空间，
## 避免商品刚装车的那一帧被误判成R键落地。
func _item_inside_cart(cart: Cart, target: Item) -> bool:
	if not is_instance_valid(cart) or not is_instance_valid(target) \
			or target.state != Item.ItemState.FREE:
		return false
	if cart.items_in_basket().has(target):
		return true
	var local := cart.to_local(target.global_position)
	return absf(local.x) <= Cart.INNER_HALF_X + 0.12 \
			and absf(local.z) <= Cart.INNER_HALF_Z + 0.12 \
			and local.y >= Cart.FLOOR_TOP - 0.2 and local.y <= 1.9

func _remove_target_items() -> void:
	for actor in [_m.player, _combat_dummy, _lab_dummy]:
		if is_instance_valid(actor):
			for i in range(actor.held.size() - 1, -1, -1):
				if actor.held[i].item_id in TARGET_IDS:
					actor.held.remove_at(i)
	for it in _m.all_items:
		if is_instance_valid(it) and it.item_id in TARGET_IDS:
			it.queue_free()

func _progress(value: float, total: float) -> String:
	return "[%d/%d]" % [mini(int(value), int(total)), int(total)]

func _say(text: String) -> void:
	_m.hud.set_tutorial_text(text + "  ·  F2重置")
