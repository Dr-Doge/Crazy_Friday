class_name ArtAssetCatalog extends RefCounted
## 3D美术资产清单。
##
## 运行时只读取已经烘焙、可直接拖入场景的TS CN prefab；原始FBX/GLB/Blend及
## 分离贴图只供tools/bake_art_prefabs.gd重新烘焙时使用。

const SOURCE_ROOT := "res://《疯狂星期五》3d资产（可用）"
const PREFAB_ROOT := "res://scenes/art_prefabs"
const ITEM_PREFAB_ROOT := PREFAB_ROOT + "/items"
const FIXTURE_PREFAB_ROOT := PREFAB_ROOT + "/fixtures"
const LIBRARY_PREFAB_ROOT := PREFAB_ROOT + "/library"
const MODEL_EXTENSIONS := ["fbx", "glb", "gltf", "blend"]

const ITEM_SOURCE_HINTS := {
	"king_crab":{"dir":"生鲜区", "prefixes":["皮皮虾"]},
	"wagyu":{"dir":"生鲜区", "prefixes":["老吴和牛礼盒"]},
	"salmon":{"dir":"材质贴图/哈兰德三文鱼", "prefixes":["tripo_convert_"]},
	"yogurt_pack":{"dir":"生鲜区", "prefixes":["MC希腊酸奶"]},
	"xianyu_fish":{"dir":"生鲜区", "prefixes":["咸鱼黄胖鱼"]},
	"moose_milk":{"dir":"生鲜区", "prefixes":["枫叶麋鹿鲜奶"]},
	"costcow_eggs":{"dir":"生鲜区", "prefixes":["Trader John牧场鸡蛋"]},
	"whole_paycheck_avocado":{"dir":"生鲜区", "prefixes":["Half food牛油果"]},
	"pizza":{"dir":"冷冻区", "prefixes":["夏威夷披萨"]},
	"ice_cream":{"dir":"冷冻区", "prefixes":["八羊冰激凌", "八羊冰淇淋"]},
	"dumplings":{"dir":"冷冻区", "prefixes":["速冻炒肝水饺"]},
	"five_dudes_burger":{"dir":"冷冻区", "prefixes":["五个老哥汉堡"]},
	"salted_sword":{"dir":"冷冻区", "prefixes":["尚方宝剑咸鱼", "尚方咸鱼宝剑"]},
	"frozen_pear":{"dir":"冷冻区", "prefixes":["东北黑金砖冻梨"]},
	"one_fifty_hotdog":{"dir":"冷冻区", "prefixes":["CostCow热狗"]},
	"chips":{"dir":"饮料零食区", "prefixes":["喜事桶装薯片"]},
	"cola":{"dir":"饮料零食区", "prefixes":["口渴可乐整箱"]},
	"candy":{"dir":"饮料零食区", "prefixes":["小小泡泡糖"]},
	"sparkling_water":{"dir":"饮料零食区", "prefixes":["怨气森林气泡水", "怨气树林气泡水"]},
	"paper_towels":{"dir":"饮料零食区", "prefixes":["阿诺牌蛋白粉"]},
	"tactical_spicy_strips":{"dir":"饮料零食区", "prefixes":["威龙战术辣条"]},
	"grandpa_coconut":{"dir":"饮料零食区", "prefixes":["爷树牌椰汁"]},
	"sidequest_energy":{"dir":"饮料零食区", "prefixes":["地球人电解质水", "地球人电解质饮料"]},
	"freedom_corn_chips":{"dir":"饮料零食区", "prefixes":["自由鹰超辣玉米片"]},
	"teddy":{"dir":"玩具区", "prefixes":["拉肚肚"]},
	"lego":{"dir":"玩具区", "prefixes":["激动武士矮达"]},
	"tongtongsahu":{"dir":"玩具区", "prefixes":["TongTongSahu木偶摆件"]},
	"ohio_final_boss":{"dir":"玩具区", "prefixes":["Ohio最终手办"]},
	"skibuddy_toilet":{"dir":"玩具区", "prefixes":["Skibuddy马桶盲盒"]},
	"gta7_disc":{"dir":"玩具区", "prefixes":["GTA7游戏实体光盘"]},
	"pocketmon_cards":{"dir":"玩具区", "prefixes":["Pocketmon集换卡"]},
	"biba_doll":{"dir":"玩具区", "prefixes":["碧芭娃娃"]},
}

const FIXTURE_SOURCE_HINTS := {
	"upright_shelf":[
		{"dir":"场景3d资产", "prefixes":["普通货架001（白膜）"]},
		{"dir":"", "prefixes":["huojia0001all"]},
	],
	"cold_case_1":[{"dir":"场景3d资产", "prefixes":["冰柜001（带材质）"]}],
	"cold_case_2":[{"dir":"场景3d资产", "prefixes":["冰柜002（带材质）"]}],
	"led_tube":[{"dir":"场景3d资产", "prefixes":["LED灯管"]}],
}

