# Game implementation contract

Every playable game in Game Hub is three small scripts plus a string pack. The
specification below is normative: the shared session layer, the game screen, the
bot dispatcher and the test harness all rely on it. `chess` is the reference
implementation — read `scripts/games/chess/` next to this document.

## Files per game

```
scripts/games/<game>/<game>_engine.gd   # rules, deterministic, no UI, no net
scripts/games/<game>/<game>_bot.gd      # AI, RefCounted, choose_action()
scripts/games/<game>/<game>_view.gd     # table UI, extends GameView
data/i18n/en/game_<game>.json           # English strings for this game
tests/games/test_<game>.gd              # rules suite run headless
```

The three script paths are already registered:

* `scripts/autoload/game_session_service.gd` → `ENGINE_SCRIPTS`
* `scripts/core/bot_director.gd` → `BOT_SCRIPTS`
* `scripts/ui/screens/game_screen.gd` → `VIEW_SCRIPTS`

## Engine (`extends GameEngine`, `class_name <Game>Engine`)

* Pure logic. No nodes, no signals other than the inherited ones, no file or
  network access, no `Time`-dependent behaviour except the bot's time budget.
  All randomness comes from the inherited `rng` (seeded from the match seed), so
  a match is reproducible.
* `game_id() -> String` — must match the catalog id.
* `setup(options)` — call `super.setup(options)` first, then read your own
  options, build the initial state and write the opening entry to the log.
* `legal_actions(player) -> Array[Dictionary]` — every action the player may take
  *now*, built with `make_action(type, params, label_key)`. Rules:
  * Parameters that identify the action (`from`/`to`/`card`/`bid`/…) are part of
    the key. Fields whose name starts with `_` (or `label_key`) are metadata and
    are ignored by `action_key`, so the same action keeps the same key whether or
    not you attach presentation data.
  * Set `_direct = false` for actions the board view submits (they are hidden
    from the generic action bar) and give a `label_key` for the ones the action
    bar should render as buttons (then `_direct` stays true).
  * Actions must be *validated* again in `apply_action`; never trust the caller.
  * For "choose one of N options" games, generate one action per option so the
    action bar can render them; for board games generate one action per move and
    `"label_key": ""`.
* `apply_action(action) -> Dictionary` — validate, mutate, then
  `return _ok(action)`. Reject with `_fail("game.<game>.error.<something>")`.
* `decision_player() -> int` — whose input the engine waits for. Override when
  the turn order is not simply `turn % player_count()`.
* `phase() -> String` and `phases() -> PackedStringArray` — machine ids; every id
  must have `game.<game>.phase.<id>` in the string pack.
* `public_state()` — call `super.public_state()` and add your public fields.
  Prefix purely presentational extras that clients may drop with `_`
  (e.g. `_last_drawn`). Everything here is sent to *all* players.
* `private_state(player)` — only the extra state that belongs to `player`
  (a hand, a secret role, a hidden objective). Never include another player's
  secrets; the test suite checks this.
* `private_state(-1)` — optional: table secrets nobody owns (a shuffled draw
  pile, a face-down market). Only save/load paths ask for it, so games without
  table secrets can keep returning `{}`.
* `_restore_extra(state)` — rebuild your fields from a snapshot. The state
  produced by `public_state()` plus the state produced by `private_state(p)`
  must always be enough to continue playing. Two shapes are supported and both
  are exercised by `EngineHarness.check_snapshot_round_trip`:
  * *online client shape* — the public snapshot with the acting player's
    private state merged at the **top level** (this is exactly what a client
    receives: public state + its own `private` payload);
  * *save-file shape* — the public snapshot plus a reserved `private_states`
    **bag**: a dictionary keyed by seat index (`str(p)`, with `"-1"` for table
    secrets) holding each seat's `private_state(p)`. Unknown keys are ignored,
    so games that only need the client shape can skip the bag and vice versa.
* `finish(winner, reason_key, scores)` — `winner` is a player index or `-1` for a
  draw; `scores` is `[{"player": int, "name": String, "score": Variant}]`.
* `log_event(key, args, player)` — append to the shared move log. Args are
  substituted into the translated string, so keep them small and stable
  (`{"player": "Ann", "card": "Guard"}`).
