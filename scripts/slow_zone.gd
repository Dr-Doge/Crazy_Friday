class_name SlowZone extends Node3D
## 通用减速地形：李洋促销链接与软糖道具共用。
## 主机负责判定，客户端只显示；immune_actor 可让施法者免疫自己的区域。

var radius := 3.0
var lifetime := 6.0
var slow_factor := 0.6
var immune_actor: Actor = null
var disc: MeshInstance3D
var label: Label3D
var _total_life := 6.0
var _pulse := 0.0

static func create(root: Node3D, pos: Vector3, zone_radius: float, life: float,
		factor: float, immune: Actor, title: String, color: Color) -> SlowZone:
	var z := SlowZone.new()
	z.radius = zone_radius
	z.lifetime = life
	z._total_life = life
	z.slow_factor = factor
	z.immune_actor = immune
	z.position = Vector3(pos.x, 0.0, pos.z)

	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = zone_radius
	cyl.bottom_radius = zone_radius
	cyl.height = 0.035
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.24)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.32
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	mi.mesh = cyl
	mi.position.y = 0.035
	z.add_child(mi)
	z.disc = mi

	var lb := Label3D.new()
	lb.text = title
	lb.font = Catalog.ui_font_bold()
	lb.font_size = 40
	lb.pixel_size = 0.003
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.modulate = color.lightened(0.25)
	lb.outline_size = 10
	lb.outline_modulate = Color(0.08, 0.02, 0.08, 0.92)
	lb.position = Vector3(0, 0.32, 0)
	z.add_child(lb)
	z.label = lb

	root.add_child(z)
	return z

func _physics_process(delta: float) -> void:
	lifetime -= delta
	_pulse += delta
	if lifetime <= 0.0:
		queue_free()
		return
	var fade := clampf(lifetime / minf(1.2, _total_life), 0.0, 1.0)
	var pulse_scale := 1.0 + sin(_pulse * 5.0) * 0.025
	disc.scale = Vector3(pulse_scale, 1.0, pulse_scale)
	label.modulate.a = fade
	# 客户端是纯渲染傀儡，减速状态由主机位置包自然体现。
	if Main.instance != null and Main.instance.net_client:
		return
	for node in get_tree().get_nodes_in_group("characters"):
		if not (node is Actor):
			continue
		var a: Actor = node
		if a == immune_actor or a.downed or a.immune:
			continue
		var offset := a.global_position - global_position
		offset.y = 0.0
		if offset.length() <= radius:
			a.apply_slow(slow_factor, 0.16)
