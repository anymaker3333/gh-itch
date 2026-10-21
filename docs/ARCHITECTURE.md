# Architecture

How Game Hub is put together: the process layout, the service layer, the game
core, the network stack and the data files. Every statement below matches the
cited source.

Files read for this document: `project.godot`, `scripts/ui/main.gd`,
`scripts/ui/app_shell.gd`, `scripts/ui/screen_base.gd`, `scripts/ui/ui_factory.gd`,
`scripts/ui/palette.gd`, `scripts/ui/theme_builder.gd`,
`scripts/autoload/theme_service.gd`,
`scripts/ui/components/game_card.gd`, every file in `scripts/autoload/`,
`scripts/core/game_engine.gd`, `scripts/core/game_session.gd`,
`scripts/core/bot_director.gd`, `scripts/core/net_protocol.gd`,
`scripts/core/steam_gateway.gd`, `scripts/core/display_manager.gd`,
`scripts/core/game_entry.gd`, `scripts/core/expansion_set.gd`,
`docs/GAME_ENGINE_CONTRACT.md`.

## 1. Layered view

```
┌──────────────────────────────────────────────────────────────────────┐
│ screens/          library · details · setup · game · lobby · online  │
│                   settings · diagnostics · about · star realms sets  │
├──────────────────────────────────────────────────────────────────────┤
│ ui/               app_shell (routes) · screen_base · ui_factory (UI) │
│                   palette · theme_builder · GameCard · modal/toasts  │
├──────────────────────────────────────────────────────────────────────┤
│ core/             GameEngine · GameSession · BotDirector             │
│                   GameEntry · ExpansionSet · NetProtocol             │
├──────────────────────────────────────────────────────────────────────┤
│ autoload/         Log Prefs ThemeSvc Loc Catalog Audio Notify        │
│                   SteamSvc Net Session Nav                           │
├──────────────────────────────────────────────────────────────────────┤
│ data/             data/catalog/games.json · data/i18n/**             │
│ assets/art/       one banner per game                                │
└──────────────────────────────────────────────────────────────────────┘
```

There is no scene per screen: `main.tscn` contains one shell node and the shell
swaps screen scripts onto it. Game rules have no nodes at all (`RefCounted`),
which is what makes them testable headless and replicable over the network.

## 2. Runtime graph

`main.tscn` → `scripts/ui/main.gd` → `scripts/ui/app_shell.gd`.

* `AppShell` owns the top bar, the sidebar, the content host, the modal layer
  (`ui/modal_layer.gd`) and the toast layer (`ui/toast_layer.gd`).
* `Nav.go(route, params, mode, transition)` resolves the route through the shell's
  route table (`app_shell.gd`), pushes the previous screen onto a stack and calls
  the new screen's `build()`; `Nav.back()` pops.
* Screens extend `screen_base.gd`, build themselves with `UI.*` helpers
  (`ui_factory.gd`) and listen to services; they never own game state.
* Built screens are cached per route on the way out. On `Loc.locale_changed`,
  `AppShell` evicts and frees every cached screen except the current one,
  refreshes the current screen and chrome, and rebuilds old routes in the new
  language on their next visit. This is why changing language no longer needs a
  restart.
* `GameScreen` mounts each game view inside an auto-scrolling board host, so
  oversized tables (Star Realms, Bridge, Monopoly) keep their hands and far
  board edges reachable instead of being clipped by the 1328x812 content area.

## 3. Services (autoload singletons)

| Service | File | Responsibility |
|---------|------|----------------|
| `Log` | `autoload/log.gd` | levelled logging with structured context; the diagnostics screen reads it |
| `Prefs` | `autoload/prefs.gd` | typed preference store on disk (`get_value`/`set_value`, favourites, recents, UI scale, locale, display, Star Realms set selection); sanitising + migration |
| `ThemeSvc` | `autoload/theme_service.gd` | built-in and user menu themes, JSON validation/import, palette activation; see `docs/THEMES.md` |
| `Loc` | `autoload/loc.gd` | ten locales, native names, catalogue loading, `Loc.t` / `Loc.tp`, fallback to English, coverage report |
| `Catalog` | `autoload/catalog.gd` | loads `data/catalog/games.json` into `GameEntry` objects, sorting/filters, favourites interplay, edition registries (`load_edition_registry`, `edition_sets`, `validate_selection`) |
| `Audio` | `autoload/audio_service.gd` | UI and game sound effects through bus volumes from `Prefs` |
| `Notify` | `autoload/notify.gd` | info/success/warning/error toasts, prompts, confirms, choosers |
| `SteamSvc` | `autoload/steam_service.gd` | Steamworks init (App ID 480 in development), lobbies with verifiable metadata, friends/invites, relay status |
| `Net` | `autoload/net_service.gd` | owns the active transport (Steam peer or local ENet test peer), polls it, runs the hello/welcome handshake and seat assignment |
| `Session` | `autoload/game_session_service.gd` | the current match: engine registry, player count/config, mode, start/stop |
| `Nav` | `autoload/nav.gd` | routes, navigation stack, back handling |

Game script paths are registered in three places and must all agree:
`Session` (`ENGINE_SCRIPTS`), `BotDirector` (`BOT_SCRIPTS`) and
`game_screen.gd` (`VIEW_SCRIPTS`).

## 4. Game core

* **`GameEngine`** (`core/game_engine.gd`) — base class for every rules engine.
  Pure logic: no nodes, no file or network access; randomness only through the
  seeded `rng`. It provides players, turn/round bookkeeping, the move log,
  legal-action helpers (`make_action`, `find_legal_action`, `apply_action_by_key`),
  the public/private state split (`public_state`, `private_state`,
  `restore_state` + `_restore_extra`) and `finish(winner, reason_key, scores)`.
  The full override contract is `docs/GAME_ENGINE_CONTRACT.md`.