const MATERIAL_PROFILES := {
	"upright_shelf": {
		"albedo_sequence_dir":"材质贴图/普通货架001（材质贴图）",
		"albedo_sequence_suffix":"_base_color.jpg",
		"roughness_value":0.68,
		"metallic_value":0.12,
	},
	"cold_case_1": {
		"albedo":"材质贴图/冰柜001（材质）.fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture.jpg",
		"metallic":"材质贴图/冰柜001（材质）.fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_metallic.png",
		"normal":"材质贴图/冰柜001（材质）.fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_normal.png",
		"roughness":"材质贴图/冰柜001（材质）.fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_fbx/Meshy_AI_冰柜001（白膜）_0813084829_texture_roughness.png",
	},
	"cold_case_2": {
		"albedo":"材质贴图/冰柜002（材质）/tripo_rgb_c9b6e0d7-08b7-43d5-bea1-79bd40b20829.jpg",
		"roughness_value":0.42,
		"metallic_value":0.18,
	},
	"led_tube": {
		"albedo":"材质贴图/LED灯管/ledlight_glb_basecolor.JPEG",
		"metallic":"材质贴图/LED灯管/ledlight_glb_metallic.JPEG",
		"normal":"材质贴图/LED灯管/ledlight_glb_normal.JPEG",
		"roughness":"材质贴图/LED灯管/ledlight_glb_roughness.JPEG",
		"emission":true,
	},
	"item:sparkling_water": {
		"albedo":"材质贴图/怨气森林气泡水/green_bottle_3d_model_basecolor.JPEG",
		"metallic":"材质贴图/怨气森林气泡水/green_bottle_3d_model_metallic.JPEG",
		"normal":"材质贴图/怨气森林气泡水/green_bottle_3d_model_normal.JPEG",
		"roughness":"材质贴图/怨气森林气泡水/green_bottle_3d_model_roughness.JPEG",
	},
}

static func item_prefab_path(item_id: String) -> String:
	var path := ITEM_PREFAB_ROOT + "/" + item_id + ".tscn"
	return path if ResourceLoader.exists(path) else ""

static func fixture_prefab_path(kind: String) -> String:
	var path := FIXTURE_PREFAB_ROOT + "/" + kind + ".tscn"
	return path if ResourceLoader.exists(path) else ""

## 兼容现有调用点；从现在起“模型路径”就是已经连好贴图的prefab路径。
static func item_model_path(item_id: String) -> String:
	return item_prefab_path(item_id)

static func scene_model_path(kind: String) -> String:
	return fixture_prefab_path(kind)

static func item_source_model_path(item_id: String) -> String:
	return _resolve_source_hint(ITEM_SOURCE_HINTS.get(item_id, {}))

static func fixture_source_model_path(kind: String) -> String:
	for hint in FIXTURE_SOURCE_HINTS.get(kind, []):
		var path := _resolve_source_hint(hint)
		if path != "":
			return path
	return ""

static func source_item_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in ITEM_SOURCE_HINTS:
		out.append(item_id)
	out.sort()
	return out

static func fixture_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in FIXTURE_SOURCE_HINTS:
		out.append(kind)
	out.sort()
	return out

## 资产库总扫描；冰柜003按项目规则从任何可用prefab中排除。
static func all_source_model_paths() -> Array[String]:
	var out: Array[String] = []
	_collect_source_models(SOURCE_ROOT, out)
	out.sort()
	return out

static func library_prefab_path(source_path: String) -> String:
	return LIBRARY_PREFAB_ROOT + "/asset_%s.tscn" % source_path.sha256_text().left(12)

static func source_display_name(source_path: String) -> String:
	return source_path.get_file().get_basename()

static func material_profile(kind: String) -> Dictionary:
	return MATERIAL_PROFILES.get(kind, {})

static func item_material_profile(item_id: String) -> Dictionary:
	return MATERIAL_PROFILES.get("item:" + item_id, {})

static func available_item_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in ITEM_SOURCE_HINTS:
		if item_prefab_path(item_id) != "":
			out.append(item_id)
	out.sort()
	return out

static func _resolve_source_hint(hint: Dictionary) -> String:
	if hint.is_empty():
		return ""
	var dir := SOURCE_ROOT
	var relative_dir := str(hint.get("dir", ""))
	if relative_dir != "":
		dir += "/" + relative_dir
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return ""
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for prefix in hint.get("prefixes", []):
		for file_name in files:
			var file := str(file_name)
			if not file.get_basename().begins_with(str(prefix)):
				continue
			if file.get_extension().to_lower() not in MODEL_EXTENSIONS:
				continue
			var path := dir + "/" + file
			if ResourceLoader.exists(path):
				return path
	return ""

static func _collect_source_models(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var path := dir_path + "/" + entry
			if dir.current_is_dir():
				_collect_source_models(path, out)
			elif entry.get_extension().to_lower() in MODEL_EXTENSIONS \
					and "冰柜003" not in path and ResourceLoader.exists(path):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
