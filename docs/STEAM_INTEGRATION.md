# Steam integration

This build targets itch.io and does **not** ship Steamworks.

* The `godotsteam` addon has been removed; `ClassDB` no longer exposes
  `SteamMultiplayerPeer`, so the Steam transport in `Net` reports unavailable.
* `SteamSvc` (autoload) is kept as a disabled stub so the rest of the
  application and the test runner continue to work; it always reports
  `DISABLED` and never initialises Steamworks.
* Online play is provided only through the local ENet test transport, which is
  always labelled *not Steam* in the UI.
* `steam_appid.txt` is not generated or shipped.
* If a Steam build is ever needed again, restore the addon and revert
  `scripts/autoload/steam_service.gd` to its previous implementation.