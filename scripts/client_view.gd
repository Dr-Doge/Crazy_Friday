class_name ClientView extends RefCounted
## 联机客户端的渲染层。
##
## 客户端不做任何模拟:所有实体已被 Main._make_client_puppets()冻结,
## 这里只把主机 20Hz 送来的状态包插值到本地节点上,做到画面顺滑。
## 参数 m 是 Main(不写类型注解以避免 class_name 循环引用)。

## 插值收敛速度:越大越贴近主机权威位置、但越容易显出网络抖动
const LERP_LAMBDA := 14.0

## 状态包字段(与 net.gd 的 _gather_* 一一对应):
##   p  玩家c  购物车   g  大妈   i  商品   co 闸机
##   t  剩余时间   ig 是否宽限期   gl 宽限剩余
var state := {}
## 主机单独推给本机的 HUD 数据(清单行与分数)
var rows: Array = []
var score := 0

var _m

func _init(m) -> void:
	_m = m

## A包/B包是拆开发的,按键合并而非整体覆盖
func apply_state(d: Dictionary) -> void:
	for k in d:
		state[k] = d[k]

## hot_carts: [[车下标, 提示或""], ...] —— 李洋只收到链接图标，不泄露商品名
func set_hud(new_rows: Array, new_score: int, hot_carts: Array) -> void:
	rows = new_rows
	score = new_score
	var by_idx := {}
	for e in hot_carts:
		if e is Array and e.size() >= 2:
			by_idx[int(e[0])] = str(e[1])
	for i in _m.net.carts_net.size():
		var c = _m.net.carts_net[i]
		if is_instance_valid(c):
			var on: bool = by_idx.has(i)
			c.set_highlight(on)
			c.set_hot_name(str(by_idx.get(i, "")) if on else "")

func interpolate(delta: float) -> void:
	if state.is_empty():
		return
	var k := 1.0 - exp(-LERP_LAMBDA * delta)
	_players(k, delta)
	_carts(k)
	_grannies(k, delta)
	_buddies(k, delta)
	_items(k)
	_gates()
	_clock()

## 玩家:位置/朝向插值,状态量(失衡/体力/倒地/技能CD)直接覆盖
func _players(k: float, delta: float) -> void:
	var ps: Array = state.get("p", [])
	for i in mini(ps.size(), _m.players.size()):
		var a: Array = ps[i]
		var p: Player = _m.players[i]
		p.global_position = p.global_position.lerp(a[0], k)
		p.body_root.rotation.y = lerp_angle(p.body_root.rotation.y, a[1], k)
		p.hand_pose = a[2]
		p.imbalance = a[3]
		p.stamina = a[4]
		p.downed = a[5]
		p.braced = a[6]
		p.channel_progress = a[7]
		p.body_root.rotation.x = lerpf(p.body_root.rotation.x, a[8], k)
		p.locate_cd = a[9]
		p.prop_cd = a[10]
		p.brace_cd = a[11]
		# 角色技能状态(HUD 显示用;客户端不做判定)
		if a.size() > 14:
			p.char_cd = a[12]
			p.stance_time = a[13]
			p.stance = a[13] > 0.0
			p.stun_time = a[14]
		if a.size() > 18:
			p.taser_time = a[15]
			p.taser_immunity_time = a[16]
			p.obscure_time = a[17]
			p.obscure_factor = a[18]
		if a.size() > 19:
			_apply_cart_attachment(p, bool(a[19]))
		if a.size() > 20:
			_sync_held(p, a[20])
		p.puppet_update(delta)

## 主机权威的上/下车状态必须在客户端显式落地。位置插值只能让角色看起来跟着车走，
## 不能替代 attached：本机相机、商品轮盘和右键投掷都以此字段切换模式。
func _apply_cart_attachment(p: Player, attached: bool) -> void:
	if not is_instance_valid(p.cart):
		p.attached = false
		return
	p.attached = attached
	if attached:
		p.cart.attached_agent = p
		p.collision_layer = 0
		p.collision_mask = 0
	else:
		if p.cart.attached_agent == p:
			p.cart.attached_agent = null
		p.collision_layer = Catalog.L_CHAR
		p.collision_mask = Catalog.L_WORLD | Catalog.L_CHAR | Catalog.L_CART

