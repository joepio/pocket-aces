# Pocket Aces

Texas Hold'em in a warm 3D saloon. The shared screen shows a 3D table;
each player uses a phone or tablet for their private cards and betting.
Two to six seats, no real money, no purchases.

## Play

Join a GameNight room, link your profile to your seat in the lobby, then select Pocket Aces. Open GameNight's
Game tab on your phone. The host opens the bundled companion page for your
linked profile. The TV shows the room QR and each seat's connection/readiness.
Every human taps **Ready** on their phone before the first hand is dealt. House
bots are ready automatically. Disconnecting before the deal resets that seat's
Ready status; reconnecting during a hand pauses/resumes the same hand and clock.
You don't enter a player number or open a separate game server.

- Each hand starts with two private cards and small/big blinds of 10/20.
- Your phone keeps those cards face down. Tap the cards to look, then tap again
  to hide them. A new hand, refresh, reconnect, pause or leaving the page hides
  them automatically. Hiding still works while a betting action is pending.
- Fold, check, call or raise using your phone. **Raise to** means your total
  contribution on this betting street, not the extra chips you add.
- The flop, turn and river appear on the table. Best five-card hand wins.
- All-ins, side pots, ties, odd chips and short raises are supported. A short
  all-in only reopens betting if accumulated raises reach a full minimum raise.
- Showdown reveals remaining hands on the TV. Folded hands and uncontested
  winners' cards stay hidden. Phones only receive their owner's hole cards.
- A new hand starts after ten seconds. The dealer rotates. Busted players get
  1,000 free chips, so everybody can keep playing.
- A disconnected phone pauses betting and the turn clock until it reconnects.
- After 45 seconds without an action from a connected player, the player checks if possible, otherwise
  folds. No bot spends an absent human's chips. AI seats have modest house bots.

Blinds (next hand), starting chips (next session) and turn time are exposed
through GameNight's `declare_settings`, so the assistant can discover them.
Back/F1 uses the shared SDK's lobby handling. Pause freezes timers and rejects
betting until Resume. The game reports a finished hand without changing games.

## Run locally

Godot 4.5 or newer, GL Compatibility. From this directory:

```sh
godot --path .                     # four bots, no host needed
godot --headless --path . --script res://tests/rules.gd
godot --headless --path . --script res://tests/readiness.gd
```

For a real room, register a **local shelf** entry with the current host. This is
the native protocol library format, separate from `gamenight.json` store metadata:

```json
[
  {
    "id": "pocket-aces",
    "title": "Pocket Aces",
    "min_players": 2,
    "max_players": 6,
    "launch": {
      "command": "/absolute/path/to/godot",
      "args": ["--path", "/absolute/path/to/pocket-aces"],
      "cwd": "/absolute/path/to/pocket-aces"
    }
  }
]
```

Use absolute Windows paths for a Windows host. Set `GAMENIGHT_LIBRARY` to that
JSON file and enable the host's companion relay (`GAMENIGHT_WEB=1` on the tested
host revision). The launch handshake, seats and phone identity come from the
host. A lone local player gets one house bot. Roster changes take effect on a
fresh game session; a departure during a hand pauses the table. Return to the lobby to change seats.

This game uses the companion API currently on public GameNight `main`, pinned
in `sdk-source.json`. It does not depend on the older local checkout's unmerged
hosted-only web migration. That migration still needs a companion relay decision
before these phone screens can work through it.

## Integration and privacy

`main.gd` uses the real Godot SDK: `declare_companion`, `companion_presence`,
`companion_message`, `send_companion_message`, and the prepare/start/pause/
resume/dispose lifecycle. It extracts only `phone/` into a writable real folder
for the host to serve, including from an exported PCK.

`setup_ui.gd` shows public join information supplied by the host's local
`/api/player-links` endpoint (`GAMENIGHT_LINKS_URL` overrides the loopback base).
It never creates its own join token or embeds a private profile URL in the QR.
`table_visuals.gd` draws the shared saloon from public game state only.

