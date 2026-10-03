# Field-test log

The game writes stats to `user://stats/session_<time>.json` (on the Pi:
`~/.local/share/godot/app_userdata/Takatak Play/stats/`). No images or audio
are ever saved.

## Phase 2 milestones

- [ ] P0 `./run.sh debug` works on the Pi; `./run.sh test` passes
- [ ] P1 `./run.sh vision` sends hello/pose/gesture/status + JPEG; `./run.sh record` and `mock --replay` work
- [ ] P2 Godot shows the mirrored feed full-screen at ≥ 25 fps on the TV, reconnects when vision restarts, and `--deva-test` renders correctly
- [ ] P3 Hand sparkles follow hands (< 150 ms lag); the mascot idles, cheers and talks; voice ducks music
- [ ] P4 Full Simon Says: praise variants, mascot demo on timeout, pause/callback when the child leaves
- [ ] Field test after P4 (with parent consent)

## Session template

```
Date / time:
Room (lit / dark), screen (TV / projector):
Camera (wide / noir), IR on?:
Distance from camera (m):
Child age / tester:
Difficulty, language mode, primary language:
Rounds played / successes:
Timeouts per prompt:
False triggers (prompt, what they were doing):
Prompts that confused the child:
How long attention lasted:
fps / temp from the D overlay (game, feed, vision):
Notes / tolerance changes made:
Stats file:
```
