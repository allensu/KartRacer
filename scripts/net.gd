extends Node
## Autoload "Net": connection to the relay server, room/lobby state, and the
## settings for the next race (single player or online).

signal status_changed(text: String)
signal lobby_changed
signal race_starting
signal returned_to_lobby
signal message(from_id: int, data: Dictionary)
signal room_closed(reason: String)
signal failed(text: String)

## Change this after deploying the relay (see README), or open the game with
## ?server=wss://your-relay.example.com to override it.
const DEFAULT_SERVER := "wss://kartracer-relay.onrender.com"
const MAX_PLAYERS := 4

enum Mode { SINGLE, ONLINE }

var mode := Mode.SINGLE
var server_url := DEFAULT_SERVER
var player_name := "Player"

var socket: WebSocketPeer
var connected := false
var room_code := ""
var my_id := 0
var host_id := 0
var players: Array = []       # [{id, name}] in join order
var race_players: Array = []  # roster frozen at race start
var race_seed := 0

var _pending: Dictionary = {}  # first message to send once the socket opens
var _ping_timer := 0.0
var _was_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var env_url := OS.get_environment("KARTRACER_SERVER")
	if env_url != "":
		server_url = env_url
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		if typeof(q) == TYPE_STRING and q != "":
			server_url = q


func is_online() -> bool:
	return mode == Mode.ONLINE


func is_host() -> bool:
	return my_id != 0 and my_id == host_id


func create_room(name: String) -> void:
	player_name = name
	_open({"t": "create", "name": name})


func join_room(code: String, name: String) -> void:
	player_name = name
	_open({"t": "join", "code": code.strip_edges().to_upper(), "name": name})


func start_race() -> void:
	if is_host():
		_send({"t": "start"})


func back_to_lobby() -> void:
	if is_host():
		_send({"t": "lobby"})


func relay(data: Dictionary) -> void:
	if connected and room_code != "":
		_send({"t": "relay", "d": data})


func leave() -> void:
	if socket:
		socket.close()
	_reset()


func _reset() -> void:
	socket = null
	connected = false
	_was_open = false
	room_code = ""
	my_id = 0
	host_id = 0
	players = []
	_pending = {}


func _open(first: Dictionary) -> void:
	if socket and connected:
		_send(first)
		return
	_reset()
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	socket.outbound_buffer_size = 1 << 20
	var err := socket.connect_to_url(server_url)
	if err != OK:
		failed.emit("Could not connect to " + server_url)
		_reset()
		return
	_pending = first
	status_changed.emit("Connecting to server... (a sleeping server can take up to a minute to wake up)")


func _send(obj: Dictionary) -> void:
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(obj))


func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var st := socket.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connected = true
			if not _pending.is_empty():
				_send(_pending)
				_pending = {}
		_ping_timer += delta
		if _ping_timer > 20.0:
			_ping_timer = 0.0
			_send({"t": "ping"})
		while socket and socket.get_available_packet_count() > 0:
			var text := socket.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(text)
			if typeof(msg) == TYPE_DICTIONARY:
				_handle(msg)
	elif st == WebSocketPeer.STATE_CLOSED:
		var was_in_room := room_code != ""
		var had_opened := _was_open
		_reset()
		if was_in_room:
			room_closed.emit("Lost connection to the server")
		elif not had_opened:
			failed.emit("Could not reach the server. Try again in a minute.")


func _handle(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"joined":
			room_code = msg.code
			my_id = int(msg.id)
			host_id = int(msg.hostId)
			players = msg.players
			lobby_changed.emit()
		"lobby":
			host_id = int(msg.hostId)
			players = msg.players
			lobby_changed.emit()
			if msg.get("back", false):
				returned_to_lobby.emit()
		"start":
			race_seed = int(msg.seed)
			race_players = msg.players
			mode = Mode.ONLINE
			race_starting.emit()
		"msg":
			message.emit(int(msg.from), msg.d)
		"closed":
			var reason: String = msg.get("reason", "Room closed")
			leave()
			room_closed.emit(reason)
		"error":
			failed.emit(str(msg.get("msg", "Error")))
