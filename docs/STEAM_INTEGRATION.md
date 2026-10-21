# Steam integration

How Game Hub turns a Steam lobby into a host-authoritative gameplay session, what
is Steam-specific and what is test scaffolding, and what still has to be verified
on two real Steam accounts.

This document was written on 2026-10-18 from the files cited below. All behaviour
described here is taken from those files; the live two-account Steam path has
**not** been exercised (see "Verification status"). Earlier windowed runs
initialised the Steam client and App ID 480 successfully, but the client was not
running during the latest verification attempt.

## Verification status

| Item | State |
|------|-------|
| Godot | 4.7.2 (`/usr/bin/godot`; `project.godot` declares `config/features` `"4.7"`) |
| GodotSteam GDExtension | v4.23.1 (`addons/godotsteam/plugin.cfg`, git-ignored, ~106 MB) |
| Extension registration | `.godot/extension_list.cfg` → `res://addons/godotsteam/godotsteam.gdextension` (`compatibility_minimum = "4.4"`) |
| App ID | 480 = Spacewar, the public Steamworks test app (`steam_appid.txt` contains `480`; `Prefs.DEFAULTS["steam/app_id"] = 480`) |
| Steam gameplay transport | **not yet verified** in this environment |
| Local test transport | exercised by `tools/run_net_smoke.sh` (ENet loopback — **not Steam**) |
| Steam client, latest attempt (2026-10-20) | **not running** — `SteamSvc` `FAILED`, "Cannot create IPC pipe to Steam client process." |

Earlier windowed runs reached `State.READY` for App ID 480 with a valid persona
and Steam ID when the Steam client was running (logs showed `Steamworks active
for App 480`). During the latest attempt the client was not running and
`SteamSvc` reported `FAILED`; this is the expected degraded state, not a code
failure. Even with a running client, only one Steam account/peer is available:
no second account can join a lobby, so no two-account gameplay run has happened
and nothing below is presented as a two-account test result.

<!-- TODO(verify): run the manual steps in section "Manual verification" on two Steam accounts (two machines or one machine with Steam Family Sharing is not enough) and record the result here. -->

## 1. Roles and components

Game Hub is a **host-authoritative listen server** (`scripts/autoload/net_service.gd`
header, `scripts/core/game_session.gd` header):

* The **host** runs the rules engine. It owns the match seed, applies every
  action and broadcasts the resulting state.
* **Clients** send *intended actions* only (`T_ACTION`). They render snapshots
  received from the host and never apply rules locally.
* Hidden information (hands, secret roles, hidden objectives) is sent **only to
  its owner** via the per-peer snapshot (`GameSession._replicate_state`).

| Component | File | Responsibility |
|-----------|------|----------------|
| `SteamSvc` | `scripts/autoload/steam_service.gd` | Steamworks init, identity, lobby lifecycle, metadata, invites/overlay, chat, relay status. Reads Steam state but never simulates it. |
| `SteamGateway` | `scripts/core/steam_gateway.gd` | Defensive wrapper around the `Steam` GDExtension singleton: availability, `supports()`, `call_method()`, `connect_signal()`. |
| `Net` | `scripts/autoload/net_service.gd` | Transport + link state machine, peer registry, heartbeats, protocol handshake, packet polling. |
| `GameSession` | `scripts/core/game_session.gd` | One match: host replication, client snapshot handling, resign, disconnect handling, bots. |
| `Session` | `scripts/autoload/game_session_service.gd` | Session lifecycle; `start_online_host()` / `start_online_client()`; the `lobby` context dictionary. |
| `OnlineScreen` | `scripts/ui/screens/online_screen.gd` | Steam status, lobby creation, lobby browser, friends/invites, local-test panel. |
| `LobbyScreen` | `scripts/ui/screens/lobby_screen.gd` | Member list, seat/ready state, chat, host "Start match", client "wait for start". |

## 2. The Steam transport

### 2.1 Dependency

