# Display settings

How display and interface-scale preferences are stored, validated, applied and
reported. Every statement below is taken from the cited source file.

Files read for this document: `scripts/autoload/prefs.gd`,
`scripts/core/display_manager.gd`, `scripts/ui/main.gd`, `scripts/ui/app_shell.gd`,
`scripts/ui/screens/settings_screen.gd`,
`scripts/ui/screens/diagnostics_screen.gd`, `scripts/ui/ui_factory.gd`,
`scripts/autoload/log.gd`, `scripts/autoload/audio_service.gd`, `project.godot`.

## 1. Settings, defaults and accepted ranges

All display-related keys of `Prefs.DEFAULTS` (`scripts/autoload/prefs.gd`) and the
range its sanitizer `Prefs._sanitize` enforces when a value is written or loaded:

| Key (`Prefs.DEFAULTS`) | Default | Sanitizer rule (`Prefs._sanitize`) | Typed helper |
|------------------------|---------|-------------------------------------|--------------|
| `display/mode` | `0` | `clampi(int(value), 0, 2)` | `Prefs.window_mode()` |
| `display/width` | `1600` | `clampi(int(value), 640, 16384)` | `Prefs.window_width()` |
| `display/height` | `900` | `clampi(int(value), 640, 16384)` | `Prefs.window_height()` |
| `display/screen` | `0` | `clampi(int(value), 0, maxi(0, DisplayServer.get_screen_count() - 1))` | `Prefs.screen_index()` |
| `display/vsync` | `1` | `clampi(int(value), 0, 3)` | - (`Prefs.get_value("display/vsync", 1)`) |
| `display/max_fps` | `0` | `clampi(int(value), 0, 480)` | - (`Prefs.get_value("display/max_fps", 0)`) |
| `general/ui_scale` | `1.0` | `clampf(float(value), 0.75, 1.75)` when the value is a `float` or `int`, else `1.0` | `Prefs.ui_scale()` |

Notes:

- `display/mode` values are named in `DisplayManager`
  (`scripts/core/display_manager.gd`): `MODE_WINDOWED = 0`,
  `MODE_FULLSCREEN = 1`, `MODE_BORDERLESS = 2`. `Prefs` also declares
  `enum WindowMode { WINDOWED = 0, FULLSCREEN = 1, BORDERLESS_FULLSCREEN = 2 }`,
  but grep found no user of that enum; the `DisplayManager` constants are the ones
  actually used.
- `general/ui_scale` is sanitized by type: a non-numeric value becomes `1.0`
  rather than being clamped.
- The sanitizer for `display/screen` depends on the monitors present when the
  value is checked, so a persisted monitor index is clamped on the next load on a
  machine with fewer screens.
- `project.godot` sets the boot window to `viewport_width=1600`,
  `viewport_height=900` - the same values as the defaults.
- Not display keys, but they live in `Prefs.DEFAULTS` and appear on the same
  settings screen: `general/reduced_motion` (default `false`; consumed by
  `scripts/ui/ui_factory.gd` and `scripts/ui/toast_layer.gd` animation code, not
  by display code) and `general/show_development_titles` (default `true`).

## 2. Window modes and size validation at apply time

`DisplayManager` is the only code that changes the window
(`scripts/core/display_manager.gd`). It adds a second layer of validation on top
of `Prefs._sanitize`:

| Constant | Value | Effect |
|----------|-------|--------|
| `MIN_WIDTH` | `800` | Floor applied by `DisplayManager.sanitize_size`. |
| `MIN_HEIGHT` | `540` | Floor applied by `DisplayManager.sanitize_size`. |
| `REVERT_SECONDS` | `12.0` | Countdown before an unconfirmed change is reverted. |

`DisplayManager._apply(mode, size, screen, with_revert)`:

1. Clamps `screen` to `0 .. max(0, DisplayServer.get_screen_count() - 1)`.
2. Reads `DisplayServer.screen_get_usable_rect(safe_screen)` and clamps the
   requested size to it with `sanitize_size` (minimum `800x540`, maximum the
   usable rect).
