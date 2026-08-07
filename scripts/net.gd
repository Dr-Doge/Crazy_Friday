class_name Net extends Node
## 局域网联机(2-6人,同一网络):主机权威模拟,客户端发输入、收状态渲染。
## 大厅制:主机建房→客户端陆续加入→主机点"开始对局"统一开局。
## 世界用共享种子在各端确定性重建,运行时只同步动态状态(20Hz不可靠)+关键事件(可靠RPC)。

const PORT := 7788
const MAX_CLIENTS := 5     # 主机+5客户端=6人
const SYNC_INTERVAL := 3   # 每3个物理帧同步一次(约20Hz)
const NET_VERSION := 3     # 联机协议版本:两端不一致直接拒绝,防止种子世界不同步

var main: Main
var is_host := false
var active := false            # 联机对局进行中
var peers: Array[int] = []     # 大厅接入顺序(开局时座位=下标+1)
var seat_peers: Array[int] = []# 开局后:座位i(≥1)对应seat_peers[i-1]的peer id
## 大厅档案:peer_id -> {name: String, color: int}。客户端连上后自行上报,
## 之后在大厅里改名/换色也会实时推送过来。
var lobby_profiles := {}
var _frame := 0
var _item_cursor := 0
var carts_net: Array = []      # 同步用固定顺序:玩家车们+大妈车们
var grannies_net: Array = []

func peer_of_seat(idx: int) -> int:
	if idx <= 0 or idx > seat_peers.size():
		return 0
	return seat_peers[idx - 1]

func seat_of_peer(pid: int) -> int:
	var i := seat_peers.find(pid)
	return i + 1 if i >= 0 else -1

func peer_alive(pid: int) -> bool:
	return pid != 0 and multiplayer.get_peers().has(pid)

## 本机局域网IPv4列表(菜单直接显示,不必为了看IP去建房)
static func local_ips() -> String:
	var ips: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			ips.append(a)
	return ", ".join(ips) if not ips.is_empty() else "127.0.0.1"

func host_room() -> String:
	var p := ENetMultiplayerPeer.new()
	var port := PORT
	var env_port := OS.get_environment("WHITEBOX_PORT")
	if env_port != "":
		port = int(env_port)   # 单机多实例测试用
	var err := p.create_server(port, MAX_CLIENTS)
	if err != OK:
		print("[Net] 创建服务器失败 err=", err)
		return ""
	multiplayer.multiplayer_peer = p
	is_host = true
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)
	print("[Net] 服务器已监听端口 ", port, " (最多", MAX_CLIENTS + 1, "人)")
	return local_ips()

func join_room(ip: String) -> bool:
	# 关键:先彻底退出"主机"身份再加入!
	# 常见操作是双方都先点了"创建房间"看自己的IP,再由一方加入对方——
	# 若不清掉is_host与peer_connected回调,加入方连上后会把自己也当主机开局。
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null   # 关掉本机的房间监听
	is_host = false
	active = false
	peers = []
	seat_peers = []
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip.strip_edges(), PORT) != OK:
		return false
	multiplayer.multiplayer_peer = p
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
	if not multiplayer.connection_failed.is_connected(_on_connect_fail):
		multiplayer.connection_failed.connect(_on_connect_fail)
	if not multiplayer.server_disconnected.is_connected(_on_server_lost):
		multiplayer.server_disconnected.connect(_on_server_lost)
	print("[Net] 开始连接 ", ip.strip_edges(), ":", PORT)
	return true

## 客户端:主机没了→回开始界面
func _on_server_lost() -> void:
	print("[Net] 与主机断开(server_disconnected)")
	multiplayer.multiplayer_peer = null
	main.get_tree().paused = false
	main.get_tree().reload_current_scene()

func _on_connected_ok() -> void:
	print("[Net] 已连上主机,等待开局指令")
	main.hud.set_menu_status("已连上主机!正在同步你的角色档案...")
	push_profile()

## 把本机档案(昵称+配色)上报给主机。在大厅里改名换色也调这个。
func push_profile() -> void:
	if is_host:
		# 主机自己就是权威,直接刷新大厅
		if active:
			return
		_lobby_update()
		return
	if multiplayer.multiplayer_peer == null or not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	rpc_id(1, "client_profile", PlayerProfile.display_name, PlayerProfile.color_index)

