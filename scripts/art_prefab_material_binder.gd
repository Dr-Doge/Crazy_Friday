@tool
class_name ArtPrefabMaterialBinder extends Node3D
## 让轻量prefab在被拖入编辑器或运行时后自动补齐分离交付的贴图。

@export var material_profile_key := ""

func _enter_tree() -> void:
	# Many marketplace FBX files contain their authoring cameras and 1000-energy
	# preview lights. They are not part of the game asset and become catastrophic
	# when a shelf module is repeated across the level, so strip them immediately
	# in both the editor and the running game.
	_strip_imported_render_helpers(self)

func _ready() -> void:
	if material_profile_key == "":
		return
	var profile := ArtAssetCatalog.item_material_profile(
			material_profile_key.trim_prefix("item:")) \
			if material_profile_key.begins_with("item:") \
			else ArtAssetCatalog.material_profile(material_profile_key)
	ArtAssetFitter.apply_material_profile(self, profile)

func _strip_imported_render_helpers(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child is WorldEnvironment:
			child.free()
			continue
		_strip_imported_render_helpers(child)