3. Applies by mode:
   - `MODE_FULLSCREEN`: `window.mode = Window.MODE_FULLSCREEN`.
   - `MODE_BORDERLESS`: `window.mode = Window.MODE_WINDOWED`,
     `window.borderless = true`, size and position set to the usable rect (the
     stored width/height are ignored in this mode).
   - windowed (default branch): `MODE_WINDOWED`, `borderless = false`, size is the
     clamped size, and the window position is clamped so the window stays inside
     the usable area of the target screen.
4. Logs `DisplayManager: applied` with mode/size/screen and emits the
   `"applied"` event.

`DisplayManager.sanitize_size(requested, usable)` clamps width and height to
`MIN_WIDTH`/`MIN_HEIGHT` as a floor and to the usable rect as a ceiling.

## 3. Where each setting is applied

| Setting | Applied by | When |
|---------|------------|------|
| `display/mode`, `display/width`, `display/height`, `display/screen` | `DisplayManager.apply_from_prefs()` -> `_apply(...)` (saved values) or `DisplayManager.request(mode, size, screen)` (user change) | Boot (`scripts/ui/main.gd::_ready`, before the shell exists) and from the Display settings section. |
| `display/vsync` | `DisplayManager._apply_vsync` -> `DisplayServer.window_set_vsync_mode(mode)`; the settings screen also calls `DisplayServer.window_set_vsync_mode(int(value))` directly on change | Boot via `apply_from_prefs()` and immediately on change. `_apply_vsync` returns early when `DisplayServer.get_name() == "headless"`. |
| `display/max_fps` | `DisplayManager._apply_max_fps` -> `Engine.max_fps = maxi(0, value)`; the settings screen sets `Engine.max_fps = int(value)` directly on change | Boot via `apply_from_prefs()` and immediately on change. |
| `general/ui_scale` | `AppShell._apply_ui_scale()` -> `get_window().content_scale_factor = clampf(Prefs.ui_scale(), 0.75, 1.75)` (`scripts/ui/app_shell.gd`) | `AppShell._ready()` and on every `Prefs.setting_changed` for `general/ui_scale`. |

Boot order (`scripts/ui/main.gd`): `DisplayManager.apply_from_prefs()` runs before
the shell is built, then `Log.info("Main: display configured", {"summary":
DisplayManager.display_summary()})`. `apply_from_prefs()` reads mode, size and
screen from `Prefs`, applies them with `with_revert = false`, then applies VSync
and max FPS.

Safety revert (only for mode/size/screen changes):

- `DisplayManager.request()` snapshots the current `Prefs` display values into
  `_pending_snapshot`, then applies with `with_revert = true`.
- `_arm_revert()` creates a `SceneTreeTimer` of `REVERT_SECONDS = 12.0`; on
  timeout `revert_pending("timeout")` restores the snapshot and emits
  `"reverted"` / `"confirmation_finished"` events.
- `confirm_pending()` cancels the timer, clears the snapshot and emits
  `"confirmation_finished" {"kept": true}`.
- `has_pending()` reports whether the countdown is armed.
- Static listener hook: `DisplayManager.add_listener(callback)` /
  `remove_listener(callback)`; events are `"applied"`, `"reverted"` and
  `"confirmation_finished"`. The Display settings screen is the only listener
  registered in the code read (`settings_screen.gd::build`); it shows the revert
  banner, keeps or reverts the change.
- VSync and max-FPS changes set the value immediately and do **not** arm the
  countdown.

Keyboard: `F11` is handled in `AppShell._unhandled_input` and calls
`DisplayManager.toggle_fullscreen()`, which switches between
`Window.MODE_FULLSCREEN` and windowed mode (it cannot select borderless), writes
`display/mode` to `Prefs`, applies without revert, shows the `display.toggled`
notice and emits `"applied"`.

## 4. Settings UI

