class_name ForgeRules
extends RefCounted
## The forging rules that do not need a screen: which quality tier a score
## earns, which tiers the player is allowed to make, and how hard a forge job
## is for this player. Implements design/game-brief.md, "Forging".
##
## Pure logic over plain data. Tuning comes from data/forging_tiers.json and
## data/forging_difficulty.json; the player's progress is passed in as a
## Dictionary (`smithing_level`, `quests`, `blueprints`), so nothing here
## touches an autoload and everything is unit-testable.

## Requirement-gap kinds returned by [method requirement_gaps].
const GAP_SMITHING_LEVEL: String = "smithing_level"
const GAP_QUEST: String = "quest"
const GAP_BLUEPRINT: String = "blueprint"
const GAP_NO_BLUEPRINT: String = "no_blueprint"

var _tiers: Array[Dictionary] = []
var _difficulty: Dictionary = {}


func _init(tiers_config: Dictionary, difficulty_config: Dictionary) -> void:
	for tier: Variant in tiers_config.get("tiers", []):
		if tier is Dictionary:
			_tiers.append(tier)
	_tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("min_score", 0.0)) < float(b.get("min_score", 0.0)))
	_difficulty = difficulty_config


## Number of quality tiers, lowest first.
func tier_count() -> int:
	return _tiers.size()


## Id of the tier at [param index] (0 is the lowest tier).
func tier_id(index: int) -> String:
	return str(_tiers[index].get("id", ""))


## Lowest score that reaches the tier at [param index].
func tier_min_score(index: int) -> int:
	return int(_tiers[index].get("min_score", 0))


## Index of the highest tier whose cutoff [param score] reaches, ignoring locks.
func earned_tier_index(score: float) -> int:
	var best: int = 0
	for index: int in _tiers.size():
		if roundi(score) >= tier_min_score(index):
			best = index
	return best


## What still stops the player from making the tier at [param index] of
## [param recipe]. Empty when the tier is unlocked. Each gap is a Dictionary
## with `kind` (one of the GAP_ constants) plus `need` and `have` for a level
## gap or `id` for a quest or blueprint gap.
func tier_gaps(index: int, progress: Dictionary, recipe: Dictionary) -> Array[Dictionary]:
	var tier: Dictionary = _tiers[index]
	var requires: Dictionary = tier.get("requires", {})
	var gaps: Array[Dictionary] = requirement_gaps(requires, progress)
	if bool(requires.get("recipe_blueprint", false)):
		var tier_blueprints: Dictionary = recipe.get("tier_blueprints", {})
		var blueprint_id: String = str(tier_blueprints.get(tier_id(index), ""))
		if blueprint_id.is_empty():
			# The tier needs a blueprint and this recipe has none: stay locked.
			gaps.append({ "kind": GAP_NO_BLUEPRINT })
		elif not _has(progress.get("blueprints", []), blueprint_id):
			gaps.append({ "kind": GAP_BLUEPRINT, "id": blueprint_id })
	return gaps


## True when the player may make the tier at [param index] of [param recipe].
func is_tier_unlocked(index: int, progress: Dictionary, recipe: Dictionary) -> bool:
	return tier_gaps(index, progress, recipe).is_empty()


## Decides the tier a finished forge job is awarded.
##
## The score earns a tier by its cutoff, then the award climbs from the lowest
## tier and stops at the first locked one, so skill alone can never pass a
## lock. Returns `score`, `earned_index`/`earned_id` (by score alone),
## `tier_index`/`tier_id` (awarded), `capped`, and for a capped result
## `blocking_index`/`blocking_id` with the `gaps` that lock it.
func award(score: float, progress: Dictionary, recipe: Dictionary) -> Dictionary:
	var earned: int = earned_tier_index(score)
	var awarded: int = 0
	var blocking: int = -1
	var gaps: Array[Dictionary] = []
	for index: int in range(1, earned + 1):
		var tier_gap_list: Array[Dictionary] = tier_gaps(index, progress, recipe)
		if not tier_gap_list.is_empty():
			blocking = index
			gaps = tier_gap_list
			break
		awarded = index
	return {
		"score": roundi(score),
		"earned_index": earned,
		"earned_id": tier_id(earned),
		"tier_index": awarded,
		"tier_id": tier_id(awarded),
		"capped": blocking >= 0,
		"blocking_index": blocking,
		"blocking_id": tier_id(blocking) if blocking >= 0 else "",
		"gaps": gaps,
	}