## 购物车:三轴旋转都要插值(会翻车,不能只插y)
func _carts(k: float) -> void:
	var cs: Array = state.get("c", [])
	for i in mini(cs.size(), _m.net.carts_net.size()):
		if cs[i] == null:
			continue
		var c = _m.net.carts_net[i]
		if not is_instance_valid(c):
			continue
		c.global_position = c.global_position.lerp(cs[i][0], k)
		var r: Vector3 = cs[i][1]
		c.global_rotation = Vector3(
				lerp_angle(c.global_rotation.x, r.x, k),
				lerp_angle(c.global_rotation.y, r.y, k),
				lerp_angle(c.global_rotation.z, r.z, k))

func _grannies(k: float, delta: float) -> void:
	var gs: Array = state.get("g", [])
	for i in mini(gs.size(), _m.net.grannies_net.size()):
		if gs[i] == null:
			continue
		var g = _m.net.grannies_net[i]
		if not is_instance_valid(g):
			continue
		g.global_position = g.global_position.lerp(gs[i][0], k)
		g.body_root.rotation.y = lerp_angle(g.body_root.rotation.y, gs[i][1], k)
		g.hand_pose = gs[i][2]
		g.body_root.rotation.x = lerpf(g.body_root.rotation.x, gs[i][3], k)
		if gs[i].size() > 4:
			_sync_held(g, gs[i][4])
		g.puppet_update(delta)

func _buddies(k: float, delta: float) -> void:
	var bs: Array = state.get("b", [])
	for i in mini(bs.size(), _m.warehouse_buddies.size()):
		if bs[i] == null:
			continue
		var buddy: WarehouseBuddy = _m.warehouse_buddies[i]
		if not is_instance_valid(buddy):
			continue
		buddy.global_position = buddy.global_position.lerp(bs[i][0], k)
		buddy.body_root.rotation.y = lerp_angle(buddy.body_root.rotation.y, bs[i][1], k)
		buddy.body_root.rotation.x = lerpf(buddy.body_root.rotation.x, bs[i][2], k)
		buddy.imbalance = bs[i][3]
		buddy.downed = bs[i][4]
		buddy.active = bs[i][5]
		buddy.puppet_update(delta)

## 商品:四态同步;已扫码的标签本地也要转绿
func _items(k: float) -> void:
	for e in state.get("i", []):
		var idx: int = e[0]
		if idx < 0 or idx >= _m.all_items.size():
			continue
		var it = _m.all_items[idx]
		if not is_instance_valid(it):
			continue
		_apply_item_state(it, e[1])
		it.global_position = it.global_position.lerp(e[2], k)
		it.global_rotation.y = lerp_angle(it.global_rotation.y, e[3], k)
		if it.state == Item.ItemState.SCANNED and it.label != null:
			it.label.modulate = Color(0.1, 0.55, 0.2)

## 玩家包20Hz直接携带手持商品索引，避免等待轮转的世界商品分片。
## 这既是第一人称手持显示的数据源，也让客户端容量/装车提示与主机一致。
func _sync_held(actor: Actor, indices: Array) -> void:
	var rebuilt: Array[Item] = []
	for raw_idx in indices:
		var idx := int(raw_idx)
		if idx < 0 or idx >= _m.all_items.size():
			continue
		var it: Item = _m.all_items[idx]
		if is_instance_valid(it):
			rebuilt.append(it)
			_apply_item_state(it, Item.ItemState.HELD)
	actor.held = rebuilt

## 客户端永不模拟商品刚体，但仍维护碰撞层供车斗 Area 查询轮盘库存。
func _apply_item_state(it: Item, new_state: int) -> void:
	it.state = new_state
	it.freeze = true
	if it.state == Item.ItemState.SHELVED or it.state == Item.ItemState.FREE:
		it.collision_layer = Catalog.L_ITEM
		it.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
	else:
		it.collision_layer = 0
		it.collision_mask = 0

## 闸机升降杆高度
func _gates() -> void:
	var cos: Array = state.get("co", [])
	for i in mini(cos.size(), _m.checkouts.size()):
		_m.checkouts[i].gate.position.y = cos[i][0]
		_m.checkouts[i].south_gate.position.y = cos[i][1]

## 计时以主机为准
func _clock() -> void:
	_m.time_left = state.get("t", _m.time_left)
	_m.in_grace = state.get("ig", false)
	_m.grace_left = state.get("gl", _m.grace_left)
