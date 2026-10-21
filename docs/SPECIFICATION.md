# Specification

What Game Hub is, what it must do, and the acceptance criteria it is judged by.
This document is the product contract; the code contract for games is
`docs/GAME_ENGINE_CONTRACT.md` and the running verification log is
`AI_PROGRESS.md`.

## 1. Vision

A desktop board-game platform that runs entirely offline-capable but supports
real online play: thirteen complete games, ten languages, honest status labels
and no simulated features. Everything a screen shows must come from a real
engine, a real locale pack or a real preference — never from a placeholder.

## 2. Platform and technology

* Godot 4.7.2 (GDScript), single window, mouse + keyboard.
* Target resolution 1280×720 and above; UI scale 75 %–175 %.
* No backend server: online play is peer-to-peer, host-authoritative.
* Steam is not used in this build. Online play uses the local ENet test transport
  (labelled *not Steam*) or is disabled for web builds.

## 3. Games

Thirteen games ship as fully playable engines (deterministic rules, legal-action
validation, bots where the mode requires them, string packs, rule tests):

| # | Game | Players | Modes | Category |
|---|------|---------|-------|----------|
| 1 | Citadels | 2–8 | hotseat, solo AI, online | drafting / hidden roles |
| 2 | Codenames | 2–8 | hotseat, online | word deduction, teams |
| 3 | Dany | 2–6 | hotseat, solo AI, online | hidden information card game |
| 4 | Spyfall | 3–8 | hotseat, online | social deduction |
| 5 | Chess | 2 | hotseat, solo AI, online | classic strategy |
| 6 | Durak | 2–4 | hotseat, solo AI, online | climbing card game |
| 7 | Bridge | 4 | hotseat, solo AI | bidding / trick taking |
| 8 | King | 3–6 | hotseat, solo AI, online | avoidance trick taking |
| 9 | Monopoly | 2–6 | hotseat, solo AI, online | economic board game |
| 10 | Ticket to Ride: Europe | 2–5 | hotseat, solo AI, online | route building |
| 11 | Coup | 2–6 | hotseat, solo AI, online | bluffing / elimination |
| 12 | Splendor | 2–4 | hotseat, solo AI, online | engine building |
| 13 | Star Realms | 2–4 | hotseat, solo AI, online | deckbuilding, editions |

Requirements per game:

1. **Deterministic rules.** Same seed and same actions produce the same state.
   Randomness only through the engine's seeded generator.
2. **Validated actions.** Illegal actions are rejected with a translation key;
   the acting player never mutates state directly from the UI.
3. **Termination.** Every match ends (win, draw, or an explicit documented cap)
   and reports a reason key.
4. **Hidden information.** Games with secrets never expose them in
   `public_state()`; hotseat screens use a handover step before showing them.
5. **Bots.** Games with a `solo_ai` mode have a deterministic bot that can
   finish a match unattended; all games have a fallback so no match deadlocks.
6. **Tests.** Each game ships a rules suite per `docs/TEST_PLAN.md` §5.

## 4. Shell and modes

* **Library** — cards for every catalog game with art, name, description,
  players/modes, favourites and recents; filters for category, player count,
  playable-now and sorting.
* **Details** — full description, rules summary, status, edition entry point for
  Star Realms.
* **Setup** — player count, names, mode, per-game options.
* **Hotseat** — one device, per-player handover for hidden information.
* **Solo AI** — the player plays against bots of every other seat.
* **Online** — host or join via Steam lobbies (or the labelled local test
  transport); lobby screen lists seats, readiness and game metadata; the host
  starts the match; disconnects are detected and reported.
* **Reconnection is not promised.** A dropped player is marked disconnected and
  bots never impersonate them silently.

## 5. Localisation

* Exactly ten locales: `en`, `uk`, `ru`, `de`, `zh_CN`, `az`, `be`, `cs`, `pl`,
  `fr`, shown by native name (`English`, `Українська`, `Русский`, `Deutsch`,
  `中文`, `Azərbaycanca`, `Беларуская`, `Čeština`, `Polski`, `Français`).
* Every visible string comes from a catalogue: no raw keys are ever displayed.
* English is the source of truth; other locales must cover the full key set
  (the suite enforces full coverage and lists any missing key).
* Switching locale applies immediately and persists.

## 6. Display settings

Window mode (windowed / fullscreen / borderless), resolution list, UI scale,
max FPS, vsync, monitor selection, plus a safety revert window when the change
could make the window unusable. Details: `docs/DISPLAY_SETTINGS.md`.

## 7. Star Realms editions

The catalog registers Star Realms with an edition registry. The set-picker
screen lets the player enable or disable expansions; the selection is validated
(dependencies, conflicts, mandatory base set), persisted, and used when a match
starts. Registry-only sets are labelled honestly as not playable content.
Details: `docs/STAR_REALMS_EXPANSIONS.md`.

## 8. Online requirements

* Steam is not used in this build; there is no `steam_appid.txt` and no Steamworks
  dependency.
* Online play (where available) uses the local ENet test transport, labelled *not
  Steam* in the UI; the Steam transport is not shipped.
* Host-authoritative state; clients never apply unvalidated actions.
* The wire protocol is versioned and rejects mismatches with a typed reason.
* The local test transport must be usable without Steam and must say so in the
  UI. Details: `docs/STEAM_INTEGRATION.md`.

## 9. Non-functional requirements

* **Honesty.** Status labels (game status, online status, expansion content)
  must reflect reality; a feature that cannot be verified in this environment is
  documented as such in `KNOWN_ISSUES.md`, never claimed as verified.
* **Data safety.** No destructive commands, no rewriting user files, no secrets
  in the repository.
* **Determinism and privacy** as in §3.
* **Quality gates.** The full test suite, the compile guard, the boot smoke and
  the network smoke must pass as documented in `docs/TEST_PLAN.md`.

## 10. Acceptance criteria

1. The application boots to the library with zero script errors (boot smoke).
2. The full test suite passes with zero failures on the release tree.
3. All thirteen games are playable in every mode their catalog entry claims.
   Their engines, bots, views and gates are covered by the automated suites;
   manual visual review is documented as environment-limited in
   `KNOWN_ISSUES.md`.
4. All ten locales show translated UI; no raw key appears anywhere.
5. Online play works host-authoritative over a real transport; the Steam path is
   verified as far as the environment allows, with the remainder documented.
6. `docs/` contains SPECIFICATION, ARCHITECTURE, LOCALIZATION, DISPLAY_SETTINGS,
   GAME_CATALOG, STAR_REALMS_EXPANSIONS, STEAM_INTEGRATION, TEST_PLAN,
   KNOWN_ISSUES and AI_PROGRESS, all matching the code.

Current verification status for these criteria is tracked in `AI_PROGRESS.md`.
