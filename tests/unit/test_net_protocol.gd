extends RefCounted
## Wire-protocol validation contract.
##
## `NetProtocol.validate()` is the guard that runs *before* any message reaches
## game code. It must therefore never raise: a peer that sends `{"t": null}`
## has to be rejected with a reason, not take the receiver down with it.
##
## The trap this suite pins down: Godot 4.7 has no universal `String(x)` /
## `int(x)` constructor, so `String(message.get("t", ""))` fails at runtime
## when the value is not a String. And `Dictionary.get(key, default)` returns
## `null` - not the default - when the key exists with a null value.

func suite_name() -> String:
	return "net protocol"


func run(h: TestHarness) -> void:
	_test_type_and_version(h)
	_test_validate_rejects(h)
	_test_validate_accepts(h)
	_test_encode_decode(h)
	_test_reason_keys(h)


func _test_type_and_version(h: TestHarness) -> void:
	h.equal(NetProtocol.type_of({"t": "hello"}), "hello", "type_of reads a String type")
	h.equal(NetProtocol.type_of({"t": null}), "", "type_of survives a null type")
	h.equal(NetProtocol.type_of({"t": 42}), "", "type_of survives a numeric type")
	h.equal(NetProtocol.type_of({}), "", "type_of survives a missing type")
	h.equal(NetProtocol.version_of({"v": 1}), 1, "version_of reads an int version")
	h.equal(NetProtocol.version_of({"v": 1.0}), 1, "version_of reads a float version")
	h.equal(NetProtocol.version_of({"v": null}), -1, "version_of survives a null version")
	h.equal(NetProtocol.version_of({}), -1, "version_of survives a missing version")


func _test_validate_rejects(h: TestHarness) -> void:
	h.equal(NetProtocol.validate("not a dictionary"), "malformed", "a non-dictionary is malformed")
	h.equal(NetProtocol.validate([]), "malformed", "an array is malformed")
	h.equal(NetProtocol.validate({}), "malformed", "a message without a type is malformed")
	h.equal(NetProtocol.validate({"v": 1}), "malformed", "a message without a type field is malformed")
	h.equal(NetProtocol.validate({"t": null, "v": 1}), "malformed", "a null type is malformed")
	h.equal(NetProtocol.validate({"t": 42, "v": 1}), "malformed", "a numeric type is malformed")
	h.equal(NetProtocol.validate({"t": "hello"}), "malformed", "a message without a version is malformed")
	h.equal(NetProtocol.validate({"t": "hello", "v": null}), "malformed", "a null version is malformed")
	h.equal(NetProtocol.validate({"t": "hello", "v": "1"}), "malformed", "a string version is malformed")
	h.equal(NetProtocol.validate({"t": "hello", "v": 99}), "version", "a wrong version is a version error")
	h.equal(NetProtocol.validate({"t": "nonsense", "v": 1}), "unknown_type", "an unknown type is reported")


func _test_validate_accepts(h: TestHarness) -> void:
	for type: String in [
		NetProtocol.T_HELLO, NetProtocol.T_WELCOME, NetProtocol.T_REJECT,
		NetProtocol.T_PLAYERS, NetProtocol.T_LOBBY_STATE, NetProtocol.T_START_MATCH,
		NetProtocol.T_ACTION, NetProtocol.T_ACTION_RESULT, NetProtocol.T_STATE,
		NetProtocol.T_PRIVATE_STATE, NetProtocol.T_CHAT, NetProtocol.T_PING,
		NetProtocol.T_PONG, NetProtocol.T_RESIGN, NetProtocol.T_MATCH_END,
		NetProtocol.T_BYE,
	]:
		h.equal(NetProtocol.validate({"t": type, "v": NetProtocol.VERSION}), "",
			"validate accepts the %s message" % type)
		h.is_true(NetProtocol.is_known_type(type), "%s is a known type" % type)


func _test_encode_decode(h: TestHarness) -> void:
	var message := NetProtocol.envelope(NetProtocol.T_PING, {"echo": 7})
	h.equal(int(message.get("v", 0)), NetProtocol.VERSION, "the envelope carries the protocol version")
	h.equal(String(message.get("t", "")), NetProtocol.T_PING, "the envelope carries the message type")
	var encoded := NetProtocol.encode(message)
	h.check(encoded.size() > 0, "the envelope encodes to bytes")
	var decoded := NetProtocol.decode(encoded)
	h.equal(decoded.get("t", ""), NetProtocol.T_PING, "the envelope survives a round trip")
	h.equal(decoded.get("echo", 0), 7, "the payload survives a round trip")
	h.equal(NetProtocol.decode(PackedByteArray()), {}, "an empty packet decodes to an empty dictionary")
	h.equal(NetProtocol.decode("not json".to_utf8_buffer()), {}, "an undecodable packet decodes to an empty dictionary")
	h.equal(NetProtocol.decode("[1,2]".to_utf8_buffer()), {}, "a JSON array decodes to an empty dictionary")
	h.equal(NetProtocol.decode("null".to_utf8_buffer()), {}, "a JSON null decodes to an empty dictionary")
	var oversized := PackedByteArray()
	oversized.resize(NetProtocol.MAX_PACKET_BYTES + 1)
	h.equal(NetProtocol.decode(oversized), {}, "an oversized packet is rejected")


func _test_reason_keys(h: TestHarness) -> void:
	h.equal(NetProtocol.reason_key(int(NetProtocol.Reject.VERSION)), "net.reject_version", "the version reason has a key")
	h.equal(NetProtocol.reason_key(int(NetProtocol.Reject.MALFORMED)), "net.reject_malformed", "the malformed reason has a key")
	h.equal(NetProtocol.reason_key(int(NetProtocol.Reject.UNKNOWN_TYPE)), "net.reject_unknown_type", "the unknown-type reason has a key")
	h.equal(NetProtocol.reason_key(9999), "net.reject_generic", "an unknown reason falls back to the generic key")
	var rejection := NetProtocol.reject(NetProtocol.Reject.MALFORMED, "detail")
	h.equal(int(rejection.get("reason", 0)), int(NetProtocol.Reject.MALFORMED), "the rejection carries the reason code")
	h.equal(String(rejection.get("detail", "")), "detail", "the rejection carries the detail text")
