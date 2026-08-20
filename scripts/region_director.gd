class_name RegionDirector extends RefCounted
## New_Level分区规则：处理冷冻/个护状态，并驱动生鲜、熊孩子、挡路大妈生态。

const FREEZE_FILL_TIME := 18.0
const FREEZE_DURATION := 5.0
const THAW_TIME := 9.0
const BEAUTY_VISIBILITY_FACTOR := 0.12
const BEAUTY_CLEAR_DISTANCE := 3.0
const BEAUTY_HIDDEN_DISTANCE := 18.0 # 仅保留兼容常量；不再用远裁切硬隐藏
const BEAUTY_VIEW_TRANSITION_TIME := 1.6
const KID_COUNT := 8
const GRANNY_MIN_COUNT := 6
const GRANNY_MAX_COUNT := 8
const LIVE_MAX_IMBALANCE := 30.0
const LIVE_HIT_IMBALANCE := 18.0
const LIVE_STUN_DURATION := 8.0

var _main
var _bounds: Dictionary = {}
var _region_npcs: Array[RegionNpc] = []
var _live_goods: Array[Item] = []
var _live_jump_time := {}
var _live_imbalance := {}
var _live_stun_time := {}
var _vending_hit_count := {}
var _vending_prizes_left := {}
var _default_camera_far := -1.0
var _beauty_gradient_shells: Array[MeshInstance3D] = []
var _beauty_view_blend := 0.0

func _init(main) -> void:
	_main = main

func setup(bounds: Dictionary) -> void:
	_bounds = bounds.duplicate()
	_setup_beauty_fog()
	_spawn_region_ecology()

func tick(delta: float) -> void:
	if _bounds.is_empty():
		return
	for actor in _actors():
		if not is_instance_valid(actor):
			continue
		_tick_cold(actor, delta)
		_tick_beauty(actor)
	_tick_local_beauty_view(delta)
	_tick_live_goods(delta)

func _spawn_region_ecology() -> void:
	# 熊孩子固定8名，分散在玩具与零食两区；大妈每局6–8名，只是服饰区障碍生态，
	# 两者都不是参赛扫货AI，不占四队八席。
	var kid_rects: Array[Rect2] = []
	for key in ["Toys", "Snacks"]:
		if _bounds.has(key):
			kid_rects.append(_bounds[key])
	if not kid_rects.is_empty():
		for i in KID_COUNT:
			_spawn_region_npc(RegionNpc.Kind.KID, kid_rects[i % kid_rects.size()], i, KID_COUNT)
	if _bounds.has("Clothing"):
		# 从共享对局种子直接派生，主机与客户端不会因前序随机调用数不同而产生数量分歧。
		var granny_count := GRANNY_MIN_COUNT + posmod(_main.match_seed, \
				GRANNY_MAX_COUNT - GRANNY_MIN_COUNT + 1)
		for i in granny_count:
			_spawn_region_npc(RegionNpc.Kind.BLOCKING_GRANNY,
					_bounds["Clothing"], i, granny_count)
	if _bounds.has("Fresh"):
		_spawn_live_fresh_goods(_bounds["Fresh"])

func _spawn_region_npc(kind: RegionNpc.Kind, rect: Rect2, index: int, count: int) -> void:
	var npc := RegionNpc.new()
	_main.add_child(npc)
	npc.setup(_main, kind, rect, index)
	var cols := maxi(2, int(ceil(sqrt(float(count)))))
	var row := int(index / cols)
	var col := index % cols
	var x := lerpf(rect.position.x + 1.2, rect.end.x - 1.2,
			(float(col) + 0.5) / float(cols))
	var rows := maxi(1, int(ceil(float(count) / float(cols))))
	var z := lerpf(rect.position.y + 1.2, rect.end.y - 1.2,
			(float(row) + 0.5) / float(rows))
	npc.global_position = Vector3(x, 0.12, z)
	_region_npcs.append(npc)

