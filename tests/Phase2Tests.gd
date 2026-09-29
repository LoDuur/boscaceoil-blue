extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _ready() -> void:
	var rel := GridClipboard.to_relative([Vector3i(5, 3, 2), Vector3i(7, 1, 4), Vector3i(6, 2, 1)] as Array[Vector3i])
	_check(rel == ([Vector3i(0, 2, 2), Vector3i(2, 0, 4), Vector3i(1, 1, 1)] as Array[Vector3i]), "to_relative: %s" % [rel])
	
	var ghost := GhostPlacement.new(rel, GhostPlacement.Source.PASTE, Rect2i(0, 0, 16, 10))
	_check(ghost.get_extent() == Vector2i(3, 3), "extent")
	ghost.follow_cell(Vector2i(15, 9))
	_check(ghost.anchor_cell == Vector2i(13, 7), "clamp to far edge: %s" % ghost.anchor_cell)
	ghost.follow_cell(Vector2i(-4, -4))
	_check(ghost.anchor_cell == Vector2i(0, 0), "clamp to near edge")
	var mask := ghost.is_valid_at(Vector2i(0, 0), func(c: Vector2i) -> bool: return c == Vector2i(1, 1))
	_check(mask[2] == GhostPlacement.FIT_CONFLICT && mask[0] == GhostPlacement.FIT_FREE, "conflict mask %s" % [mask])
	
	var big := GhostPlacement.new([Vector3i(0, 0, 1), Vector3i(0, 19, 1)] as Array[Vector3i], GhostPlacement.Source.PASTE, Rect2i(0, 0, 16, 8))
	big.follow_cell(Vector2i(3, 5))
	_check(big.anchor_cell == Vector2i(3, 0), "oversized pinned: %s" % big.anchor_cell)
	var bmask := big.is_valid_at(big.anchor_cell, func(_c: Vector2i) -> bool: return false)
	_check(bmask[1] == GhostPlacement.FIT_NONE, "overflow item reported")
	
	var sel := GridSelection.new()
	var count := [0]
	sel.changed.connect(func() -> void: count[0] += 1)
	sel.add(Vector2i(1, 1)); sel.add(Vector2i(1, 1)); sel.toggle(Vector2i(2, 2))
	sel.set_keys([Vector2i(1, 1), Vector2i(2, 2)] as Array[Vector2i])
	_check(count[0] == 2 && sel.size() == 2, "selection change events %d" % count[0])
	sel.retain(func(k: Vector2i) -> bool: return k.x == 1)
	_check(sel.size() == 1 && sel.has(Vector2i(1, 1)), "retain")
	
	print("PHASE2 TESTS: %d failures" % _failures)
	get_tree().quit()
