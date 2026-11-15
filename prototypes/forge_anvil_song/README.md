# Forge prototype 3: Anvil Song

PROTOTYPE - NOT FOR PRODUCTION

- **Question:** Does forging feel best as pure rhythm, with the four stages as four phrases of one short song and no pauses between them?
- **Design source:** `design/game-brief.md`, "Forging". Keeps the four stage names and per-stage scores; replaces each stage's own mechanic with on-beat presses.
- **Status:** in progress (waiting for Marcel's play-test).

## How to run

- Editor: open `forge_anvil_song.tscn`, press F6.
- Command line (from the repo root):
  `"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . res://prototypes/forge_anvil_song/forge_anvil_song.tscn`
- Bot playthrough for checks: add `--headless --fixed-fps 60` before the scene and `-- --autoplay` after it.

## Controls

Top lane: F / gamepad X (bellows). Bottom lane: Space / gamepad A (hammer). Long notes: hold, then release when the end of the bar reaches the ring.

## Notes

- Play with sound on. The beat tick and the hit clang are generated in code (no audio files).
- The song timer runs on frame time, not the audio clock. Good enough to judge the idea; a real version would sync to audio.
- The whole chart (which beat, which button, how long) is in `forge_anvil_song.json` under `phrases`, next to the tempo and timing windows.

## Findings

None yet.
