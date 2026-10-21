# Test plan

How the Game Hub test suite is organised, how to run it, what it proves and what
it deliberately does not prove. Every statement below matches the cited files.

Files read for this document: `tests/run_tests.gd`,
`tests/support/test_runner_core.gd`, `tests/support/test_harness.gd`,
`tests/support/engine_harness.gd`, `tests/support/i18n_scanner.gd`,
`tests/unit/test_localization.gd`, `tests/unit/test_scripts_compile.gd`,
`tests/unit/test_ui_smoke.gd`, `tests/unit/test_themes.gd`, `tests/games/test_chess.gd`,
`tools/run_boot_smoke.sh`, `tools/run_net_smoke.sh`, `tools/net_smoke.gd`,
`tools/i18n_scan.gd`, `tools/run_screen_smoke.sh`, `tools/screen_smoke.gd`,
`tools/screen_smoke_core.gd`, `tools/run_acceptance.sh`,
`docs/GAME_ENGINE_CONTRACT.md`.

## 1. Running the suites

```bash
godot --headless --path . --import                      # refresh the class cache
godot --headless --path . --script tests/run_tests.gd   # everything
godot --headless --path . --script tests/run_tests.gd -- --filter chess
godot --headless --path . --script tests/run_tests.gd -- --list
```

* `--import` must run after scripts are added, renamed or deleted. Concurrent
  `--import` runs in the same checkout corrupt `.godot/`; one import at a time
  per directory.
* `--filter` is a **substring match on the suite file path**, not on the suite
  name: `--filter test_chess` or `--filter tests/games`. Several terms can be
  combined with commas or pipes and the suite runs when **any** term matches:
  `--filter test_coup,test_dany` (same as `--filter 'test_coup|test_dany'`).
* The process exit code equals the number of failed checks, capped at 100
  (`tests/run_tests.gd`). Zero failures → exit code 0.
* Suites are auto-discovered from `res://tests/unit` and `res://tests/games`
  (`SUITE_DIRS` in `test_runner_core.gd`); a suite is any non-underscore `.gd`
  file in those directories.
* The runner first asserts that all autoload services exist (`Log`, `Prefs`,
  `ThemeSvc`, `Loc`, `Catalog`, `Audio`, `Notify`, `SteamSvc`, `Net`, `Session`,
  `Nav`) and prints a header with the Godot version, locale count, catalog size
  and Steam state.
* A suite that fails to load or instantiate is reported as a failure; it can no
  longer be silently skipped.

## 2. Suite catalogue

| Suite | File | What it proves |
|-------|------|----------------|
| localisation | `tests/unit/test_localization.gd` | exactly 10 locales; every key referenced from GDScript exists in English; every locale is >99.9 % translated against the English key set; every catalog game has a name + substantial description and a translation for every phase its engine declares; no key ever renders as a raw key |
| compilation | `tests/unit/test_scripts_compile.gd` | every `.gd` under `scripts/`, `tests/` and `tools/` loads and can be instantiated (catches parse errors the other suites never touch, e.g. in screens) |
| ui smoke | `tests/unit/test_ui_smoke.gd` | widgets survive the exact call order the screens use (`configure()` before entering the tree), and `CardFace` builds the documented hierarchy |
| themes | `tests/unit/test_themes.gd` | built-in default/Casino packs load, theme switching updates `Palette`, invalid or incomplete custom files are rejected without changing the active theme, and a valid import/delete round trip restores the original theme |
| playable game gate | `tests/unit/test_playable_games.gd` | the catalog status is enforced: every game marked `playable` ships an engine that sets up, offers valid actions, restores snapshots, replays deterministically and plays to completion under the shipped bot policy at both ends of its player range; a bot when solo AI is claimed; a view that mounts a real local match and re-renders it to the end; and an English pack whose keys resolve. Dormant while nothing is marked `playable`; it armed itself on chess when that status was flipped |
| chess rules | `tests/games/test_chess.gd` | the rules of chess: deterministic opening, legality, castling, en passant, promotion, check/checkmate, draws, snapshot round trip, bot playout |
| &lt;game&gt; rules | `tests/games/test_<game>.gd` | one suite per playable game; required coverage is listed in §5 |

