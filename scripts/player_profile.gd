class_name PlayerProfile
## 本机玩家档案:昵称 + 配色。存在 user://profile.cfg,下次启动自动带出。
##
## 联机时这份档案会随"加入房间"上报给主机,主机在开局时把全员档案
## 分发给所有人,保证每台机器上看到的名字与颜色完全一致。

const PATH := "user://profile.cfg"
const MAX_NAME_LEN := 8

## 可选配色。联机时若有人撞色,开局前由 resolve_colors() 自动错开
const COLORS: Array[Color] = [
	Color(0.25, 0.50, 0.90),   # 蓝
	Color(0.95, 0.55, 0.20),   # 橙
	Color(0.30, 0.80, 0.45),   # 绿
	Color(0.70, 0.40, 0.90),   # 紫
	Color(0.95, 0.40, 0.55),   # 粉
	Color(0.35, 0.80, 0.85),   # 青
	Color(0.95, 0.85, 0.30),   # 黄
	Color(0.60, 0.42, 0.28),   # 棕
]

const COLOR_NAMES: Array[String] = ["蓝", "橙", "绿", "紫", "粉", "青", "黄", "棕"]

## 没起名时的随机默认名
const DEFAULT_NAMES: Array[String] = [
	"扫货王", "代购老王", "跑腿小张", "囤货狂",
	"批发大户", "手快张三", "抢购达人", "满载而归",
]

static var display_name := ""
static var color_index := 0
static var _loaded := false

## 读档(幂等)。没有存档或名字为空时给一个随机默认档案。
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		display_name = sanitize(str(cfg.get_value("profile", "name", "")))
		color_index = clampi(int(cfg.get_value("profile", "color", 0)), 0, COLORS.size() - 1)
	if display_name == "":
		display_name = DEFAULT_NAMES.pick_random()
		color_index = randi() % COLORS.size()

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", display_name)
	cfg.set_value("profile", "color", color_index)
	cfg.save(PATH)

static func set_name_and_save(raw: String) -> String:
	display_name = sanitize(raw)
	if display_name == "":
		display_name = DEFAULT_NAMES.pick_random()
	save()
	return display_name

static func set_color_and_save(idx: int) -> void:
	color_index = clampi(idx, 0, COLORS.size() - 1)
	save()

static func color() -> Color:
	return COLORS[clampi(color_index, 0, COLORS.size() - 1)]

static func color_of(idx: int) -> Color:
	return COLORS[clampi(idx, 0, COLORS.size() - 1)]

static func color_name_of(idx: int) -> String:
	return COLOR_NAMES[clampi(idx, 0, COLOR_NAMES.size() - 1)]

## 昵称清洗:去首尾空白、压掉换行制表、限长。
## 方括号必须替掉:昵称会进 HUD 的 RichTextLabel(开了 bbcode),
## 否则 "[color=red]" 这种输入会被当标签解析,破坏排版。
static func sanitize(raw: String) -> String:
	var s := raw.strip_edges()
	for ch in ["\n", "\r", "\t"]:
		s = s.replace(ch, " ")
	s = s.replace("[", "(").replace("]", ")")
	if s.length() > MAX_NAME_LEN:
		s = s.substr(0, MAX_NAME_LEN)
	return s.strip_edges()

##撞色处理:场上两人同色会分不清谁是谁。
## 按座位顺序保留先到者的颜色,后来者顺移到最近的空闲色位。
static func resolve_colors(indices: Array) -> Array[int]:
	var used := {}
	var out: Array[int] = []
	for raw in indices:
		var idx := clampi(int(raw), 0, COLORS.size() - 1)
		if used.has(idx):
			for step in COLORS.size():
				var cand := (idx + step + 1) % COLORS.size()
				if not used.has(cand):
					idx = cand
					break
		used[idx] = true
		out.append(idx)
	return out

## 重名处理:同名也难分辨,给重复者加序号后缀
static func resolve_names(names: Array) -> Array[String]:
	var seen := {}
	var out: Array[String] = []
	for raw in names:
		var n := sanitize(str(raw))
		if n == "":
			n = DEFAULT_NAMES[out.size() % DEFAULT_NAMES.size()]
		if seen.has(n):
			seen[n] = int(seen[n]) + 1
			n = "%s%d" % [n, seen[n]]
		else:
			seen[n] = 1
		out.append(n)
	return out
