# Localization

How the localization service (`Loc`) loads catalogues, resolves strings and is
checked by the test suite. Every statement below is taken from the cited source
file; nothing here describes behaviour the code does not have.

Files read for this document: `scripts/autoload/loc.gd`,
`scripts/autoload/prefs.gd`, `data/i18n/en.json`, `data/i18n/en/game_chess.json`,
`scripts/ui/screens/settings_screen.gd`, `scripts/ui/screens/diagnostics_screen.gd`,
`tests/unit/test_localization.gd`, `tests/support/i18n_scanner.gd`,
`tests/support/test_harness.gd`, `tests/games/test_chess.gd`,
`tools/i18n_scan.gd`, `docs/GAME_ENGINE_CONTRACT.md`.

## 1. Supported languages

`Loc.LOCALES` (`scripts/autoload/loc.gd`) is the single source of truth. The ten
entries, in order:

| Code | `native` (shown in the UI) | `english` | `cjk` |
|------|----------------------------|-----------|-------|
| `en` | English | English | false |
| `uk` | Українська | Ukrainian | false |
| `ru` | Русский | Russian | false |
| `de` | Deutsch | German | false |
| `zh_CN` | 中文 | Simplified Chinese | true |
| `az` | Azərbaycanca | Azerbaijani | false |
| `be` | Беларуская | Belarusian | false |
| `cs` | Čeština | Czech | false |
| `pl` | Polski | Polish | false |
| `fr` | Français | French | false |

Exactly these ten are supported:

- `Loc.locale_codes()` returns one code per `LOCALES` entry and
  `Loc.is_supported(code)` is a membership test against that list
  (`scripts/autoload/loc.gd`).
- `Loc.native_name(code)` returns the `native` field, or the code itself when the
  code is not in `LOCALES` (`scripts/autoload/loc.gd::native_name`).
- `tests/unit/test_localization.gd::_check_locale_set` asserts the count is 10,
  that each of `en, uk, ru, de, zh_CN, az, be, cs, pl, fr` is registered and that
  its native name equals the hard-coded value in `_expected_native` (same values
  as the table above).
- The `english` and `cjk` fields are metadata in `LOCALES` only: no consumer of
  either field exists in `scripts/`, `tests/` or `tools/` (checked with grep;
  only the ten `LOCALES` literals match).

## 2. Catalogue layout

| Path | Role |
|------|------|
| `data/i18n/<locale>.json` | Shell catalogue: one flat JSON object of `dotted.key -> text`. `I18N_DIR` is `res://data/i18n/`. |
| `data/i18n/<locale>/<namespace>.json` | Optional *game string pack(s)*. Every `*.json` in this directory is merged over the shell catalogue. |
| `data/i18n/en/game_chess.json` | Example game pack for the `game.chess.*` family. |

Boot sequence (`scripts/autoload/loc.gd::load_catalogues`):

1. For each `LOCALES` entry, read `data/i18n/<code>.json`
   (`_read_json`; a missing file, unreadable file or JSON parse error returns an
   empty dictionary and logs through `Log`).
2. An empty/missing shell catalogue is skipped with
   `Log.warn("Loc: catalogue missing or empty", ...)`; its packs are *not* loaded
   in that case.
3. `_load_packs(code)` merges `data/i18n/<code>/*.json`; files are taken from
   `DirAccess.get_files_at`, filtered by the `.json` suffix and sorted with
   `names.sort()`. Each file's keys are copied into the merged map in filename
   order, so a later file wins on a duplicate key. Merged pack keys are then
   written over the shell-catalogue keys in `strings`, so **packs override the
   shell catalogue**.
4. The merged dictionary is stored in `_raw[code]` and converted into a
   `Translation` resource (`translation.add_message(key, text)`), registered with
   `TranslationServer.add_translation`. Loading more than one pack logs
   `Loc: string packs merged` with the pack count and key count.
5. `translation_count_check()` logs `Loc: some catalogues failed to load` when any
   locale has no `Translation` after step 1-4.
6. `Loc._ready` selects `Prefs.locale()` via `set_locale`; if that fails it logs a
   warning and selects `FALLBACK_LOCALE` (`"en"`).

Why packs exist, per the comment in `load_catalogues`: keeping per-game strings in
their own file means a game can be added, translated and removed without touching
the shell catalogue or racing other games' translations.

