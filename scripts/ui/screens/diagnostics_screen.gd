extends ScreenBase
## Diagnostics: live log, service state, catalog/translation coverage, exports.
## Every action here performs real work (copy report, export log, check files).

var _log_list: VBoxContainer
var _summary: VBoxContainer
var _filter_level: int = -1


func build() -> void:
	title_key = "diagnostics.title"
	subtitle_key = "diagnostics.subtitle"
	var layout := UI.row(16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.margin_xy(layout, 24, 20, 24, 24))

	var left := UI.column(12)
	left.custom_minimum_size = Vector2(360, 0)
	layout.add_child(left)
	var summary_panel := UI.panel("CardPanel")
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(summary_panel)
	_summary = UI.column(8)
	summary_panel.add_child(UI.margin_container(UI.scroll(_summary), 14))

	var right := UI.column(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(right)
	var toolbar := UI.flow(8, 8)
	right.add_child(toolbar)
	toolbar.add_child(UI.button(Loc.t("diagnostics.copy_report"), "Button", _copy_report))
	toolbar.add_child(UI.button(Loc.t("diagnostics.export_log"), "Button", _export_log))
	toolbar.add_child(UI.button(Loc.t("diagnostics.clear"), "GhostButton", func() -> void:
		Log.clear()
		_rebuild()
		Notify.success(Loc.t("diagnostics.cleared"))
	))
	toolbar.add_child(UI.button(Loc.t("diagnostics.errors_only"), "ChipButton", func() -> void:
		_filter_level = Log.Level.ERROR
		_rebuild()
	))
	toolbar.add_child(UI.button(Loc.t("diagnostics.all"), "ChipButton", func() -> void:
		_filter_level = -1
		_rebuild()
	))
	var log_panel := UI.panel("CardPanel")
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	var log_scroll := UI.scroll(UI.column(4), false)
	log_panel.add_child(UI.margin_container(log_scroll, 12))
	_log_list = log_scroll.get_child(0) as VBoxContainer


func on_enter() -> void:
	Log.message_logged.connect(_on_log)
	Log.error_logged.connect(_on_log)
	_rebuild()


func on_exit() -> void:
	if Log.message_logged.is_connected(_on_log):
		Log.message_logged.disconnect(_on_log)
	if Log.error_logged.is_connected(_on_log):
		Log.error_logged.disconnect(_on_log)


func _on_log(_entry: Dictionary) -> void:
	_rebuild()


func _rebuild() -> void:
	if _summary == null:
		return
	for child: Node in _summary.get_children():
		_summary.remove_child(child)
		child.queue_free()
	for child: Node in _log_list.get_children():
		_log_list.remove_child(child)
		child.queue_free()
	_build_summary()
	_build_log()


func _build_summary() -> void:
	_summary.add_child(UI.section_header(Loc.t("diagnostics.services"), Loc.t("diagnostics.services_hint")))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.engine"), String(Engine.get_version_info().get("string", "?"))))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.platform"), "%s %s" % [OS.get_name(), OS.get_version()]))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.renderer"), "%s / %s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		RenderingServer.get_video_adapter_name(),
	]))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.uptime"), "%.1f s" % Log.uptime_seconds()))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.errors"), str(Log.error_count()), Palette.DANGER if Log.error_count() > 0 else Palette.POSITIVE))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.warnings"), str(Log.warn_count()), Palette.WARNING if Log.warn_count() > 0 else Palette.POSITIVE))
	_summary.add_child(UI.divider())
	_summary.add_child(UI.section_header(Loc.t("diagnostics.steam"), SteamSvc.status_text()))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.steam_state"), SteamSvc.state_name()))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.steam_app_id"), str(SteamSvc.app_id)))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.steam_steam_id"), SteamSvc.steam_id_string() if SteamSvc.steam_id != 0 else Loc.t("common.none")))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.steam_relay"), Loc.t("common.yes") if SteamSvc.relay_available else Loc.t("common.no")))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.steam_detail"), SteamSvc.state_detail))
	_summary.add_child(UI.divider())
	_summary.add_child(UI.section_header(Loc.t("diagnostics.catalog"), Loc.t("diagnostics.catalog_hint")))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.games"), str(Catalog.count())))
	var engines := 0
	var playable := 0
	for entry: GameEntry in Catalog.games():
		if Session.engine_available(entry.id):
			engines += 1
		if entry.status == GameEntry.Status.PLAYABLE:
			playable += 1
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.engines"), str(engines)))
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.playable"), str(playable)))
	_summary.add_child(UI.divider())
	_summary.add_child(UI.section_header(Loc.t("diagnostics.localisation"), Loc.t("diagnostics.localisation_hint")))
	var coverage := Loc.coverage_report()
	for code: String in Loc.locale_codes():
		var stats: Dictionary = coverage.get(code, {})
		var missing := int(stats.get("missing", 0))
		_summary.add_child(UI.kv_row(
			Loc.native_name(code),
			"%d / %d (%d%%)" % [int(stats.get("translated", 0)), int(stats.get("total_keys", 0)), int(float(stats.get("percent", 0.0)))],
			Palette.POSITIVE if missing == 0 else Palette.WARNING
		))
	var runtime_missing := Loc.missing_keys()
	_summary.add_child(UI.kv_row(Loc.t("diagnostics.missing_runtime"), str(runtime_missing.size()), Palette.DANGER if runtime_missing.size() > 0 else Palette.POSITIVE))
	_summary.add_child(UI.divider())
	_summary.add_child(UI.section_header(Loc.t("diagnostics.network"), Net.link_name()))
	for key: Variant in Net.stats():
		_summary.add_child(UI.kv_row(String(key), str(Net.stats()[key])))


func _build_log() -> void:
	var entries := Log.get_entries(_filter_level, 250)
	for entry: Dictionary in entries:
		var row := UI.row(8)
		var level_label := UI.label(String(entry.get("level_name", "")), "Caption")
		level_label.custom_minimum_size = Vector2(52, 0)
		level_label.add_theme_color_override("font_color", _level_color(int(entry.get("level", 0))))
		row.add_child(level_label)
		var time_label := UI.label("%7.2f" % float(entry.get("uptime", 0.0)), "Mono")
		time_label.custom_minimum_size = Vector2(64, 0)
		row.add_child(time_label)
		var text := UI.label(String(entry.get("message", "")), "Small")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var context := String(JSON.stringify(entry.get("context", {})))
		if context != "{}":
			var context_label := UI.label(context, "Mono")
			context_label.custom_minimum_size = Vector2(280, 0)
			context_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
			row.add_child(context_label)
		_log_list.add_child(row)


func _level_color(level: int) -> Color:
	match level:
		Log.Level.ERROR:
			return Palette.DANGER
		Log.Level.WARN:
			return Palette.WARNING
		Log.Level.INFO:
			return Palette.INFO
		_:
			return Palette.TEXT_DIM


func _copy_report() -> void:
	DisplayServer.clipboard_set(Log.build_report())
	Notify.success(Loc.t("diagnostics.report_copied"))


func _export_log() -> void:
	var path := "user://logs/gamehub_report.txt"
	var report := Log.build_report()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Log.error("Diagnostics: report export failed", {"path": path, "error": FileAccess.get_open_error()})
		Notify.error(Loc.t("diagnostics.export_failed"))
		return
	file.store_string(report)
	file.close()
	DisplayServer.clipboard_set(report)
	Notify.success(Loc.t("diagnostics.exported", {"path": ProjectSettings.globalize_path(path)}))


func refresh_texts() -> void:
	_rebuild()
