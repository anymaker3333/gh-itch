# AI progress log

A running, honest log of what was built, what was verified and what is still
open. Claims are paired with the evidence that supports them; anything not yet
verified is marked as such. Last updated: 2026-10-20.

## How to read this log

* **Evidence** = the exact command/result that supports the claim.
* **Pending** = designed but not yet done or not yet verified.
* Session IDs of interrupted subagent runs (if any) are recorded so their work
  can be resumed; recovered commits are recorded under the wave that merged
  them.

## Wave 0 — foundation (commit `5479fd1`)

* Godot 4.7.2 project, 13-game catalog (`data/catalog/games.json`), app shell
  with routes and screens (library, details, setup, game, lobby, online,
  settings, diagnostics, about), ten autoload services, the UI kit
  (`UI.*`, palette, theme), the game-engine contract and the test framework.
* Chess is the reference implementation (engine, bot, view, string pack, rules
  suite).
* Evidence: `docs/GAME_ENGINE_CONTRACT.md`, `tests/games/test_chess.gd`,
  commit `5479fd1`.

## Wave 1 — online multiplayer + nine shell locales (commit `3976354`)

* Session/net rewrite: `NetService` owns and polls the transport, hello/welcome
  handshake, seat assignment (`Net.seat_assigned`), host-authoritative
  replication (`GameSession`), disconnect detection, match-end grace period.
* Steam lobby metadata (`gamehub_id`, `protocol_version`, `game_version`,
  `game_id`, `game_mode`, `status`, `expansions`), friends/invites, relay
  status, graceful degradation without Steam.
* Two-process network smoke over the **real** local ENet transport:
  host + client, 17 checks per side, 0 failures
  (`tools/run_net_smoke.sh`; logs in `$TMPDIR/gh-net-smoke`).
* Nine non-English shell catalogues added (`uk`, `ru`, `de`, `zh_CN`, `az`,
  `be`, `cs`, `pl`, `fr`).
* Evidence: commit `3976354`; smoke logs; `docs/STEAM_INTEGRATION.md`.

## Wave 2 — boot integrity (commit `3fbfb45`)

* Fixed five scripts that could not be parsed at all (the application could not
  start): chess view type inference, card-face glyph check, lambda-in-array /
  stray-brace syntax in the library, online and settings screens.
* Fixed two runtime defects found by actually launching the app: `GameCard`
  configured before `_ready()` (null children) and `CardFace` breaking its own
  hierarchy.
* New guards: `tests/unit/test_scripts_compile.gd` (every `.gd` under
  `scripts/`, `tests/`, `tools/` must load **and** instantiate),
  `tests/unit/test_ui_smoke.gd` (widget lifecycle + `CardFace` hierarchy) and
  `tools/run_boot_smoke.sh` (real app, headless, fails on any `SCRIPT ERROR`).
* Nine translated chess packs (`data/i18n/<locale>/game_chess.json`, 33 keys
  each) — the localisation suite's nine locale failures went to zero.
* Docs: `LOCALIZATION.md`, `DISPLAY_SETTINGS.md`, `STEAM_INTEGRATION.md`.
* Evidence: full suite **848 checks, 36 failures** (all 36 = the twelve games
  not yet merged missing `game.<id>.name`/`.desc`); boot smoke 300 frames,
  0 script errors; compile suite green; commit `3fbfb45`.

## Wave 3 — twelve games in parallel worktrees

Six background workstreams, each on its own branch in its own worktree
(`~/.local/share/opencode/worktree/5479fd/`), each committing per finished game
so nothing is lost if a run is interrupted:

| Branch | Games | Session |
|--------|-------|---------|
| `wt-games1-citadels-coup` | citadels, coup | ses_ead178cbbffe9oyb7ijSgjGJap |
| `wt-games2-codenames-dany-spyfall` | codenames, dany, spyfall | ses_ead178cbaffe5uvIbH1NdgOYnd |
| `wt-games3-durak-king-bridge` | durak, king, bridge | ses_ead178cbaffdYy6QWfP6zwTSEz |
| `wt-games4-monopoly-ttr` | monopoly, ticket_to_ride_europe | ses_ead178cb9ffe449dzUs4agrqyO |
| `wt-games5-splendor` | splendor | ses_ead178cb8ffesfwpiOORhuNTvR |
| `wt-games6-star-realms` | star_realms + edition registry + set-picker screen | ses_ead178cb7ffeKPkCHXG9CmWV0b |

Deliverable per game: engine, bot, view, English string pack, rules suite —
following `docs/GAME_ENGINE_CONTRACT.md`; script paths were already registered
in `Session`, `BotDirector` and `game_screen.gd`.

Status: five of the six streams finished and were merged (wave 4). Stream 3
committed durak and king; its bridge work never landed, so the stream was merged
partially and Bridge was implemented directly on main in wave 6.

## Wave 4 — merging the game streams and arming the gate

Merge commits on the main branch (each branch had been verified in its own
worktree first):

| Merge | Branch | Evidence on the branch |
|-------|--------|------------------------|
| `1de17bb` | `wt-games2-codenames-dany-spyfall` | codenames 502, dany 781, spyfall 483 checks, 0 failures |
| `6023ab1` | `wt-games5-splendor` | 2778 checks, 0 failures |
| `a1c3885` | `wt-games6-star-realms` | 255 checks, 0 failures; registry with 12 sets |
| `c4f7f1b` | `wt-games1-citadels-coup` | citadels 331, coup 276 checks, 0 failures |
| `d9cfa7c` | `wt-games4-monopoly-ttr` | monopoly 560, TTR 1005 checks, 0 failures |

Design notes from the merges:

* **Snapshot round trip unified.** Stream 1 and stream 6 each found that a
  hidden-information match cannot be resumed from public state alone, and each
  solved it differently. `tests/support/engine_harness.gd` now feeds the copy
  **both** shapes the contract describes: the acting player's private state
  merged at the top level (exactly what an online client receives) *and* a
  `private_states` bag with every seat plus `-1` table secrets (what a save file
  needs). Engines consume whichever their snapshot format uses; the contract
  (`GAME_ENGINE_CONTRACT.md`) documents both.
* **A latent crash class fixed.** `String(int)` is not a valid constructor in
  Godot 4.7 (only `str()` is universal). Real crashes were fixed in
  `star_realms_view.gd` (a card's integer uid), `ui_factory.gd` (dropdown
  metadata — any numeric option value would have crashed) and `modal_layer.gd`
  (choice values). A scripted scan of every `String(x.get(...))` site found
  exactly these four risky conversions.
* **MCP bridge artefacts ignored.** The external Godot MCP injects an autoload
  and a receiver script into the project; `.mcp_input_receiver.gd` and
  `screenshots/` are now git-ignored and the injected autoload line was removed
  from `project.godot`.
* New development helper `tools/capture_scene.gd` (+ `capture_core.gd`): saves a
  real window screenshot after `frame_post_draw` for manual visual checks. It
  cannot be verified in this sandbox (windows started from automation come up
  minimised, so zero frames are drawn — see `KNOWN_ISSUES.md` §1.4) and is
  therefore shipped as a documented, explicitly non-automated tool.

Evidence after the merges (`--import`, then the full suite, 2026-10-19; interim
snapshot, superseded by the wave 7 acceptance run below):

* Full suite: **14 suites, 9592 checks, 18 failures** — 9 locale-coverage
  failures plus the 3 still-unmerged games' (durak/king/bridge) missing
  name/description strings. Nothing else fails.
* **Playable gate**: 10 games marked `playable`, **1545 checks, 0 failures**
  (`tests/unit/test_playable_games.gd`, ~42 s — dominated by real bot playouts
  and mounted-view matches).
