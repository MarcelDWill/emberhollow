# Forge prototype 1: Four Stages

PROTOTYPE - NOT FOR PRODUCTION

- **Question:** Does the brief's four-stage forge (Heat, Hammer, Quench, Finish) feel good as four separate little games played back to back?
- **Design source:** `design/game-brief.md`, "Forging".
- **Status:** in progress (waiting for Marcel's play-test).

## How to run

- Editor: open `forge_four_stage.tscn`, press F6.
- Command line (from the repo root):
  `"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . res://prototypes/forge_four_stage/forge_four_stage.tscn`
- Bot playthrough for checks: add `--headless --fixed-fps 60` before the scene and `-- --autoplay` after it.

## Controls

Space / gamepad A for stages 1 to 3. WASD / left stick for stage 4.

## Tuning

Everything (timings, windows, tier cutoffs, anvil lines, on-screen text) is in `forge_four_stage.json`.

## Findings

None yet.
