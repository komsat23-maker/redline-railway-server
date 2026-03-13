extends Node

@export var port: int = 2457
@export var max_clients: int = 32

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
	print("Redline dedicated websocket server listening on port %d" % port)

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	rpc("net_remove_peer", id)

@rpc("any_peer", "unreliable")
func net_submit_state(state: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	rpc("net_receive_state", sender, state)

@rpc("any_peer", "unreliable")
func net_submit_shot(payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	rpc("net_spawn_shot_fx", sender, payload)

@rpc("authority", "call_local")
func net_remove_peer(_peer_id: int) -> void:
	pass