All sections are one screen: `scripts/ui/screens/settings_screen.gd`
(`SettingsScreen`, enum `Section`). Routes `settings`, `settings_display`,
`settings_language`, `settings_audio` and `settings_accessibility`
(`scripts/autoload/nav.gd`) all resolve to this screen
(`scripts/ui/app_shell.gd::ROUTE_SCREENS`); `on_enter()` picks the section from the
route or from the optional `params["section"]` index, clamped to
`0 .. Section.size() - 1`.

Display section controls (`_build_display`):

| Control type | UI label key | Behaviour on change |
|--------------|--------------|---------------------|
| Key/value row | `display.current` (key) | Shows `DisplayManager.display_summary()` (`display.summary` with `{mode}`, `{size}`, `{native}`, `{screens}`). Not a control. |
| `OptionButton` (`UI.dropdown`) | `display.mode`, hint `display.mode_hint` | `_apply_display(int(value), current stored size)`: writes `display/mode`, `display/width`, `display/height`, calls `DisplayManager.request(...)` (arms the 12 s countdown) and rebuilds. Options: `display.mode_windowed` (0), `display.mode_fullscreen` (1), `display.mode_borderless` (2). |
| `OptionButton` | `display.resolution`, hint `display.resolution_hint` | Parses `WxH` and calls `_apply_display(current mode, size)`. Options come from `DisplayManager.available_resolutions()`: `1280x720, 1366x768, 1440x900, 1600x900, 1920x1080, 2560x1440, 3840x2160` plus the native size of the current screen when not already in the list, sorted smallest area first, labelled `W × H`. |
| `OptionButton` (only when `DisplayServer.get_screen_count() > 1`) | `display.screen` | Writes `display/screen` with `Prefs.set_value`, then `_apply_display(mode, stored size)` (countdown armed). Items are labelled `"<n> (<W>×<H>)"` for each screen; the value is the zero-based index. |
| `OptionButton` | `display.vsync` | Writes `display/vsync` and calls `DisplayServer.window_set_vsync_mode(int(value))` directly. Options: `display.vsync_disabled` (0), `display.vsync_enabled` (1), `display.vsync_adaptive` (2), `display.vsync_mailbox` (3) - matching the 0..3 range of the sanitizer. |
| `HSlider` + value label (`UI.slider` + `UI.label`) | `display.max_fps` (`display.max_fps_hint`, value label `display.max_fps_value`) | Writes `display/max_fps`, sets `Engine.max_fps`, updates the `{value} fps` label. Slider range `0..240`, step `10`. |
| `HSlider` + value label | `display.ui_scale` (`display.ui_scale_hint`) | Writes `general/ui_scale` and updates a `NN%` label; the `AppShell` listener then updates `content_scale_factor`. Range `0.75..1.75`, step `0.05`. The same pref is exposed again in the Accessibility section under `accessibility.ui_scale` / `accessibility.ui_scale_hint`. |
| Buttons | `display.restore_safe`, `display.native_size`, `display.toggle_fullscreen` | See below. |

Buttons:

- `display.restore_safe` ("Restore safe display settings"): asks
  `Notify.confirm` with `display.restore_safe_confirm`; on accept it writes
  `display/mode = MODE_WINDOWED`, `display/width = 1600`, `display/height = 900`,
  `display/screen = 0`, calls `DisplayManager.apply_from_prefs()` and shows
  `display.restore_done`.
- `display.native_size` ("Use desktop size"): reads
  `DisplayServer.screen_get_size(screen)` and calls
  `_apply_display(MODE_WINDOWED, native)`.
- `display.toggle_fullscreen` ("Toggle fullscreen"): calls
  `DisplayManager.toggle_fullscreen()`.

Revert banner (above the section content, visible while
`DisplayManager.has_pending()`): the label uses `display.confirm_change` with
`{seconds} = int(DisplayManager.REVERT_SECONDS)`; buttons `display.keep`
(`DisplayManager.confirm_pending()`) and `display.revert`
(`DisplayManager.revert_pending("user")`).

