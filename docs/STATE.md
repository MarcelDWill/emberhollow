# Project state

Last updated: 2026-11-15

## What exists

**Build order step 1 (forging prototypes) is built and waiting for Marcel's play-test.** Nothing of the main game exists yet.

Four standalone forging prototypes, each in its own folder under `prototypes/` with a scene, a script, a tuning JSON, and a README:

| # | Folder | Idea | Main skill | Buttons |
| --- | --- | --- | --- | --- |
| 1 | `prototypes/forge_four_stage/` | The brief's four stages back to back (Heat, Hammer, Quench, Finish) | A different skill per stage | Space/A, then WASD/stick |
| 2 | `prototypes/forge_one_heat/` | One screen: heat the bar, strike while it is in the sweet band, decide when to reheat | Judgement under time pressure | Hold F/X, tap Space/A |
| 3 | `prototypes/forge_anvil_song/` | Rhythm game: the four stages are four phrases of one song | Rhythm | F/X and Space/A |
| 4 | `prototypes/forge_blade_trace/` | Trace the dagger's outline with a weighted hammer, strike at each ring | Steadiness | WASD/stick and Space/A |

How to run one: open its `.tscn` in the Godot editor and press F6, or from the repo root:
`"C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . res://prototypes/<name>/<name>.tscn`

Shared by all four:
- Ends with a 0 to 100 score, a quality tier, and one anvil quip. Space / A retries.
- All tuning (timings, windows, tier cutoffs, anvil lines, on-screen text) is in the prototype's JSON.
- `debug_state_text()` returns the state as JSON.
- Bot check: `--headless --fixed-fps 60 <scene> -- --autoplay` plays a full forge, prints the state, and quits.

Also added:
- Input Map actions in `project.godot`: `p1_forge_primary` (Space, gamepad A), `p1_forge_secondary` (F, gamepad X), `p1_move_left/right/up/down` (WASD, left stick).
- Screenshots of every prototype in `production/qa/evidence/forge-proto-*.png`.

## What's next

1. Marcel plays all four and picks one (or a mix). Record what he found in each prototype's README under "Findings".
2. Answer the open design questions below.
3. Build order step 2: core project (GameState and EventBus autoloads, text state dump, save system).

## Open design questions (for Marcel)

- Tier cutoffs. The brief names the five tiers but not the scores. Prototypes use Crude 0, Fine 40, Superior 60, Masterwork 78, Legendary 92.
- Second forge button. The brief only names Space / A. Prototypes 2 and 3 use F / gamepad X as the second button.
- Rune slot in Finish ("optional rune slot" in the brief) is not in any prototype.
- Difficulty by smithing level (pillar 1) is not in any prototype. Every value that would scale is already in JSON.

## Known issues

- No human has played these yet. Feel, difficulty, and gamepad input are untested; only a bot has played them.
- The bot always plays near-perfectly, so the Legendary result is the one seen in every bot run. The lower tiers use the same code path and were seen once (Crude) during development.
- Prototype 3's song timer follows frame time, not the audio clock. Fine for judging the idea, not for a final rhythm game.
- Prototype 4 is hard to play precisely on a keyboard (WASD is all-or-nothing). It is meant for a stick.
- Not tested in a web export. The JSON files are read with `FileAccess`; check they are included when the export is set up (build order step 4).
- No main scene is set, on purpose. Always run a scene by path.
