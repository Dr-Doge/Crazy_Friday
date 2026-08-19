class_name TutorialProbe extends RefCounted
## 五房教学导演的确定性无头回归。实际玩法细节由各专项探针覆盖，
## 本探针专注房间顺序、门禁、目标布置、三角色入口与毕业闭环。

var _m
var _guide
var _acted_key := ""
var _fails: Array[String] = []
var _started := false

func _init(m, guide) -> void:
	_m = m
	_guide = guide

func setup() -> void:
	_check(_m.get_node_or_null("TutorialRooms") != null, "教学使用独立 TutorialRooms 地图")
	_check(_m.get_node_or_null("Market") == null, "教学不生成正式卖场 Market")
	_check(_guide._gates.size() == 4, "五房之间存在四道实体门禁")
	_check(_m.grannies.is_empty() and _m.checkouts.is_empty(), "教学不生成普通NPC、随机事件与正式收银通道")
	var rooms: Node3D = _m.get_node("TutorialRooms") as Node3D
	var shelves_face_entry: bool = rooms.get_node("GoodsShelf_A_Ledge").position.z \
			> rooms.get_node("GoodsShelf_A").position.z \
			and rooms.get_node("GoodsShelf_B_Ledge").position.z \
			> rooms.get_node("GoodsShelf_B").position.z \
			and rooms.get_node("FinalShelf_Ledge").position.z \
			> rooms.get_node("FinalShelf").position.z
	_check(shelves_face_entry, "全部教学货架陈列面朝向玩家进入方向")
	_check(_guide._goods_decoy.category == Catalog.CAT_LARGE,
			"R键教学使用占满双手的非目标大件形成自然丢弃需求")
	print("[tutorial] 五房串联教学自检开始 角色=%s" % _m.player.char_id)
	_started = true

func tick() -> void:
	if not _started or _m.game_over:
		return
	var key := "%d:%d:%s" % [_guide.room, _guide.stage, str(_guide._waiting_exit)]
	if key == _acted_key:
		return
	_acted_key = key
	var p: Player = _m.player
	if _guide._waiting_exit:
		var z: float = float(TutorialRoomBuilder.GATE_ZS[_guide.room]) - 2.0
		p.global_position.z = z
		p.cart.global_position.z = z - 0.8
		return
	match _guide.room:
		0: _drive(p)
		1: _goods(p)
		2: _combat(p)
		3: _lab(p)
		4: _final(p)

func _drive(p: Player) -> void:
	match _guide.stage:
		0: p.global_position += Vector3.RIGHT * 6.0
		1:
			p.cart.global_position = p.global_position + Vector3(0, 0.2, -1.2)
			p.attach_cart()
		2:
			_guide._last_cart = p.cart.global_position
			_guide._drive_dist = TutorialGuide.DRIVE_DIST + 0.1
		3:
			p.cart.sprinting = true
			_guide._sprint_time = TutorialGuide.SPRINT_TIME + 0.1

func _goods(p: Player) -> void:
	match _guide.stage:
		0:
			if p.attached: p.detach_cart()
			_guide._goods_a.set_held()
			p.take_item(_guide._goods_a)
			_guide.on_shelf_item(_guide._goods_a)
		1:
			p.held.erase(_guide._goods_a)
			_guide._place_item_in_cart(_guide._goods_a, p.cart, Vector2.ZERO)
		2:
			_guide._goods_decoy.set_held()
			p.take_item(_guide._goods_decoy)
		3:
			p.held.erase(_guide._goods_decoy)
			_guide._place_item_in_cart(_guide._goods_decoy, p.cart, Vector2.ZERO)
			_m.get_tree().create_timer(0.7).timeout.connect(func() -> void:
				_check(_guide.marks.get("decoy_cart_redirect", false) \
						and p.held.has(_guide._goods_decoy),
						"错误大件按习惯装车时会退回手中并重新引导R键")
				if p.attached:
					p.detach_cart()
				p._drop_held())
		4: p.locate_cd = 10.0
		5: _guide._add_item_to_cart(p.cart, "thermos")