## 5. Persistence

| Aspect | Implementation |
|--------|----------------|
| File | `Prefs.SETTINGS_PATH = "user://gamehub_settings.cfg"` (a Godot `ConfigFile`). |
| Section/key mapping | `Prefs._section(path)` takes the text before the first `/`, `Prefs._key(path)` the text after it. Example: `display/vsync` -> section `display`, key `vsync`. |
| Reading | `Prefs.get_value(path, fallback)`: stored value if the section/key exists, else `Prefs.DEFAULTS[path]`, else `fallback`. `Prefs.has(path)` tests only the stored file. |
| Writing | `Prefs.set_value(path, value)` sanitizes first (`_sanitize`), skips the write when the stored value is already equal (`_values_equal`: element-wise for arrays, `JSON.stringify` for dictionaries, `is_equal_approx` for floats), otherwise stores it, marks the state dirty, (re)starts the debounce timer and emits `setting_changed(path, sanitized)`. |
| Debounce | `SAVE_DEBOUNCE_SEC = 0.6`: a one-shot `Timer` started on every accepted write, whose `timeout` is connected to `save_now`. |
| `save_now()` | No-op when nothing is dirty; otherwise `_config.save(SETTINGS_PATH)`, logs `Prefs: failed to save settings` on error, clears the dirty flag and emits `settings_saved`. Also called on `NOTIFICATION_WM_CLOSE_REQUEST` and `NOTIFICATION_EXIT_TREE` (`Prefs._notification`), from `Main._notification` and from `AppShell._quit_now`. |
| First run / corrupt file | `Prefs._load`: if `ConfigFile.load` fails, it rebuilds the config from `Prefs.DEFAULTS`, marks it dirty and saves immediately (a missing file is expected and logged only for non-`ERR_FILE_NOT_FOUND` cases). The file therefore contains the full schema after the first boot. |
| Migration | `Prefs._migrate` (run after a successful load): every missing `DEFAULTS` path is written with its default, every existing value is passed through `_sanitize` and rewritten when it changed, and both steps set the dirty flag and save once. Keys that are not in `DEFAULTS` are preserved as-is and logged at debug level (`Prefs: unknown setting kept as-is`); they are never read by typed code. |
| Reset | `Prefs.reset_to_defaults(section_filter = "")`: with an empty filter, every `DEFAULTS` path is restored. With a filter, paths that do **not** start with the filter are kept and only the filtered section is restored. It saves immediately, emits `settings_reset`, then emits `setting_changed` for every `DEFAULTS` path with the restored value. The settings UI only calls it without a filter (`settings_screen.gd`). |
| Reset button | `settings.reset_all` asks for confirmation (`settings.reset_all_confirm`), then calls `Prefs.reset_to_defaults()`, re-applies the locale (`Loc.set_locale(String(Prefs.get_value("general/locale", "en")))`), `DisplayManager.apply_from_prefs()` and `Audio.apply_volumes()`, and shows `settings.reset_done`. The confirmation text states that play history is cleared; that follows from `library/recent` being a `DEFAULTS` key with default `[]`. |

## 6. What the UI reports about the stored file and display

- Settings screen, General section, Storage block (`_build_general`):
  `settings.settings_file` shows `ProjectSettings.globalize_path(Prefs.SETTINGS_PATH)`
  next to `settings.catalog_games`, `settings.languages` and `settings.version`.
- Settings screen, Display section: `display.current` ->
  `DisplayManager.display_summary()`, which renders `display.summary` with the
  current mode key (`display.mode_windowed` / `display.mode_fullscreen` /
  `display.mode_borderless`), the **actual** window size, the screen's native size
  and the screen count.

## 7. Diagnostics

Diagnostics screen (`scripts/ui/screens/diagnostics_screen.gd`) does not have a
dedicated display panel; display data reaches the report through the log:

- `Main: display configured` with the `DisplayManager.display_summary()` string is
  logged at boot (`scripts/ui/main.gd`), and `DisplayManager: applied` with
  mode/size/screen is logged on every apply (`scripts/core/display_manager.gd`).
