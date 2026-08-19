class_name TutorialOpponent extends Actor
## 教学用受控对手：可演示走到玩家车旁偷货并返回，任务品只在倒地时掉落。

var protect_held_until_downed := true
var theft_completed := false
var stolen_item: Item

enum TheftState { IDLE, APPROACH_CART, RETURN_HOME }
var theft_state := TheftState.IDLE
var _theft_cart: Cart
var _wanted_item: Item
var _theft_home := Vector3.ZERO
const THEFT_SPEED := 3.2

func setup(title := "训练黄牛") -> void:
	build_body(Color(0.9, 0.28, 0.22), title)

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	if downed:
		apply_motion(delta, Vector3.ZERO, 0.0)
		return
	match theft_state:
		TheftState.APPROACH_CART:
			_tick_approach_cart(delta)
		TheftState.RETURN_HOME:
			_tick_return_home(delta)
		_:
			apply_motion(delta, Vector3.ZERO, 0.0)

func start_cart_theft(target_cart: Cart, target_item: Item = null) -> void:
	if not is_instance_valid(target_cart):
		return
	_theft_home = global_position
	_theft_cart = target_cart
	_wanted_item = target_item
	stolen_item = null
	theft_completed = false
	theft_state = TheftState.APPROACH_CART
	immune = true

func cancel_cart_theft() -> void:
	theft_state = TheftState.IDLE
	_theft_cart = null
	_wanted_item = null
	stolen_item = null
	theft_completed = false
	immune = false

func _tick_approach_cart(delta: float) -> void:
	if not is_instance_valid(_theft_cart):
		cancel_cart_theft()
		return
	var to_cart := _theft_cart.global_position - global_position
	to_cart.y = 0.0
	# 购物车外壳和把手会在约1.7米处挡住徒步角色；交互距离放到2.05米，
	# 让黄牛在车边伸手拿货，不再试图挤进车斗后原地卡死。
	if to_cart.length() > 2.05:
		apply_motion(delta, to_cart.normalized(), THEFT_SPEED)
		return
	var candidate: Item = null
	var basket_items := _theft_cart.items_in_basket()
	if is_instance_valid(_wanted_item) and basket_items.has(_wanted_item):
		candidate = _wanted_item
	elif not basket_items.is_empty():
		candidate = _theft_cart.take_top_item()
	if candidate == null:
		apply_motion(delta, Vector3.ZERO, 0.0)
		return
	candidate.set_held()
	take_item(candidate)
	stolen_item = candidate
	_theft_cart.show_steal_alert()
	Main.float_text(self, global_position + Vector3.UP * 2.2,
			"训练黄牛偷走了 " + candidate.display_name + "!", Color(1.0, 0.45, 0.18), 68)
	theft_state = TheftState.RETURN_HOME

func _tick_return_home(delta: float) -> void:
	var to_home := _theft_home - global_position
	to_home.y = 0.0
	if to_home.length() > 0.25:
		apply_motion(delta, to_home.normalized(), THEFT_SPEED)
		return
	global_position = Vector3(_theft_home.x, global_position.y, _theft_home.z)
	apply_motion(delta, Vector3.ZERO, 0.0)
	theft_state = TheftState.IDLE
	theft_completed = true
	immune = false

func drop_one_held(scatter := true) -> Item:
	if protect_held_until_downed and not downed:
		return null
	return super.drop_one_held(scatter)