func _spawn_live_fresh_goods(rect: Rect2) -> void:
	for i in 6:
		var id: String = Catalog.LIVE_FRESH_IDS[i % Catalog.LIVE_FRESH_IDS.size()]
		var item := Item.create(id)
		_main.add_child(item)
		_main.all_items.append(item)
		item.set_meta("live_fresh_good", true)
		var lane := float(i % 3 + 1) / 4.0
		var row := float(int(i / 3) + 1) / 3.0
		var pos := Vector3(lerpf(rect.position.x + 1.0, rect.end.x - 1.0, lane),
				0.75, lerpf(rect.position.y + 1.0, rect.end.y - 1.0, row))
		item.set_free_at(pos, Vector3(randf_range(-1.4, 1.4), 3.5, randf_range(-1.4, 1.4)))
		_live_goods.append(item)
		_live_jump_time[item] = 0.35 + i * 0.18
		_live_imbalance[item] = 0.0
		_live_stun_time[item] = 0.0

func _tick_live_goods(delta: float) -> void:
	for item in _live_goods:
		if not is_instance_valid(item):
			continue
		if item.state != Item.ItemState.FREE:
			item.freeze = false
			_live_stun_time[item] = 0.0
			_live_imbalance[item] = 0.0
			continue
		var stunned_left := maxf(0.0, float(_live_stun_time.get(item, 0.0)) - delta)
		_live_stun_time[item] = stunned_left
		item.set_meta("live_stunned", stunned_left > 0.0)
		if stunned_left > 0.0:
			# 昏迷活鲜固定视觉位置，但不再作为实体路障卡住购物车。
			# 拾取使用软件方向锥判定，不依赖碰撞层，因此关闭碰撞后仍可正常拿起。
			item.freeze = true
			item.collision_layer = 0
			item.collision_mask = 0
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			continue
		if item.freeze:
			item.freeze = false
			item.collision_layer = Catalog.L_ITEM
			item.collision_mask = Catalog.L_WORLD | Catalog.L_CART | Catalog.L_ITEM
			_live_imbalance[item] = 0.0
			_live_jump_time[item] = 0.5
		var left := float(_live_jump_time.get(item, 0.0)) - delta
		if left <= 0.0:
			var horizontal := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			if horizontal.length_squared() < 0.1:
				horizontal = Vector3.FORWARD
			item.apply_central_impulse(horizontal.normalized() * randf_range(1.8, 3.2)
					+ Vector3.UP * randf_range(2.8, 4.4))
			item.apply_torque_impulse(Vector3(randf_range(-0.7, 0.7),
					randf_range(-1.2, 1.2), randf_range(-0.7, 0.7)))
			left = randf_range(0.75, 1.65)
		_live_jump_time[item] = left

## 肘击地面活鲜：准星前方最近目标获得夸张压扁闪白、弹飞和更快的下一跳。
func try_hit_live_good(attacker: Actor, forward: Vector3, reach: float) -> bool:
	var best: Item = null
	var best_distance := reach
	for item in _live_goods:
		if not is_instance_valid(item) or item.state != Item.ItemState.FREE:
			continue
		var to_item := item.global_position - attacker.global_position
		to_item.y = 0.0
		var distance := to_item.length()
		if distance <= 0.05 or distance >= best_distance \
				or forward.dot(to_item.normalized()) <= 0.28:
			continue
		best = item
		best_distance = distance
	if best == null:
		return false
	best.play_live_hit_feedback()
	var discomfort := minf(LIVE_MAX_IMBALANCE,
			float(_live_imbalance.get(best, 0.0)) + LIVE_HIT_IMBALANCE)
	_live_imbalance[best] = discomfort
	best.set_meta("live_imbalance", discomfort)
	if discomfort >= LIVE_MAX_IMBALANCE:
		# 旧逻辑每次受击后把下一跳设为0.18秒，导致永远不会停；达到阈值后改为8秒冻结态。
		_live_stun_time[best] = LIVE_STUN_DURATION
		best.set_meta("live_stunned", true)
		best.freeze = true
		best.collision_layer = 0
		best.collision_mask = 0
		best.linear_velocity = Vector3.ZERO
		best.angular_velocity = Vector3.ZERO
		Main.float_text(best, best.global_position + Vector3.UP * 0.8,
				"活鲜被打晕! %.0f秒" % LIVE_STUN_DURATION, Color(1.0, 0.72, 0.88), 74)
	else:
		best.freeze = false
		best.sleeping = false
		best.apply_central_impulse(forward * 2.8 + Vector3.UP * 2.4)
		best.apply_torque_impulse(Vector3(randf_range(-1.6, 1.6),
				randf_range(-2.2, 2.2), randf_range(-1.6, 1.6)))
		_live_jump_time[best] = 0.45
		Main.float_text(best, best.global_position + Vector3.UP * 0.8,
				"啪叽!! 难受%.0f/%.0f" % [discomfort, LIVE_MAX_IMBALANCE],
				Color(1.0, 0.55, 0.78), 70)
	if attacker is Player:
		_main.shake_for(attacker, 0.38)
	return true

