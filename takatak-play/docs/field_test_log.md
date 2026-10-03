# Field-test log

Copy one block per session. The game writes the matching stats JSON to
`logs/stats/session_<time>.json`. No images are ever saved.

## Milestones

- [ ] M0 Hardware bring-up: both cameras preview; `hailortcli` identifies Hailo-8
- [ ] M1 `./run.sh debug`: fullscreen mirrored feed on TV, skeleton + indices, fps ≥ 20, `C` switches camera
- [ ] M2 `./run.sh text`: Devanagari shaped correctly on TV; clips play over HDMI
- [ ] M3 `./run.sh test` passes; debug overlay shows checks live
- [ ] M4 Full ATTRACT → FINISH flow, 10 rounds, keys work
- [ ] M5 TV, lit room, Wide: adult ≥ 9/10 correct; child session recorded in stats
- [ ] M6 Projector, dark room, NoIR + IR: playable; note detection rate vs Wide
- [ ] M7 Tolerances tuned from field data; real voice clips swapped in

## Session template

```
Date / time:
Room (lit / dark), screen (TV / projector):
Camera (wide / noir), IR on?:
Distance from camera (m):
Child age / tester:
Difficulty, language mode:
Rounds played / successes:
False triggers (prompt, what they were doing):
Missed detections (prompt, what they were doing):
What confused the child:
fps from logs/perf.log (cam / inf / ui, latency):
Notes / tolerance changes made:
Stats file:
```
