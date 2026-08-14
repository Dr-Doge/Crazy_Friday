class_name ObscureZone extends Node3D
## 散落遮挡区：统一承载纸屑、米粒、包装与填充物的范围视野干扰。
## 主机负责角色/NPC感知判定；客户端通过网络状态包显示本机遮挡。

var radius := Catalog.SCATTER_RADIUS
var lifetime := Catalog.SCATTER_LIFE
var perception_factor := Catalog.SCATTER_PERCEPTION_FACTOR
var _total_life := Catalog.SCATTER_LIFE
var _cloud_root: Node3D
var _pulse := 0.0

static func create(root: Node3D, pos: Vector3, zone_radius := Catalog.SCATTER_RADIUS,
		life := Catalog.SCATTER_LIFE,
		factor := Catalog.SCATTER_PERCEPTION_FACTOR) -> ObscureZone:
	var z := ObscureZone.new()
	z.radius = zone_radius
	z.lifetime = life
	z._total_life = life
	z.perception_factor = factor
	z.position = Vector3(pos.x, 0.0, pos.z)
	z.add_to_group("scatter_zones")
	z._build_visual()
	root.add_child(z)
	return z

func _build_visual() -> void:
	_cloud_root = Node3D.new()
	add_child(_cloud_root)
	var colors := [
		Color(0.78, 0.68, 0.46, 0.58),
		Color(0.72, 0.74, 0.68, 0.52),
		Color(0.42, 0.36, 0.24, 0.56),
	]
	for i in 32:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var size := 0.62 + float(i % 5) * 0.11
		sphere.radius = size
		sphere.height = size * 1.65
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = mat
		mi.mesh = sphere
		var angle := TAU * float(i) / 32.0
		var ring := radius * (0.08 + 0.76 * float((i * 11) % 29) / 28.0)
		mi.position = Vector3(cos(angle) * ring, 0.35 + float(i % 4) * 0.48, sin(angle) * ring)
		_cloud_root.add_child(mi)

	var lb := Label3D.new()
	lb.text = "散落遮挡"
	lb.font = Catalog.ui_font_bold()
	lb.font_size = 40
	lb.pixel_size = 0.003
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1.0, 0.88, 0.58)
	lb.outline_size = 10
	lb.outline_modulate = Color(0.08, 0.06, 0.03, 0.9)
	lb.position = Vector3(0, 1.45, 0)
	_cloud_root.add_child(lb)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	_pulse += delta
	if lifetime <= 0.0:
		queue_free()
		return
	var fade_scale := clampf(lifetime / minf(0.7, _total_life), 0.05, 1.0)
	var pulse_scale := 1.0 + sin(_pulse * 4.5) * 0.035
	_cloud_root.scale = Vector3.ONE * fade_scale * pulse_scale
	if Main.instance != null and Main.instance.net_client:
		return
	for node in get_tree().get_nodes_in_group("characters"):
		if not (node is Actor):
			continue
		var actor: Actor = node
		if actor.downed or actor.immune:
			continue
		var offset := actor.global_position - global_position
		offset.y = 0.0
		if offset.length() <= radius:
			actor.apply_obscure(perception_factor, 0.16)