Online play requires the GodotSteam GDExtension, which registers the `Steam`
singleton and the `SteamMultiplayerPeer` class. The addon directory is
git-ignored (`.gitignore`), so a fresh checkout does not contain it; the
`.gitignore` comment points at `tools/fetch_godotsteam.sh`, which downloads the
pinned upstream GDExtension release (v4.23.1; the URL and SHA-256 live in the
script) and extracts it into `addons/`. Run it once on a fresh checkout, then
`godot --headless --path . --import`.

`SteamGateway` (`scripts/core/steam_gateway.gd`) is the only place that touches
the extension. It records which methods and signals actually exist
(`supports()`, `supports_signal()`), and every call site goes through
`call_method()` / `connect_signal()`, which degrade to a default value and a log
entry when the extension is missing. Nothing in this layer fakes Steam: without
the extension or client, services report `UNAVAILABLE` / `FAILED` and the UI
shows a degraded state.

### 2.2 `SteamMultiplayerPeer` requirement and instantiation

`Net` requires the `SteamMultiplayerPeer` class provided by the extension. The
peer is created in `Net._create_steam_peer()` (`scripts/autoload/net_service.gd`):

```gdscript
if not ClassDB.class_exists("SteamMultiplayerPeer"):
    transport_error.emit("steam_peer", Loc.t("net.error_no_steam_peer"))
    return null
var instance: Variant = ClassDB.instantiate("SteamMultiplayerPeer")
if not (instance is MultiplayerPeer):
    transport_error.emit("steam_peer", Loc.t("net.error_no_steam_peer"))
    return null
return instance
```

The peer is then driven with methods from the GodotSteam API:

* host path — `host_with_lobby(lobby_id)` (`Net.host_steam_lobby()`);
* client path — `connect_to_lobby(lobby_id)` (`Net.join_steam_lobby()`);
* optional id mapping — `get_steam_id_for_peer_id()` / `get_peer_id_for_steam_id()`
  when the peer exposes them (`Net.steam_id_of()`, `Net.peer_id_of_steam_id()`).

`Net` polls the peer itself once per frame (`Net._poll_packets()` → `peer.poll()`)
because the peer is owned by the service, not by a `MultiplayerAPI`.

`net.error_no_steam_peer` renders as "Steam networking is unavailable in this
build." (`data/i18n/en.json`).

Verified on the development machine on 2026-10-19 while the Steam client was
`READY` (App ID 480): `ClassDB.class_exists("SteamMultiplayerPeer")` is `true` and
`ClassDB.instantiate("SteamMultiplayerPeer")` returns a `MultiplayerPeer`. The
missing-extension branch and the behaviour with Steam closed were not exercised
in this environment.

### 2.3 `steam_appid.txt`

`SteamSvc._configure_app_id()` writes `steam_appid.txt` in the working directory
when the file is missing or does not match `Prefs.get_value("steam/app_id", 480)`.
This is how the Steamworks SDK finds the App ID when the game is not launched
through Steam. The file is git-ignored and, per the code comment in
`steam_service.gd`, "is development tooling and must never be shipped".

## 3. Local test transport (not Steam)

`Net.Transport` has two values (`scripts/autoload/net_service.gd`):
`STEAM = 1` and `LOCAL_TEST = 2`. `LOCAL_TEST` uses Godot's built-in
`ENetMultiplayerPeer` and is gated by `Prefs` key
`steam/allow_local_test_transport` (default `true`, `scripts/autoload/prefs.gd`
`DEFAULTS`):

* `Net.host_local_test(port, max_clients)` → `ENetMultiplayerPeer.create_server()`;
* `Net.join_local_test(address, port)` → `ENetMultiplayerPeer.create_client()`;
* ports are clamped to `TEST_PORT_MIN..TEST_PORT_MAX` = 47000..47999.

It is explicitly labelled as a test/LAN tool everywhere it is exposed:

* `online.test_hint`: "ENet over localhost. Used by the automated multiplayer tests and for LAN debugging — this is not Steam networking."
* `online.test_warning`: "Test transport only. Lobby metadata, invites and relay are Steam features and are unavailable here."
* `lobby.transport_test`: "ENet local test (not Steam)".