- The Services block shows `diagnostics.engine`, `diagnostics.platform`,
  `diagnostics.renderer` (`rendering/renderer/rendering_method` +
  `RenderingServer.get_video_adapter_name()`), `diagnostics.uptime`,
  `diagnostics.errors`, `diagnostics.warnings`.
- The Localisation block shows per-locale coverage (`Loc.coverage_report()`) and
  `diagnostics.missing_runtime` = `Loc.missing_keys().size()`.
- Toolbar: `diagnostics.copy_report` puts `Log.build_report()` on the clipboard;
  `diagnostics.export_log` writes the same text to
  `user://logs/gamehub_report.txt`, closes the file, copies it to the clipboard and
  shows `diagnostics.exported` with the globalized path (or
  `diagnostics.export_failed` when the file cannot be opened).
- `Log.build_report()` (`scripts/autoload/log.gd`) contains: engine version,
  platform (`OS.get_name()` and `OS.get_version()`), uptime, error/warning counts,
  the log file path and all recent log entries (level, message, context) - so the
  boot display summary and every `DisplayManager: applied` line are included.
- The log file itself is `user://logs/gamehub.log`; `Log._open_log_file()` creates
  the `user://logs/` directory at boot and rotates the previous session to
  `gamehub.log.prev`.
- Observed in the diagnostics log filter: the button labelled
  `diagnostics.errors_only` ("Errors and warnings") sets
  `_filter_level = Log.Level.ERROR`, and `Log.get_entries` keeps only entries whose
  level equals the filter, so that view shows errors only, not warnings.

## 8. Known limitations (verified only)

- **Slider/range mismatch for `display/max_fps`**: the sanitizer accepts
  `0..480`, but the settings slider offers only `0..240` (step `10`). A value
  between 241 and 480 set by another means cannot be reproduced with the slider.
- **Two different size ranges**: `Prefs._sanitize` accepts width/height
  `640..16384`, while `DisplayManager.sanitize_size` additionally floors at
  `800x540` and caps at the screen's usable rect. The value stored in
  `display/width` / `display/height` can therefore differ from the window size
  actually requested.
- **Borderless mode ignores the stored size**: `_apply` sets the borderless window
  to the usable rect; `display/width` / `display/height` keep their values and are
  used again when the mode returns to windowed.
- **`display/screen` is clamped to the monitors present at check time** (both in
  `Prefs._sanitize` and again in `DisplayManager._apply`), so a configuration
  copied from a multi-monitor machine silently falls back to the highest existing
  index.
- **No global applier for `display/*`**: `Prefs.setting_changed` has exactly two
  consumers in the code read - `AppShell` (handles `general/ui_scale` and text
  refresh for `general/*` / `library/*`) and the `Audio` autoload
  (`scripts/autoload/audio_service.gd`, handles `audio/*` only). VSync and max FPS
  are applied by the settings
  screen itself and at boot by `DisplayManager.apply_from_prefs()`; a write to
  `display/vsync` or `display/max_fps` from elsewhere would be persisted but not
  applied until the next boot or settings-screen change.
- **`F11` cannot reach borderless mode**: `toggle_fullscreen` only alternates
  between `MODE_FULLSCREEN` and windowed.
- **The revert countdown is only surfaced on the settings screen**: the settings
  screen registers the single `DisplayManager` listener. Navigating away hides the
  banner and the pending checkboxes; the timer still reverts after
  `REVERT_SECONDS` (`revert_pending("timeout")`).
- **VSync changes are not verified by a countdown** and are applied directly to
  `DisplayServer`, independently of `DisplayManager._apply`.
- **No restart prompt**: every display value is applied live (mode, size, screen,
  VSync, max FPS, UI scale); the sources contain no "requires restart" path.
- **`DisplayManager.apply_from_prefs()` runs before the shell exists**
  (`main.gd::_ready`), so the window is configured before any layout code reads
  the window size.
