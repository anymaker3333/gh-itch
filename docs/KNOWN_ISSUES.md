# Known issues

Honest list of what is incomplete, unverified or simplified, with the evidence
that each entry rests on. Updated 2026-10-20.

Legend: **unverified** = no test/manual evidence exists in this environment;
**documented** = verified by automated tests and/or a documented manual run;
**by design** = intentional, with rationale.

## 1. Verification gaps (environment)

### 1.1 Real Steam multiplayer is unverified here — *unverified, environment-blocked*

Real Steam sessions cannot be completed in this sandbox because only one Steam
account/peer is available. During the latest verification attempt (2026-10-20)
the Steam client was **not running**: `SteamSvc` reported `FAILED` with
"Cannot create IPC pipe to Steam client process." Earlier windowed runs did
reach `READY` for App ID 480 with a valid persona/Steam ID, so the integration
code is not the blocker. What is missing is a running Steam client plus a second
account and a second machine to join a lobby and exchange gameplay packets.

What *is* verified instead (see `docs/STEAM_INTEGRATION.md`):

* the complete host-authoritative flow (handshake → seat assignment → match
  start → action forwarding → resign → match end) over a real socket, by
  `tools/run_net_smoke.sh`: two processes, **host 17 / client 18 checks, 0
  failures** with `expect_private` for hidden-information games, and eleven
  games exercised this way — chess, codenames, dany, splendor, star realms,
  citadels, coup, monopoly, ticket to ride, durak and king;
* when the client was running, the SteamGateway reported the installed
  GodotSteam API (798 methods, 188 signals), `SteamSvc` reached `READY` for App
  ID 480, and the lobby/metadata code paths are covered by unit/UI tests and the
  screen smoke;
* graceful degradation everywhere Steam is absent: services report
  `UNAVAILABLE` / `FAILED`, the UI shows a degraded state, nothing is faked;
* the wire protocol's validation paths (version, unknown types, oversize
  packets, typed reject reasons).

To close this, run the 10-step manual checklist in `docs/STEAM_INTEGRATION.md`
§10 on a machine with a Steam client and two accounts, and record the outcome
in its verification-status table.

### 1.2 Interactive debugger bridge can be squatted — *by design (environment)*

The MCP interactive bridge binds `127.0.0.1:9876`. When several dev sessions
run at once, a wedged connection from an older server can hold the socket, and
`game_state`-style commands time out even though the app is healthy. Workaround:
call `stop_project` before `run_interactive`. The project's own smoke checks do
not use this bridge — `tools/run_boot_smoke.sh` runs plain
`godot --headless --path . --quit-after N` and is unaffected.

### 1.3 The network smoke opens two seats — *unverified (by scope)*

`tools/run_net_smoke.sh` starts one host and one client process, so it verifies
two-seat replication. Games with a larger *minimum* cannot be exercised at their
catalog minimum through it yet:

* Spyfall needs at least three seats and Bridge needs exactly four, so both stay
  `online_status: not_implemented`; Bridge also omits the online mode in the
  catalog.
* King (catalog minimum three) was exercised with two seats and the engine
  handled the run, but a three-plus-seat multiplayer match — human or bot seats —
  has not been replicated over the network and remains a caveat on its
  `implemented` status.
* Durak (minimum two) passes the smoke at its minimum, including the
  non-empty-private-slice assertion.

Closing this needs a multi-client smoke (additional client processes), which is
not implemented.

### 1.4 Visual audit is windowed and structural; aesthetics stay manual — *documented*

Headless windows are minimised and produce transparent captures, so visual
checks run windowed at 1600x900. `tools/_ui_audit.gd` boots the real shell,
forces `uk` without persisting it, walks all 30 routes (the shell screens plus
all 13 game tables) and writes screenshots plus a structural report to
`/tmp/opencode/ui_audit`. The latest run produced 30 non-black captures with
0 clipped labels, 0 zero-size interactive controls, 0 controls outside the
screen and 0 missing keys. The check deliberately skips labels inside
`ScrollContainer` because their content is reachable by scrolling, and it does
not judge contrast, typography, readability or aesthetics. A manual look at the
captures, and a native-speaker review of the translations, are still required.

### 1.5 Headless automation disables Steam — *documented workaround*

