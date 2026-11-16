extends GdUnitTestSuite
## Checks the real tuning files in data/ against the forging rules the design
## promises (design/game-brief.md, "Forging"). These read data/*.json on
## purpose: they fail when a tuning edit breaks a promise, such as a low-level
## player being able to forge a Legendary item.

const TIERS_PATH: String = "res://data/forging_tiers.json"
const DIFFICULTY_PATH: String = "res://data/forging_difficulty.json"
const STAGES_PATH: String = "res://data/forging_stages.json"
const RECIPES_PATH: String = "res://data/forging_recipes.json"
const START_PATH: String = "res://data/game_start.json"

## Legendary must sit above the prototypes' cutoff of 92.
const OLD_LEGENDARY_CUTOFF: int = 92
const PERFECT_SCORE: float = 100.0
const EXPECTED_ORDER: Array = ["blade_trace", "anvil_song", "one_heat"]


func _rules() -> ForgeRules:
	return ForgeRules.new(JsonData.load_dict(TIERS_PATH), JsonData.load_dict(DIFFICULTY_PATH))


func _recipes() -> Array:
	return JsonData.load_dict(RECIPES_PATH).get("recipes", [])


func _new_player() -> Dictionary:
	var start: Dictionary = JsonData.load_dict(START_PATH)
	return {
		"smithing_level": int(start.get("smithing_level", 1)),
		"quests": start.get("completed_quests", []),
		"blueprints": start.get("blueprints", []),
	}


func test_tiers_data_has_five_tiers_ending_in_legendary() -> void:
	# Arrange / Act
	var rules: ForgeRules = _rules()

	# Assert
	assert_int(rules.tier_count()).is_equal(5)
	assert_str(rules.tier_id(0)).is_equal("crude")
	assert_str(rules.tier_id(4)).is_equal("legendary")


func test_tiers_data_legendary_cutoff_is_above_old_cutoff() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var cutoff: int = rules.tier_min_score(rules.tier_count() - 1)

	# Assert
	assert_int(cutoff).is_greater(OLD_LEGENDARY_CUTOFF)
	assert_int(cutoff).is_less_equal(100)


func test_tiers_data_every_tier_above_crude_is_locked_for_a_new_player() -> void:
	# Arrange
	var rules: ForgeRules = _rules()
	var new_player: Dictionary = _new_player()

	# Act / Assert: for every recipe, only the lowest tier is open at the start.
	for recipe: Dictionary in _recipes():
		assert_bool(rules.is_tier_unlocked(0, new_player, recipe)).is_true()
		for index: int in range(1, rules.tier_count()):
			assert_bool(rules.is_tier_unlocked(index, new_player, recipe)) \
				.override_failure_message("%s tier %s is open to a new player" % [recipe["id"], rules.tier_id(index)]) \
				.is_false()


func test_tiers_data_new_player_with_perfect_score_cannot_make_legendary() -> void:
	# Arrange: the rhythm-game expert on day one.
	var rules: ForgeRules = _rules()
	var new_player: Dictionary = _new_player()

	# Act / Assert
	for recipe: Dictionary in _recipes():
		var award: Dictionary = rules.award(PERFECT_SCORE, new_player, recipe)
		assert_str(award["earned_id"]).is_equal("legendary")
		assert_str(award["tier_id"]).is_not_equal("legendary")
		assert_bool(award["capped"]).is_true()


func test_tiers_data_top_tiers_need_level_quest_and_blueprint() -> void:
	# Arrange
	var rules: ForgeRules = _rules()
	var nothing: Dictionary = { "smithing_level": 0, "quests": [], "blueprints": [] }
	var legendary: int = rules.tier_count() - 1

	# Act / Assert: Legendary reports all three kinds of lock for every recipe.
	for recipe: Dictionary in _recipes():
		var kinds: Array[String] = []
		for gap: Dictionary in rules.tier_gaps(legendary, nothing, recipe):
			kinds.append(str(gap["kind"]))
		assert_array(kinds).contains([
			ForgeRules.GAP_SMITHING_LEVEL, ForgeRules.GAP_QUEST, ForgeRules.GAP_BLUEPRINT])


func test_recipes_data_every_blueprint_tier_has_a_blueprint() -> void:
	# Arrange
	var tiers: Array = JsonData.load_dict(TIERS_PATH).get("tiers", [])

	# Act / Assert: no recipe is silently stuck below a blueprint tier.
	for recipe: Dictionary in _recipes():
		var tier_blueprints: Dictionary = recipe.get("tier_blueprints", {})
		for tier: Dictionary in tiers:
			if bool(tier["requires"].get("recipe_blueprint", false)):
				assert_str(str(tier_blueprints.get(tier["id"], ""))) \
					.override_failure_message("%s has no %s blueprint" % [recipe["id"], tier["id"]]) \
					.is_not_empty()


func test_difficulty_data_gear_above_level_is_harder_for_a_new_player() -> void:
	# Arrange
	var rules: ForgeRules = _rules()
	var new_player: Dictionary = _new_player()
	var level: int = int(new_player["smithing_level"])

	# Act
	var same: float = rules.difficulty_factor(level, new_player)
	var above: float = rules.difficulty_factor(level + 2, new_player)

	# Assert
	assert_float(same).is_equal_approx(1.0, 0.0001)
	assert_float(above).is_greater(1.0)


func test_difficulty_data_mastery_is_locked_for_a_new_player() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var unlocked: bool = rules.is_mastery_unlocked(_new_player())

	# Assert
	assert_bool(unlocked).is_false()


func test_stages_data_order_is_blade_trace_anvil_song_one_heat() -> void:
	# Arrange / Act
	var stages: Dictionary = JsonData.load_dict(STAGES_PATH)

	# Assert
	assert_array(stages.get("order", [])).is_equal(EXPECTED_ORDER)
	for stage_id: String in EXPECTED_ORDER:
		assert_bool(stages["stages"].has(stage_id)).is_true()
