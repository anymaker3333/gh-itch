class_name NetProtocol
extends RefCounted
## Versioned wire protocol for Game Hub sessions.
##
## Messages are plain dictionaries so they can be inspected, logged and unit
## tested. Every message carries the protocol version; mismatching or malformed
## messages are rejected before they reach game code. Clients only ever send
## *intended actions* - the host validates them against the authoritative engine
## and broadcasts the resulting state.

const VERSION: int = 1
const MAX_PACKET_BYTES: int = 1 << 18  # 256 KiB is far more than any game needs.

## Message types.
const T_HELLO: String = "hello"
const T_WELCOME: String = "welcome"
const T_REJECT: String = "reject"
const T_PLAYERS: String = "players"
const T_LOBBY_STATE: String = "lobby_state"
const T_START_MATCH: String = "start_match"
const T_ACTION: String = "action"
const T_ACTION_RESULT: String = "action_result"
const T_STATE: String = "state"
const T_PRIVATE_STATE: String = "private_state"
const T_CHAT: String = "chat"
const T_PING: String = "ping"
const T_PONG: String = "pong"
const T_RESIGN: String = "resign"
const T_MATCH_END: String = "match_end"
const T_BYE: String = "bye"

enum Reject { NONE = 0, VERSION = 1, MALFORMED = 2, NOT_HOST = 3, ILLEGAL_ACTION = 4, OUT_OF_TURN = 5, NOT_PLAYER = 6, FULL = 7, UNKNOWN_TYPE = 8, STALE = 9, MATCH_RUNNING = 10 }


static func envelope(type: String, payload: Dictionary = {}) -> Dictionary:
	var message := payload.duplicate(true)
	message["v"] = VERSION
	message["t"] = type
	message["ts"] = Time.get_ticks_msec()
	return message


static func type_of(message: Dictionary) -> String:
	return VariantUtil.as_string(message.get("t", ""), "")


static func version_of(message: Dictionary) -> int:
	return VariantUtil.as_int(message.get("v", -1), -1)


## Returns an empty string when the message is acceptable, otherwise a reason key.
##
## A malformed field must produce a reason, never a crash: this is the guard
## that runs before any message reaches game code, so a peer that sends
## `{"t": null}` gets rejected instead of taking the receiver down with it.
static func validate(message: Variant) -> String:
	if not (message is Dictionary):
		return "malformed"
	var dict: Dictionary = message
	if not dict.has("t"):
		return "malformed"
	if not (dict["t"] is String):
		return "malformed"
	if not dict.has("v"):
		return "malformed"
	if not (dict["v"] is int or dict["v"] is float):
		return "malformed"
	if version_of(dict) != VERSION:
		return "version"
	var type := type_of(dict)
	if not is_known_type(type):
		return "unknown_type"
	return ""


static func is_known_type(type: String) -> bool:
	return type in [
		T_HELLO, T_WELCOME, T_REJECT, T_PLAYERS, T_LOBBY_STATE, T_START_MATCH,
		T_ACTION, T_ACTION_RESULT, T_STATE, T_PRIVATE_STATE, T_CHAT, T_PING,
		T_PONG, T_RESIGN, T_MATCH_END, T_BYE,
	]


static func encode(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message).to_utf8_buffer()


static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() == 0 or packet.size() > MAX_PACKET_BYTES:
		Log.warn("NetProtocol: rejecting packet", {"size": packet.size()})
		return {}
	var text := packet.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		Log.warn("NetProtocol: undecodable packet", {"error": parser.get_error_message()})
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


static func reject(reason: Reject, detail: String = "") -> Dictionary:
	return envelope(T_REJECT, {"reason": int(reason), "detail": detail})


static func reason_key(reason: int) -> String:
	match reason:
		Reject.VERSION:
			return "net.reject_version"
		Reject.MALFORMED:
			return "net.reject_malformed"
		Reject.NOT_HOST:
			return "net.reject_not_host"
		Reject.ILLEGAL_ACTION:
			return "net.reject_illegal_action"
		Reject.OUT_OF_TURN:
			return "net.reject_out_of_turn"
		Reject.NOT_PLAYER:
			return "net.reject_not_player"
		Reject.FULL:
			return "net.reject_full"
		Reject.UNKNOWN_TYPE:
			return "net.reject_unknown_type"
		Reject.STALE:
			return "net.reject_stale"
		Reject.MATCH_RUNNING:
			return "net.reject_match_running"
		_:
			return "net.reject_generic"