Packs currently shipped (top-level `data/i18n/<locale>/` directories): every one
of the ten locales ships all thirteen `game_<id>.json` packs, with the same keys
and key order as the English source. Measured on the main branch (2026-10-20):
the shell catalogue has 465 keys, the thirteen packs add 1,088 keys, and every
locale merges to 1,553 keys — the same key set, with no missing keys, no extra
keys, no empty values and no placeholder differences against English. The
structural check is automated by `tools/audit_translations.py` (section 9); it
reported `PASS all audited packs for 13 game(s)`.

`Loc.pack_names(code)` returns the sorted list of pack filenames for a locale;
grep found no call sites in `scripts/`, `tests/` or `tools/` (its docstring claims
diagnostics/tests use it, but the code paths read today do not).

`Loc.catalogue_keys(locale = "en")` returns the merged key list of a locale,
sorted; it is used by `tests/unit/test_localization.gd::_check_english_catalogue`.

### Live language changes

`Loc.set_locale()` selects the catalogue, persists the preference and emits
`locale_changed`. `AppShell._on_locale_changed()` now evicts and frees every
cached screen except the current one, refreshes the current screen (and the
top bar/sidebar), and lets the next navigation rebuild old routes in the new
language. This avoids the previous stale-cache behaviour where a screen visited
before the switch kept its old text until an application restart.

Screens that keep static labels must implement `refresh_texts()`; the base
`ScreenBase` implementation is a no-op. `AboutScreen` rebuilds its content and
`GameScreen` refreshes its log heading and handover button. A game screen that
is not current is evicted and rebuilt the next time it is opened. A currently
displayed game view would need its own refresh hook if language switching is
ever exposed from inside a match.

## 3. Key naming conventions

Observed in `data/i18n/en.json` (465 keys) and the pack
`data/i18n/en/game_chess.json` (33 keys):

| Prefix | Examples | Content |
|--------|----------|---------|
| `app.*` | `app.name`, `app.tagline` | Application identity. |
| `common.*` | `common.back`, `common.cancel`, `common.yes` | Shared button/label text. |
| `error.*` | `error.catalog_empty` | Shell-level failure messages. |
| `nav.*` | `nav.library`, `nav.settings` | Sidebar navigation. |
| `status.*`, `online_status.*`, `mode.*`, `category.*` | `status.playable`, `category.cards` | Game metadata vocabulary. |
| `exit.*` | `exit.title`, `exit.body` | Quit confirmation. |
| `library.*` | `library.title_home`, `library.sort_name` | Library screen (titles, filters, empty states). |
| `details.*` | `details.panel_about`, `details.field_status` | Game details screen. |
| `setup.*` | `setup.players_title`, `setup.error_player_count` | Match setup screen. |
| `game.common.*` | `game.common.log`, `game.common.resign` | Strings every game engine/view shares. |
| `game.<id>.*` | `game.chess.name`, `game.chess.phase.opening` | Per-game strings, shipped in the game pack. |
| `net.*` | `net.status_line`, `net.reject_full` | Networking status and rejection reasons. |
| `steam.*`, `online.*`, `lobby.*` | `steam.status_ready`, `lobby.start_match` | Steam/online flows. |
| `settings.*` | `settings.title`, `settings.reset_all` | Settings screen (all sections). |
| `display.*` | `display.mode`, `display.confirm_change` | Display section (see `docs/DISPLAY_SETTINGS.md`). |
| `audio.*`, `language.*`, `accessibility.*` | `audio.mute`, `language.coverage` | Remaining settings sections. |
| `diagnostics.*` | `diagnostics.title`, `diagnostics.localisation` | Diagnostics screen. |
| `about.*` | `about.panel_tech` | About screen. |
| `sr.*` | `sr.selection_title`, `sr.set.status_ready` | Star Realms edition selection. |

Per-game pack naming, from `docs/GAME_ENGINE_CONTRACT.md` ("String pack" section):

```
game.<game>.name / .desc                  title and one-line description
game.<game>.phase.<id>                    phase names (one per engine phase id)
game.<game>.option.<key> / .<key>_hint    setup options
game.<game>.<thing>                       everything the view shows
game.<game>.log_<event>                   log lines with {placeholders}
game.<game>.reason.<reason>               end-of-match reasons (finish())
game.<game>.error.<error>                 rejection reasons (_fail())
```

