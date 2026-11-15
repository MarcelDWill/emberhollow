# Forge prototype 4: Blade Trace

PROTOTYPE - NOT FOR PRODUCTION

- **Question:** Does forging feel best as drawing the item's shape with a steady hand, at the player's own pace, instead of reacting to timers?
- **Design source:** `design/game-brief.md`, "Forging". This take grows the brief's Finish stage ("grind along a path", steadiness) into the whole minigame and folds the hammer strikes into it.
- **Status:** in progress (waiting for Marcel's play-test).

## How to run

- Editor: open `forge_blade_trace.tscn`, press F6.
- Command line (from the repo root):
  `"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . res://prototypes/forge_blade_trace/forge_blade_trace.tscn`
- Bot playthrough for checks: add `--headless --fixed-fps 60` before the scene and `-- --autoplay` after it.

## Controls

WASD / left stick moves the hammer. Space / gamepad A strikes when the hammer is on a ring. Best with a gamepad stick.

## Rules

Score = 60% line accuracy + 40% strike accuracy, minus 2 points per second over the 30-second par. The run ends at the last ring, or at 50 seconds.

## Tuning

Everything is in `forge_blade_trace.json`, including the outline itself (`trace.points`) and which corners are strike rings (`trace.strike_points`).

## Findings

None yet.