## True once the player has met the requirements that switch on "mastery":
## gear below the player's smithing level getting easier to forge.
func is_mastery_unlocked(progress: Dictionary) -> bool:
	return mastery_gaps(progress).is_empty()


## What still stops mastery from unlocking (see [method is_mastery_unlocked]).
func mastery_gaps(progress: Dictionary) -> Array[Dictionary]:
	var mastery: Dictionary = _difficulty.get("mastery", {})
	return requirement_gaps(mastery.get("requires", {}), progress)


## Difficulty multiplier for forging gear of [param gear_level]. 1.0 is the
## baseline. Above 1.0 is harder (gear above the player's smithing level).
## Below 1.0 is easier (gear below it, only once mastery is unlocked).
func difficulty_factor(gear_level: int, progress: Dictionary) -> float:
	var gap: int = gear_level - int(progress.get("smithing_level", 1))
	var factor: float = 1.0
	if gap > 0:
		var over: Dictionary = _difficulty.get("over_level", {})
		var levels: int = mini(gap, int(over.get("max_levels", gap)))
		factor += float(over.get("factor_per_level", 0.0)) * float(levels)
	elif gap < 0 and is_mastery_unlocked(progress):
		var mastery: Dictionary = _difficulty.get("mastery", {})
		var levels: int = mini(-gap, int(mastery.get("max_levels", -gap)))
		factor -= float(mastery.get("factor_per_level", 0.0)) * float(levels)
	return clampf(factor, float(_difficulty.get("min_factor", 1.0)), float(_difficulty.get("max_factor", 1.0)))


## Gaps between a `requires` block (`smithing_level`, `quests`, `blueprints`)
## and the player's [param progress]. Empty when everything is met.
static func requirement_gaps(requires: Dictionary, progress: Dictionary) -> Array[Dictionary]:
	var gaps: Array[Dictionary] = []
	var need_level: int = int(requires.get("smithing_level", 0))
	var have_level: int = int(progress.get("smithing_level", 0))
	if have_level < need_level:
		gaps.append({ "kind": GAP_SMITHING_LEVEL, "need": need_level, "have": have_level })
	for quest: Variant in requires.get("quests", []):
		if not _has(progress.get("quests", []), str(quest)):
			gaps.append({ "kind": GAP_QUEST, "id": str(quest) })
	for blueprint: Variant in requires.get("blueprints", []):
		if not _has(progress.get("blueprints", []), str(blueprint)):
			gaps.append({ "kind": GAP_BLUEPRINT, "id": str(blueprint) })
	return gaps


## Returns a copy of a stage's tuning with [param factor] applied. The stage's
## `difficulty_scaling` block names which values shrink (`divide`, such as
## timing windows) and which grow (`multiply`, such as cooling speed).
static func apply_difficulty(stage_config: Dictionary, factor: float) -> Dictionary:
	var scaled: Dictionary = stage_config.duplicate(true)
	if factor <= 0.0:
		return scaled
	var scaling: Dictionary = stage_config.get("difficulty_scaling", {})
	for key: Variant in scaling.get("divide", []):
		if scaled.has(key):
			scaled[key] = float(scaled[key]) / factor
	for key: Variant in scaling.get("multiply", []):
		if scaled.has(key):
			scaled[key] = float(scaled[key]) * factor
	return scaled


## Weighted average of the stage scores (0 to 100 each). [param stage_scores]
## maps stage id to score; [param stages] is the `stages` block of
## data/forging_stages.json, which holds each stage's `weight`.
static func combine_scores(stage_scores: Dictionary, stages: Dictionary) -> float:
	var total: float = 0.0
	var weight_sum: float = 0.0
	for stage_id: Variant in stage_scores:
		var stage: Dictionary = stages.get(stage_id, {})
		var weight: float = float(stage.get("weight", 1.0))
		total += clampf(float(stage_scores[stage_id]), 0.0, 100.0) * weight
		weight_sum += weight
	return total / weight_sum if weight_sum > 0.0 else 0.0


static func _has(values: Variant, wanted: String) -> bool:
	if values is Array:
		for value: Variant in values:
			if str(value) == wanted:
				return true
	return false