* Screen smoke: **18 routes visited, 0 skipped, 0 failed** — the Star Realms
  set picker is live, and the earlier "17 OK / 1 skipped" is resolved.
* Boot smoke: 300 frames, 0 script errors. Net smoke: PASS.
* Catalogue status flipped to `playable` (and gate-verified) for: chess,
  codenames, dany, spyfall, splendor, star_realms, citadels, coup, monopoly,
  ticket_to_ride_europe. Per-game simplifications are recorded in
  `GAME_CATALOG.md`; Star Realms content status in
  `STAR_REALMS_EXPANSIONS.md`.
* Tooling: `--filter` now accepts several comma- or pipe-separated terms
  (`--filter test_coup,test_dany`).
* **Network smoke extended to any game.** `tools/run_net_smoke.sh` now takes
  `[port] [game_id] [players] [expect_private]`; the core gained `--game`,
  `--players` and `--expect-private` (which asserts the replicated snapshot
  carries a non-empty private slice for hidden-information games). Nine games
  were exercised with two real processes over the local ENet transport —
  chess, codenames, dany, splendor, star realms, citadels, coup, monopoly and
  ticket to ride (the eight hidden-information games with the extra private
  assertion) — and their catalog `online_status` was flipped to `implemented`
  on that evidence. Spyfall needs at least three seats, which the two-process
  smoke does not open: it stays `not_implemented` on purpose
  (`KNOWN_ISSUES.md` §1.3).

## Wave 5 — translation wave (completed)

The nine non-English locales (`az`, `be`, `cs`, `de`, `fr`, `pl`, `ru`, `uk`,
`zh_CN`) now translate the English packs of the ten games that were playable at
the time: monopoly, ticket to ride, star realms, citadels, spyfall, coup,
splendor, DANY and codenames (plus the earlier chess packs). The completed wave
is committed as `6660cbb` with `tools/audit_translations.py`, which checks JSON
validity, key set, key order, non-empty values and placeholder multisets against
the English source. The agent-based attempt was abandoned after repeated rate
limits; the packs were translated manually with one game/locale at a time.

## Wave 6 — Durak, King and the Bridge implementation

Stream 3 was merged at `921c7d9` (Durak and King engines, bots, views, English
packs and suites). Two engine fixes were needed for the snapshot contract: both
games now restore hands/deck/set-aside from the per-seat `private_states` bag and
expose table secrets through `private_state(-1)`. Bridge had no branch content,
so it was implemented on main.

* Durak: 36-card deck, trump card, attack/defend/take/pass, rank-matched joining,
  draw-back, fool detection and a documented stalemate draw. Suite: 685 checks.
  Two-process network smoke PASS with the non-empty-private-slice assertion.
* King: 52-card trick avoidance with the private three-card pass, hearts/queen/
  king penalties and shoot-the-moon. Suite: 749 checks. Two-process network
  smoke PASS (two seats; the catalog minimum is three, recorded as a caveat).
* Bridge: a new simplified contract-bridge implementation — four fixed seats,
  natural auction, declarer/dummy, follow-suit and trumps, duplicate-style
  scoring, one deal per match, and a `load_position` seam for exact tests. Suite:
  1,103 checks. Its owner, bot and view are registered; the catalog offers
  hotseat and solo AI. Online stays `not_implemented` because the smoke opens two
  seats and Bridge needs four.
* Durak and King were flipped to `online_status: implemented`; all three are
  `status: playable` and pass the 13-game gate (1,820 checks, 0 failures).
  Bridge deliberately omits the online mode from its catalog row.

## Wave 7 — final translation and acceptance

The last 27 packs (durak, king, bridge × nine locales) were translated from the
frozen English sources. Every locale now ships all thirteen game packs: 453
shell keys + 1,087 pack keys = 1,540 merged keys, identical key sets and order
for all ten locales. `python3 tools/audit_translations.py` reports
`PASS all audited packs for 13 game(s)`; its only output beyond that is review
warnings for values legitimately identical to English (game names and suit
symbols).

