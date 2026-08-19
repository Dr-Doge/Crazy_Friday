class_name RegionDirector extends RefCounted
## New_Level分区规则：处理冷冻/个护状态，并驱动生鲜、熊孩子、挡路大妈生态。

const FREEZE_FILL_TIME := 18.0
const FREEZE_DURATION := 8.0
const THAW_TIME := 9.0
const BEAUTY_VISIBILITY_FACTOR := 0.20

var _main
var _bounds: Dictionary = {}
var _region_npcs: Array[RegionNpc] = []
var _live_goods: Array[Item] = []
var _live_jump_time := {}

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
	_tick_live_goods(delta)

func _spawn_region_ecology() -> void:
	# 熊孩子固定6名，分散在玩具与零食两区；大妈固定8名，只是服饰区障碍生态，
	# 两者都不是参赛扫货AI，不占四队八席。
	var kid_rects: Array[Rect2] = []
	for key in ["Toys", "Snacks"]:
		if _bounds.has(key):
			kid_rects.append(_bounds[key])
	if not kid_rects.is_empty():
		for i in 6:
			_spawn_region_npc(RegionNpc.Kind.KID, kid_rects[i % kid_rects.size()], i, 6)
	if _bounds.has("Clothing"):
		for i in 8:
			_spawn_region_npc(RegionNpc.Kind.BLOCKING_GRANNY, _bounds["Clothing"], i, 8)
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
		var id := "king_crab" if i % 2 == 0 else "xianyu_fish"
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

func _tick_live_goods(delta: float) -> void:
	for item in _live_goods:
		if not is_instance_valid(item):
			continue
		if item.state != Item.ItemState.FREE:
			continue
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
	if not _bounds.has(key):
		return false
	var rect: Rect2 = _bounds[key]
	return rect.has_point(Vector2(actor.global_position.x, actor.global_position.z))

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
	# AI仍按进入深度逐渐缩短感知，最深处约只保留5米观察距离。
	if actor is Player:
		return
	var rect: Rect2 = _bounds["Beauty"]
	var p := Vector2(actor.global_position.x, actor.global_position.z)
	var depth := minf(minf(p.x - rect.position.x, rect.end.x - p.x),
			minf(p.y - rect.position.y, rect.end.y - p.y))
	var blend := smoothstep(0.0, 2.2, maxf(0.0, depth))
	actor.apply_obscure(lerpf(1.0, BEAUTY_VISIBILITY_FACTOR, blend), 0.22)

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
	# 约5米后只剩轮廓；边缘羽化让玩家走入时逐渐被雾吞没。
	fog.density = 0.46
	fog.albedo = Color(0.91, 0.84, 0.96)
	fog.emission = Color(0.045, 0.025, 0.055)
	fog.edge_fade = 2.2
	volume.material = fog
	_main.add_child(volume)
