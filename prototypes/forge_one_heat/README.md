# Forge prototype 2: One Heat

PROTOTYPE - NOT FOR PRODUCTION

- **Question:** Is forging more fun as one continuous juggling act (fire and anvil on one screen, two buttons) than as four separate stages?
- **Design source:** `design/game-brief.md`, "Forging". This take merges Heat and Hammer and drops Quench and Finish as separate stages.
- **Status:** in progress (waiting for Marcel's play-test).

## How to run

- Editor: open `forge_one_heat.tscn`, press F6.
- Command line (from the repo root):
  `"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . res://prototypes/forge_one_heat/forge_one_heat.tscn`
- Bot playthrough for checks: add `--headless --fixed-fps 60` before the scene and `-- --autoplay` after it.

## Controls

Hold F / gamepad X to keep the bar in the fire. Let go to bring it to the anvil. Space / gamepad A to strike.

## Rules

Each strike scores by how close the bar's heat is to the sweet spot. Each strike cools the bar. Leaving the bar in the fire too long scorches it, which wastes a strike. 24 strikes in 36 seconds; strikes you never land score zero.

## Tuning

Everything is in `forge_one_heat.json`.

## Findings

None yet.