Plural families are stored as sibling keys with `.one` / `.other` suffixes, e.g.
`library.result_count.one` / `.other`, `library.players_exact.one` / `.other`,
`library.minutes.one` / `.other`, `details.play_count.one` / `.other`,
`online.list_received.one` / `.other` (`data/i18n/en.json`).

No test asserts the *order* of keys inside a JSON file: the test suite compares
key sets/existence, and `catalogue_keys()`/`missing_keys()` sort at read time.

## 4. `Loc.t()` and `Loc.tp()`

### `t(key: String, args: Dictionary = {}) -> String`

`scripts/autoload/loc.gd::t` resolves `key` through `_translate` and, when `args`
is non-empty, formats the result with `text.format(args, "{_}")`.

Placeholder syntax is therefore `{name}` (named, brace-delimited), and the
arguments dictionary supplies the values, e.g.
`Loc.t("display.max_fps_value", {"value": "60"})`.

`_translate(key)` resolution order:

1. `TranslationServer.translate(key)` - if the result differs from the key and is
   non-empty, return it.
2. Try the plural siblings `key + ".other"` then `key + ".one"` through
   `TranslationServer.translate`. A plural-only entry is a valid answer to a
   request for the bare key (a header can show the same text a count does).
3. English fallback from `_raw["en"]`: the bare key (this path calls
   `_note_missing(key)`), else `key + ".other"` / `key + ".one"` (these paths do
   **not** call `_note_missing`).
4. Otherwise `_note_missing(key)`, `Log.warn("Loc: missing translation key", ...)`
   and return `humanize_key(key)`.

### `tp(key: String, count: int, args: Dictionary = {}) -> String`

`scripts/autoload/loc.gd::tp`:

- Suffix is `.one` when `count == 1`, otherwise `.other` (so `0`, negative and
  plural counts all take `.other`).
- Lookup order: `<key><suffix>` in the **current** locale's `_raw` table, then the
  same key in the **English** `_raw` table (read directly, without
  `_note_missing`), then `_translate(key)` (which itself retries the plural
  siblings, see above).
- `args` is duplicated and `"count"` is always set to `count` afterwards, then
  formatted with `"{_}"`. Example: `Loc.tp("library.result_count", entries.size())`
  with `"{count} games"` in the catalogue
  (`scripts/ui/screens/library_screen.gd` uses exactly this call).

Only two plural forms exist. That is verified in the code: every suffix literal in
`tp` and `_translate` is either `".one"` or `".other"` (grep for `".one"`/`".other"`
in `loc.gd` finds only those two), and `docs/GAME_ENGINE_CONTRACT.md` states
"Counts use `.one` / `.other` suffixes and `Loc.tp(key, count)`". Languages with
more plural categories (e.g. the Slavic "few"/"many" forms of ru/uk/be/pl/cs) have
to fold them all into `.other`; there is no `.few`/`.many`/`.zero` support.

## 5. Fallback chain and the "never show a raw key" rule

Chain: current locale -> English catalogue -> humanised key
(`scripts/autoload/loc.gd::_translate`, and the header comment of `loc.gd` states
"raw keys are never shown to players").

`humanize_key(key)` takes the text after the last `.`, replaces `_` with spaces,
strips edges and upper-cases the first character (`game.chess.name` -> `Name`,
`library.search_placeholder` -> `Search placeholder`). If the tail is empty the
raw key is returned unchanged.

Missing-key tracking:

- `_note_missing(key)` increments a counter in `_missing_keys` (an in-memory
  `key -> count` dictionary; `loc.gd` contains no persistence for it).
- `missing_keys()` returns the tracked keys sorted as a `PackedStringArray`.
- `reset_missing_tracking()` clears the dictionary. The test suite calls it before
  asserting.
- The diagnostics screen displays `Loc.missing_keys().size()` in the row keyed
  `diagnostics.missing_runtime`, coloured danger when the number is non-zero
  (`scripts/ui/screens/diagnostics_screen.gd`).

How the suite enforces the rule (`tests/unit/test_localization.gd`):

- `_check_runtime_keys`: every literal key found by `I18nScanner.scan_static_keys()`
  must exist in English, directly or as `.one`/`.other` (`_has_translation`); the
  scanner must find more than 200 keys. `TestHarness.check(false, ...)` fails the
  suite for each missing key, listing `key (file:line)`.
