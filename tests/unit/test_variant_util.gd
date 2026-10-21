extends RefCounted
## Variant conversion contract (Wave 12 gate).
##
## Godot 4.7 has no universal `String(x)` / `int(x)` constructor. When the
## argument is a Variant those calls fail at *runtime* and abort the enclosing
## function. `VariantUtil` is the single place that owns the safe behaviour, so
## this suite pins it down: a value of the wrong type must yield the caller's
## fallback and must never raise.

func suite_name() -> String:
	return "variant util"


func run(h: TestHarness) -> void:
	_test_as_string(h)
	_test_as_int(h)
	_test_as_float(h)
	_test_as_dict(h)
	_test_as_array(h)
	_test_json_semantics(h)


func _test_as_string(h: TestHarness) -> void:
	h.equal(VariantUtil.as_string("abc"), "abc", "as_string passes a String through")
	h.equal(VariantUtil.as_string("abc", "fallback"), "abc", "as_string ignores the fallback for a String")
	h.equal(VariantUtil.as_string(&"abc"), "abc", "as_string accepts a StringName")
	h.equal(VariantUtil.as_string(42, "fallback"), "fallback", "as_string falls back for an int")
	h.equal(VariantUtil.as_string(4.5, "fallback"), "fallback", "as_string falls back for a float")
	h.equal(VariantUtil.as_string(true, "fallback"), "fallback", "as_string falls back for a bool")
	h.equal(VariantUtil.as_string(null, "fallback"), "fallback", "as_string falls back for null")
	h.equal(VariantUtil.as_string([], "fallback"), "fallback", "as_string falls back for an Array")
	h.equal(VariantUtil.as_string({}, "fallback"), "fallback", "as_string falls back for a Dictionary")
	h.equal(VariantUtil.as_string(null), "", "as_string defaults to an empty string")


func _test_as_int(h: TestHarness) -> void:
	h.equal(VariantUtil.as_int(7), 7, "as_int passes an int through")
	h.equal(VariantUtil.as_int(7.9), 7, "as_int truncates a float")
	h.equal(VariantUtil.as_int(true), 1, "as_int maps true to 1")
	h.equal(VariantUtil.as_int(false), 0, "as_int maps false to 0")
	h.equal(VariantUtil.as_int("12"), 12, "as_int parses a numeric String")
	h.equal(VariantUtil.as_int(" 12 "), 12, "as_int trims before parsing")
	h.equal(VariantUtil.as_int(null, -1), -1, "as_int falls back for null")
	h.equal(VariantUtil.as_int("abc", -1), -1, "as_int falls back for a non-numeric String")
	h.equal(VariantUtil.as_int([], -1), -1, "as_int falls back for an Array")
	h.equal(VariantUtil.as_int({}, -1), -1, "as_int falls back for a Dictionary")


func _test_as_float(h: TestHarness) -> void:
	h.equal(VariantUtil.as_float(1.5), 1.5, "as_float passes a float through")
	h.equal(VariantUtil.as_float(2), 2.0, "as_float widens an int")
	h.equal(VariantUtil.as_float("3.5"), 3.5, "as_float parses a numeric String")
	h.equal(VariantUtil.as_float(null, -1.0), -1.0, "as_float falls back for null")
	h.equal(VariantUtil.as_float("abc", -1.0), -1.0, "as_float falls back for a non-numeric String")


func _test_as_dict(h: TestHarness) -> void:
	var source := {"a": 1}
	h.equal(VariantUtil.as_dict(source), source, "as_dict passes a Dictionary through")
	h.equal(VariantUtil.as_dict(null), {}, "as_dict returns an empty Dictionary for null")
	h.equal(VariantUtil.as_dict([]), {}, "as_dict returns an empty Dictionary for an Array")
	h.equal(VariantUtil.as_dict("x"), {}, "as_dict returns an empty Dictionary for a String")
	h.equal(VariantUtil.as_dict(3), {}, "as_dict returns an empty Dictionary for an int")
	h.equal(VariantUtil.dict_copy({"a": {"b": 1}}), {"a": {"b": 1}}, "dict_copy copies deeply")
	var original := {"a": {"b": 1}}
	var copied := VariantUtil.dict_copy(original)
	(copied["a"] as Dictionary)["b"] = 2
	h.equal((original["a"] as Dictionary)["b"], 1, "dict_copy does not alias the source")
	h.equal(VariantUtil.dict_copy(null), {}, "dict_copy returns an empty Dictionary for null")


func _test_as_array(h: TestHarness) -> void:
	var source := [1, 2]
	h.equal(VariantUtil.as_array(source), source, "as_array passes an Array through")
	h.equal(VariantUtil.as_array(null), [], "as_array returns an empty Array for null")
	h.equal(VariantUtil.as_array({}), [], "as_array returns an empty Array for a Dictionary")
	h.equal(VariantUtil.as_array("x"), [], "as_array returns an empty Array for a String")
	h.equal(VariantUtil.array_copy([1, 2]), [1, 2], "array_copy copies")
	var original := [1, 2]
	var copied := VariantUtil.array_copy(original)
	copied[0] = 9
	h.equal(original[0], 1, "array_copy does not alias the source")
	h.equal(VariantUtil.array_copy(null), [], "array_copy returns an empty Array for null")


## The two semantics that make the plain `.get(key, fallback)` pattern unsafe:
## a key that exists with a null value yields null (not the default), and JSON
## decodes every number as a float. The helpers must behave correctly on the
## values these produce.
func _test_json_semantics(h: TestHarness) -> void:
	var decoded: Variant = JSON.parse_string('{"t":null,"v":null,"n":42,"f":3.5,"s":"x"}')
	h.check(decoded is Dictionary, "the JSON fixture decodes to a Dictionary")
	if not (decoded is Dictionary):
		return
	var data: Dictionary = decoded
	h.check(data.get("t", "fallback") == null, "get() returns null for a key that exists with a null value")
	h.equal(VariantUtil.as_string(data.get("t", "fallback"), "fallback"), "fallback",
		"as_string handles a JSON null")
	h.equal(VariantUtil.as_int(data.get("v", -1), -1), -1, "as_int handles a JSON null")
	h.check(data.get("n") is float, "JSON decodes a number as a float")
	h.equal(VariantUtil.as_int(data.get("n", 0)), 42, "as_int converts a JSON float to an int")
	h.equal(VariantUtil.as_string(data.get("s", ""), ""), "x", "as_string handles a JSON string")