It exists for the two-process smoke test (`tools/run_net_smoke.sh`) and for LAN
debugging. Mechanically it runs the **same** application protocol, handshake,
seat assignment, action forwarding and replication as the Steam transport — only
the `MultiplayerPeer` implementation changes. It is **not** Steam networking and
proves nothing about Steam Networking Sockets, relay, lobbies or invites.

## 4. Lobby lifecycle (`SteamSvc`)

| Action | API | Notes |
|--------|-----|-------|
| Create | `create_lobby(visibility, max_members, metadata)` | Visibility `public` / `friends` / `private` / `invisible` maps to `LOBBY_TYPE_*`; member limit clamped to 2..16. Metadata passed by `OnlineScreen` is written once the lobby exists. |
| Search | `refresh_lobby_list(max_results = 50)` | Adds the filters below, then `requestLobbyList`. |
| Join | `join_lobby(id)` | Requires `State.READY`; leaves the previous lobby first. |
| Leave | `leave_lobby()` | Clears members and chat, unsets `lobby_id`. |
| Invite | `invite_friend(steam_id)` | `inviteUserToLobby`; failure emits `steam.error_invite_failed`. |
| Overlay invite | `open_invite_overlay()` | `activateGameOverlayInviteDialog` when supported, else `steam.error_overlay_unavailable`. |
| Chat | `send_lobby_chat(text)` | `sendLobbyChatMsg`, truncated to 400 characters; `_on_lobby_message` keeps the last 200 entries in `chat_log`. |
| Member data | `set_member_data("player_name"/"ready", …)` | Shown in `LobbyScreen._rebuild_members()`. |
| Relay | `_relay_init()` / `_on_relay_network_status()` | `initRelayNetworkAccess` when available; `relay_available` is true only when both `available == 1` and `available_relay == 1`. UI chips: `online.relay_ok` / `online.relay_unknown`. |

`SteamSvc.is_host()` compares `getLobbyOwner(lobby_id)` with the local SteamID.
`Net.host_steam_lobby()` refuses unless the local user owns the lobby.

### 4.1 Lobby metadata keys published for verification

`KEY_*` constants in `scripts/autoload/steam_service.gd` (all values are stored as
strings):

| Constant | Wire key | Written by | Content |
|----------|----------|------------|---------|
| `KEY_GAMEHUB` | `gamehub_id` | `_on_lobby_created` | `GAMEHUB_LOBBY_ID_VALUE` = `"gh-n3uf"` — the marker that makes a lobby a Game Hub lobby |
| `KEY_PROTOCOL` | `protocol_version` | `_on_lobby_created` | `Prefs` `net/protocol_version` (default 1) |
| `KEY_GAME_VERSION` | `game_version` | `_on_lobby_created` | `ProjectSettings application/config/version` (`0.1.0` in `project.godot`) |
| `KEY_HOST_NAME` | `host_name` | `_on_lobby_created` | `SteamSvc.display_name()` |
| `KEY_MAX_PLAYERS` | `max_players` | `_on_lobby_created` | Requested member limit |
| `KEY_LANGUAGE` | `language` | `_on_lobby_created` + `OnlineScreen` | `Loc.current_locale` |
| `KEY_GAME_ID` | `game_id` | `OnlineScreen._create_lobby`, later re-published by `LobbyScreen` | Catalogue id (`chess`, …) |
| `KEY_GAME_NAME` | `game_name` | `OnlineScreen._create_lobby` | Display name |
| `KEY_GAME_MODE` | `game_mode` | `OnlineScreen._create_lobby` | `"online"` |
| `KEY_STATUS` | `status` | `OnlineScreen._create_lobby` (`"open"`), `publish_lobby_state()` (`"open"` / `"in_match"`) | Lobby state shown in the browser |
| `KEY_EXPANSIONS` | `expansions` | `OnlineScreen._create_lobby` | Comma-separated selected editions (`Prefs.selected_star_realms_sets()` for games with editions, otherwise empty) |
| `KEY_TRANSPORT` | `transport` | **never written** — no call site in `scripts/` at the time of writing | — |

