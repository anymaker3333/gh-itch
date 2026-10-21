# Star Realms: editions and expansions

Star Realms is the only game in the hub with **edition selection**: the setup
screen can open a set picker (`scripts/ui/screens/star_realms_sets_screen.gd`,
route `star_realms_sets`) and the selection is stored in preferences, validated
against the registry and handed to the engine as its card pool.

This document is the honest map of what is playable content and what is only
registered.

## Where the data lives

| Piece | File |
|---|---|
| Set registry | `data/catalog/star_realms_sets.json` |
| Card definitions, faction and set helpers | `scripts/games/star_realms/star_realms_cards.gd` |
| Picker screen | `scripts/ui/screens/star_realms_sets_screen.gd` |
| Validation | `Catalog.validate_selection()` (`scripts/autoload/catalog.gd`) |
| Preferences | `Prefs.selected_star_realms_sets()` / `Prefs.set_star_realms_sets()` |
| Engine consumption | `StarRealmsEngine._selected_sets()` |

`Catalog.validate_selection("star_realms", ids)` returns
`{"selected": [...], "rejected": [{"id", "reason"}]}`. Reasons are `unknown`
(not in the registry), `conflict` (two sets that declare they cannot combine)
and `content_pending` (registered but not implemented). Required sets (the core
set) are always prepended to the selection. The picker disables pending sets and
writes every toggle through this validation, so a preference can never hold an
unplayable set. The engine additionally drops unknown and unimplemented ids as a
second line of defence, and its `editions` option can force `core` only
(`selected` is the default).

## The registry

Twelve sets are registered. Only the first two have content:

| Set id | Kind | Content ready | Trade-deck copies | Notes |
|---|---|---|---|---|
| `sr_core` | base | **yes** | 80 | Required and default. The 80-copy trade deck. |
| `sr_mercenary_garrison` | promo | **yes** | 1 | Single promo card, off by default. |
| `sr_colony_wars` | expansion | no | 80 | Registry only. |
| `sr_crisis_bases` | expansion | no | 12 | Registry only. |
| `sr_crisis_fleets` | expansion | no | 12 | Registry only. |
| `sr_crisis_events` | expansion | no | 12 | Registry only. |
| `sr_crisis_heroes` | expansion | no | 12 | Registry only. |
| `sr_united_assault` | expansion | no | 12 | Registry only. |
| `sr_united_command` | expansion | no | 12 | Registry only. |
| `sr_united_heroes` | expansion | no | 12 | Registry only. |
| `sr_frontiers` | expansion | no | 80 | Registry only. |
| `sr_promos` | promo | no | 0 | Placeholder for future promo cards. |

`card_count` and `implemented_card_count` are **trade-deck copy counts**, not
distinct card definitions: `sr_core` is 80 copies drawn from 41 distinct card
definitions (38 faction cards plus 3 unaligned), and the mercenary garrison is
a single copy of one definition. Every pending set lists
`depends_on: ["sr_core"]`, so none of them can be selected without the base set.

Every set in the registry has English string keys
`sr.set.<id>.name` / `sr.set.<id>.desc` in `data/i18n/en/game_star_realms.json`,
and the picker's own keys live under `sr.picker.*` in the same pack.

## What "content ready" means

A set may be marked `content_ready: true` only when **all** of the following are
true, and the flag is what the picker and the validator trust:

1. its card definitions exist in `star_realms_cards.gd` with cost, kind
   (ship/base/outpost), defence and faction data;
2. its trade-deck composition is defined and its `card_count` matches the
   implemented copy count while shuffling in the deck;
3. `StarRealmsCards.implemented_sets()` lists it (the engine builds
   `used_sets` from that intersection);
4. its English strings exist;
5. the rules suite covers at least its composition (the `sr_core` deck size,
   faction distribution and the promo card are asserted).

The 10 pending sets fail step 1 today: they have no card data, so they cannot
be enabled, and the validator reports them as `content_pending` rather than
silently accepting them.

## Rights note

`data/catalog/star_realms_sets.json` carries the accreditation string used by
the app: *Star Realms is a trademark of Wise Wizard Games. This is a fan
implementation of the rules; card names and values are used for interoperability
only.* The hub does not ship any official card art or text beyond the names and
numeric values needed for play.

## Adding a set

To move a pending set to `content_ready: true`:

1. add its card definitions and trade-deck composition to
   `star_realms_cards.gd` (constants for the set id, entries in `CARDS`, the
   pool list `implemented_sets()` returns);
2. flip `content_ready` in `data/catalog/star_realms_sets.json` and update
   `implemented_card_count` so it matches the composition;
3. add the English `sr.set.<id>.*` strings and run the translation wave for the
   nine locales;
4. extend `tests/games/test_star_realms.gd` with a composition check for the
   set (deck size, faction mix, any new mechanics), and re-run the playable gate
   — the gate mounts the game with the default selection, so a set that breaks
   shuffling or setup fails there.
