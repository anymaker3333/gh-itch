class_name VariantUtil
extends RefCounted
## Type-safe conversions from [Variant] to the concrete types the code expects.
##
## Godot 4.7 has no universal `String(x)` / `int(x)` constructor: those calls
## only accept a statically typed argument. When the argument is a [Variant]
## (a `Dictionary.get()` result, an array element, a decoded JSON value, the
## return value of `Callable.call()`) the call fails at *runtime* with
## "Invalid call. Nonexistent 'String' constructor." and aborts the enclosing
## function from that line on.
##
## Two details make the plain `.get(key, fallback)` pattern unsafe:
##
##  * `Dictionary.get(key, default)` returns `null` - not the default - when
##    the key *exists* with a `null` value. The default only applies when the
##    key is absent, so it gives no protection against a JSON `null`.
##  * `JSON.parse_string` decodes every number as a `float` and `null` as
##    `null`.
##
## These helpers are the single place that owns that behaviour. They never
## raise: a value of the wrong type yields the caller's fallback, so a
## malformed packet, snapshot or file degrades into a handled error instead of
## a crashed handler.

## Returns `value` as a [String], or `fallback` when it is not string-like.
## A [StringName] is accepted because it is a common key type.
static func as_string(value: Variant, fallback: String = "") -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return fallback


## Returns `value` as an [int], or `fallback` when it cannot be converted.
## Accepts `int`, `float` (truncated), `bool` and numeric `String`s.
static func as_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		var text: String = (value as String).strip_edges()
		# `int("abc")` returns 0 rather than raising, so a non-numeric string
		# must be rejected explicitly or it would silently become a valid 0.
		return int(text) if text.is_valid_int() else fallback
	if value is StringName:
		return as_int(String(value), fallback)
	return fallback


## Returns `value` as a [float], or `fallback` when it cannot be converted.
static func as_float(value: Variant, fallback: float = 0.0) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String:
		var text: String = (value as String).strip_edges()
		# `float("abc")` returns 0.0 rather than raising.
		return float(text) if text.is_valid_float() else fallback
	if value is StringName:
		return as_float(String(value), fallback)
	return fallback


## Returns `value` as a [Dictionary], or an empty dictionary when it is not
## one. Replaces the `x as Dictionary` cast, which raises "Invalid cast" on a
## value of the wrong type.
static func as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


## Returns `value` as an [Array], or an empty array when it is not one.
## Replaces the `x as Array` cast, which raises "Invalid cast" on a value of
## the wrong type.
static func as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


## Returns a copy of `value` as a [Dictionary], or an empty dictionary when it
## is not one. Use this where the caller mutates the result.
static func dict_copy(value: Variant) -> Dictionary:
	return as_dict(value).duplicate(true)


## Returns a copy of `value` as an [Array], or an empty array when it is not
## one. Use this where the caller mutates the result.
static func array_copy(value: Variant) -> Array:
	return as_array(value).duplicate(true)
