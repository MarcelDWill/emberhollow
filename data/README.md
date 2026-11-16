# Tuning data

Every number and line of text the forge uses lives in these JSON files. Change a value, save, and run the game again; no code changes are needed. Design source: `design/game-brief.md`, "Forging".

Rules for all files: keys are `snake_case`, files must stay valid JSON (no comments, no trailing commas), and ids used in one file must match the ids in the others. Run the tests after editing (`tests/README.md`); they fail if an edit breaks a design promise, such as a new player being able to forge a Legendary item.

## `forging_tiers.json`: quality tiers and their locks

`tiers` is a list, lowest tier first. For each tier:

| Key | Meaning |
| --- | --- |
| `id` | Tier id. Its display name is in `forging_text.json` under `tiers`. |
| `min_score` | Lowest job score (0 to 100) that earns this tier. |
| `requires.smithing_level` | Smithing level the player needs to make this tier. |
| `requires.quests` | Quest ids that must all be finished. `[]` for none. |
| `requires.recipe_blueprint` | `true` if the player must own this item's blueprint for this tier (the id comes from the recipe's `tier_blueprints`). |

How a result is decided: the score earns a tier by `min_score`. The award then climbs from the lowest tier and stops at the first tier the player has not unlocked. A locked tier therefore also blocks every tier above it.

## `forging_difficulty.json`: how hard a job is

The difficulty factor starts at 1.0. Above 1.0 is harder, below is easier.

| Key | Meaning |
| --- | --- |
| `over_level.factor_per_level` | Added to the factor for each level the gear is above the player's smithing level (0.15 = 15% harder per level). |
| `over_level.max_levels` | Levels above the player that count. Further levels add nothing. |
| `mastery.requires` | What unlocks "mastery" (gear below the player's level getting easier): `smithing_level`, `quests`, `blueprints`. |
| `mastery.factor_per_level` | Taken off the factor for each level the gear is below the player, once mastery is unlocked. |
| `mastery.max_levels` | Levels below the player that count. |
| `min_factor`, `max_factor` | The factor never leaves this range. |

What the factor does to each stage is set per stage in `forging_stages.json` (`difficulty_scaling`).

## `forging_recipes.json`: what can be forged

| Key | Meaning |
| --- | --- |
| `id` | Recipe id. Its display name is in `forging_text.json` under `recipes`. |
| `gear_level` | Compared with the player's smithing level to set difficulty. |
| `tier_blueprints` | Tier id to the blueprint id that unlocks that tier for this item. A tier that needs a blueprint stays locked for a recipe that lists none. |

All recipes currently trace the same outline (the dagger) in Blade Trace.

## `forging_stages.json`: the three stages

| Key | Meaning |
| --- | --- |
| `order` | The stages of a forge job, in play order. |
| `flow.intro_seconds` | How long each stage's title card shows. |
| `flow.stage_done_seconds` | How long each stage's score shows. |
| `ratings` | Per-hit ratings, best first: a hit scoring at least `min_score` gets that rating. |
| `juice` | Feedback: `strong_min_score` (hits at or above this get the brighter feedback and count toward a One Heat streak), spark count, speed (pixels per second), gravity and lifetime, screen shake in pixels and how fast it fades, and how long pop-up text stays. |
| `sounds` | Placeholder tones: pitch in `hz`, length in `seconds`, and `volume_db`. |
| `stages.<id>.weight` | How much the stage counts in the job score. Equal weights give a plain average. |
| `stages.<id>.difficulty_scaling` | Keys in `divide` are divided by the difficulty factor (they shrink when harder); keys in `multiply` are multiplied by it. |

`stages.blade_trace` (distances in pixels, on a 1152 x 648 screen):

| Key | Meaning |
| --- | --- |
| `points` | The outline to trace, as `[x, y]` corners in order. |
| `strike_points` | Which corners (counting from 0) have a strike ring. |
| `max_speed`, `acceleration` | Hammer top speed (pixels per second) and how fast it speeds up and slows down. Lower acceleration feels heavier. |
| `perfect_radius`, `miss_radius` | Tracing within `perfect_radius` of the line scores 100, falling to 0 at `miss_radius`. |
| `off_radius` | Further than this from the line, tracing does not advance. |
| `look_ahead` | How far ahead along the line the hammer may pull the trace. |
| `strike_perfect_radius`, `strike_miss_radius` | Same as the line radii, for the distance to a ring when striking. |
| `par_seconds`, `late_penalty_per_second` | Points lost per second past par. |
| `time_limit_seconds` | The stage ends here whatever is left. |
| `path_weight`, `strike_weight` | Shares of line accuracy and strike accuracy in the stage score. They should add up to 1. |

`stages.anvil_song`:

| Key | Meaning |
| --- | --- |
| `bpm` | Song speed in beats per minute. |
| `lead_in_beats`, `outro_beats` | Empty beats before the first note and after the last. |
| `scroll_pixels_per_beat` | How fast notes slide. |
| `perfect_window_seconds`, `miss_window_seconds` | A press within the perfect window scores 100, falling to 0 at the miss window. |
| `phrases` | The chart. Each phrase has an `id` (name in `forging_text.json`), a length in `beats`, and `notes`: `beat` within the phrase, `button` (`primary` = Space / A, `secondary` = F / X), and optional `hold_beats` for a long note. |

`stages.one_heat` (heat runs from 0 = cold to 1 = white-hot):

| Key | Meaning |
| --- | --- |
| `time_limit_seconds`, `strikes_needed` | The stage ends at the time limit or after this many strikes. The score is the average over `strikes_needed`, so strikes not made count as 0. |
| `start_heat` | Heat of the bar at the start. |
| `fire_heat_per_second`, `fire_roar_per_second` | Heating speed in the fire, and how much it speeds up for each second the bar stays in. |
| `cool_per_second`, `strike_cool` | Heat lost per second out of the fire, and per strike. |
| `strike_cooldown_seconds` | Shortest gap between strikes. |
| `move_seconds` | Time for the bar to travel between fire and anvil. |
| `sweet_heat`, `perfect_window`, `miss_window` | A strike within `perfect_window` of `sweet_heat` scores 100, falling to 0 at `miss_window`. |
| `burn_heat`, `burn_reset_heat` | At `burn_heat` the bar scorches: it counts as a strike scoring 0 and the heat drops to `burn_reset_heat`. |
| `polish.low_time_seconds` | The timer turns red and ticks for this many final seconds. |
| `polish.burn_warning_margin` | The "TOO HOT" warning starts this far below `burn_heat`. |
| `polish.streak_bark_every` | The anvil remarks on every this-many strong strikes in a row. |
| `polish.bark_seconds` | How long an anvil remark stays up. |
| `polish.embers_per_second`, `polish.needle_smoothing` | Embers from the fire, and how quickly the gauge needle follows the heat (higher is snappier). |

## `forging_text.json`: on-screen text

All forge text: tier, rating, stage, recipe, quest and blueprint names, prompts, the anvil's result lines per tier (`anvil_lines`), its lines for a capped result (`anvil_lines_capped`), and its remarks during One Heat (`stages.one_heat.barks`). Text with `%d`, `%s` or `%.2f` has values filled in by the game: keep those markers, in the same order.

## `game_start.json`: a new game

Starting values for the player: `day`, `time_minutes` (minutes since midnight), `coin`, `reputation`, `smithing_level`, `completed_quests`, `blueprints`. Until quests and levelling exist, edit `smithing_level`, `completed_quests` and `blueprints` here to try out the tier locks.
