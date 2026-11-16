# Project state

Last updated: 2026-11-15

## What exists

**The real forging system is built** (`src/forging/`), made from three of the four prototypes. It is the project's main scene: press F5 in the editor, or from the repo root run
`"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path .`

### The forge (`src/forging/forge.tscn`)

- A forge job is three stages in order: **Blade Trace**, then **Anvil Song**, then **One Heat**. Each scores 0 to 100; the job score is their weighted average (equal weights).
- **Ready screen:** choose an item (A / D or left stick), see its gear level against your smithing level, the difficulty, and every quality tier with what still locks it. Space / A starts.
- **Quality tiers** (Crude 0, Fine 40, Superior 60, Masterwork 78, Legendary 96) are **locked** behind smithing level, quests, and per-item blueprints. The score earns a tier, then the award stops at the first locked tier. A capped result says what you earned and what unlocks the next tier.
- **Difficulty:** gear above your smithing level is harder (15% per level, up to five levels). Gear below your level gets easier (6% per level) only after **mastery** is unlocked (smithing level 3 and the quest "The anvil's first lesson").
- **One Heat has the most polish:** the bar glows with its heat and pulses when ready to strike, strikes build a streak with a rising clang, impact rings and sparks, embers from the fire, a "TOO HOT" warning before scorching, a red ticking timer for the last seconds, and remarks from the anvil while you work.
- Controls: Space / gamepad A is the main button, F / gamepad X the second button, WASD / left stick moves.
- Three recipes to try: Copper Dagger (gear level 1), Iron Sword (3), Silver Pickaxe (5).
- The result is announced on `EventBus.item_forged`.

### Code map

| Path | What it is |
| --- | --- |
| `src/core/game_state.gd` | `GameState` autoload: day, time, inventory, coin, reputation, relationships, smithing level, finished quests, blueprints, `reset()`, `debug_state_text()` |
| `src/core/event_bus.gd` | `EventBus` autoload: `item_forged`, `day_ended` |
| `src/core/json_data.gd` | Loads the JSON files in `data/` |
| `src/forging/forge_rules.gd` | The rules with no screen: tier cutoffs, tier locks, difficulty, score averaging. Pure logic, fully tested |
| `src/forging/forge.gd`, `forge.tscn` | The forge screen: runs the three stages, shows locks and the result. Has `debug_state_text()` |
| `src/forging/stages/*.gd` | The three stages |
| `src/forging/forge_stage.gd`, `forge_canvas.gd`, `forge_audio.gd` | Shared stage base, placeholder drawing, placeholder sounds |

### Tuning

Every cutoff, lock, requirement, difficulty step, stage timing and line of text is in JSON under `data/`. `data/README.md` explains every key.

To try the locks before quests and levelling exist, edit `smithing_level`, `completed_quests` and `blueprints` in `data/game_start.json`.

### Tests

gdUnit4 6.2.2 is installed in `addons/gdUnit4/`. 30 tests pass:
- `tests/unit/forging/forging_tier_locks_test.gd`: tier cutoffs, tier locks, difficulty (fixed test data).
- `tests/integration/forging/forging_data_test.gd`: checks the real `data/` files still keep the design's promises (for example, a new player with a perfect score cannot make Legendary).

Run them (from the repo root):
```
"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

### Automated checks of the forge

- Bot playthrough: add `--headless --fixed-fps 60 res://src/forging/forge.tscn -- --autoplay`. It plays a full job, prints the state at each step, and quits.
- Set up the player for a run: `--recipe=<id> --smithing-level=<n> --quests=<id,id> --blueprints=<id,id>` (after `--`).
- Screenshots: `--capture-dir=<folder>` (windowed, not headless). The current set is in `production/qa/evidence/forging-system/` (`locked/` = new player, capped at Crude; `unlocked/` = level 10 with everything, Legendary).

### Prototypes

The four forging prototypes are still in `prototypes/` for reference. The game does not use their code. `forge_four_stage` was not carried forward.

## What's next

1. Marcel plays the real forge and tunes it in `data/`.
2. Decide the open questions below.
3. Build order step 2, the rest of the core project: save system, and smithing experience (so the smithing level can rise in play).
4. Build order step 3: Shop scene.

## Open design questions (for Marcel)

- **Lock values are placeholders.** The smithing levels, quest names and blueprint rules per tier are a first guess (`data/forging_tiers.json`). The quests named there do not exist yet.
- **A new player can only make Crude.** Fine needs smithing level 2. Is that the start you want, or should Fine be open from level 1?
- **Job length.** Three stages take about 75 to 90 seconds, longer than the brief's old 30 to 60. The Anvil Song was cut to two phrases (Hammer, Quench) to keep it down.
- **Stage weights** are equal. One Heat could count for more.
- **How smithing level rises** is not built. Nothing grants smithing experience yet.
- **One outline for every item.** Blade Trace traces the dagger shape for all three recipes.
- **Mastery wording.** "Difficulty scaling by smithing level unlocks after set requirements" was built as: gear below your level gets easier only after mastery unlocks. Gear above your level is always harder.

## Known issues

- No human has played the real forge yet. A bot completes it; feel, difficulty and real gamepad input are untested.
- The bot plays perfectly, so only capped-at-Crude and Legendary results have been seen on screen. The tiers in between are covered by tests, not by a played run.
- Placeholder sounds are generated tones. Nobody has listened to them.
- The Anvil Song timer follows frame time, not the audio clock. Fine for now, not for a final rhythm game.
- Blade Trace is hard to play precisely on a keyboard (WASD is all-or-nothing). It is meant for a stick.
- Not tested in a web export. The JSON files are read with `FileAccess`; check they are included when the export is set up (build order step 4).
- The "Web" export preset named in `project.yaml` (`commands.build`) does not exist yet.
