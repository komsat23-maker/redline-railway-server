extends Node

const SERVER_BUILD_TAG := "DUEL_NET_V2_2026-03-14"
const ONLINE_MAX_PLAYERS: int = 2
const SERVER_MAX_HP: int = 100
const HIT_RADIUS_PX: float = 22.0
const KILL_REWARD_PVP: int = 500
const START_MONEY_PVP: int = 800
const WEAPON_DAMAGE: Dictionary = {"ak": 20, "glock": 10}
const WEAPON_RANGE: Dictionary = {"ak": 1300.0, "glock": 1100.0}

@export var port: int = 2457

var server_states: Dictionary = {}
var server_names: Dictionary = {}


func _ready() -> void:
	var env_port := int(OS.get_environment("PORT"))
	if env_port > 0:
		port = env_port
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Server start failed: %s" % error_string(err))
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Redline dedicated websocket server listening on port %d [%s]" % [port, SERVER_BUILD_TAG])


func _on_peer_connected(id: int) -> void:
	if server_states.size() >= ONLINE_MAX_PLAYERS:
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		print("Peer rejected (max players reached): %d" % id)
		return
	_server_ensure_peer(id)
	_server_broadcast_state()
	print("Peer connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	_server_drop_peer(id)
	if _can_send_rpc_to_peers():
		rpc("net_remove_peer", id)
	_server_broadcast_state()


func _spawn_for_index(idx: int) -> Vector2:
	if idx % 2 == 0:
		return Vector2(-220.0, 0.0)
	return Vector2(220.0, 0.0)


func _server_ensure_peer(peer_id: int) -> void:
	if server_states.has(peer_id):
		return
	var idx := server_states.size()
	var spawn := _spawn_for_index(idx)
	server_states[peer_id] = {
		"x": spawn.x,
		"y": spawn.y,
		"aim": 0.0,
		"weapon": "glock",
		"hp": SERVER_MAX_HP,
		"armor": 0,
		"money": START_MONEY_PVP
	}
	server_names[peer_id] = "P%d" % peer_id


func _server_set_name(peer_id: int, nick: String) -> void:
	_server_ensure_peer(peer_id)
	var clean := nick.strip_edges()
	if clean == "":
		clean = "P%d" % peer_id
	if clean.length() > 16:
		clean = clean.substr(0, 16)
	server_names[peer_id] = clean


func _server_update_state(peer_id: int, state: Dictionary) -> void:
	_server_ensure_peer(peer_id)
	if not server_states.has(peer_id):
		return
	var s: Dictionary = server_states[peer_id]
	s["x"] = float(state.get("x", s.get("x", 0.0)))
	s["y"] = float(state.get("y", s.get("y", 0.0)))
	s["aim"] = float(state.get("aim", s.get("aim", 0.0)))
	var w := str(state.get("weapon", s.get("weapon", "glock")))
	if not WEAPON_DAMAGE.has(w):
		w = "glock"
	s["weapon"] = w
	s["armor"] = clampi(int(state.get("armor", s.get("armor", 0))), 0, 100)
	s["money"] = maxi(0, int(state.get("money", s.get("money", START_MONEY_PVP))))
	server_states[peer_id] = s


func _server_drop_peer(peer_id: int) -> void:
	server_states.erase(peer_id)
	server_names.erase(peer_id)


func _server_build_snapshot() -> Dictionary:
	var snapshot := {}
	for peer_id in server_states.keys():
		var s: Dictionary = (server_states[peer_id] as Dictionary).duplicate(true)
		s["nick"] = server_names.get(peer_id, "P%d" % peer_id)
		snapshot[str(peer_id)] = s
	return snapshot


func _can_send_rpc_to_peers() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return not multiplayer.get_peers().is_empty()


func _server_broadcast_state() -> void:
	if _can_send_rpc_to_peers():
		rpc("net_receive_world_state", _server_build_snapshot())


func _distance_point_to_ray(origin: Vector2, dir: Vector2, point: Vector2, max_range: float) -> float:
	var to_p := point - origin
	var t := to_p.dot(dir)
	if t < 0.0 or t > max_range:
		return 999999.0
	var closest := origin + dir * t
	return closest.distance_to(point)


func _server_handle_shot(sender: int, payload: Dictionary) -> void:
	_server_ensure_peer(sender)
	if not server_states.has(sender):
		return
	var shooter_state: Dictionary = server_states[sender]
	var shooter_pos := Vector2(float(shooter_state.get("x", 0.0)), float(shooter_state.get("y", 0.0)))
	var dir := Vector2(float(payload.get("dx", 0.0)), float(payload.get("dy", 0.0)))
	if dir.length_squared() <= 0.0001:
		return
	dir = dir.normalized()
	var weapon := str(payload.get("weapon", "glock"))
	if not WEAPON_DAMAGE.has(weapon):
		weapon = "glock"
	var max_range := float(WEAPON_RANGE.get(weapon, 1000.0))
	var victim_id: int = -1
	var best_dist_along: float = 999999.0
	for peer_id in server_states.keys():
		if int(peer_id) == sender:
			continue
		var target_state: Dictionary = server_states[peer_id]
		var target_pos := Vector2(float(target_state.get("x", 0.0)), float(target_state.get("y", 0.0)))
		var to_target := target_pos - shooter_pos
		var along := to_target.dot(dir)
		if along < 0.0 or along > max_range:
			continue
		var dist := _distance_point_to_ray(shooter_pos, dir, target_pos, max_range)
		if dist <= HIT_RADIUS_PX and along < best_dist_along:
			best_dist_along = along
			victim_id = int(peer_id)
	if victim_id != -1:
		var v: Dictionary = server_states[victim_id]
		var dmg_total := int(WEAPON_DAMAGE[weapon])
		var armor_now := int(v.get("armor", 0))
		var absorbed := 0
		if armor_now > 0:
			absorbed = mini(armor_now, int(round(float(dmg_total) * 0.6)))
			armor_now -= absorbed
		var hp_loss := maxi(0, dmg_total - absorbed)
		var hp_now := int(v.get("hp", SERVER_MAX_HP))
		hp_now -= hp_loss
		if hp_now <= 0:
			hp_now = SERVER_MAX_HP
			armor_now = 0
			var spawn := _spawn_for_index(0 if victim_id % 2 == 0 else 1)
			v["x"] = spawn.x
			v["y"] = spawn.y
		v["hp"] = clampi(hp_now, 0, SERVER_MAX_HP)
		v["armor"] = clampi(armor_now, 0, 100)
		server_states[victim_id] = v
		if hp_now == SERVER_MAX_HP:
			var shooter_state: Dictionary = server_states[sender]
			var shooter_money := int(shooter_state.get("money", START_MONEY_PVP)) + KILL_REWARD_PVP
			shooter_state["money"] = shooter_money
			server_states[sender] = shooter_state
			if _can_send_rpc_to_peers():
				rpc_id(sender, "net_award_kill_reward", KILL_REWARD_PVP)
	if _can_send_rpc_to_peers():
		rpc("net_spawn_shot_fx", sender, payload)
	_server_broadcast_state()


@rpc("any_peer")
func net_submit_profile(profile: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_server_set_name(sender, str(profile.get("nick", "Player")))
	_server_broadcast_state()


@rpc("any_peer", "unreliable")
func net_submit_state(state: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_server_update_state(sender, state)
	_server_broadcast_state()


@rpc("any_peer", "unreliable")
func net_submit_shot(payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_server_handle_shot(sender, payload)


@rpc("authority", "call_local", "unreliable")
func net_receive_world_state(_snapshot: Dictionary) -> void:
	pass


@rpc("authority", "call_local", "unreliable")
func net_spawn_shot_fx(_peer_id: int, _payload: Dictionary) -> void:
	pass


@rpc("authority", "call_local")
func net_award_kill_reward(_amount: int) -> void:
	pass


@rpc("authority", "call_local")
func net_remove_peer(_peer_id: int) -> void:
	pass
