extends Node
## Development account + multiplayer presence client for FFDRealms 0.4.0.
## Passwords are never stored locally. "Remember me" stores a renewable session token.
signal account_result(action: String, result: Dictionary)
signal account_changed
signal multiplayer_changed
signal players_changed

const Catalog = preload("res://scripts/catalog.gd")
const SESSION_PATH: String = "user://network_session.json"
const IDENTITY_PATH: String = "user://install_identity.txt"
const DEFAULT_SERVER: String = "http://127.0.0.1:8765"
const SEND_INTERVAL: float = 0.12

var server_url: String = DEFAULT_SERVER
var username: String = ""
var email: String = ""
var updates_opt_in: bool = false
var token: String = ""
var remember_session: bool = true
var offline_mode: bool = false
var account_ready: bool = false
var account_checking: bool = false
var session_verified: bool = false
var last_error: String = ""

var socket: WebSocketPeer = WebSocketPeer.new()
var multiplayer_state: String = "offline"
var self_player_id: int = 0
var remote_players: Dictionary = {}
var _send_time: float = 0.0
var _last_appearance_signature: String = ""
var _last_state_signature: String = ""
var _hello_sent: bool = false
var _install_id: String = ""

func _ready() -> void:
	server_url = str(ProjectSettings.get_setting("ffdrealms/network/server_url", DEFAULT_SERVER)).trim_suffix("/")
	_install_id = _load_or_create_install_id()
	_load_session()
	_send_open_event()
	if not token.is_empty():
		account_checking = true
		_request("me", "GET", "/api/me", {}, true)
	else:
		account_ready = true
		account_changed.emit()

func _process(delta: float) -> void:
	if multiplayer_state in ["connecting", "online"]:
		socket.poll()
		var state: int = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if multiplayer_state != "online":
				multiplayer_state = "online"
				multiplayer_changed.emit()
			if not _hello_sent and Game.profile_slot > 0:
				_send_hello()
			while socket.get_available_packet_count() > 0:
				_parse_socket_packet(socket.get_packet().get_string_from_utf8())
			_send_time += delta
			if _send_time >= SEND_INTERVAL:
				_send_time = 0.0
				_send_player_state()
		elif state == WebSocketPeer.STATE_CLOSED:
			if multiplayer_state != "offline":
				multiplayer_state = "offline"
				remote_players.clear()
				self_player_id = 0
				_hello_sent = false
				players_changed.emit()
				multiplayer_changed.emit()

func is_signed_in() -> bool:
	return session_verified and not token.is_empty() and not username.is_empty()

func server_label() -> String:
	return server_url

func sign_in(user: String, password: String, remember: bool = true) -> void:
	remember_session = remember
	last_error = ""
	_request("login", "POST", "/api/login", {"username": user.strip_edges(), "password": password}, false)

func register_account(user: String, password: String, signup_email: String, opt_in: bool, remember: bool = true) -> void:
	remember_session = remember
	last_error = ""
	_request("register", "POST", "/api/register", {
		"username": user.strip_edges(), "password": password,
		"email": signup_email.strip_edges(), "updates_opt_in": opt_in,
	}, false)

func update_subscription(new_email: String, opt_in: bool) -> void:
	if not is_signed_in():
		account_result.emit("subscription", {"ok": false, "error": "Sign in first."})
		return
	_request("subscription", "POST", "/api/subscription", {
		"token": token, "email": new_email.strip_edges(), "updates_opt_in": opt_in,
	}, false)

func sign_out() -> void:
	leave_multiplayer()
	if not token.is_empty():
		_request("logout", "POST", "/api/logout", {"token": token}, false)
	token = ""
	session_verified = false
	username = ""
	email = ""
	updates_opt_in = false
	offline_mode = false
	_save_or_clear_session()
	account_changed.emit()

func use_offline_mode() -> void:
	leave_multiplayer()
	offline_mode = true
	account_ready = true
	account_changed.emit()

func exit_offline_mode() -> void:
	offline_mode = false
	account_changed.emit()

func join_multiplayer() -> bool:
	if not is_signed_in() or Game.profile_slot < 1:
		last_error = "Sign in and load an adventure before joining multiplayer."
		multiplayer_changed.emit()
		return false
	if multiplayer_state in ["connecting", "online"]:
		return true
	var ws_url: String = server_url
	if ws_url.begins_with("https://"):
		ws_url = "wss://" + ws_url.substr(8)
	elif ws_url.begins_with("http://"):
		ws_url = "ws://" + ws_url.substr(7)
	ws_url += "/ws?token=" + token.uri_encode()
	socket = WebSocketPeer.new()
	var error: Error = socket.connect_to_url(ws_url)
	if error != OK:
		last_error = "Could not start multiplayer connection (error %d)." % int(error)
		multiplayer_state = "offline"
		multiplayer_changed.emit()
		return false
	multiplayer_state = "connecting"
	remote_players.clear()
	self_player_id = 0
	_hello_sent = false
	_send_time = 0.0
	multiplayer_changed.emit()
	return true

func leave_multiplayer() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close(1000, "Leaving world")
	multiplayer_state = "offline"
	remote_players.clear()
	self_player_id = 0
	_hello_sent = false
	players_changed.emit()
	multiplayer_changed.emit()

func multiplayer_online() -> bool:
	return multiplayer_state == "online"

func multiplayer_label() -> String:
	match multiplayer_state:
		"connecting": return "Connecting..."
		"online": return "Online (%d other player%s)" % [remote_players.size(), "" if remote_players.size() == 1 else "s"]
		_: return "Offline"