The Steamworks client can abort a short-lived headless engine process while it
tears down (`SIGSEGV`/`SIGABRT` inside `steamclient.so` after the tests already
reported `PASS`), which made scripted runs non-deterministic. Every automated
headless phase therefore exports `GAMEHUB_DISABLE_STEAM=1` — set by
`tests/run_tests.gd`, `tools/screen_smoke.gd` and `tools/net_smoke.gd` in their
`_initialize()`, and exported by `tools/run_boot_smoke.sh`. `SteamSvc` reports
`State.DISABLED` ("Steam disabled for this automated run.") and initialises
nothing. A normal windowed run never sets the variable: it reaches `READY` for
App ID 480 exactly as documented in `docs/STEAM_INTEGRATION.md`. Passing real
Steam checks by hand remains required for the Steam path (see §1.1).

## 2. GDScript 4.7.2 parser quirks (workarounds enforced by tests)

### 2.1 Multiline lambda inside an array literal is a parse error — *documented*

```gdscript
# Does NOT parse ("Unindent doesn't match the previous indentation level"):
UI.row(10, [
	UI.slider(..., func(value: float) -> void:
		_apply(value)
	),
])
```

Fix: hoist the callable into a local variable first, then use it in the array.
This is the pattern every screen now follows, and
`tests/unit/test_scripts_compile.gd` fails the build if a new one sneaks in.

### 2.2 `const X: PackedStringArray = PackedStringArray([...])` is a parse error — *documented*

Use `const X: Array[String] = [...]` and `PackedStringArray(X)` at the use site
(see `FONT_FAMILIES` in `scripts/ui/theme_builder.gd`).

### 2.3 A lambda body's dedent must return to the statement's indentation — *documented*

Lambdas passed as arguments must end at the indentation level of the line that
started the statement. Nested call arguments after the lambda then continue from
that level. Where that gets unreadable, hoist the callable instead (same fix as
§2.1).

### 2.4 `load()` does not return `null` for scripts with parse errors — *documented*

Loader code must check `is GDScript` **and** `can_instantiate()` to detect a
broken script; the compile suite and the test runner both do.

## 3. Content and integration gaps

### 3.1 No bundled fonts — *by design, with a CJK caveat*

`assets/fonts/` is empty. `ThemeBuilder` resolves a family list at runtime
(`Inter`, `Noto Sans`, `DejaVu Sans`, …, including `Noto Sans CJK SC` for
Chinese) and falls back to Godot's built-in font. Consequence: Chinese text is
only rendered with a proper CJK font when one of the listed CJK families is
installed on the system; otherwise glyphs fall back to the built-in font.
Bundling a font is a follow-up if distribution requires it.

### 3.2 `data/cards/` is an empty placeholder — *by design*

Card definitions live as typed constants inside their game scripts (the engine
contract forbids runtime file loading; determinism comes from the seeded RNG).
The empty directory is kept for future card-data tooling.

### 3.3 Translation quality is structurally verified — *documented limit*

All ten locales ship all thirteen game packs with exact key parity, order and
placeholder multisets, and `tools/audit_translations.py` passes for all games.
No native-speaker style review has been done, so terminology can still be
awkward even where the structure is correct. Values identical to English are
reported as review warnings rather than failures when they are proper nouns,
game names or card symbols.

### 3.4 Catalog status labels — *by design*

`data/catalog/games.json` carries an explicit status per game
(`playable` / `partial` / `planned` / `in_development`) and an online status
(`verified` / `implemented` / `not_implemented`). Games are only moved to
`playable` once their rules suite and the automated playable gate pass: engine,
deterministic actions, bot when solo AI is advertised, a mounted view and the
English pack. Visual layout is checked by the windowed audit in §1.4, but the
label does not imply a human playthrough, aesthetic review or native-speaker
style review. Online status stays at `implemented` (not `verified`) until
the real-Steam checklist (§1.1) is completed. The promise is executable:
`tests/unit/test_playable_games.gd` fails whenever a game marked `playable`
lacks a working engine, bot, view or English string pack.

### 3.5 Star Realms expansions — *documented per set*

The set picker marks each expansion with real content (`content_ready`) or
registry-only. Only sets whose cards are implemented in the engine can be
enabled for a match; registry-only sets are visible with an honest status.
Details: `docs/STAR_REALMS_EXPANSIONS.md`.

## 4. Recently fixed (kept for context)

