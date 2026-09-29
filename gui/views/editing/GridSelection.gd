###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## A set of selected grid items, stored as data keys (never UI objects), so a
## selection can survive the rebuild of the editor's visual state.
## Notes are keyed by Vector2i(value, position); arrangement placements are
## keyed by Vector2i(bar, channel).
class_name GridSelection extends RefCounted

signal changed()

var _keys: Dictionary = {} # Vector2i -> true


func size() -> int:
	return _keys.size()


func is_empty() -> bool:
	return _keys.is_empty()


func has(key: Vector2i) -> bool:
	return _keys.has(key)


func get_keys() -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for key: Vector2i in _keys:
		keys.push_back(key)
	return keys


func add(key: Vector2i) -> void:
	if _keys.has(key):
		return
	
	_keys[key] = true
	changed.emit()


func add_all(keys: Array[Vector2i]) -> void:
	var modified := false
	for key in keys:
		if not _keys.has(key):
			_keys[key] = true
			modified = true
	
	if modified:
		changed.emit()


func toggle(key: Vector2i) -> void:
	if _keys.has(key):
		_keys.erase(key)
	else:
		_keys[key] = true
	changed.emit()


func set_keys(keys: Array[Vector2i]) -> void:
	var next_keys := {}
	for key in keys:
		next_keys[key] = true
	
	if next_keys.size() == _keys.size() && next_keys.keys().all(func(key: Vector2i) -> bool: return _keys.has(key)):
		return
	
	_keys = next_keys
	changed.emit()


## Drops every key the validator rejects, e.g. items removed by another edit.
func retain(is_valid: Callable) -> void:
	var stale: Array[Vector2i] = []
	for key: Vector2i in _keys:
		if not is_valid.call(key):
			stale.push_back(key)
	
	if stale.is_empty():
		return
	
	for key in stale:
		_keys.erase(key)
	changed.emit()


func clear() -> void:
	if _keys.is_empty():
		return
	
	_keys.clear()
	changed.emit()