The browser (`online_screen.gd::_populate_lobby_list`) shows `game_id`/`game_name`,
`host`, `members/max_members`, `status`, `language` and an `expansions` chip.
The lobby screen header shows game, host, visibility, Steam lobby id, transport,
relay state, player count and editions (`lobby_screen.gd::_rebuild_header`).

### 4.2 Search filters that keep unrelated App 480 lobbies out

`SteamSvc.refresh_lobby_list()` applies exactly two required filters before
`requestLobbyList`:

1. `addRequestLobbyListStringFilter(KEY_GAMEHUB, "gh-n3uf", LOBBY_COMPARISON_EQUAL)`
   — only lobbies that published the Game Hub marker are returned, so unrelated
   Spacewar (App 480) lobbies are excluded.
2. `addRequestLobbyListNumericalFilter(KEY_PROTOCOL, net/protocol_version, LOBBY_COMPARISON_EQUAL)`
   — only lobbies speaking the same protocol version.

plus `addRequestLobbyListResultCountFilter(max_results)` (default 50).

What is **not** filtered: `game_version`, game id, mode or visibility. A Game Hub
lobby from a different build but the same protocol version is listed and shown in
the browser; the client relies on the displayed metadata and the start-match
message to reconcile the actual game.

<!-- TODO(verify): the exact shape of the dictionary delivered by the GodotSteam lobby_match_list signal (key casing, member count field) was not executed; _lobby_key() and _on_lobby_match_list() were written to tolerate both `lobby_id`/`lobby` spellings, but this needs a live check. -->

## 5. Connection handshake (hello / welcome)

Runs in `Net._poll_packets()`, identical for Steam and ENet; no screen is
involved.

1. **Transport up.** The client's peer reports `CONNECTION_CONNECTED` while the
   link is `CONNECTING` → link `CONNECTED`, then `Net.announce_self()`.
2. **`T_HELLO` (client → host).** `announce_self()` sends name, `steam_id`
   (`SteamSvc.steam_id`, 0 without Steam), `protocol` (`NetProtocol.VERSION`),
   `game_version` and `language`.
3. **Seat assignment + `T_WELCOME` (host → client).** `_accept_hello()` picks a
   seat with `next_seat_index()` (seat 0 is the host; remotes are numbered in
   introduction order), registers the peer and answers with `T_WELCOME` carrying
   `host`, `host_peer_id = Net.local_peer_id`, `seat`, `protocol` and the host's
   `Session.lobby` context.
4. **`host_peer_id`.** Under ENet it starts as 1; under Steam it starts as the
   host's peer id and is then corrected to the host's real unique id when
   `T_WELCOME` arrives (`Net.set_host_peer()`). Game code never hardcodes a peer
   id — it asks `Net.host_peer_id` / `Net.is_host_peer()`.
5. **`T_WELCOME` handling (client).** `_accept_welcome()` registers the host as
   seat 0 (`steam_id` from `SteamSvc.host_steam_id()`), marks it `ready`, and
   merges the host's `Session.lobby` context into the local one.
6. `Net.register_peer()` emits `seat_assigned` when a peer first gains a seat
   (`player_index >= 0`). The lobby screen listens to both `peer_registered` and
   `seat_assigned` to keep the member list accurate.

## 6. Starting a match and seat mapping

`LobbyScreen._start_match()` (host):

1. Ensures the gameplay transport (`Net.host_steam_lobby(lobby_id)` for the
   Steam path; the local-test path is already open).
2. Chooses the final seat count: seat 0 = host, connected clients in seat order,
   every remaining seat filled with a bot (`game.common.bot` names) so a match
   can start before the lobby is full.
3. Calls `Session.configure(game_id, player_count)` and
   `Session.start_online_host(remote_seats)`; the host engine is built with
   `player_kinds` `local`/`remote`/`bot` and each player's `peer_id`/`steam_id`.
4. Broadcasts `T_START_MATCH` with `game_id`, `seed`, `seats`
   (`[{peer_id, index, name}, …]`), `config` and `player_count`, then pushes the
   first state (`session.push_state()`), and republishes lobby metadata
   `status = "in_match"`.

