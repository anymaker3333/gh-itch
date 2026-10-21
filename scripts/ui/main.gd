extends Control
## Application entry point (root of `scenes/main.tscn`).
##
## Boot order matters: display preferences are applied before the UI exists so
## the window is already correct when the shell lays out, and the shell is only
## created once the catalog, localisation and settings services are ready
## (autoloads run before this scene).

const APP_SHELL_SCRIPT: String = "res://scripts/ui/app_shell.gd"

var shell: Control = null


func _ready() -> void:
	Log.info("Main: booting application", {"engine": Engine.get_version_info().get("string", "")})
	DisplayManager.apply_from_prefs()
	Log.info("Main: display configured", {"summary": DisplayManager.display_summary()})
	_build_shell()
	_report_environment()
	_announce_offline_mode()


func _build_shell() -> void:
	var script := load(APP_SHELL_SCRIPT) as GDScript
	if script == null:
		Log.error("Main: application shell script missing", {"path": APP_SHELL_SCRIPT})
		return
	var instance: Variant = script.new()
	if not (instance is Control):
		Log.error("Main: application shell is not a Control")
		return
	shell = instance
	shell.name = "AppShell"
	add_child(shell)


func _report_environment() -> void:
	var report: Dictionary = {
		"games": Catalog.count(),
		"locale": Loc.current_locale,
		"locales": Loc.locale_codes().size(),
		"steam": SteamSvc.state_name(),
	}
	Log.info("Main: services ready", report)
	if Catalog.count() == 0:
		Notify.error(Loc.t("error.catalog_empty"))


func _announce_offline_mode() -> void:
	# Keep the persistent sidebar status and the Online screen as the places
	# that explain Steam availability. A startup toast overlapped the library
	# cards for several seconds, which was more intrusive than useful.
	match SteamSvc.state:
		SteamSvc.State.UNAVAILABLE:
			Log.info("Main: Steam unavailable; online play disabled")
		SteamSvc.State.FAILED:
			Log.warn("Main: Steam initialization failed; online play disabled", {
				"detail": SteamSvc.state_detail,
			})
		SteamSvc.State.DISABLED:
			pass
		_:
			pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Prefs.save_now()
