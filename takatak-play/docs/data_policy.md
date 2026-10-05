# Data policy

The proposal promises **no recording, no identity, anonymous counts only**. This page
says what that means for the code and for anyone collecting data.

## On the kit (field build)

- The camera sees body points and shapes. Frames are processed in memory and dropped.
  Nothing writes a frame, a mask, audio or keypoints to disk.
- No network. The game talks only to the local vision service (`ws://127.0.0.1:8765`).
  Wi-Fi is off in the field image.
- Voice temp files (echo games, Phase P5) live in `/run/takatak`, which is RAM (tmpfs).
  They are deleted after playback and are gone after a reboot.
- No child names. The Phase 2 name-clip feature is off in field builds.
- Usage counters only (`/var/lib/takatak/usage/YYYY-MM.json`): sessions, minutes,
  rounds and successful rounds per game, movement minutes, uptime and faults, per day.
  Nothing is stored per child. "Successes" count rounds, not children.
- The supervisor can export the counters to a USB stick as CSV. Nothing else leaves the box.
- Field packages (`tools/make_field_build.py`) contain no recording tools at all.
  `tools/tests/test_privacy.py` checks this on every test run.

## Training data for custom models (local objects, Marathi words)

- **Never use images or audio of children from sessions.** The kit cannot record them,
  and no one may record them some other way for training.
- Object photos: real items and printed picture cards **held by adults**, on
  anganwadi-like backgrounds (floor mats, walls, mixed daylight).
- Keyword audio: **adult** volunteers (team members, family) who have agreed in writing.
  Approximate children's voices with pitch and speed augmentation.
- Keep calibration images (for the Hailo compiler) separate from training images. Keep the
  held-out test set in a different room from both.
- Training data stays on the team's machines. Don't commit it to git and don't upload it
  to third-party services without a written decision.

## Dev builds

`TAKATAK_BUILD=dev` in a source checkout unlocks `record_session.py` (keypoints only, or
frames with `--with-frames --i-have-consent`) and `record_clip.py`. Use them only with
yourself or consenting adult testers, never at an anganwadi. The output goes to `logs/`,
which git ignores.
