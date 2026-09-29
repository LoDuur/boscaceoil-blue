extends Node
# Compiles every project script (with autoloads present) and reports failures.
func _ready() -> void:
	var files := _collect("res://")
	var failed := 0
	for f in files:
		var s: Script = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null or not s.can_instantiate():
			failed += 1
			print("FAIL ", f)
	for f in _collect_ext("res://", ".tscn"):
		if ResourceLoader.load(f) == null:
			failed += 1
			print("FAIL ", f)
	print("CHECKED %d scripts, %d failed" % [files.size(), failed])
	get_tree().quit()

func _collect(dir: String) -> PackedStringArray:
	return _collect_ext(dir, ".gd")

func _collect_ext(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "bin" or d == "addons" or d == "tests":
			continue
		out.append_array(_collect_ext(dir.path_join(d), ext))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	return out