## 3. Harness API (`tests/support/test_harness.gd`)

`check(condition, message)`, `equal(actual, expected, message)`,
`not_equal`, `greater(actual, minimum, message)`, `has_key(dictionary, key,
message)`, `is_true(value, message)`, `no_raw_key(text, message)`, plus
`begin_suite` / `end_suite` / `summary_line`. Checks never throw; a suite runs
to the end and every failure is listed with its suite tag in the final report.

## 4. Engine scaffolding (`tests/support/engine_harness.gd`)

* `EngineHarness.create(game_id, player_count, seed, options)` — build an engine
  exactly like the session layer does.
* `step_first_legal(engine)` / `play_out(engine, max_steps)` — advance with the
  first legal action or with the registered bot until the match ends; returns
  the number of steps taken.
* `check_legal_action_shape(h, engine, label)` — every action must carry a
  unique, stable key and a usable shape.
* `check_snapshot_round_trip(h, engine, label)` — the copy is restored from the
  public snapshot **plus both private forms** the contract allows: the acting
  player's `private_state()` merged at the top level (the online-client shape)
  and a `private_states` bag with every seat and `-1` table secrets (the
  save-file shape). The restored engine must produce the same public state and
  the same legal actions.
* `check_privacy(h, engine, secrets_of, label)` — no other player's secrets may
  appear anywhere in `public_state()`.

## 5. Required coverage for a new game suite

Per `docs/GAME_ENGINE_CONTRACT.md` §Tests, every game suite must check:

1. the opening position / counts and that it is deterministic for a fixed seed;
2. at least one check per rule the game claims to implement;
3. rejection of an action that is not legal for the acting player;
4. the end of the match (win condition or draw) and its `reason_key`;
5. a snapshot round trip;
6. a bot-only playout that finishes (or reaches a stable, non-finished state);
7. hidden information, when the game has any.

## 6. End-to-end smoke checks

All automated headless phases export `GAMEHUB_DISABLE_STEAM=1` (the suite and
screen/net scripts set it themselves; `tools/run_boot_smoke.sh` exports it
before launching Godot). Steamworks teardown can abort a short-lived headless
engine process on this machine, so automation runs with the integration
disabled and reports `steam=DISABLED`; a normal windowed run leaves the
variable unset and initialises Steam as usual.

| Tool | Command | What it proves |
|------|---------|----------------|
| boot smoke | `tools/run_boot_smoke.sh [frames]` | starts the real application headless for N frames (default 300) and fails on any `SCRIPT ERROR` while the shell builds its first screen; Steam messages do not fail it |
| screen smoke | `tools/run_screen_smoke.sh` | boots the real shell and drives the real router through every screen route (library, details, setup, settings, diagnostics, online, lobby, game, …), failing when a route produces no visible screen or the log contains a `SCRIPT ERROR`. The `game` route starts a real hotseat chess match first, because without a session the app intentionally redirects to the library. The library routes additionally assert that the page fills the screen, that at least `Catalog.count()` game cards exist and that a card intersects the visible screen rectangle. Catches bugs that only appear when a lazily-built screen is opened; found the `HSlider.disabled` crash in the setup screen on first run, and the empty-library regression (see `AI_PROGRESS.md`, wave 8) |
| visual audit (windowed) | `godot --path . --resolution 1600x900 --position 180,80 --script tools/_ui_audit.gd` | boots the real shell, forces `uk` without persisting it, walks 30 routes (all shell screens plus all 13 game tables), captures PNGs and a structural report in `/tmp/opencode/ui_audit`, and fails on clipped labels, zero-size interactive controls or controls outside the screen. Labels inside `ScrollContainer` are skipped because they are reachable by scrolling. Latest run: 30 screenshots, 0 issues, 0 missing keys. It does not judge aesthetics or contrast |
| net smoke | `tools/run_net_smoke.sh [port] [game_id] [players] [expect_private]` | two processes over the **local ENet test transport** (explicitly *not* Steam): handshake, seat assignment, match start, action forwarding, host replication, resign, match end; host 17 / client 18 checks with `expect_private` (both 17 without; the extra client check asserts the replicated snapshot carries a non-empty private slice for hidden-information games); logs in `$TMPDIR/gh-net-smoke/<game>` |
| i18n scan | `godot --headless --path . --script tools/i18n_scan.gd` | read-only listing of every localisation key referenced from GDScript, with file:line, plus the patterns completed at runtime |
| acceptance run | `tools/run_acceptance.sh` | all of the above in one report: the full suite (plus a `SCRIPT ERROR` scan of its log), the boot smoke, the screen smoke and the net smoke, with a pass/fail table and a non-zero exit code if any phase fails |

