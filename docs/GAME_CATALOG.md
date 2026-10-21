# Game catalogue

Game Hub ships thirteen games in `data/catalog/games.json`. This document is the
per-game reference: what each implementation actually implements, which
simplifications were made on purpose, how large its test suite is and what its
catalog status means. The status itself is machine-checked (see
[The playable gate](#the-playable-gate)); this file explains the numbers behind
it.

Status of this document: all thirteen games are `playable`. Their engines, bots
(where solo AI is offered), views, English string packs, rules suites and the
nine non-English locale packs are merged into the main branch and verified there.
Durak, King and Bridge were the last three merged (Bridge is a new
implementation); their catalog rows were flipped only after the automated gate
passed.

## Status vocabulary

| Field | Values | Meaning |
|---|---|---|
| `status` | `playable` | Engine, bot (when solo AI is offered), view and English string pack exist and pass the automated gate. |
| | `in_development` | Work has started or is planned; the game is not offered as finished. |
| | `partial` / `planned` | Reserved for partially playable / not started games. |
| `online_status` | `implemented` | The game has been exercised over the real two-process network smoke (ENet, host-authoritative, two seats): handshake, seat assignment, replicated snapshots, action forwarding, resign, match end. Games with hidden information are additionally run with `expect_private`, which asserts the replicated snapshot carries a non-empty private slice. |
| | `not_implemented` | The generic online transport exists, but this game has not been exercised over it yet (Spyfall needs at least three human seats; Bridge needs four and its catalog offers no online mode until a multi-client smoke exists). |
| | `verified` | Reserved for online status confirmed against real Steam sessions (see `STEAM_INTEGRATION.md` §10). |

Every game offers `hotseat`; the games with a shipped bot policy also offer
`solo_ai`. Online is offered everywhere except Spyfall (not yet exercised at its
three-seat minimum) and Bridge (four fixed seats; the current smoke opens only
two).

## Summary

| # | Game | Players | Modes | Status | Online | English keys | Suite checks |
|---|---|---|---|---|---|---|---|
| 1 | Citadels | 2–8 | hotseat, solo AI, online | playable | implemented | 104 | 331 |
| 2 | Codenames | 2–8 | hotseat, online | playable | implemented | 37 | 502 |
| 3 | DANY | 2–6 | hotseat, solo AI, online | playable | implemented | 54 | 781 |
| 4 | Spyfall | 3–8 | hotseat, online | playable | not_implemented | 81 | 483 |
| 5 | Chess | 2 | hotseat, solo AI, online | playable | implemented | 33 | 286 |
| 6 | Durak | 2–4 | hotseat, solo AI, online | playable | implemented | 41 | 685 |
| 7 | Bridge | 4 | hotseat, solo AI | playable | not_implemented | 48 | 1103 |
| 8 | King | 3–6 | hotseat, solo AI, online | playable | implemented | 41 | 749 |
| 9 | Monopoly | 2–6 | hotseat, solo AI, online | playable | implemented | 180 | 560 |
| 10 | Ticket to Ride: Europe | 2–5 | hotseat, solo AI, online | playable | implemented | 200 | 1005 |
| 11 | Coup | 2–6 | hotseat, solo AI, online | playable | implemented | 77 | 276 |
| 12 | Splendor | 2–4 | hotseat, solo AI, online | playable | implemented | 74 | 2778 |
| 13 | Star Realms | 2–4 | hotseat, solo AI, online | playable | implemented | 118 | 255 |

Suite-check numbers are the totals the rules suites report on the merged main
branch; they grow with the depth of the white-box coverage, so the Splendor
suite (which loops whole matches for the token-limit and noble sections) is much
larger than the others. The English-key counts are the size of
`data/i18n/en/game_<id>.json`; after the wave-9 Coup role guide every locale
carries the same keys.

## Games

### 1. Citadels — `citadels`

Hidden-role city building for 2–8 players (45 min, complexity 3). Each round is
drafted first, then the eight characters are called: the owner takes income (two
gold or two cards), uses their power once and may build one district (three as
the Architect). The first player to complete a city of eight districts ends the
round; the highest score wins.

*Implemented:* the eight roles with their powers (Assassin, Thief, Magician,
King, Bishop, Merchant, Architect, Warlord), the 2–3 player double draft, income
choice, district costs and colours, five district colours for scoring, the
crown.
*Documented simplifications:* the deck is 45 districts and unique (purple)
districts score only — their special powers are not implemented; the Assassin's
victim is revealed immediately; the Thief robs as soon as the role is called; the
Bishop shields the city from destruction; the Warlord destroys one district; the
Magician may swap hands with another player or discard and redraw; a
`round_limit` option ends stalled matches by score.
*Hidden information:* hands and drafted characters. The draw pile travels in the
table-secrets half of the snapshot (`private_state(-1)`).

### 2. Codenames — `codenames`

Word deduction for 2–8 players (30 min, complexity 2). Two teams race to uncover
their agents on a 5×5 grid with one-word clues from their spymasters.

*Implemented:* the 5×5 grid drawn from the word list with a key card, the
spymaster clue step (word + number), the guessing step, bystanders, the
assassin, team win conditions.
*Documented simplifications:* hotseat teams are split by seat parity (even
seats red, odd seats blue) and the lowest-index member of a team is its
spymaster — with two players every seat is both spymaster and operative, which
is playable but degenerate, and four or more seats are the intended experience.
Clues are drawn from a fixed cue vocabulary associated with the grid words
through a static table instead of free text, which is what makes bot play (and
deterministic testing) possible.
*Hidden information:* the key card and each player's team/role; operatives never
see the key.

### 3. DANY — `dany`

An original hidden-information bluffing game for 2–6 players (25 min). A
45-card deck (five cosmetic suits, values 1–9) is dealt out; the remainder is
sealed away. On a turn a player lays 1–3 cards face down and claims a value V
("these cards add up to exactly V") — and may lie. Every other living player, in
seat order, either inspects the claim or lets it stand. A truthful inspected
claim earns the claimant 1 insight and costs the inspector 1 reputation; a false
one costs the claimant 1 reputation and earns the inspector 2 insight. The
*oracle* is the minimum legal claim value; it starts at 1 and rises to V+1 after
every resolved claim, so rounds get bolder. Reputation lost past zero eliminates
the player; the last player standing, an oracle overflow or an insight majority
ends the match.

Because DANY has no published ruleset, this is an original interpretation
designed for the hub: 45 cards, claim versus oracle (1→27), reputation/insight,
eliminations and three endings — all documented in the engine header and covered
by the 781-check suite.

*Hidden information:* hands and the sealed remainder; only hand sizes,
reputations, insights and the move log are public.

### 4. Spyfall — `spyfall`

One spy among the agents for 3–8 players (20 min, complexity 1). Everyone but
the spy knows the location; the table asks questions until somebody dares to
accuse.

*Implemented:* location deck, spy assignment, question/answer rounds, the
accusation step, the spy's "name the location" comeback, win conditions for both
sides.
*Documented simplifications:* the spoken part is modelled with fixed question
cards and a fixed list of vague answer cards; locations declare which answers
are on topic for them, so a spy who does not know the location gives off-topic
answers and can be caught by deduction. `name_location` is offered to every
player (a non-spy naming the location is ignored, with a log entry); each player
has one accusation token; roles are flavour only.
*Hidden information:* the spy's identity and, for the spy only, that they do not
know the location.

### 5. Chess — `chess`

The classic game (2 players, complexity 4) with the full ruleset: castling,
en passant, promotion, check/checkmate/stalemate, repetition, the fifty-move
rule and insufficient material. The first game to pass the playable gate: a real
two-process ENet match runs in the network smoke (`tools/run_net_smoke.sh`).
Per-game online play still has the Steam caveat in `STEAM_INTEGRATION.md`.

### 6. Durak — `durak`

The classic attack-and-defend card game for 2–4 players (20 min, complexity 2),
played with the 36-card deck (6–Ace). The engine, bot, view, English pack, nine
locale packs and 685-check suite are playable.

*Implemented:* seeded shuffle; the bottom card fixes the trump and is drawn last;
a configurable hand size (4–9, default 6); drawing back up after each round,
attacker first and defender last; the lowest trump opens (seat 0 if nobody holds
one); one card is answered at a time, with a higher card of the same suit or any
trump beating it (and a trump only by a higher trump); the defender may take the
whole table; any non-defender may join with a rank already on the table, capped
at six attacks and at the defender's opening hand size; a beaten table is
discarded and the defender attacks next, while a pick-up passes the attack on;
players leave at zero cards and the last player holding cards is the fool. A
safety limit turns an endless empty-deck pick-up loop into a documented draw.
*Online:* exercised with two real processes over the local ENet transport with
the private-slice assertion (`online_status: implemented`).
*Tests:* `tests/games/test_durak.gd`, 685 checks.

### 7. Bridge — `bridge`

Contract bridge for exactly four players in fixed partnerships (60 min,
complexity 5): seats 0 and 2 are North–South, seats 1 and 3 East–West, and seat 0
deals. The engine, bot, view, English pack, nine locale packs and 1103-check
suite are playable.

*Implemented:* a 52-card deal (13 each); a natural auction of 35 contracts
(levels 1–7 in clubs, diamonds, hearts, spades, no-trump) plus pass, where every
bid must be strictly higher; four opening passes pass the deal out as a draw and
three passes after a bid end the auction; the declarer is the first player of the
winning partnership to name the final strain; the declarer's partner is dummy,
whose hand is exposed only after the opening lead and whose cards the declarer
plays; the player to the declarer's left leads; follow-suit is enforced; the
highest card of the led suit wins unless a trump was played; thirteen tricks;
duplicate-style scoring without vulnerability (20 per minor trick, 30 per major,
40 for the first no-trump trick and 30 after, partscore 50, game 300, small slam
500, grand slam 750, overtricks at the contract rate, 50 per undertrick).
*Documented simplifications:* one deal per match; no doubles, redoubles,
vulnerability or declarer-played dummy variations; a partnership result is
represented by one seat in the shared result shape (`contract` carries the full
detail and `scores[]` lists both partners). The bot opens 1♣ when nobody has bid
and otherwise passes, then always plays its lowest legal card.
*Online:* not offered in the catalog yet. The engine is host-authoritative, but
the current smoke harness opens only two seats and Bridge needs four; a
multi-client smoke is tracked in `KNOWN_ISSUES.md` §1.3.
*Tests:* `tests/games/test_bridge.gd`, 1103 checks.

### 8. King — `king`

The trick-avoidance classic for 3–6 players (30 min, complexity 2), played with
the full 52-card deck. The engine, bot, view, English pack, nine locale packs and
749-check suite are playable.

*Implemented:* the deck is dealt evenly and leftovers are set aside face down;
the optional pass (default on) has every player pick three cards privately, then
all picks go to the player on the left, so nobody can react to a hand-over; the
leader opens; follow-suit is enforced and the highest card of the led suit takes
the trick. Hearts score one point, the queen of spades five and the king of
hearts a −5 bonus; the lowest score wins. Shooting the moon (default on) waives
all heart and queen points for a player who takes every heart and the queen,
while keeping the king bonus. The optional pass and the moon rule are both setup
options. A public-only snapshot is a spectator model and cannot act.
*Online:* exercised with two real processes over the local ENet transport with
the private-slice assertion (`online_status: implemented`). The smoke opens two
seats while the catalog minimum is three; the engine accepted the two-seat run,
but a three-plus-seat multi-client smoke remains unautomated (see
`KNOWN_ISSUES.md` §1.3).
*Tests:* `tests/games/test_king.gd`, 749 checks.

### 9. Monopoly — `monopoly`

Economic board game for 2–6 players (90 min, complexity 3).

*Implemented:* the standard 40-space board, 2d6 movement with doubles (three
doubles → jail), GO salary, buy-or-auction, colour-group doubling, railroad and
utility rents, Chance and Community Chest (drawn from the seeded RNG), taxes,
jail (fine, card or doubles), houses and hotels with the even-build rule,
property trading with accept/decline, bankruptcy to the bank or a creditor, and
a turn cap as the final end condition.
*Documented simplifications:* no mortgages and no discretionary house sales
(houses sell back automatically at half price when a payment is short, and the
shortfall is forgiven on bankruptcy); trading is one house-free property per
side with an optional cash sweetener, or a cash-only offer; jail-free cards are
discarded when used or when their holder is bankrupted; deck order travels in
the public snapshot under `_`-prefixed keys (the host needs it to restore the
match exactly; the view never shows it).
*Hidden information:* trade terms (until accepted) are private; everything else
on the board is public.

### 10. Ticket to Ride: Europe — `ticket_to_ride_europe`

Route-building board game for 2–5 players (75 min, complexity 3).

*Implemented:* eight colours plus locomotives (110 cards), the five-card market
row with the locomotive restrictions, blind and face-up drawing, route claiming
with colour or gray payment, locomotive requirements on ferry routes, tunnel
exploration with extra payment or clean retreat, destination tickets (three at
the start keeping at least two; three mid-game keeping at least one), the final
round triggered by a player's last trains, and scoring with route points,
completed/unfinished tickets and the +10 longest-path bonus.
*Documented simplifications:* no train stations (a route must touch the player's
own network); the route table is a compact recreation of the Europe board —
47 routes over 43 cities including tunnels and ferries; the longest path is the
longest *simple* city path (ties share the bonus); a `turn_cap` and a safety
`pass` action guarantee termination; deck order travels in the public snapshot
under `_`-prefixed keys.
*Hidden information:* hands, kept tickets and pending ticket offers are private;
only the offer player, size and minimum are public.

### 11. Coup — `coup`

Hidden-influence bluffing for 2–6 players (20 min, complexity 2). Two face-down
influence cards and two coins each; on a turn: income, foreign aid, a claim
(Tax, Steal, Assassinate, Exchange) or a coup. Claims may be challenged and
targeted actions blocked; a failed challenge or a completed coup costs one
influence. Last player with influence standing wins.

*Implemented:* the full base game — all five roles, challenges, blocks, the
mandatory coup at 10+ coins, exchange, influence loss and elimination, the
15-card Court deck.
*Documented simplifications:* costs paid for an action whose own challenge is
caught are refunded, while an assassination stopped by a block keeps its cost
paid; a proven claim's shown card is shuffled back into the deck and replaced;
the bot never bluffs (it claims only what it holds and challenges only when all
three copies are accounted for) — deterministic, not a bluffing AI; a
`MAX_TURNS` safety ends pathological matches by surviving influence; no
Inquisitor/Reformation cards, no team variant.
*Hidden information:* influence cards; the Court deck travels as table secrets.

### 12. Splendor — `splendor`

Gem-merchant engine building for 2–4 players (40 min, complexity 2).

*Implemented:* 90 development cards in three tiers, 10 nobles, five gem colours
plus gold, the take-3-different / take-2-same actions, reservations (max three,
with a gold joker), purchases from the market or reserve, permanent bonuses,
noble visits and the end-of-round trigger at the target score.
*Documented simplifications:* the ten-token limit is enforced by automatically
returning the excess (most abundant colour first, gold only when strictly most
abundant) instead of letting the player choose; when several nobles qualify at
once they visit in reveal order; a `pass` action exists only when nothing else
is legal, plus safety valves (consecutive passes and a stale-action limit) so
bot-only matches always terminate.
*Hidden information:* reserved cards; each player's reserved pile is private.

### 13. Star Realms — `star_realms`

Deck-building combat game for 2–4 players (30 min, complexity 3).

*Implemented:* the ten-card starting deck (8 Scouts, 2 Vipers) and 50 authority,
draw-to-five, trade/combat spending, the shared trade row plus the always
available Explorer, base and outpost defence (outposts fall before their owner
can be attacked), ally abilities, scrap abilities, optional scrap/destroy
effects and destroy-base abilities, authority victory.
*Documented simplifications:* combat must be spent in one go (bases are
destroyed for exactly their defence; authority takes the whole remaining pool);
optional effects stay available until the end of the turn; unaligned cards never
trigger ally abilities. Card content: 42 card definitions (41 core, 1 promo)
forming the 80-copy core trade deck. The edition registry and the pending
expansions are documented in [STAR_REALMS_EXPANSIONS.md](STAR_REALMS_EXPANSIONS.md).

## The playable gate

`tests/unit/test_playable_games.gd` makes the catalog self-enforcing: a game
marked `playable` must prove, inside the ordinary test run, that

1. the engine is registered and instantiable;
2. it offers legal actions in the documented shape at the minimum **and** maximum
   player count;
3. a snapshot (public state plus the acting player's private state) round trips
   into a fresh engine and yields the same legal actions;
4. the same seed and the same first-legal action sequence reproduce the exact
   same public state (determinism);
5. when `solo_ai` is claimed, a registered bot exists and can play the match;
6. the view script loads, mounts a real local match, re-renders it through bot
   play and finishes without script errors;
7. the English string pack resolves every name/description/phase key the catalog
   references.

The gate was falsified once on purpose (a broken chess view path made it fail)
before it was armed. Current state on the main branch: **13 games marked
playable, 1820 gate checks, 0 failures**.

## Honest limits

* Per-game online play is implemented on top of the shared host-authoritative
  transport, and eleven of the thirteen playable games have been exercised over
  it end-to-end with two real processes: chess, codenames, dany, splendor, star
  realms, citadels, coup, monopoly, ticket to ride, durak and king — the
  hidden-information games with the extra non-empty-private-slice assertion.
  Spyfall's minimum is three seats and Bridge's is four, while the smoke opens
  two: their `online_status` deliberately stays `not_implemented`, and Bridge
  also omits the online mode in the catalog. King's smoke used two seats although
  its catalog minimum is three; the engine handled the run, but a three-plus-seat
  multi-client smoke is still missing. None of this is Steam: real Steam sessions
  need a Steam client and two accounts (`KNOWN_ISSUES.md` §1.1).
* The views are verified headlessly (mount, render, bot playout, no script
  errors) and by the boot/screen smokes. Pixel-level visual checks are not part
  of the automated runs in this environment (see `KNOWN_ISSUES.md` §1.4).
* Translation status per locale lives in `LOCALIZATION.md`; the packs are
  machine-checked for key parity and placeholders, not for stylistic quality.
