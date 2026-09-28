###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## In-app clipboard for grid items. Items are stored relative to an anchor
## (the minimum X and minimum Y of the group) as Vector3i(dx, dy, payload).
## The payload is the note length for notes, or the pattern index for
## arrangement placements.
class_name GridClipboard extends RefCounted

var _items: Array[Vector3i] = []


func is_empty() -> bool:
	return _items.is_empty()


func size() -> int:
	return _items.size()


## Stores items given in absolute cells, as Vector3i(x, y, payload).
func store(absolute_items: Array[Vector3i]) -> void:
	_items = GridClipboard.to_relative(absolute_items)


func get_items() -> Array[Vector3i]:
	return _items.duplicate()


## Converts absolute Vector3i(x, y, payload) items into items relative to the
## group's anchor.
static func to_relative(absolute_items: Array[Vector3i]) -> Array[Vector3i]:
	var relative: Array[Vector3i] = []
	if absolute_items.is_empty():
		return relative
	
	var anchor := Vector2i(absolute_items[0].x, absolute_items[0].y)
	for item in absolute_items:
		anchor.x = mini(anchor.x, item.x)
		anchor.y = mini(anchor.y, item.y)
	
	for item in absolute_items:
		relative.push_back(Vector3i(item.x - anchor.x, item.y - anchor.y, item.z))
	return relative