Clients handle `T_START_MATCH` in `LobbyScreen._on_match_started()`: they find
their own `peer_id` in `seats`, learn their `index`, call
`Session.start_online_client(game_id, local_index)`, apply the seed, then ask the
host for the first snapshot via `T_LOBBY_STATE {request_state: true}` (the host
answers with `GameSession.handle_network_message()` → `push_state()`).

`Session.lobby` (`scripts/autoload/game_session_service.gd`) is the shared
context dictionary: `lobby_id`, `visibility`, `max_players`, `game_id`, `mode`
(`"online"` or `"local_test"`), `expansions`.

## 7. Replication and message types

Wire format: UTF-8 JSON dictionaries via `NetProtocol` (`scripts/core/net_protocol.gd`).
Every message is an envelope with `v = VERSION (1)`, `t` = type and `ts`; messages
over `MAX_PACKET_BYTES` (256 KiB) are refused on both send and receive, and
`Net.validate()` rejects malformed, unknown and wrong-version messages before
they reach game code.

| Type | Direction / handler | Purpose |
|------|---------------------|---------|
| `hello` | client → host (`Net._accept_hello`) | Introduce a peer (name, steam_id, protocol, language) |
| `welcome` | host → client (`Net._accept_welcome`) | Seat, host peer id, host name, lobby context |
| `reject` | both (`NetProtocol.reject`) | Indexed reject reason (`Reject` enum), localised via `NetProtocol.reason_key()` |
| `players` | — | Defined; **no send or receive site** at the time of writing |
| `lobby_state` | both (`Net`, `GameSession`, `LobbyScreen`) | Client `ready` flag, or `request_state` to pull a snapshot |
| `start_match` | host → all (`LobbyScreen._on_match_started`) | Seats, seed, config, player count |
| `action` | client → host (`GameSession.handle_remote_action`) | Intended action: `seq`, `player`, `key`, `based_on` |
| `action_result` | host → client (`GameSession.handle_network_message`) | Per-action verdict (`ok`, `reason`, `error_key`) |
| `state` | host → each client (`GameSession._replicate_state`) | `seq`, `game`, `public`, `private`, `legal` — **tailored per peer** |
| `private_state` | — | Accepted by the client handler but never sent; private data travels inside `state` |
| `chat` | peer ↔ peer (`LobbyScreen`) | Test-transport lobby chat only; Steam chat uses `sendLobbyChatMsg` |
| `ping` / `pong` | both (`Net`) | Heartbeat every 2.5 s; `pong` updates `rtt_ms` in the peer entry |
| `resign` | client → host (`GameSession`) | Resignation; host then replicates or finishes the match |
| `match_end` | host → all (`GameSession`) | Final result (`game.common.last_player_standing` for the smoke flow) |
| `bye` | both (`Net`) | Graceful teardown (`closed`, `host_shutdown`) |

Host replication (`GameSession._replicate_state()`): for each connected peer it
builds one payload with the engine's `public_state()`, that peer's
`private_state(player_index)` and — only if that peer is the decision player and
the match is not finished — its `legal_actions()`. State messages larger than
200 000 bytes are logged as a warning.

Client action flow (`GameSession.submit_action_key()` → `handle_remote_action()`):

1. Client increments `action_seq_sent` and sends `T_ACTION` with the local seat.
2. Host validates in order: the peer has a seat (else `NOT_PLAYER`), `seq` is
   newer than the last applied one (duplicates are ignored and answered with the
   current snapshot so the client can resynchronise), `key` is non-empty (else
   `MALFORMED`), the match is not finished (else `MATCH_RUNNING`), it is that
   player's turn (else `OUT_OF_TURN` + `ACTION_RESULT`), and the action is legal
   for the engine (else `ILLEGAL_ACTION`).
3. On success the host replies `ACTION_RESULT {ok: true}`, replicates the new
   state to every peer and emits `state_updated`.

`based_on` is sent by clients but is not currently read by the host; ordering is
enforced by the per-peer `seq` counter.