@rpc("any_peer", "call_remote", "reliable")
func client_profile(pname: String, color: int) -> void:
	if not is_host or active:
		return
	var pid := multiplayer.get_remote_sender_id()
	lobby_profiles[pid] = {
		"name": PlayerProfile.sanitize(pname),
		"color": clampi(color, 0, PlayerProfile.COLORS.size() - 1),
	}
	_lobby_update()

func _on_connect_fail() -> void:
	print("[Net] 连接失败")
	main.hud.set_menu_status("连接失败,请确认对方已创建房间且IP正确")

func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	# 对局已开始:拒绝迟到的连接
	if active or main.game_started:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null:
			enet.disconnect_peer(id)
		return
	peers.append(id)
	print("[Net] 玩家接入 peer=", id, " 大厅人数=", peers.size() + 1)
	_lobby_update()
	# 自动化测试:WHITEBOX_HOST=N表示凑够N名客户端自动开局(默认1)
	var env_host := OS.get_environment("WHITEBOX_HOST")
	if env_host != "" and peers.size() >= maxi(1, int(env_host)):
		start_game()

## 汇总大厅成员并推给所有人。下标即座位号,0=房主
func _lobby_update() -> void:
	var members := lobby_members()
	main.hud.set_lobby(members, true)
	main.hud.set_menu_status("房间已开:%d/%d 人。人齐了就点\"开始对局\"" % [members.size(), MAX_CLIENTS + 1])
	for pid in peers:
		rpc_id(pid, "ev_lobby", members)

## [{name, color}] 按座位顺序;尚未上报档案的显示占位
func lobby_members() -> Array:
	var out: Array = [{
		"name": PlayerProfile.display_name,
		"color": PlayerProfile.color_index,
	}]
	for pid in peers:
		var prof: Dictionary = lobby_profiles.get(pid, {})
		out.append({
			"name": str(prof.get("name", "连接中…")),
			"color": int(prof.get("color", 0)),
		})
	return out

@rpc("authority", "call_remote", "reliable")
func ev_lobby(members: Array) -> void:
	main.hud.set_lobby(members, false)
	main.hud.set_menu_status("已在房间中(%d/%d 人),等待房主开始对局..." % [members.size(), MAX_CLIENTS + 1])

## 主机点"开始对局":分配座位、消歧昵称与配色,统一开局
func start_game() -> void:
	if not is_host or active or peers.is_empty():
		return
	active = true
	seat_peers = peers.duplicate()
	var world_seed := randi()
	var total := peers.size() + 1
	# 撞色/重名会导致场上分不清谁是谁,由主机统一消歧后下发,保证各端一致
	var members := lobby_members()
	var raw_names: Array = []
	var raw_colors: Array = []
	for m in members:
		raw_names.append(m["name"])
		raw_colors.append(m["color"])
	var names := PlayerProfile.resolve_names(raw_names)
	var colors := PlayerProfile.resolve_colors(raw_colors)
	for i in peers.size():
		rpc_id(peers[i], "client_start", world_seed, main.pending_npc, NET_VERSION,
				i + 1, total, names, colors)
	print("[Net] 进入对局 身份=主机 玩家数=", total)
	main.start_mp(true, world_seed, main.pending_npc, 0, total, names, colors)

func _on_peer_left(id: int) -> void:
	if is_host:
		if not active:
			print("[Net] 大厅离开 peer=", id)
			peers.erase(id)
			lobby_profiles.erase(id)
			_lobby_update()
			return
		# 对局中有客户端掉线:该玩家退场,比赛继续
		var seat := seat_of_peer(id)
		if seat > 0:
			main.on_player_disconnected(seat)
		return
	# 客户端侧其他peer离开不处理(主机没了走server_disconnected)

func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null

@rpc("authority", "call_remote", "reliable")
func client_start(world_seed: int, npc: int, ver: int, my_seat: int, total: int,
		names: Array, colors: Array) -> void:
	print("[Net] 收到开局指令 seed=", world_seed, " npc=", npc, " ver=", ver, " 座位=", my_seat, " 总人数=", total)
	if ver != NET_VERSION:
		main.hud.set_menu_status("联机失败:各电脑的游戏版本不一致!\n请把同一份exe拷给所有人后重试")
		multiplayer.multiplayer_peer = null
		return
	if main.game_started:
		return
	active = true
	print("[Net] 进入对局 身份=客户端 座位=", my_seat)
	main.start_mp(false, world_seed, npc, my_seat, total, names, colors)

