extends Node

signal gift_received(gift_name: String, sender: String, count: int, user_id: String)
signal comment_received(sender: String, user_id: String, text: String)
signal command_received(cmd: String)
signal connection_changed(connected: bool)

@export var ws_url: String = "ws://127.0.0.1:8080"
@export var reconnect_interval: float = 3.0

var ws: WebSocketPeer = WebSocketPeer.new()
var connected: bool = false
var _reconnect_timer: float = 0.0
var _should_reconnect: bool = true

func _ready() -> void:
	connect_to_bridge()

func _process(delta: float) -> void:
	ws.poll()
	var state = ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				connection_changed.emit(true)
			_handle_messages()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if connected:
				connected = false
				connection_changed.emit(false)
			if _should_reconnect:
				_reconnect_timer += delta
				if _reconnect_timer >= reconnect_interval:
					_reconnect_timer = 0.0
					connect_to_bridge()

func connect_to_bridge() -> void:
	ws.connect_to_url(ws_url)

func _handle_messages() -> void:
	while ws.get_available_packet_count() > 0:
		var pkt = ws.get_packet().get_string_from_utf8()
		var json = JSON.new()
		if json.parse(pkt) == OK:
			var data = json.data
			if data is Dictionary:
				var msg_type: String = data.get("type", "")
				var sender: String = data.get("sender", "")
				var user_id: String = data.get("userId", sender)
				if msg_type == "gift" or msg_type == "share":
					gift_received.emit(
						data.get("gift", ""),
						sender,
						data.get("count", 1),
						user_id
					)
				elif msg_type == "comment":
					comment_received.emit(sender, user_id, data.get("text", ""))
				elif msg_type == "cmd":
					command_received.emit(data.get("cmd", ""))

func send_message(data: Dictionary) -> void:
	if connected:
		ws.send_text(JSON.stringify(data))

func disconnect_from_bridge() -> void:
	_should_reconnect = false
	ws.close()
