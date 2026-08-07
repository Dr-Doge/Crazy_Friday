class_name NavGrid
## 寻路服务:AStarGrid2D,格子边长1米,世界坐标的 (x, z) 直接映射到格子。
## 大妈NPC通过 Main.find_path() 使用本模块。

## 找不到可走格子时的哨兵值
const INVALID := Vector2i(9999, 9999)

## 世界坐标→ 格子坐标
static func cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.z)))

## 从c 起向外螺旋找最近的可走格子(半径上限5格)。
## 终点落在货架体内时靠这个兜底,否则大妈会走不到、原地卡死(v0.4.1 修过的坑)。
static func nearest_open(grid: AStarGrid2D, c: Vector2i) -> Vector2i:
	for r in 5:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var id := c + Vector2i(dx, dy)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
					return id
	return INVALID

## 返回路点数组(y=0)。无解时退化为"直奔终点",保证调用方永远拿到可用路径。
static func find_path(grid: AStarGrid2D, from: Vector3, to: Vector3) -> Array:
	var fallback: Array = [Vector3(to.x, 0, to.z)]
	if grid == null:
		return fallback
	var a := nearest_open(grid, cell(from))
	var b := nearest_open(grid, cell(to))
	if a == INVALID or b == INVALID:
		return fallback
	var ids := grid.get_id_path(a, b)
	if ids.is_empty():
		return fallback
	var pts: Array = []
	for id in ids:
		pts.append(Vector3(id.x + 0.5, 0, id.y + 0.5))
	pts.append(Vector3(to.x, 0, to.z))
	return pts