- `_check_no_raw_keys`: after `loc.reset_missing_tracking()`, every static key is
  rendered with `Loc.t`; the text must pass `TestHarness.no_raw_key` (fails when
  the text contains `.`, has no spaces and is all lower-case - i.e. looks like a
  machine key; humanised fallbacks are explicitly allowed by design) and must not
  be empty; finally `Loc.missing_keys().size()` must be `0` in English.

## 6. Source-key scanning (`I18nScanner`)

`tests/support/i18n_scanner.gd` is a static analysis helper shared by the test
suite and `tools/i18n_scan.gd`:

- Scans `res://scripts` and `res://tests` (`SCAN_DIRS`), all `.gd` files recursing
  into directories, skipping dotfiles and the scanner file itself.
- `scan_static_keys()` matches the `LITERAL_PATTERNS` regexes - `Loc.t("...")`,
  `UI.t("...")`, `Loc.tp("...")`, `"label_key": "..."` / `label_key = "..."`,
  `"text_key"...`, `key = "..."`, `"reason_key": "..."`, `has_key("...")`,
  `return "lower.dotted"`, a lower-case dotted string alone on a line (keys
  collected in constant arrays such as `SECTION_KEYS` and looked up later),
  `log_event("...")`, `_fail("...")`,
  `finish(..., "...")`, `warning/success/info("...")`, `_emit_rejection("...")`,
  `emit("...")` - and returns `{ key: "path:line" }`. `Loc.t`, `UI.t`, `Loc.tp`
  and `has_key` also accept a slash (`audio/master`), so a key that mixes
  separators fails the gate instead of silently falling back to a humanised
  string.
- `scan_dynamic_patterns()` collects the *patterns* that are completed at runtime
  with `%s`/`%d` formatting; it is used by the developer tool only.
- `_is_ignored` drops values that begin with `res://`, `user://` or `127.0.0.1`,
  and any value containing `:` (URI-style developer strings). A slash alone is
  no longer ignored because translation keys may contain one.

## 7. Coverage reporting

`Loc.coverage_report()` (`scripts/autoload/loc.gd`) returns per-locale statistics
using the **merged English** table as the reference:

| Field | Meaning |
|-------|---------|
| `total_keys` | `_raw["en"].size()` (shell catalogue + English packs). |
| `translated` | `table.size()` - all keys of that locale's merged table. |
| `missing` | number of reference keys absent from the locale. |
| `missing_keys` | the sorted list of those keys. |
| `percent` | `translated / total_keys * 100`, or `100.0` when the reference is empty. |

Note: the numerator counts *all* locale keys, including keys that English does not
have; such extra keys can push `percent` above the true translation ratio.

Who reads it:

- `scripts/ui/screens/settings_screen.gd::_build_language` renders one row per
  locale: a button labelled with `Loc.native_name(code)`, the
  `language.coverage` label (`{translated} of {total} strings ({percent}%)`), a
  `language.partial` chip when the locale is not active and `percent < 99.9`, and
  a `language.active` chip for the current locale.
- `scripts/ui/screens/diagnostics_screen.gd::_build_summary` prints
  `translated / total (percent%)` per locale, coloured positive when
  `missing == 0` and warning otherwise, plus the runtime missing-key count.

## 8. How to add a string

1. Add the key to `data/i18n/en.json` (shell UI text) or to the owning game pack
   `data/i18n/en/game_<game>.json`. Flat `key -> text`, `{name}` placeholders,
   full sentences, `.one`/`.other` for counts
   (`docs/GAME_ENGINE_CONTRACT.md`).
2. Use it from code with a string literal (`Loc.t("...")`, `Loc.tp("...", n)`,
   `label_key`, `_fail("...")`, ...) - the scanner only sees literals that match
   the patterns in section 6.
3. Mirror the key into every other locale catalogue/pack.
4. Run the gates (section 10) and the placeholder/key-set diff (section 9).

## 9. Verification commands for translators

The automated gates (docstrings of `tests/run_tests.gd` and
`tools/i18n_scan.gd`):

```bash
# full test run, and the localisation suite only
godot --headless --path . --script tests/run_tests.gd
godot --headless --path . --script tests/run_tests.gd -- --filter localization

# list every static key and every runtime-completed key pattern
godot --headless --path . --script tools/i18n_scan.gd

# structural audit of every locale pack against English: key set, key order,
# non-empty values and placeholder multisets
python3 tools/audit_translations.py            # all games
python3 tools/audit_translations.py bridge     # one game
```

