# Pocket Aces

Texas Hold'em on a moonlit rooftop. The shared screen shows a 3D table;
each player uses a phone or tablet for their private cards and betting.
Two to six seats, no real money, no purchases.

## Play

Join a GameNight room, take a seat, then select Pocket Aces. Open GameNight's
Game tab on your phone. The host opens the bundled companion page for your
linked profile. You don't enter a player number or open a separate game server.

- Each hand starts with two private cards and small/big blinds of 10/20.
- Fold, check, call or raise using your phone. **Raise to** means your total
  contribution on this betting street, not the extra chips you add.
- The flop, turn and river appear on the table. Best five-card hand wins.
- All-ins, side pots, ties, odd chips and short raises are supported. A short
  all-in only reopens betting if accumulated raises reach a full minimum raise.
- Showdown reveals remaining hands on the TV. Folded hands and uncontested
  winners' cards stay hidden. Phones only receive their owner's hole cards.
- A new hand starts after ten seconds. The dealer rotates. Busted players get
  1,000 free chips, so everybody can keep playing.
- After 45 seconds without an action, the player checks if possible, otherwise
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
      "args": ["--path", "/absolute/path/to/gamenight-games/pocket-aces"],
      "cwd": "/absolute/path/to/gamenight-games/pocket-aces"
    }
  }
]
```

Use absolute Windows paths for a Windows host. Set `GAMENIGHT_LIBRARY` to that
JSON file and enable the host's companion relay (`GAMENIGHT_WEB=1` on the tested
host revision). The launch handshake, seats and phone identity come from the
host. A lone local player gets one house bot. Roster changes take effect on a
fresh game session; a departure during a hand uses the safe timeout above.

This game uses the companion API currently on public GameNight `main`, pinned
in `sdk-source.json`. It does not depend on the older local checkout's unmerged
hosted-only web migration. That migration still needs a companion relay decision
before these phone screens can work through it.

## Integration and privacy

`main.gd` uses the real Godot SDK: `declare_companion`, `companion_presence`,
`companion_message`, `send_companion_message`, and the prepare/start/pause/
resume/dispose lifecycle. It extracts only `phone/` into a writable real folder
for the host to serve, including from an exported PCK.

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

Build `gamenight-daemon` and `gamenight-local-web` from the revision in
`sdk-source.json`. Install Python `websockets` (15.0.1 tested), then run:

```sh
python tests/integration.py \
  --daemon /path/to/gamenight-daemon \
  --web /path/to/gamenight-local-web \
  --godot /path/to/godot
```

The test uses ports 18112/18113, disposable profiles and temporary host storage.
It checks two distinct private hands, unlinked-phone rejection, a spoofed sender,
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

Playable local source, not a published store release or certified game.
`gamenight.json` is candidate metadata. Publishing still needs native export
packages, a real gameplay montage and platform/controller acceptance. Keep the
`phone/*.html`, `phone/*.css` and `phone/*.js` resources in exported packages
(Godot export include filter: `*.html,*.css,*.js`). No fabricated artwork/video
or certification score is supplied.

Validated locally: 7,341 rule assertions / 400 complete hands; actual host and
companion relay with headless Linux and native Windows Godot; two mobile-size
browser clients over the LAN bridge; Windows release export and startup.
Physical phone browsers, macOS export and a deployed store release are not yet
validated. The CI workflow is added but has not run remotely on this branch.