Final acceptance run (2026-10-19), `tools/run_acceptance.sh`:

```text
1/4 test suite   PASS  17 suites, 12,773 checks, 0 failures
2/4 boot smoke   PASS  300 frames, no script errors
3/4 screen smoke PASS  every available screen came up without script errors
4/4 net smoke    PASS  two-process Durak match, private slice replicated
ACCEPTANCE PASS
```

The suite total moves by a few checks between runs because several rules suites
assert on every bot step of randomly dealt matches; the acceptance run above is
the recorded final number. Separately, the playable gate reported 13 games /
1,820 checks / 0 failures, and the Durak and King network smokes each reported
host 17 / client 18 checks / 0 failures with `expect_private`.

## Wave 8 — library regression fix, missing translations, deterministic automation

The user reported an empty game-selection menu and a couple of missing
translations. Root cause of the empty menu was a chain of full-rect anchor
bugs plus one layout bug:

* `scenes/main.tscn` was rooted at a plain `Node`, so `AppShell` never filled
  the viewport (`shell.size == 0×0`).
* `set_anchors_preset(PRESET_FULL_RECT)` keeps the current zero size by writing
  negative offsets; every full-rect site now uses
  `set_anchors_and_offsets_preset()` (`AppShell`, its background and root row,
  `ScreenBase`, the modal dim and dialog centre, the toast layer).
* `ScreenBase` pinned the first built page to the screen (`_fit_build_root`);
  a plain `Control` is not a container, so the page previously kept its
  minimum size.
* Library filter captions autowrapped to ~200 px tall, collapsing the scroll
  area to height 0; they now disable autowrap and shrink vertically, and the
  horizontal recent/favourites rows use `HBoxContainer` instead of
  `HFlowContainer` (cards used to stack vertically and push the grid below the
  fold).

The missing translations were real catalogue gaps: `settings.section_general`,
`settings.section_display`, `settings.section_language`, `settings.section_audio`
and `settings.section_accessibility` (the settings sidebar) and
`audio.master`/`audio.sfx`/`audio.music` (the volume rows) were referenced by
code but existed in no locale, so `Loc.t` fell back to humanised English-like
text in all ten languages. All eight keys are now in all ten shell catalogues.
The i18n scanner additionally finds keys collected in constant arrays and keys
containing a slash, so this class of gap fails the localisation suite instead
of passing silently.

Automated headless runs now set `GAMEHUB_DISABLE_STEAM=1` (suite, screen smoke,
net smoke, boot smoke) because Steamworks teardown can abort a short-lived
headless process after the tests already printed `PASS`; windowed runs are
unaffected and still reach `READY`.

Final acceptance run (2026-10-19), `tools/run_acceptance.sh`:

```text
1/4 test suite   PASS  17 suites, 12,822 checks, 0 failures
2/4 boot smoke   PASS  300 frames, no script errors
3/4 screen smoke PASS  every available screen came up; library page/cards guard passed
4/4 net smoke    PASS  two-process Durak match, private slice replicated
ACCEPTANCE PASS
```

The screen smoke now fails when the library page does not fill the screen,
when fewer than `Catalog.count()` cards exist or when no card intersects the
visible screen rectangle — the regression that produced the empty menu can no
longer pass silently.


## Wave 9 — live locale refresh, readable King/Coup cards, scrollable oversized boards

User-reported defects: language changes appeared to need a restart, King looked
like it had no cards, and Coup cards/UI were hard to understand.

* **Locale refresh.** `AppShell` cached every screen forever and
  `_on_locale_changed` only refreshed the visible one. It now evicts every
  cached screen except the current instance and frees it, refreshes the current
  screen and shell chrome, and lets the next navigation build the route in the
  new locale. `AboutScreen` rebuilds its content on `refresh_texts`, and
  `GameScreen` refreshes its log heading and handover button. The actual
  language-row button was exercised: switching `uk -> en` on Settings produced
  `Settings`, English section buttons and a rebuilt English library/details;
  old cached instances were gone (`screens after=["settings_language"]`) and no
  stale visible Cyrillic remained outside native language names.
