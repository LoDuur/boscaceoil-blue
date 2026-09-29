extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _find(node: Node, suffix: String) -> Node:
	if node.get_script() and node.get_script().resource_path.ends_with(suffix):
		return node
	for c in node.get_children():
		var f := _find(c, suffix)
		if f:
			return f
	return null

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Controller.music_player.stop_playback()
	var song := Controller.current_song
	for i in 3:
		Controller.create_pattern()
	var p := song.patterns.duplicate()
	song.patterns[2].add_note(60, 0, 1)
	song.arrangement.apply_cell_changes({ Vector2i(0, 0): 0, Vector2i(1, 3): 2, Vector2i(4, 1): 2 })
	Controller.edit_pattern(3)
	_check(Controller.get_unused_pattern_indices() == ([1, 3] as Array[int]), "unused detected: %s" % [Controller.get_unused_pattern_indices()])
	Controller.remove_unused_patterns()
	_check(song.patterns.size() == 2 && song.patterns[0] == p[0] && song.patterns[1] == p[2], "patterns removed")
	_check(song.arrangement.get_pattern(1, 3) == 1 && song.arrangement.get_pattern(4, 1) == 1 && song.arrangement.get_pattern(0, 0) == 0, "arrangement renumbered")
	_check(Controller.current_pattern_index == 0, "edited pattern valid")
	Controller.state_manager.undo_state_change()
	_check(song.patterns.size() == 4 && song.patterns == p, "undo restores patterns")
	_check(song.arrangement.get_pattern(1, 3) == 2 && song.arrangement.get_pattern(4, 1) == 2, "undo restores arrangement")
	_check(Controller.current_pattern_index == 3, "undo restores edited pattern")
	Controller.state_manager.do_state_change()
	_check(song.patterns.size() == 2 && song.arrangement.get_pattern(1, 3) == 1, "redo")
	
	# All unused keeps one.
	song.arrangement.apply_cell_changes({ Vector2i(0, 0): -1, Vector2i(1, 3): -1, Vector2i(4, 1): -1 })
	_check(Controller.get_unused_pattern_indices() == ([1] as Array[int]), "one pattern always kept")
	
	# Follow toggle.
	var dock := _find(main, "PatternDock.gd") as ItemDock
	var follow: SquishyButton = dock._extra_buttons[0]
	_check(follow.text == "FOLLOW: OFF", "follow off by default")
	follow.button_pressed = true
	_check(Controller.follow_playback && follow.text == "FOLLOW: ON", "follow toggled")
	var pm := _find(main, "PatternMap.gd")
	_check(pm._following_playback_cursor, "pattern map follows")
	_check(dock._extra_buttons[1].position.y < dock._extra_buttons[0].position.y || dock.size.y == 0, "buttons stacked")
	
	# Esc does not quit, Ctrl+E is bound.
	_check(not InputMap.has_action("bosca_exit"), "no exit action")
	_check(InputMap.has_action("bosca_export"), "export action")
	
	print("PHASE7 TESTS: %d failures" % _failures)
	get_tree().quit()
