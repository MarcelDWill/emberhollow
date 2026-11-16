class_name JsonData
extends RefCounted
## Loads the JSON data files under `data/`. All tuning lives in those files
## (see data/README.md), so every system reads its numbers through here.


## Returns the JSON object stored at [param path], or an empty Dictionary
## (after logging an error) when the file is missing or is not a JSON object.
static func load_dict(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("%s is not a JSON object" % path)
		return {}
	return parsed