`rules.gd` owns the deck, hands, turn and chips. It validates the sender supplied
by GameNight, the state revision, whole-chip amounts and legal actions. Client
supplied player IDs are ignored. Duplicate taps and delayed actions cannot
apply to another turn. `private_view(id)` contains just that seat's hole cards;
`public_view()` withholds hands until a contested showdown. No game state,
decks or private cards are written to disk or logged.

The host is trusted. The current companion relay identifies phones through the
existing profile URL capability on the LAN. Do not share a private hand URL,
and do not treat the LAN relay as an internet gambling service. The game does
not add authentication or replace the host's identity boundary.

## Validate with the actual host

The TV setup screen can link a scanned phone without returning to the lobby.
Scan the room QR, then use left/right and A on your own controller to pick your
profile. The game uses GameNight's canonical seat/controller frames and the
loopback pickup endpoint. Mouse clicks cannot choose a controller for you.
After linking, open Pocket Aces on the phone and tap Ready. Linking a profile
alone does not connect the companion: the phone must open the game's private
companion screen. The host supplies that route; the TV never displays private
phone URLs or cards. All human phones must be connected and ready before dealing.
The same pickup selector is available during a phone reconnection pause.

Build `gamenight-daemon` and `gamenight-local-web` from the revision in
`sdk-source.json`. Install Python `websockets` (15.0.1 tested), then run:

```sh
python tests/integration.py \
  --daemon /path/to/gamenight-daemon \
  --web /path/to/gamenight-local-web \
  --godot /path/to/godot
```

The test uses ports 18112/18113, disposable profiles and temporary host storage.
It checks the ready gate, reset on disconnect before dealing, a paused clock
during a mid-hand disconnect, two distinct private hands, unlinked-phone rejection, a spoofed sender,
an illegal raise, paused input/timers, a full showdown, chip conservation, the next
hand and reconnect. The test cleans up its own processes.

Add `--serve --visible` to leave that disposable test table running for an hour.
When testing on Windows with a WSL host, add `--windows-game` and pass the Windows
Godot executable via its `/mnt/c/...` path. The harness uses the native GPU and
sets `POCKET_ACES_COMPANION_ROOT` to the host-visible source phone folder. This
development override is unnecessary when host and game run on the same OS.
If Windows only forwards WSL ports to loopback, run `node tests/lan-proxy.cjs`
on Windows to expose this disposable relay on LAN port 18114. Give each tester
only their own fixture URL, with the host/port changed to the Windows LAN address
and 18114. Stop the proxy after testing. This is test tooling, not a shipped server.
Its two private phone links are in `/tmp/pocket-aces-fixture.json`; don't publish
them. Stop the test with Ctrl+C. `--phone-test` also runs `tests/phone.cjs` with
Playwright installed and Chromium available. Set `NODE_PATH` if installed outside
this directory. Screenshots go to `--screenshots DIR`. The browser test checks
touch raise/fold, results, refresh, socket reconnect and mobile overflow.

Rules tests cover hand ranking, kickers, wheel straights, heads-up order,
short/cumulative raises, side pots, odd chips and 400 seeded complete hands.
`POCKET_ACES_DEMO=1` provides a reproducible four-seat flop for visual review;
`POCKET_ACES_CAPTURE=/absolute/path.png` captures the rendered viewport.

## Publishing status

Public source repository: [joepio/pocket-aces](https://github.com/joepio/pocket-aces).
Not yet a published GameNight store release or certified game.
`gamenight.json` is candidate metadata. Publishing still needs native export
packages, a real gameplay montage and platform/controller acceptance. Keep the
`phone/*.html`, `phone/*.css` and `phone/*.js` resources in exported packages
(Godot export include filter: `*.html,*.css,*.js`). No fabricated artwork/video
or certification score is supplied.

Validated locally: 7,341 rule assertions / 400 complete hands; actual host and
companion relay with headless Linux and native Windows Godot; two mobile-size
browser clients over the LAN bridge; Windows release export and startup.
Physical phone browsers, macOS export and a deployed store release are not yet
validated. The ready gate and reconnection checks also run in CI. Local validation covers
Linux and native Windows Godot 4.5.2 with the real host, plus two mobile browser
clients and setup layouts at 320, 390 and 540 pixels.
