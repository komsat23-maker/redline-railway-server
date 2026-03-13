extends Node

const ONLINE_VIRTUAL_SIZE := Vector2(1920.0, 1080.0)
const ONLINE_MAX_PLAYERS := 2
const SERVER_BUILD_TAG := "SIMPLE_NET_V2_2026-03-13"

@export var port: int = 2457
@export var tick_rate: float = 30.0
@export var move_speed: float = 440.0
@export var pawn_radius: float = 18.0

var tick_accum: float = 0.0
var inputs: Dictionary = {}
var positions: Dictionary = {}


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


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	tick_accum += delta
	var step := 1.0 / maxf(1.0, tick_rate)
	while tick_accum >= step:
		tick_accum -= step
		_server_step(step)
		_broadcast_world_state()


func _on_peer_connected(id: int) -> void:
	if positions.size() >= ONLINE_MAX_PLAYERS:
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		print("Peer rejected (max players reached): %d" % id)
		return
	_register_peer(id)
	_broadcast_world_state()
	print("Peer connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	positions.erase(id)
	inputs.erase(id)
	rpc("net_remove_peer", id)
	_broadcast_world_state()


func _register_peer(peer_id: int) -> void:
	if positions.has(peer_id):
		return
	var spawn := Vector2(ONLINE_VIRTUAL_SIZE.x * 0.35, ONLINE_VIRTUAL_SIZE.y * 0.5)
	if positions.size() == 1:
		spawn = Vector2(ONLINE_VIRTUAL_SIZE.x * 0.65, ONLINE_VIRTUAL_SIZE.y * 0.5)
	positions[peer_id] = spawn
	inputs[peer_id] = {"u": 0, "d": 0, "l": 0, "r": 0}


func _sanitize_input(packet: Dictionary) -> Dictionary:
	return {
		"u": int(bool(packet.get("u", 0))),
		"d": int(bool(packet.get("d", 0))),
		"l": int(bool(packet.get("l", 0))),
		"r": int(bool(packet.get("r", 0)))
	}


func _server_step(step: float) -> void:
	for peer_id in positions.keys():
		var pos: Vector2 = positions[peer_id]
		var inp: Dictionary = inputs.get(peer_id, {})
		var dir := Vector2(
			float(inp.get("r", 0)) - float(inp.get("l", 0)),
			float(inp.get("d", 0)) - float(inp.get("u", 0))
		)
		if dir.length_squared() > 0.0:
			dir = dir.normalized()
		pos += dir * move_speed * step
		pos.x = clampf(pos.x, pawn_radius, ONLINE_VIRTUAL_SIZE.x - pawn_radius)
		pos.y = clampf(pos.y, pawn_radius, ONLINE_VIRTUAL_SIZE.y - pawn_radius)
		positions[peer_id] = pos


func _build_world_snapshot() -> Dictionary:
	var snapshot := {}
	for peer_id in positions.keys():
		var pos: Vector2 = positions[peer_id]
		snapshot[str(peer_id)] = {"x": pos.x, "y": pos.y}
	return snapshot


func _broadcast_world_state() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.get_peers().is_empty():
		return
	rpc("net_receive_world_state", _build_world_snapshot())


@rpc("any_peer", "unreliable")
func net_submit_input(packet: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not positions.has(sender):
		return
	inputs[sender] = _sanitize_input(packet)


@rpc("authority", "call_local", "unreliable")
func net_receive_world_state(_snapshot: Dictionary) -> void:
	pass


@rpc("authority", "call_local")
func net_remove_peer(_peer_id: int) -> void:
	pass