func send_appearance_now() -> void:
	if multiplayer_online():
		_send_json({"type": "appearance", "appearance": Game.character.get("appearance", {})})

func _send_hello() -> void:
	if _hello_sent or not multiplayer_online() or Game.profile_slot < 1:
		return
	_hello_sent = true
	_last_appearance_signature = JSON.stringify(Game.character.get("appearance", {}))
	_send_json({
		"type": "hello",
		"name": str(Game.character.get("name", username)),
		"appearance": Game.character.get("appearance", {}),
	})
	_send_player_state(true)

func _send_player_state(force: bool = false) -> void:
	if not multiplayer_online() or not Game.playing:
		return
	var pos: Vector3 = Game.position_of_player()
	var facing: Vector3 = Game.facing
	var signature: String = "%.2f|%.2f|%.2f|%.2f" % [pos.x, pos.z, facing.x, facing.z]
	if force or signature != _last_state_signature:
		_last_state_signature = signature
		_send_json({"type": "state", "x": pos.x, "z": pos.z, "fx": facing.x, "fz": facing.z})
	var look_signature: String = JSON.stringify(Game.character.get("appearance", {}))
	if look_signature != _last_appearance_signature:
		_last_appearance_signature = look_signature
		_send_json({"type": "appearance", "appearance": Game.character.get("appearance", {})})

func _send_json(payload: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(payload))

func _parse_socket_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var kind: String = str(data.get("type", ""))
	if kind == "welcome":
		self_player_id = int(data.get("id", 0))
		_update_remote_players(data.get("players", []))
	elif kind == "players":
		_update_remote_players(data.get("players", []))

func _update_remote_players(source: Variant) -> void:
	if not source is Array:
		return
	var next: Dictionary = {}
	for raw: Variant in source:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var pid: int = int(entry.get("id", 0))
		if pid <= 0 or pid == self_player_id:
			continue
		next[pid] = {
			"id": pid,
			"name": str(entry.get("name", "Adventurer")).substr(0, 16),
			"pos": Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0))),
			"facing": Vector3(float(entry.get("fx", 0.0)), 0.0, float(entry.get("fz", -1.0))),
			"appearance": entry.get("appearance", {}) if entry.get("appearance", {}) is Dictionary else {},
		}
	remote_players = next
	players_changed.emit()
	multiplayer_changed.emit()

func _request(action: String, method_name: String, path: String, payload: Dictionary, authenticated: bool) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(action, request), CONNECT_ONE_SHOT)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if authenticated and not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var method: HTTPClient.Method = HTTPClient.METHOD_GET if method_name == "GET" else HTTPClient.METHOD_POST
	var body: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var error: Error = request.request(server_url + path, headers, method, body)
	if error != OK:
		request.queue_free()
		_on_account_transport_error(action, "Could not reach the test server (error %d)." % int(error))

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, action: String, request: HTTPRequest) -> void:
	request.queue_free()
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var reason: String = str(data.get("error", "Server unavailable or request failed (%d)." % response_code))
		_on_account_transport_error(action, reason)
		return
	if not bool(data.get("ok", false)):
		var reason: String = str(data.get("error", "Request was rejected."))
		if action == "me":
			session_verified = false
			token = ""
			username = ""
			email = ""
			updates_opt_in = false
			_save_or_clear_session()
			account_checking = false
			account_ready = true
			account_changed.emit()
		account_result.emit(action, data)
		return
	if action in ["login", "register"]:
		token = str(data.get("token", ""))
		session_verified = not token.is_empty()
		username = str(data.get("username", ""))
		email = str(data.get("email", ""))
		updates_opt_in = bool(data.get("updates_opt_in", false))
		offline_mode = false
		account_ready = true
		_save_or_clear_session()
		account_changed.emit()
	elif action == "me":
		session_verified = true
		username = str(data.get("username", username))
		email = str(data.get("email", ""))
		updates_opt_in = bool(data.get("updates_opt_in", false))
		account_checking = false
		account_ready = true
		account_changed.emit()
	elif action == "subscription":
		email = str(data.get("email", email))
		updates_opt_in = bool(data.get("updates_opt_in", updates_opt_in))
		_save_or_clear_session()
		account_changed.emit()
	account_result.emit(action, data)

func _on_account_transport_error(action: String, reason: String) -> void:
	last_error = reason
	if action == "me":
		session_verified = false
		account_checking = false
		account_ready = true
	account_result.emit(action, {"ok": false, "error": reason})
	account_changed.emit()

func _send_open_event() -> void:
	_request("open", "POST", "/api/open", {"install_id": _install_id, "build": Catalog.VERSION}, false)

func _load_or_create_install_id() -> String:
	if FileAccess.file_exists(IDENTITY_PATH):
		var existing: String = FileAccess.get_file_as_string(IDENTITY_PATH).strip_edges()
		if existing.length() >= 16:
			return existing
	var crypto := Crypto.new()
	var generated: String = crypto.generate_random_bytes(18).hex_encode()
	var file := FileAccess.open(IDENTITY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(generated)
		file.close()
	return generated

func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	token = str(data.get("token", ""))
	username = str(data.get("username", ""))
	email = str(data.get("email", ""))
	updates_opt_in = bool(data.get("updates_opt_in", false))
	remember_session = true

func _save_or_clear_session() -> void:
	if not remember_session or token.is_empty():
		if FileAccess.file_exists(SESSION_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"token": token,
			"username": username,
			"email": email,
			"updates_opt_in": updates_opt_in,
		}))
		file.close()