## 开局后由main调用:登记同步对象表(两端顺序一致)
func register_world() -> void:
	carts_net = []
	for p in main.players:
		carts_net.append(p.cart)
	for g in main.grannies:
		carts_net.append(g.cart)
	grannies_net = []
	for g in main.grannies:
		grannies_net.append(g)

func granny_left(g: Granny) -> void:
	if not active or not is_host:
		return
	var i := grannies_net.find(g)
	if i >= 0:
		rpc("ev_granny_left", i)

func item_gone(it: Item) -> void:
	if not active or not is_host:
		return
	var i := main.all_items.find(it)
	if i >= 0:
		rpc("ev_item_gone", i)

func _physics_process(_delta: float) -> void:
	if not active:
		return
	_frame += 1
	if is_host:
		# 所有客户端都断开时不再广播(向已死peer发包会刷channel报错)
		if multiplayer.get_peers().is_empty():
			return
		# 玩家包与车辆包20Hz各自独立发(6人数据合包会超MTU);大妈/商品包10Hz交替
		if _frame % SYNC_INTERVAL == 0:
			rpc("sync_state", _gather_players())
			rpc("sync_state", _gather_carts())
			@warning_ignore("integer_division")
			if (_frame / SYNC_INTERVAL) % 2 == 0:
				rpc("sync_state", _gather_world())
	else:
		# 客户端:每帧上送持续输入+本机镜头朝向(主机按客户端视角解算移动方向)
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		rpc_id(1, "client_input", mv,
				Input.is_action_pressed("sprint"),
				Input.is_action_pressed("brace"),
				Input.is_action_pressed("interact"),
				main.cam_yaw)

func send_action(kind: String, dir := Vector3.ZERO) -> void:
	if active and not is_host:
		rpc_id(1, "client_action", kind, dir)

# ---------- 主机侧接收 ----------

@rpc("any_peer", "call_remote", "unreliable")
func client_input(mv: Vector2, sprint: bool, brace: bool, interact_held: bool, cam_yaw: float = 0.0) -> void:
	if not is_host:
		return
	var seat := seat_of_peer(multiplayer.get_remote_sender_id())
	if seat <= 0 or seat >= main.players.size():
		return
	# 【权威边界】绝不直接采信远程输入。
	# 本机 Input.get_vector() 天然落在单位圆内,但改过的客户端可以发 (0,-50):
	# 推车路径的 throttle := -input.y 会直接乘进 apply_central_force(player.gd),
	# 等于把推力和撞击动能放大数十倍(徒步路径有 normalized() 兜住,推车没有)。
	# NaN/inf 则会污染物理状态并在各端扩散,必须整帧丢弃。
	if not mv.is_finite() or not is_finite(cam_yaw):
		return
	if mv.length() > 1.0:
		mv = mv.normalized()
	main.players[seat].set_net_input(mv, sprint, brace, interact_held, cam_yaw)

@rpc("any_peer", "call_remote", "reliable")
func client_action(kind: String, dir: Vector3) -> void:
	if not is_host:
		return
	var seat := seat_of_peer(multiplayer.get_remote_sender_id())
	if seat <= 0:
		return
	# 同上:方向向量只取朝向,长度一律归一(肘击/投掷会用它施力)
	if not dir.is_finite():
		return
	if dir.length() > 0.001:
		dir = dir.normalized()
	main.apply_remote_action(seat, kind, dir)

# ---------- 状态同步 ----------

var _text_cache := {}

## 字符串(提示/想要/气泡)变化才走可靠通道,20Hz包只装数值,压在MTU内
func _sync_text(key: String, kind: String, idx: int, text: String) -> void:
	if _text_cache.get(key, "") != text:
		_text_cache[key] = text
		rpc("ev_text", kind, idx, text)

@rpc("authority", "call_remote", "reliable")
func ev_text(kind: String, idx: int, text: String) -> void:
	match kind:
		"pp":
			if idx < main.players.size():
				main.players[idx].prompt_text = text
		"gw":
			if idx < grannies_net.size() and is_instance_valid(grannies_net[idx]):
				grannies_net[idx].want_label.text = text
		"gb":
			if idx < grannies_net.size() and is_instance_valid(grannies_net[idx]):
				grannies_net[idx].bubble.text = text
				grannies_net[idx].bubble.visible = text != ""