* **King.** The 17-card hand was laid out at y=1081..1543 below the 812 px
  viewport; empty-state and player labels also wrapped to 1 px width. The hand
  is now a horizontal scroll strip sized to the viewport, trick/pick cards use a
  76 px compact width, player rows use a flow layout and all dynamic labels
  disable autowrap. A clean windowed run found 17 card faces at y=615, all
  inside the screen; after 12 legal actions the trick/round layout still fits.
* **Coup.** Player names were squeezed to 1 px and coin chips stretched.
  Player rows now use non-wrapping names; hand cards show their role ability
  (reusing the translated action names), and a compact role guide lists all five
  roles. Two cards render at 96x176 with readable titles/bodies; the action bar
  and victim chooser remain visible.
* **Oversized boards.** The shared board host in `GameScreen` now wraps game
  views in an auto-scrolling `ScrollContainer`. Durak fits without scroll;
  Star Realms, Bridge and Monopoly expose vertical/horizontal scrolling instead
  of clipping their hands and far board edges. The windowed audit's
  `outside screen` findings for those pages went to zero.
* **Visual audit.** The 30-route windowed harness (forced `uk`, 1600x900)
  captures every shell route plus all 13 game tables. Latest run: 30
  screenshots, 0 clipped labels, 0 zero-size controls, 0 controls outside the
  screen, 0 missing keys, `AUDIT EXIT=0`. Labels inside ScrollContainers are
  intentionally skipped by the structural check; the affected pages were also
  reviewed from the screenshots.
* **Test support.** `tools/screen_smoke_core.gd` previously expected the `game`
  route to be visible without a session, contradicting the intentional redirect
  to the library. It now starts a real hotseat chess match before visiting that
  route.
* **Final acceptance (2026-10-20).** `tools/run_acceptance.sh`: suite PASS
  17 suites, 12,780 checks, 0 failures; boot PASS 300 frames; screen PASS every
  route; net smoke PASS. Locale key count is now **1,553 per locale** (465 shell
  + 1,088 pack keys) after adding `game.coup.roles_title`; the 30-route audit
  reports 0 missing keys.

## Wave 10 — switchable menu themes and the Casino palette

The shell now supports user-selected menu themes without changing game rules or
game-specific accents.

* **Theme format.** `docs/THEMES.md` defines the `gamehub-theme/1` JSON format.
  A theme may override any subset of the 22 `Palette` colour tokens, but must
  provide `bg_base`, `bg_panel`, `text` and `accent`. Invalid files are rejected
  before the active theme changes.
* **Registry.** `ThemeSvc` loads `data/themes/casino.json`, scans
  `user://themes/`, validates every file, persists the selection in
  `appearance/theme_id`, and emits `theme_changed`. `Palette` tokens became
  runtime values so `ThemeBuilder` can be invalidated and rebuilt without a
  restart.
* **Casino theme.** `data/themes/casino.json` is both the built-in Casino preset
  and a complete example: green felt surfaces, warm card-room text and a brass
  accent. The theme picker shows live palette swatches.
* **Settings UI.** Settings gained an **Appearance** section with the built-in
  and custom theme list, upload/import through the native file picker, delete
  for custom themes, and **Export example theme…** to produce a complete
  starter JSON file. The AppShell updates its background, sidebar, top bar and
  cached screens when a theme is selected.
* **Verification (2026-10-20).** Windowed 1600x900 captures reviewed for the
  default Appearance page, Casino, a custom "Midnight Plum" import, the delete
  action, and the switch through the real `OptionButton` callback. Theme
  selection persisted across a restart. Full suite: 18 suites, 12,811 checks,
  0 failures; i18n scan exit 0; translation audit PASS with 110 review warnings.
  New shell strings were added to all ten locales.