Hidden information: `private_state(p)` is only ever placed in the payload
addressed to the peer holding seat `p`. Clients ignore any `state` message whose
sender is not the authoritative host (`GameSession._apply_snapshot()` checks
`Net.is_host_peer(from_peer)`). The rules-level guarantee is tested per game with
`EngineHarness.check_privacy()` (see `docs/GAME_ENGINE_CONTRACT.md`).

## 8. Failure and timeout handling

| Condition | Detection | Behaviour | User-visible string (en) |
|-----------|-----------|-----------|--------------------------|
| Steam not ready | `SteamSvc.is_ready()` in `Net.host_steam_lobby` / `join_steam_lobby` | `transport_error` with `steam_join` / `steam_host` | "Steam is not ready yet." |
| Steam init failure | `steamInitEx` status != 0 (`SteamSvc.initialise`) | `State.FAILED`; `OnlineScreen` shows the detail and disables Create/Join | "Steam failed to initialise" / `online.offline_notice` |
| `SteamMultiplayerPeer` missing | `ClassDB.class_exists` in `Net._create_steam_peer` | `transport_error` | "Steam networking is unavailable in this build." |
| `host_with_lobby` / `connect_to_lobby` error | `err != OK` | `transport_error`, link falls back | "The transport could not be created (error {code})." |
| Not the lobby owner | `SteamSvc.is_host()` check | `transport_error` | "You are not the host of this lobby." |
| Already connected | link is `CONNECTED`/`MATCH_RUNNING` | `transport_error` | "A network connection is already active." |
| Peer silent | host-only check every heartbeat; `PEER_TIMEOUT_SEC = 15 s` without traffic | `disconnect_peer(id, false)` + `transport_error` | "Connection to {name} timed out." |
| Transport died | `peer.get_connection_status() == CONNECTION_DISCONNECTED` in `Net._poll_packets()` | Link torn down, `close()`; clients get a notice | "The connection to the host was lost." |
| Client disconnected mid-match | `Net.peer_unregistered` → `GameSession.handle_peer_left()` | Seat is handed to a bot so the match can continue; logged | "{player} left the match and is now played by the AI." |
| Steam leaves READY while in a lobby | `LobbyScreen._on_steam_state` | Warn + leave lobby (test transport unaffected) | "Steam is running but could not be initialised; online play is disabled." |
| Client resigns | `T_RESIGN` → `GameSession._resign_player()` | Seat marked resigned; if ≤1 player remains the match finishes with `game.common.last_player_standing` | "{player} resigned." |

`GameSession.reclaim_player()` exists to hand a bot seat back to a reconnecting
player, but **no caller was found** in `scripts/` at the time of writing; mid-match
reconnection is therefore an API, not a working flow.

## 9. What is verifiable in this environment, and the blocker

Verifiable today:

* The full application protocol: `hello`/`welcome`, seat assignment,
  `host_peer_id` learning, `start_match`, action forwarding with all reject
  reasons, per-peer state replication, resign, match end, `bye`.
* The transport state machine, peer registry, heartbeat, RTT and timeout logic
  (over ENet).
* Local test transport and LAN play.
* The localisation strings and metadata key definitions.
* On the development machine, Steam initialisation to `State.READY`, App ID 480,
  persona and Steam ID, in earlier runs when the Steam client was running. The
  latest attempt had no client, so that path was not re-exercised.

Still unverified here — the two-account Steam path:

* Lobby create/join/leave, `SteamMultiplayerPeer.host_with_lobby()` /
  `connect_to_lobby()`, lobby search filters, metadata round-trip, invites,
  overlay and relay status.
* A match moved over the Steam transport, including hidden-information
  replication; no game action has been sent over Steam.
* `steam_id` values on peers (the ENet path carries 0).

The hard blocker: verification of the Steam path needs **two Steam accounts on
two machines** (or two Steam clients with distinct accounts) with Steam running
and signed in. One account/machine, as available here, cannot complete even the
happy path of lobby join + match start. The automated smoke test deliberately
uses ENet loopback and is **not** a Steam test.

### Automated runs disable Steam

