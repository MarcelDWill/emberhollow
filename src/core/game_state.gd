extends Node
## GameState autoload: the player's persistent state (CLAUDE.md, "Tech rules").
## Starting values come from data/game_start.json.

const START_PATH: String = "res://data/game_start.json"

## Current in-game day, starting at 1.
var day: int = 1
## Minutes since midnight of the current in-game day.
var time_minutes: int = 0
## Item id -> count.
var inventory: Dictionary = {}
## Coin the player holds.
var coin: int = 0
## Town reputation.
var reputation: int = 0
## Villager id -> friendship points.
var relationships: Dictionary = {}
## Smithing skill level. Gates quality tiers and sets forging difficulty.
var smithing_level: int = 1
## Ids of quests the player has finished.
var completed_quests: Array[String] = []
## Ids of blueprints the player has acquired.
var blueprints: Array[String] = []


func _ready() -> void:
	reset()


## Puts every value back to the new-game start from data/game_start.json.
func reset() -> void:
	var start: Dictionary = JsonData.load_dict(START_PATH)
	day = int(start.get("day", 1))
	time_minutes = int(start.get("time_minutes", 0))
	coin = int(start.get("coin", 0))
	reputation = int(start.get("reputation", 0))
	smithing_level = int(start.get("smithing_level", 1))
	inventory = {}
	relationships = {}
	completed_quests = _string_array(start.get("completed_quests", []))
	blueprints = _string_array(start.get("blueprints", []))


## The part of the state the forging rules read, as plain data, so the rules
## never depend on this autoload (see ForgeRules).
func forge_progress() -> Dictionary:
	return {
		"smithing_level": smithing_level,
		"quests": completed_quests.duplicate(),
		"blueprints": blueprints.duplicate(),
	}


## Returns the whole game state as JSON text (the project's test hook).
func debug_state_text() -> String:
	return JSON.stringify({
		"day": day,
		"time_minutes": time_minutes,
		"coin": coin,
		"reputation": reputation,
		"smithing_level": smithing_level,
		"completed_quests": completed_quests,
		"blueprints": blueprints,
		"inventory": inventory,
		"relationships": relationships,
	})


func _string_array(values: Variant) -> Array[String]:
	var out: Array[String] = []
	if values is Array:
		for value: Variant in values:
			out.append(str(value))
	return out