## 肘击自动贩卖机：每台最多吐出3张券，每4次有效击打有保底，其余按28%概率出券。
## 券只记在攻击者队伍名下，必须把指定商品送过收银台才会兑现。
func try_hit_vending_machine(attacker: Actor, forward: Vector3, reach: float) -> bool:
	if not attacker is Player:
		return false
	var best: CSGBox3D = null
	var best_distance := reach
	for node in _main.find_children("Vending_*", "CSGBox3D", true, false):
		if str(node.name).ends_with("_Screen"):
			continue
		var machine := node as CSGBox3D
		var to_machine := machine.global_position - attacker.global_position
		to_machine.y = 0.0
		var distance := to_machine.length()
		if distance <= 0.05 or distance >= best_distance \
				or forward.dot(to_machine.normalized()) <= 0.25:
			continue
		best = machine
		best_distance = distance
	if best == null:
		return false
	var now := Time.get_ticks_msec()
	if now < int(best.get_meta("vending_next_hit_ms", 0)):
		return true
	best.set_meta("vending_next_hit_ms", now + 320)
	_main.play_vending_hit_visual(str(best.name))
	var key := str(best.name)
	var hits := int(_vending_hit_count.get(key, 0)) + 1
	_vending_hit_count[key] = hits
	var prizes := int(_vending_prizes_left.get(key, 3))
	var wins := prizes > 0 and (hits % 4 == 0 or randf() < 0.28)
	if wins and attacker.team_id >= 0:
		_vending_prizes_left[key] = prizes - 1
		var item_id: String = _main.random_voucher_item_id()
		if item_id != "":
			_main.grant_vending_voucher(attacker.team_id, item_id,
					"free" if randf() < 0.28 else "half")
			return true
	Main.float_text(best, best.global_position + Vector3.UP * 1.8,
			["哐当!! 没掉东西", "咣!! 再来一下?", "机器：禁止殴打"].pick_random(),
			Color(1.0, 0.72, 0.28), 62)
	return true

func zone_at(pos: Vector3) -> String:
	var point := Vector2(pos.x, pos.z)
	for key in _bounds:
		var rect: Rect2 = _bounds[key]
		if rect.has_point(point):
			return str(key)
	return ""

func _actors() -> Array[Actor]:
	var out: Array[Actor] = []
	for node in _main.get_tree().get_nodes_in_group("characters"):
		if node is Actor:
			out.append(node as Actor)
	return out

func _inside(actor: Actor, key: String) -> bool:
	return is_inside_zone(actor.global_position, key)

func is_inside_zone(pos: Vector3, key: String) -> bool:
	if not _bounds.has(key):
		return false
	var rect: Rect2 = _bounds[key]
	return rect.has_point(Vector2(pos.x, pos.z))

func _tick_cold(actor: Actor, delta: float) -> void:
	var inside := _inside(actor, "Frozen")
	if inside and actor.frozen_time <= 0.0:
		var adapt_mult := 0.5 if actor.cold_adapt_time > 0.0 else 1.0
		actor.cold_meter = minf(1.0, actor.cold_meter + delta / FREEZE_FILL_TIME * adapt_mult)
		if actor.cold_meter >= 0.75 and not bool(actor.get_meta("cold_warned", false)):
			actor.set_meta("cold_warned", true)
			Main.float_text(actor, actor.global_position + Vector3.UP * 2.25,
					"冷得牙打颤!快离开冷库", Color(0.45, 0.9, 1.0), 58)
		if actor.cold_meter >= 1.0:
			actor.frozen_time = FREEZE_DURATION
			actor.cold_meter = 1.0
			Main.float_text(actor, actor.global_position + Vector3.UP * 2.35,
					"冻成冰棍! %.1f秒" % FREEZE_DURATION, Color(0.35, 0.82, 1.0), 72)
	else:
		actor.cold_meter = maxf(0.0, actor.cold_meter - delta / THAW_TIME)
		if actor.cold_meter < 0.6:
			actor.set_meta("cold_warned", false)

