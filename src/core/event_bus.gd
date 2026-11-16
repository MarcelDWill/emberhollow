extends Node
## EventBus autoload: cross-scene signals. Scenes talk through these instead of
## reaching into each other (CLAUDE.md, "Tech rules").

## Emitted when a forge job finishes. [param result] holds `recipe_id`, `score`
## (0 to 100), `tier_id` (the awarded tier), `earned_tier_id` (what the score
## alone would have given), `capped` and `stage_scores`.
@warning_ignore("unused_signal")
signal item_forged(result: Dictionary)

## Emitted when the in-game day ends. [param day] is the day that just ended.
@warning_ignore("unused_signal")
signal day_ended(day: int)