Steamworks teardown can abort a short-lived headless engine process on this
machine (the tests print `PASS` and the process then dies inside
`steamclient.so`), which made scripted runs non-deterministic. Automated
headless phases therefore set `GAMEHUB_DISABLE_STEAM=1` — in
`tests/run_tests.gd`, `tools/screen_smoke.gd` and `tools/net_smoke.gd` via
`_initialize()`, and as an export in `tools/run_boot_smoke.sh`. `SteamSvc`
then reports `State.DISABLED` ("Steam disabled for this automated run.") and
never initialises Steamworks. A normal windowed run leaves the variable unset
and reaches `READY` when a Steam client is running; use that for the manual
checks in §10. Recorded in `docs/KNOWN_ISSUES.md` §1.5.

## 10. Manual verification

Preconditions (both machines): Steam client running and signed in; the
GodotSteam addon present; `steam_appid.txt` containing `480` (written
automatically from `Prefs` `steam/app_id`); build from the same repository state.

1. **Without Steam (negative test).** Launch the game with the Steam client
   closed. Open *Online*. Expected: status chip shows a failure/offline state,
   `online.offline_notice` is displayed, "Create Steam lobby" and "Join" are
   disabled, and the local test panel is still usable.
2. **Host, machine A.** With Steam running, open *Online*; confirm the status row
   shows "Steam is ready", `App 480` and a SteamID, and the relay chip
   (`online.relay_ok` / `online.relay_unknown`). Pick a game, visibility and
   lobby size, press "Create Steam lobby".
3. **Inspect the lobby (host).** The lobby screen header must show transport
   "Steam Networking Sockets (SteamMultiplayerPeer)", the Steam lobby id and
   `lobby.relay`. Check the member list shows the host as seat 1
   (`lobby.members_hint`).
4. **Join, machine B.** On the second account open *Online* → "Refresh list";
   the browser should list the lobby (game/host/`members/max`/status/language,
   editions chip when the game has editions). Press "Join".
5. **Handshake check.** On both machines the lobby member list must show two
   members, the client with seat 2 once `T_WELCOME` has been processed; the media
   session header/link state should reach `CONNECTED`.
6. **Chat and ready.** Exchange lobby chat both ways (Steam lobby chat); toggle
   "I am ready" and verify it appears on the host.
7. **Start a match.** Host presses "Start match"; both machines must open the
   game screen, the client must receive `T_START_MATCH` with its seat, and moves
   must be relayed through the host. On a hidden-information game verify the
   client sees only its own private state (e.g. its hand) and never the host's.
8. **Invites and overlay.** With a lobby open, use "Invite through Steam
   overlay" and the friends list; the invitee should see the invitation dialog
   (`online.invite_title` / `online.invite_body`) and join via the overlay.
9. **Failure paths.** Stop the Steam client on one machine mid-lobby → the other
   should leave/log the state change. Kill the host process mid-match → the
   client should show the link-lost notice. Let a peer stay silent longer than
   15 s → the host should time the peer out.
10. **Evidence.** Use *Diagnostics* (Steam state, App ID, SteamID, relay, network
    stats) and "Export log file" / "Copy report" on both machines, and attach
    both logs to the verification note.

<!-- TODO(verify): record the outcome of steps 1-10 in the verification status table above; include whether host_with_lobby/connect_to_lobby work against App 480 and whether any lobby metadata key needs to be renamed for Steam's data limits. -->

## 11. Open items

* `tools/fetch_godotsteam.sh` now exists (added 2026-10-19): it downloads the
  pinned GodotSteam v4.23.1 GDExtension archive from the upstream Codeberg
  release, verifies its SHA-256 and extracts it into `addons/`.
* `steam.key_note` ("Lobby metadata published for verification: {key}.") exists in
  `data/i18n/en.json` but is not referenced by any script.
* `KEY_TRANSPORT` is defined but never published.
* `T_PLAYERS` and `T_PRIVATE_STATE` are defined but unused (private data travels
  inside `T_STATE`).
* Mid-match reconnection (`GameSession.reclaim_player()`) has no caller yet.