`tools/audit_translations.py` exits non-zero on structural defects. Values that
are identical to English are reported as review warnings only (proper nouns such
as game names and card-suit symbols legitimately stay the same). The older
hand-written Python check below is kept for ad-hoc debugging of one locale:

```bash
python3 - <<'PY'
import glob, json, re

LOCALE = "de"                      # <-- locale to check
BASE = "data/i18n"

def shell(locale):
    return json.load(open(f"{BASE}/{locale}.json", encoding="utf-8"))

def merged(locale):
    out = shell(locale)
    for path in sorted(glob.glob(f"{BASE}/{locale}/*.json")):
        out.update(json.load(open(path, encoding="utf-8")))
    return out

ref = merged("en")
target = merged(LOCALE)

missing = sorted(set(ref) - set(target))
extra = sorted(set(target) - set(ref))
print(f"{LOCALE}: missing {len(missing)}", missing[:10])
print(f"{LOCALE}: extra   {len(extra)}", extra[:10])

placeholders = re.compile(r"\{[a-z_]+\}")
for key in sorted(set(ref) & set(target)):
    value = target[key]
    if not str(value).strip():
        print("EMPTY:", key)
    want, got = set(placeholders.findall(ref[key])), set(placeholders.findall(value))
    if want != got:
        print("PLACEHOLDERS:", key, sorted(want), sorted(got))
PY
```

## 10. What the test suite enforces

`tests/unit/test_localization.gd` (`suite_name() == "localisation"`) runs:

| Check | Function | Assertion |
|-------|----------|-----------|
| Locale set | `_check_locale_set` | Exactly 10 locales, the ten codes above, matching native names. |
| English catalogue | `_check_english_catalogue` | More than 300 keys; `app.name` and `game.common.log` exist. |
| Literal keys | `_check_runtime_keys` | Every `I18nScanner` static key exists in English (or as `.one`/`.other`); scanner finds more than 200 keys. |
| Coverage | `_check_coverage` | Every locale's `percent` is greater than 99.9. |
| Game families | `_check_game_families` | For every `Catalog.games()` entry: `name_key` and `desc_key` exist in English, `Loc.t(name_key)` is not a raw key, the description is longer than 20 characters; when the engine is available, every `engine.phases()` id has `game.<id>.phase.<id>`. |
| No raw keys | `_check_no_raw_keys` | Every static key renders as text (passes `no_raw_key`), is non-empty, and `Loc.missing_keys()` is empty while playing in English. |

`tests/games/test_chess.gd::_bot_match` additionally asserts that every move-log
`text_key` exists in English and that `game.chess.log_move` never appears in
`Loc.missing_keys()`.

## 11. Known limitations (verified only)

- **Two plural forms only.** `tp`/`_translate` use `.one` and `.other`
  exclusively, so `ru`, `uk`, `be`, `pl` and `cs` must write "few"/"many" wording
  into `.other`. `count == 1` is the only trigger for `.one`.
- **English plural fallback is not counted as missing.** Only the bare-key English
  fallback calls `_note_missing`, so a locale that falls back on `key.other`/
  `key.one` does not surface in `Loc.missing_keys()`; and `tp`'s direct English
  plural read bypasses `_note_missing` entirely.
- **`coverage_report().translated` counts keys English does not have**, so a pack
  that exists only in a translation inflates `percent` (the `missing` count stays
  correct).
- **Missing-key tracking is in memory only.** `_missing_keys` is cleared by
  `reset_missing_tracking()` and is not written to disk or to `Prefs`.
- **`native_name()` returns the code itself** for an unrecognised locale code.
- **The dynamic key patterns are reported, not gated.** Only
  `scan_static_keys()` feeds a test; `scan_dynamic_patterns()` is used by
  `tools/i18n_scan.gd` for a developer report.
- **The Godot suite does not validate placeholders by itself.**
  `tools/audit_translations.py` performs the structural key/order/placeholder
  audit; run it after touching any pack. Placeholder mismatches, empty values and
  key-set drift are therefore caught by an automated tool but not by the GDScript
  test run alone.
- **Pack counts are time-sensitive**: the numbers in section 2 were re-measured on
  2026-10-20 after the wave-9 UI work (465 shell keys + 1,088 pack keys = 1,553
  merged keys per locale).
- **`Loc.pack_names()` has no call sites** in `scripts/`, `tests/` or `tools/`.