## Wave 11 — responsive game tables and final layout audit

The remaining Game Hub layout findings are resolved without changing rules,
engines, bots or networking.

* **Log and action bar.** The match log auto-hides below 1500 px and returns when
  the window grows, unless the player explicitly toggles it; that override
  resets when the window crosses the breakpoint again. The shared action row is
  one horizontal line inside a scroll container, with tighter spacing so Coup's
  full action set fits at 1280x720.
* **Star Realms.** Compact card faces are now 132x142 px. The trade row is
  rendered first, the hand immediately after it, and rivals/fleet below, so the
  five-card hand stays above the fold at 1280x720. The deck chip no longer
  stretches to the card-row height.
* **Splendor.** Cards use 160x84 px panels with colour/count cost pills and the
  full localised cost in the tooltip. Nobles are compact cost summaries, player
  cards have a fixed readable width, and the reserved heading shares its row
  with the hint. All three tiers and the token bank fit at 1280x720; players and
  reserves follow in the board scroll.
* **Monopoly.** Cells are 70x42 px at normal heights and 70x33 px below 820 px,
  with the duplicate board footer hidden in compact mode. The full ring is
  visible at 1280x720, and the 360 px side panel keeps the player and details
  text readable at 1600x900.
* **Verification (2026-10-20).** Actual PNGs inspected at 1600x900 (fullscreen),
  1280x720 (windowed) and 1920x1080 (offscreen SubViewport). Captures include
  Splendor, Star Realms, Monopoly, Coup, the library and Appearance, plus log
  shown/hidden states at 1280 and 1600. Final suite: **18 suites, 12,809 checks,
  0 failures**; boot smoke 300 frames; screen smoke every route; i18n scan exit
  0; translation audit PASS with 110 review warnings.

## Pending

1. **Real Steam verification** (two Steam accounts) per
   `docs/STEAM_INTEGRATION.md` §10. Earlier windowed runs reached `READY` for App
   ID 480, but the Steam client was **not running** during the latest attempt
   (`SteamSvc: FAILED`, "Cannot create IPC pipe to Steam client process").
   Both a running client and a second account/peer are required. Recorded in
   `KNOWN_ISSUES.md` §1.1.
2. **Multi-client network smoke** for Spyfall (3+), Bridge (4) and King at its
   catalog minimum (3+). The current harness opens one client / two seats, so
   Spyfall and Bridge stay `not_implemented` and King's `implemented` status is
   qualified. Recorded in `KNOWN_ISSUES.md` §1.3.
3. **Manual aesthetic review** of the game tables and shell screens. The
   windowed structural audit now passes on all 30 routes, but it cannot judge
   contrast, typography or visual polish; use `tools/_ui_audit.gd` and review the
   screenshots by eye. Star Realms, Splendor and Monopoly now have compact
   responsive modes at short heights; Bridge still relies on board scrolling at
   1280x720, and aesthetic review of all tables remains pending.
4. **Native-speaker style review** of the newest packs; structural parity is
   automated (1,615 keys per locale), stylistic quality is not.
5. **Cross-platform theme import dialog.** The native file picker was exercised
   on Linux/X11. macOS and Windows use the same Godot `FileDialog` fallback and
   still need a manual pass on those platforms.

## 2026-10-21 follow-up

- Fixed Ticket to Ride: Europe grey-route claim generation so grey routes offer
  real-colour payment actions (resolves tunnel/ferry/payment failures).
- Added `less_equal`/`less`/`greater_equal` helpers to `TestHarness`.
- Added `tests/unit/test_setup_options.gd` and `tests/unit/test_view_errors.gd`.
- Extended `tools/run_net_smoke.sh` and `tools/net_smoke_core.gd` to drive
  3- and 4-player matches (Spyfall, King, Bridge) with multiple client processes.
- Verified: full suite 22 suites / 13670+ checks / 0 failures; boot, screen and
  net smokes PASS; acceptance PASS.
