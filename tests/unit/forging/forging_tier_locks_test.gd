extends GdUnitTestSuite
## Unit tests for ForgeRules: quality tier cutoffs, tier locks (smithing level,
## quests, blueprints), and forging difficulty. Design: design/game-brief.md,
## "Forging". Fixtures are defined here, so tuning data/ never breaks these.

const TIERS: Dictionary = {
	"tiers": [
		{ "id": "crude", "min_score": 0, "requires": { "smithing_level": 1, "quests": [], "recipe_blueprint": false } },
		{ "id": "fine", "min_score": 40, "requires": { "smithing_level": 2, "quests": [], "recipe_blueprint": false } },
		{ "id": "superior", "min_score": 60, "requires": { "smithing_level": 4, "quests": ["shop_quest"], "recipe_blueprint": false } },
		{ "id": "masterwork", "min_score": 78, "requires": { "smithing_level": 7, "quests": ["guild_quest"], "recipe_blueprint": true } },
		{ "id": "legendary", "min_score": 96, "requires": { "smithing_level": 10, "quests": ["anvil_quest"], "recipe_blueprint": true } },
	],
}

const DIFFICULTY: Dictionary = {
	"min_factor": 0.6,
	"max_factor": 1.8,
	"over_level": { "factor_per_level": 0.15, "max_levels": 5 },
	"mastery": {
		"requires": { "smithing_level": 3, "quests": ["mastery_quest"], "blueprints": [] },
		"factor_per_level": 0.06,
		"max_levels": 5,
	},
}

const DAGGER: Dictionary = {
	"id": "dagger",
	"gear_level": 1,
	"tier_blueprints": { "masterwork": "bp_dagger_masterwork", "legendary": "bp_dagger_legendary" },
}

const RECIPE_WITHOUT_BLUEPRINTS: Dictionary = { "id": "nail", "gear_level": 1, "tier_blueprints": {} }

const ALL_QUESTS: Array = ["shop_quest", "guild_quest", "anvil_quest", "mastery_quest"]
const ALL_DAGGER_BLUEPRINTS: Array = ["bp_dagger_masterwork", "bp_dagger_legendary"]

const PERFECT_SCORE: float = 100.0


func _rules() -> ForgeRules:
	return ForgeRules.new(TIERS, DIFFICULTY)


func _progress(smithing_level: int, quests: Array = [], blueprints: Array = []) -> Dictionary:
	return { "smithing_level": smithing_level, "quests": quests, "blueprints": blueprints }


# --- Cutoffs ----------------------------------------------------------------

func test_earned_tier_score_below_legendary_cutoff_is_masterwork() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var earned: String = rules.tier_id(rules.earned_tier_index(95.0))

	# Assert
	assert_str(earned).is_equal("masterwork")


func test_earned_tier_score_at_legendary_cutoff_is_legendary() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var earned: String = rules.tier_id(rules.earned_tier_index(96.0))

	# Assert
	assert_str(earned).is_equal("legendary")


func test_earned_tier_zero_score_is_lowest_tier() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var earned: String = rules.tier_id(rules.earned_tier_index(0.0))

	# Assert
	assert_str(earned).is_equal("crude")


# --- Tier locks -------------------------------------------------------------

func test_award_low_level_player_with_perfect_score_is_capped_at_crude() -> void:
	# Arrange: a level 1 player who is very good at the minigames.
	var rules: ForgeRules = _rules()

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, _progress(1), DAGGER)

	# Assert
	assert_str(award["earned_id"]).is_equal("legendary")
	assert_str(award["tier_id"]).is_equal("crude")
	assert_bool(award["capped"]).is_true()
	assert_str(award["blocking_id"]).is_equal("fine")


func test_award_fully_unlocked_player_with_perfect_score_is_legendary() -> void:
	# Arrange
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ALL_QUESTS, ALL_DAGGER_BLUEPRINTS)

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("legendary")
	assert_bool(award["capped"]).is_false()


func test_award_level_met_but_quest_missing_stops_below_that_tier() -> void:
	# Arrange: level 10, but the Superior quest is not done.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ["guild_quest", "anvil_quest"], ALL_DAGGER_BLUEPRINTS)

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, DAGGER)

	# Assert: a locked tier also blocks every tier above it.
	assert_str(award["tier_id"]).is_equal("fine")
	assert_str(award["blocking_id"]).is_equal("superior")
	assert_str(award["gaps"][0]["kind"]).is_equal(ForgeRules.GAP_QUEST)
	assert_str(award["gaps"][0]["id"]).is_equal("shop_quest")


func test_award_level_and_quests_met_but_blueprint_missing_is_capped_at_masterwork() -> void:
	# Arrange: everything for Legendary except its blueprint.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ALL_QUESTS, ["bp_dagger_masterwork"])

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("masterwork")
	assert_str(award["blocking_id"]).is_equal("legendary")
	assert_str(award["gaps"][0]["kind"]).is_equal(ForgeRules.GAP_BLUEPRINT)
	assert_str(award["gaps"][0]["id"]).is_equal("bp_dagger_legendary")


func test_award_quests_and_blueprints_met_but_level_too_low_is_capped() -> void:
	# Arrange: every quest and blueprint, but only smithing level 9.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(9, ALL_QUESTS, ALL_DAGGER_BLUEPRINTS)

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("masterwork")
	assert_str(award["gaps"][0]["kind"]).is_equal(ForgeRules.GAP_SMITHING_LEVEL)
	assert_int(award["gaps"][0]["need"]).is_equal(10)


func test_award_blueprint_for_another_recipe_does_not_unlock_tier() -> void:
	# Arrange: the player owns a Masterwork blueprint, but for a different item.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ALL_QUESTS, ["bp_sword_masterwork"])

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("superior")