func _tick_beauty(actor: Actor) -> void:
	if not _inside(actor, "Beauty"):
		return
	# 本机玩家的画面交给真正的FogVolume，不再套散落物那种块状全屏遮罩；
	# AI仍按进入深度逐渐缩短感知，最深处只保留约3米观察距离。
	if actor is Player:
		return
	var rect: Rect2 = _bounds["Beauty"]
	var p := Vector2(actor.global_position.x, actor.global_position.z)
	var depth := minf(minf(p.x - rect.position.x, rect.end.x - p.x),
			minf(p.y - rect.position.y, rect.end.y - p.y))
	var blend := smoothstep(0.0, 2.2, maxf(0.0, depth))
	actor.apply_obscure(lerpf(1.0, BEAUTY_VISIBILITY_FACTOR, blend), 0.22)

func _tick_local_beauty_view(delta: float) -> void:
	if not is_instance_valid(_main.player) or _main.cam_rig == null \
			or not is_instance_valid(_main.cam_rig.camera):
		return
	var camera: Camera3D = _main.cam_rig.camera
	if _default_camera_far < 0.0:
		_default_camera_far = camera.far
	_setup_beauty_gradient_shells(camera)
	var inside := is_inside_zone(_main.player.global_position, "Beauty")
	# 散落遮蔽道具与个护区共用同一套粉雾壳和渐入渐出。
	var target := 1.0 if inside or _main.player.obscure_time > 0.0 else 0.0
	_beauty_view_blend = move_toward(_beauty_view_blend, target,
			delta / BEAUTY_VIEW_TRANSITION_TIME)
	var eased_blend := smoothstep(0.0, 1.0, _beauty_view_blend)
	for shell in _beauty_gradient_shells:
		if is_instance_valid(shell):
			shell.visible = _beauty_view_blend > 0.002
			var mat := shell.mesh.material as StandardMaterial3D
			if mat != null:
				var base_alpha := float(shell.get_meta("beauty_base_alpha", 0.0))
				var tint := mat.albedo_color
				tint.a = base_alpha * eased_blend
				mat.albedo_color = tint
	# 保持正常远裁切；通过多层半透明体积逐级吞没远景，避免6米处突然消失。
	camera.far = _default_camera_far

## 三层以相机为圆心的无碰撞粉雾壳：近物会通过深度测试挡住雾壳，远物依次叠加粉白，
## 因而真正形成3米开始、6米结束的径向渐变，而不是一张整屏色块。
func _setup_beauty_gradient_shells(camera: Camera3D) -> void:
	if not _beauty_gradient_shells.is_empty():
		return
	var specs := [
		[BEAUTY_CLEAR_DISTANCE + 0.05, 0.06],
		[4.5, 0.11],
		[6.5, 0.17],
		[9.5, 0.24],
		[13.5, 0.31],
		[18.0, 0.38],
	]
	for i in specs.size():
		var shell := MeshInstance3D.new()
		shell.name = "BeautyFogGradient_%d" % (i + 1)
		var sphere := SphereMesh.new()
		var radius := float(specs[i][0])
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		mat.albedo_color = Color(1.0, 0.82, 0.92, float(specs[i][1]))
		mat.render_priority = i + 1
		sphere.material = mat
		shell.mesh = sphere
		shell.set_meta("beauty_base_alpha", float(specs[i][1]))
		shell.visible = false
		camera.add_child(shell)
		_beauty_gradient_shells.append(shell)

func _setup_beauty_fog() -> void:
	if not _bounds.has("Beauty") or _main.find_child("BeautyVolumetricFog", true, false) != null:
		return
	var rect: Rect2 = _bounds["Beauty"]
	var volume := FogVolume.new()
	volume.name = "BeautyVolumetricFog"
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	volume.size = Vector3(rect.size.x, 5.8, rect.size.y)
	volume.position = Vector3(rect.get_center().x, 2.9, rect.get_center().y)
	var fog := FogMaterial.new()
	# 高明度草莓奶油粉：降低吸光感并提高粉白自发光，避免浓雾呈灰黑色。
	fog.density = 0.62
	fog.albedo = Color(1.0, 0.84, 0.92)
	fog.emission = Color(0.32, 0.13, 0.22)
	fog.edge_fade = 1.6
	volume.material = fog
	_main.add_child(volume)