* `options_schema()` — table options for the setup screen:
  `{"key", "label_key", "type": "bool"|"int"|"enum", "default", "min", "max",
  "values", "hint_key"}`.

### Determinism and legality invariants (enforced by tests)

1. Two engines with the same seed and the same action sequence produce identical
   `public_state()`.
2. `apply_action` rejects anything not in `legal_actions` for the acting player.
3. Every legal action key is unique and stable across snapshots.
4. A snapshot restored into a fresh engine yields the same legal action list
   (snapshots include the private halves described above, since hand-driven
   actions cannot be reproduced from public state alone).
5. `private_state(p)` never contains another player's secrets.
6. Bots can always finish a match (or reach a stable, non-finished state) in a
   bounded number of steps: no infinite loops, no dead ends.

## Bot (`extends RefCounted`)

* `choose_action(engine: GameEngine, player: int) -> String` returns the **key**
  of a legal action (an empty string means "no idea" — `BotDirector` then falls
  back to the first legal action). `BotDirector` re-validates the key, so a bot
  bug can never corrupt a match; it only wastes a turn.
* Deterministic: no `randi()`/`randf()`; use fixed tie-breaking. Prefer obvious
  heuristics (material, mobility, points, distance to a goal) over long searches.
* A time budget is welcome (see `chess_bot.gd`), but a plain greedy policy that
  is *correct* beats an ambitious one that stalls.

## View (`extends GameView`, `class_name <Game>View`)

* `build_board()` — build the static structure once (call `UI.*` helpers: `UI.row`,
  `UI.column`, `UI.panel_with`, `UI.button`, `UI.chip`, `UI.section_header`, …).
* `refresh_board()` — re-render from `engine.public_state()` /
  `engine.private_state(acting_player())`. Called on every state change.
* Submit moves with `submit(key)`; never mutate the engine. `legal_actions()`
  returns the local player's legal actions (works online).
* `requires_handover()` — return `true` when hotseat play must hide the board
  between turns (any game with hands, roles or secret goals).
* `action_bar_extras()` — optional per-turn buttons (e.g. "confirm selection").
* Keep the board readable at 1600×900 and usable at interface scale 0.75–1.75.
* Use `CardFace` for cards, `Palette` for colours (never hardcode a theme colour
  that already exists there) and `Audio.play(Audio.Sfx.*)` for feedback.

## String pack (`data/i18n/en/game_<game>.json`)

Flat `key → text` JSON. Naming:

```
game.<game>.name / .desc                  title and one-line description
game.<game>.phase.<id>                    phase names
game.<game>.option.<key> / .<key>_hint    setup options
game.<game>.<thing>                       everything the view shows
game.<game>.log_<event>                   log lines with {placeholders}
game.<game>.reason.<reason>               end-of-match reasons (finish())
game.<game>.error.<error>                 rejection reasons (_fail())
```

House rules: use `{name}` placeholders (never `%s`), write full sentences, and
never leave a key in the pack that the code does not use. Counts use `.one` /
`.other` suffixes and `Loc.tp(key, count)`.

## Tests (`tests/games/test_<game>.gd`)

```gdscript
extends RefCounted

func suite_name() -> String:
	return "<game> rules"

func run(h: TestHarness) -> void:
	# ...
```

Use `EngineHarness` for the shared scaffolding:

* `EngineHarness.create(game_id, player_count, seed, options)` — set up an engine.
* `EngineHarness.check_legal_action_shape(h, engine, label)` — key/label sanity.
* `EngineHarness.check_snapshot_round_trip(h, engine, label)`.
* `EngineHarness.play_out(engine, max_steps)` — bot-driven run to the end.
* `EngineHarness.check_privacy(h, engine, secrets_of, label)` — hidden data check.

Every suite must cover, at minimum:

1. the opening position/count and that it is deterministic,
2. each rule you claim to implement (at least one check per rule),
3. rejection of an illegal action,
4. the end of the match (win condition or draw) and its `reason_key`,
5. snapshot round trip,
6. a bot-only match that finishes or reaches a stable state,
7. hidden information, if the game has any.

Run it with:

```bash
godot --headless --path . --import                      # refresh the class cache first
godot --headless --path . --script tests/run_tests.gd -- --filter test_<game>
```

The suite must finish with `0 failures`, and the whole run must stay green.