func test_award_recipe_without_blueprint_stays_locked_at_blueprint_tiers() -> void:
	# Arrange: the tier needs a blueprint and the recipe defines none.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ALL_QUESTS, ALL_DAGGER_BLUEPRINTS)

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, progress, RECIPE_WITHOUT_BLUEPRINTS)

	# Assert: a missing blueprint definition never unlocks by default.
	assert_str(award["tier_id"]).is_equal("superior")
	assert_str(award["gaps"][0]["kind"]).is_equal(ForgeRules.GAP_NO_BLUEPRINT)


func test_award_unlocked_tier_still_needs_the_score() -> void:
	# Arrange: fully unlocked player, middling forge.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(10, ALL_QUESTS, ALL_DAGGER_BLUEPRINTS)

	# Act
	var award: Dictionary = rules.award(65.0, progress, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("superior")
	assert_bool(award["capped"]).is_false()


func test_award_missing_progress_keys_are_treated_as_locked() -> void:
	# Arrange: an empty progress record (no level, quests or blueprints).
	var rules: ForgeRules = _rules()

	# Act
	var award: Dictionary = rules.award(PERFECT_SCORE, {}, DAGGER)

	# Assert
	assert_str(award["tier_id"]).is_equal("crude")
	assert_bool(award["capped"]).is_true()


func test_is_tier_unlocked_lists_every_missing_requirement() -> void:
	# Arrange
	var rules: ForgeRules = _rules()
	var legendary: int = rules.tier_count() - 1

	# Act
	var gaps: Array[Dictionary] = rules.tier_gaps(legendary, _progress(1), DAGGER)

	# Assert: level, quest and blueprint are all reported.
	assert_bool(rules.is_tier_unlocked(legendary, _progress(1), DAGGER)).is_false()
	assert_int(gaps.size()).is_equal(3)


# --- Difficulty -------------------------------------------------------------

func test_difficulty_gear_at_player_level_is_baseline() -> void:
	# Arrange
	var rules: ForgeRules = _rules()

	# Act
	var factor: float = rules.difficulty_factor(3, _progress(3))

	# Assert
	assert_float(factor).is_equal_approx(1.0, 0.0001)


func test_difficulty_gear_above_player_level_is_harder() -> void:
	# Arrange: gear two levels above the player.
	var rules: ForgeRules = _rules()

	# Act
	var factor: float = rules.difficulty_factor(3, _progress(1))

	# Assert: 1 + 2 levels x 0.15
	assert_float(factor).is_equal_approx(1.3, 0.0001)


func test_difficulty_far_above_player_level_stops_at_max_levels() -> void:
	# Arrange: gear 20 levels above the player; only 5 levels count.
	var rules: ForgeRules = _rules()

	# Act
	var factor: float = rules.difficulty_factor(21, _progress(1))

	# Assert: 1 + 5 levels x 0.15
	assert_float(factor).is_equal_approx(1.75, 0.0001)


func test_difficulty_gear_below_level_stays_baseline_while_mastery_locked() -> void:
	# Arrange: level 8 player without the mastery quest.
	var rules: ForgeRules = _rules()

	# Act
	var factor: float = rules.difficulty_factor(1, _progress(8))

	# Assert
	assert_bool(rules.is_mastery_unlocked(_progress(8))).is_false()
	assert_float(factor).is_equal_approx(1.0, 0.0001)


func test_difficulty_gear_below_level_is_easier_once_mastery_unlocked() -> void:
	# Arrange: level 4 player with the mastery quest, forging level 1 gear.
	var rules: ForgeRules = _rules()
	var progress: Dictionary = _progress(4, ["mastery_quest"])

	# Act
	var factor: float = rules.difficulty_factor(1, progress)

	# Assert: 1 - 3 levels x 0.06
	assert_float(factor).is_equal_approx(0.82, 0.0001)


func test_difficulty_mastery_quest_alone_does_not_unlock_below_level_requirement() -> void:
	# Arrange: has the quest, but is below the mastery smithing level.
	var rules: ForgeRules = _rules()

	# Act
	var unlocked: bool = rules.is_mastery_unlocked(_progress(2, ["mastery_quest"]))

	# Assert
	assert_bool(unlocked).is_false()


func test_apply_difficulty_shrinks_windows_and_grows_rates() -> void:
	# Arrange
	var stage: Dictionary = {
		"difficulty_scaling": { "divide": ["perfect_window"], "multiply": ["cool_per_second"] },
		"perfect_window": 0.04,
		"cool_per_second": 0.07,
		"strikes_needed": 24,
	}

	# Act
	var scaled: Dictionary = ForgeRules.apply_difficulty(stage, 2.0)

	# Assert
	assert_float(scaled["perfect_window"]).is_equal_approx(0.02, 0.0001)
	assert_float(scaled["cool_per_second"]).is_equal_approx(0.14, 0.0001)
	assert_int(scaled["strikes_needed"]).is_equal(24)
	assert_float(stage["perfect_window"]).is_equal_approx(0.04, 0.0001)


func test_combine_scores_uses_stage_weights() -> void:
	# Arrange: one_heat counts double.
	var stages: Dictionary = {
		"blade_trace": { "weight": 1.0 },
		"anvil_song": { "weight": 1.0 },
		"one_heat": { "weight": 2.0 },
	}
	var scores: Dictionary = { "blade_trace": 100.0, "anvil_song": 60.0, "one_heat": 80.0 }

	# Act
	var combined: float = ForgeRules.combine_scores(scores, stages)

	# Assert: (100 + 60 + 160) / 4
	assert_float(combined).is_equal_approx(80.0, 0.0001)
