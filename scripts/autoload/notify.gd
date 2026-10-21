extends Node
## In-app notification bridge (autoload `Notify`).
##
## Screens and services emit notifications here instead of touching the UI tree;
## the application shell renders them. Notifications raised before the shell is
## ready are queued, so start-up problems (for example Steam initialisation
## failures) are never silently lost.

signal notification_posted(message: String, kind: String)
signal confirmation_requested(title: String, body: String, confirm_label: String)

enum Kind { INFO = 0, SUCCESS = 1, WARNING = 2, ERROR = 3 }

var _queue: Array[Dictionary] = []
var modal_host: Node = null


## The application shell registers itself as the modal host at start-up.
func set_modal_host(host: Node) -> void:
	modal_host = host


func has_modal_host() -> bool:
	return modal_host != null and is_instance_valid(modal_host)


func confirm(title: String, body: String, confirm_label: String, on_confirmed: Callable, cancel_label: String = "", danger: bool = false) -> void:
	if has_modal_host():
		modal_host.call("confirm", title, body, confirm_label, on_confirmed, cancel_label, danger)
	else:
		Log.warn("Notify: confirm requested before the UI was ready", {"title": title})
		on_confirmed.call(false)


func alert(title: String, body: String) -> void:
	if has_modal_host():
		modal_host.call("alert", title, body)
	else:
		warning("%s: %s" % [title, body])


func prompt(title: String, placeholder: String, initial: String, on_submit: Callable) -> void:
	if has_modal_host():
		modal_host.call("prompt", title, placeholder, initial, on_submit)
	else:
		on_submit.call(initial)


func choose(title: String, body: String, entries: Array, on_choose: Callable) -> void:
	if has_modal_host():
		modal_host.call("choose", title, body, entries, on_choose)
	else:
		Log.warn("Notify: choice requested before the UI was ready", {"title": title})


func info(message: String) -> void:
	_post(message, Kind.INFO)


func success(message: String) -> void:
	_post(message, Kind.SUCCESS)


func warning(message: String) -> void:
	_post(message, Kind.WARNING)


func error(message: String) -> void:
	_post(message, Kind.ERROR)
	if Log.error_count() < 50:
		Log.warn("Notify: error shown to user", {"message": message})


func _post(message: String, kind: Kind) -> void:
	if message.strip_edges().is_empty():
		return
	var payload: Dictionary = {"message": message, "kind": int(kind), "time": Time.get_ticks_msec()}
	_queue.append(payload)
	notification_posted.emit(message, _kind_name(kind))


func _kind_name(kind: Kind) -> String:
	match kind:
		Kind.SUCCESS:
			return "success"
		Kind.WARNING:
			return "warning"
		Kind.ERROR:
			return "error"
		_:
			return "info"


## Called by the shell right after it is built to flush queued notifications.
func drain_queue() -> Array[Dictionary]:
	var entries := _queue.duplicate()
	_queue.clear()
	return entries


func kind_name(kind: int) -> String:
	return _kind_name(kind as Kind)


static func color_for_kind(kind_name: String) -> Color:
	match kind_name:
		"success":
			return Palette.POSITIVE
		"warning":
			return Palette.WARNING
		"error":
			return Palette.DANGER
		_:
			return Palette.INFO