## 玩家包(20Hz):全部玩家的位姿与状态
func _gather_players() -> Dictionary:
	var ps: Array = []
	for i in main.players.size():
		var p := main.players[i]
		ps.append([p.global_position, p.body_root.rotation.y, p.hand_pose,
				p.imbalance, p.stamina, p.downed, p.braced,
				p.channel_progress, p.body_root.rotation.x,
				p.locate_cd, p.bottle_cd, p.brace_cd])
		_sync_text("pp%d" % i, "pp", i, p.prompt_text)
	return {"p": ps}

## 车辆包(20Hz):全部购物车+闸机+计时
func _gather_carts() -> Dictionary:
	var cs: Array = []
	for c in carts_net:
		if is_instance_valid(c):
			cs.append([c.global_position, c.global_rotation])
		else:
			cs.append(null)
	var cos: Array = []
	for co in main.checkouts:
		cos.append([co.gate.position.y, co.south_gate.position.y])
	return {"t": main.time_left, "ig": main.in_grace, "gl": main.grace_left,
			"c": cs, "co": cos}

## 世界包(10Hz):大妈+活动商品(货架上没动过的跳过,各端初始布局一致;超量轮转分片)
func _gather_world() -> Dictionary:
	var gs: Array = []
	for i in grannies_net.size():
		var g = grannies_net[i]
		if is_instance_valid(g):
			gs.append([g.global_position, g.body_root.rotation.y, g.hand_pose,
					g.body_root.rotation.x])
			_sync_text("gw%d" % i, "gw", i, g.want_label.text)
			_sync_text("gb%d" % i, "gb", i, g.bubble.text if g.bubble.visible else "")
		else:
			gs.append(null)
	var act: Array = []
	for i in main.all_items.size():
		var it: Item = main.all_items[i]
		if not is_instance_valid(it):
			continue
		if it.state == Item.ItemState.SHELVED:
			continue
		act.append([i, it.state, it.global_position, it.global_rotation.y])
	var its: Array = []
	if act.size() <= 14:
		its = act
	else:
		for j in 14:
			its.append(act[(_item_cursor + j) % act.size()])
		_item_cursor = (_item_cursor + 14) % act.size()
	return {"g": gs, "i": its}

@rpc("authority", "call_remote", "unreliable")
func sync_state(d: Dictionary) -> void:
	if is_host:
		return
	main.apply_net_state(d)

# ---------- 可靠事件(主机→客户端) ----------

@rpc("authority", "call_remote", "reliable")
func ev_float(pos: Vector3, text: String, color: Color, size: int) -> void:
	Main.float_text(self, pos, text, color, size)

@rpc("authority", "call_remote", "reliable")
func ev_broadcast(text: String) -> void:
	main.hud.broadcast(text)

@rpc("authority", "call_remote", "reliable")
func ev_shake(v: float) -> void:
	main.add_camera_shake(v)

@rpc("authority", "call_remote", "reliable")
func ev_hud(rows: Array, score: int, hot_carts: Array) -> void:
	main.client_hud(rows, score, hot_carts)

@rpc("authority", "call_remote", "reliable")
func ev_locate(idxs: Array) -> void:
	main.client_locate(idxs)

@rpc("authority", "call_remote", "reliable")
func ev_spawn_items(ids: Array, poss: Array) -> void:
	main.client_spawn_items(ids, poss)

@rpc("authority", "call_remote", "reliable")
func ev_slippery(pos: Vector3, life: float) -> void:
	SlipperyZone.create(main, pos, Vector3(3.5, 2, 3.5), life)

@rpc("authority", "call_remote", "reliable")
func ev_item_gone(idx: int) -> void:
	main.client_item_gone(idx)

@rpc("authority", "call_remote", "reliable")
func ev_granny_left(idx: int) -> void:
	if idx >= 0 and idx < grannies_net.size():
		var g = grannies_net[idx]
		if is_instance_valid(g):
			if is_instance_valid(g.cart):
				g.cart.queue_free()
			g.queue_free()
		grannies_net[idx] = null

@rpc("authority", "call_remote", "reliable")
func ev_result(lines: Array) -> void:
	main.client_show_result(lines)