* **`GameSession`** (`core/game_session.gd`) — one match in one of four modes:
  `LOCAL_HOTSEAT`, `SOLO_AI`, `ONLINE_HOST`, `ONLINE_CLIENT`. In local modes it
  applies actions directly; in online modes the host is authoritative: the
  client sends `action`, the host validates and broadcasts `state` and
  per-player `private_state` snapshots; rejections come back as
  `action_rejected(reason_key, detail)`. It schedules AI turns through
  `BotDirector` with a short think delay, tracks disconnected players and emits
  `session_finished` when the engine finishes.
* **`BotDirector`** (`core/bot_director.gd`) — loads the game's bot script and
  asks it for an action key; a missing or failing bot falls back to the first
  legal action so a match can always continue.
* **`GameEntry` / `ExpansionSet`** (`core/game_entry.gd`, `core/expansion_set.gd`)
  — catalog and edition models (players, modes, category, art, accent, status,
  minutes, complexity, edition registry).

Determinism rules that the whole stack relies on: same seed + same action
sequence ⇒ identical `public_state()`; hidden information never leaves
`private_state(owner)`; a snapshot taken from `public_state() + private_state(p)`
must restore into a fresh engine with identical legal actions.

## 5. Network stack

* **`NetProtocol`** (`core/net_protocol.gd`) — the wire format. JSON envelopes
  with `protocol_version = 1`; packet types: `hello`, `welcome`, `reject`,
  `players`, `lobby_state`, `start_match`, `action`, `action_result`, `state`,
  `private_state`, `chat`, `ping`, `pong`, `resign`, `match_end`, `bye`.
  `validate()` / `decode()` reject oversized or malformed packets, unknown types
  and version mismatches with a typed reject reason.
* **`SteamGateway`** (`core/steam_gateway.gd`) — the only place that touches the
  GodotSteam GDExtension; it reports whether the extension is available and
  exposes the methods/signals the service needs.
* **`SteamSvc`** — initialises Steamworks (App ID 480 — Spacewar — for
  development only), creates lobbies whose metadata is machine-checkable:
  `gamehub_id`, `protocol_version`, `game_version`, `game_id`, `game_mode`,
  `status`, `expansions`; joins/invites through Steam friends, and reports
  relay availability.
* **`Net`** — owns and polls the active peer itself (nothing else may call
  `poll()`), turns transport signals into service signals and runs the
  handshake: the client sends `hello`, the host answers `welcome` and allocates
  a seat, firing `seat_assigned(player_index, peer_id)`; `peer_connected` /
  `peer_disconnected` drive the player registry and loss detection. After a
  match the host keeps its socket open for a short grace period (~1.5 s) so
  in-flight packets are delivered before the transport closes. The Steam
  transport is `ClassDB.instantiate("SteamMultiplayerPeer")`; the local test
  transport is ENet and is always labelled as *not Steam*.

The host-authoritative loop, end to end: client action → `action` packet →
host validates against its own engine → `state` + `private_state` broadcast →
clients restore → views refresh.

## 6. Localisation

`Loc` loads a shell catalogue per locale (`data/i18n/<locale>.json`) plus
namespace packs (`data/i18n/<locale>/<namespace>.json`, e.g. one per game),
sorted so packs override the shell. Lookup falls back to English and finally to
the key itself; the server-side `I18nScanner` (used by tests and
`tools/i18n_scan.gd`) extracts every key literal from GDScript, and the
localisation suite fails when a literal has no English string or a locale is not
fully translated. `Loc.set_locale` emits `locale_changed`; the shell evicts
cached screens so every previously visited route is rebuilt in the new
language. Details: `docs/LOCALIZATION.md`.

## 7. Preferences and display

`Prefs` stores the game's own settings (`user://prefs.json`) with defaults,
sanitising and migration. `DisplayManager` (`core/display_manager.gd`) applies
window mode/size/scale/vsync to the real window and offers
`display_summary()` plus a revert-safe flow used by the display settings
screen. Details: `docs/DISPLAY_SETTINGS.md`.

## 8. Data files

| Path | Contents |
|------|----------|
| `data/catalog/games.json` | the 13-game catalog: ids, name/desc keys, players, modes, category, tags, accent, art path, status, order, edition registry id |
| `data/catalog/star_realms_sets.json` | Star Realms edition registry read by `Catalog.edition_sets` |
| `data/i18n/<locale>.json` | shell strings per locale (10 files) |
| `data/i18n/<locale>/game_<id>.json` | per-game string packs |
| `assets/art/<id>.svg` | one banner per game, referenced from the catalog |

## 9. Testing

`tests/run_tests.gd` discovers suites in `tests/unit` and `tests/games`, verifies
that all ten services exist, and exits with the number of failed checks.
`tests/support/engine_harness.gd` gives game suites their scaffolding (create,
legal-action shape, snapshot round trip, playout, privacy). Boot and two-process
network smoke checks live in `tools/`. Full details: `docs/TEST_PLAN.md`.

## 10. Adding a game

Per `docs/GAME_ENGINE_CONTRACT.md`: create
`scripts/games/<dir>/<game>_engine.gd`, `<game>_bot.gd`, `<game>_view.gd`,
`data/i18n/en/game_<id>.json` and `tests/games/test_<id>.gd`; register the three
script paths in `Session`, `BotDirector` and `game_screen.gd`; add the catalog
entry (or reuse the pre-registered one) and the art banner. No other file needs
to change: the library, setup screen, lobby, game screen and bot dispatcher all
work off those registrations.