* **Language changes required a restart on previously visited screens.** The
  shell kept every screen cached forever and refreshed only the current one on
  `Loc.locale_changed`. It now evicts and frees every non-current cached screen,
  refreshes the current screen and lets the next route rebuild in the new
  language; About and GameScreen also refresh their static labels. The real
  language-row button was exercised (`uk -> en`) and the settings screen, shell
  chrome and a revisited library/details route were all English with no stale
  cached instance.
* **King's cards were below the viewport.** Empty-state and player labels
  autowrapped to 1 px width, making tall text columns; the 17-card hand started
  at y=1081 in an 812 px viewport. Dynamic labels now use non-wrapping flow
  layouts, trick/pick cards use a compact width and the hand is a horizontal
  scroll strip. A clean windowed run shows all 17 cards at y=615, inside the
  screen.
* **Coup's player panel was unreadable and the cards had no explanation.**
  Player names are no longer squeezed, role cards show their ability text using
  the existing translated action names, and a role guide explains all five
  roles. The cards, victim chooser and action bar are visible at 1600x900.
* **Oversized game tables were clipped.** GameScreen now wraps the mounted view
  in an auto-scrolling board host. Durak fits without scrolling; Star Realms,
  Bridge and Monopoly expose scrollbars so hands and far board edges are
  reachable. The windowed audit's outside-screen findings went to zero.
* **The screen smoke asserted the old no-session game route.** The game route
  intentionally redirects to the library without a session; the smoke now
  starts a real hotseat chess match before visiting it, so the game screen is
  exercised rather than the redirect.
* **The library screen rendered no games at all** (user report). The chain:
  `scenes/main.tscn` rooted at a plain `Node` so the shell never filled the
  viewport (`shell.size == 0×0`); `set_anchors_preset()` preserved the current
  zero size via offsets in `AppShell`, `ScreenBase`, the modal dim and the
  dialog centre; and the library filter captions autowrapped to ~200 px tall,
  collapsing the scroll area to height 0. Fixed by a full-rect `Control` root,
  `set_anchors_and_offsets_preset()` at every full-rect site, a `ScreenBase`
  hook that pins the first built page to the screen, non-wrapping filter
  captions and an `HBoxContainer` (not `HFlowContainer`) for the horizontal
  home rows. `tools/screen_smoke_core.gd` now asserts the page fills the
  screen, all 13 cards exist and a card intersects the visible rectangle.
* **Missing translations in Settings.** `settings.section_*` (the sidebar
  buttons) and `audio.master`/`audio.sfx`/`audio.music` (the volume rows) were
  referenced but absent from every catalogue, so `Loc.t` fell back to
  humanised English-like text in all ten locales. Added to all ten shell
  catalogues; the i18n scanner now also finds keys collected in constant
  arrays and keys containing a slash (`Loc.t("audio/master")`-style mistakes
  now fail the localisation suite instead of passing silently).
* `String(int)` is not a valid constructor in Godot 4.7 (`str()` is the
  universal converter). Real crashes were found and fixed in the Star Realms
  view (a card's integer uid — it aborted `_card()` and cascaded into
  `add_child(null)`), the dropdown factory (metadata for any numeric option
  value) and the modal layer (choice values). A scripted scan of every
  `String(x.get(...))` site found exactly these four risky conversions.
* The snapshot round-trip harness only restored public state, which cannot
  reproduce hand-driven legal actions in hidden-information games. It now feeds
  both private shapes (top-level acting-player merge + a `private_states` bag);
  two game workstreams had independently patched the same helper, and the
  merged version is documented in `GAME_ENGINE_CONTRACT.md`.
* The external Godot MCP bridge injects an autoload and a receiver script into
  the project; `.mcp_input_receiver.gd` and `screenshots/` are now git-ignored
  and the injected autoload line was removed.
* Five scripts that could not be parsed at all (the app could not boot) —
  fixed in `3fbfb45`, guarded by the compile suite.
* `GameCard` dereferenced null children when configured before entering the
  tree; `CardFace` broke its own hierarchy with `remove_child` on a non-child —
  fixed in `3fbfb45`, guarded by the UI smoke suite.
* `data/catalog/star_realms_sets.json` was referenced by `Catalog` but missing
  (a logged, non-fatal error at boot) — resolved by the Star Realms workstream.
* `tools/fetch_godotsteam.sh`, referenced by `.gitignore` and the Steam doc but
  missing, now exists: pinned download + SHA-256 verification.