## 7. What the suite does not prove

* **Steam transport.** The Steam path (`SteamSvc` + `ClassDB.instantiate("SteamMultiplayerPeer")`)
  requires a running Steam client and two accounts; the sandbox has neither. It
  is exercised only by the ENet local test transport and must be verified
  manually (see `docs/STEAM_INTEGRATION.md`).
* **Rendering.** The automated suites run headless. Visual layout is checked
  separately by the windowed audit (30 routes, structural geometry) and by
  screenshots; it is not a pixel-comparison or aesthetic review.
* **Balance or fun.** Bots must be legal and terminating, not good.

## 8. Current status

Main branch, after the menu-theme and responsive-table work (2026-10-20):
**18 suites, 12,809 checks, 0 failures** in the final
`tests/run_tests.gd` run. The count moves by a few between runs because
several suites assert on every bot step of randomly dealt matches. The
playable-game gate covers all **13 games marked `playable`: 1,820 checks, 0
failures**. Every locale ships all thirteen game packs and all shell keys:
**1,615 merged keys per locale** (503 shell + 1,112 pack keys), and
`python3 tools/audit_translations.py` reports
`PASS all audited packs for 13 game(s)` (values identical to English are review
warnings for proper nouns and card symbols only). Boot (300 frames), screen
(every available route, plus the library content guard and a real hotseat game
screen) and network (Durak, two processes, hidden-information private-slice
assertion) phases of the acceptance run all pass.

The windowed visual audit covers 30 routes (the shell screens plus all 13 game
tables) and reports 0 clipped labels, 0 zero-size controls, 0 controls outside
the screen and 0 missing keys. King and Coup were additionally checked with
clean windowed captures at 1600x900: King's 17-card hand is visible inside the
viewport; Coup's cards show role abilities and its player rows are readable.

The final responsive pass was inspected as PNGs at **1600x900, 1280x720 and
1920x1080**. At 1280x720 the log auto-hides unless explicitly reopened, Coup's
action row fits without horizontal clipping, Splendor's three tiers and token
bank stay above the fold, Star Realms shows the trade row plus its five-card
hand, and Monopoly's full ring is visible. The 1920x1080 frames were rendered
through a 1920x1080 SubViewport because the virtual audit display itself is
1600x900. Log shown/hidden overrides were captured at 1280 and 1600 as well.

Eleven of the thirteen games have been exercised over the two-process network
smoke — chess, codenames, dany, splendor, star realms, citadels, coup, monopoly,
ticket to ride, durak and king (± the `expect_private` assertion for the nine
with hidden information). `spyfall` needs at least three seats and `bridge`
needs four, while the smoke opens two, so they stay `online_status:
not_implemented` on purpose; Bridge also omits the online mode in the catalog.
King was exercised with two seats although its catalog minimum is three, which
is recorded as a caveat in `KNOWN_ISSUES.md` §1.3. See `AI_PROGRESS.md` for the
running log and `GAME_CATALOG.md` for the per-game state.