func _combat(p: Player) -> void:
	match _guide.stage:
		0: _guide.on_player_stole(_guide._steal_cart, _guide._combat_item)
		1:
			# 探针会瞬移玩家购物车跨越房间；先清掉这次测试专用的惯性，
			# 否则训练黄牛会一直追逐一辆仍在滑行的车。
			p.cart.linear_velocity = Vector3.ZERO
			p.cart.angular_velocity = Vector3.ZERO
			p.cart.freeze = true
			p.take_item(_guide._combat_item)
			p.held.erase(_guide._combat_item)
			_guide._place_item_in_cart(_guide._combat_item, p.cart, Vector2.ZERO)
			# 探针靠瞬移跨门，车斗会在同一物理帧产生很大速度；固定任务品，
			# 避免测试专用瞬移把商品甩出车外，实际玩家流程仍保持真实物理。
			_guide._combat_item.freeze = true
		2: pass # 让训练黄牛真实走到购物车、拿货并返回原位。
		3:
			p.cart.freeze = false
			_check(_guide._combat_dummy.theft_completed \
					and _guide._combat_dummy.held.has(_guide._combat_item) \
					and _guide._combat_dummy.global_position.distance_to(
							_guide._points["combat_dummy"]) < 0.5,
					"第三房训练黄牛真实往返玩家购物车并偷走商品")
			_guide._combat_dummy.imbalance = 56.0
		4: _guide._combat_dummy.knockdown()
		5: _guide._add_item_to_cart(p.cart, "thermos")
		6: p.braced = true

func _lab(p: Player) -> void:
	match _guide.stage:
		0:
			# 留出物理静置时间，真实验证无人机仍在车斗而非只检查生成瞬间。
			_m.get_tree().create_timer(0.8).timeout.connect(func() -> void:
				_check(_guide._cart_has(p.cart, "drone"),
						"第四房无人机静置后仍在玩家车斗并可进入轮盘")
				if not p.attached:
					p.global_position = p.cart.handle_pos()
					p.attach_cart()
				_guide.on_wheel_cycled())
		1: _guide.marks["throw_actor"] = true
		2: _guide.marks["throw_cart"] = true
		3: _guide.marks["ground_effect"] = true
		4: _guide.marks["taser"] = true
		5:
			p.char_cd = CharacterDef.skill_cd(p.char_id)
			_guide.on_char_skill_used(p)

func _final(p: Player) -> void:
	var checkout: Vector3 = _guide._points["checkout"]
	p.cart.right_up()
	p.cart.global_position = checkout
	if not p.attached:
		p.global_position = p.cart.handle_pos()
		p.attach_cart()
	for id in TutorialGuide.TARGET_IDS:
		_guide._add_item_to_cart(p.cart, id)
	# 等待Area3D刷新新放入车斗的三件商品，再走真实2秒结业扫描。
	_m.get_tree().create_timer(3.0).timeout.connect(_report)

func _check(ok: bool, msg: String) -> void:
	print("[tutorial] %s %s" % [(" OK  " if ok else " FAIL"), msg])
	if not ok:
		_fails.append(msg)

func _report() -> void:
	_check(_m.game_over, "第五房结业收银进入教学成绩卡")
	for i in _guide._gates.size():
		var gate = _guide._gates[i]
		var visual := gate.get_node_or_null("Visual") as MeshInstance3D
		_check(bool(gate.get_meta("open", false)) and gate.collision_layer == 0 \
				and visual != null and str(visual.get_meta("gate_color", "")) == "green" \
				and visual.visible,
				"门禁%d按顺序变绿、升起并关闭碰撞" % (i + 1))
	print("[tutorial] RESULT=%s assertions=%d" % [("PASS" if _fails.is_empty() else "FAIL"), 14])
	_m.get_tree().quit(0 if _fails.is_empty() else 1)
