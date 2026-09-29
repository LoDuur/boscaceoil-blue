extends Node

var _failures := 0
var _statuses: Array[String] = []
var pm: PatternMap = null

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _find(node: Node, cls: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == cls:
		return node
	for c in node.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null

func _arr() -> Arrangement:
	return Controller.current_song.arrangement

func _key(k: Key, ctrl := false, shift := false, alt := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()

func _cells() -> Array[Vector3i]:
	return pm._get_all_placements()

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Controller.status_updated.connect(func(_l: int, m: String) -> void: _statuses.push_back(m))
	Controller.navigate_to(Menu.NavigationTarget.ARRANGEMENT)
	await get_tree().process_frame
	await get_tree().process_frame
	pm = _find(main, "PatternMap")
	_check(pm != null && pm.is_visible_in_tree(), "PatternMap visible")
	Controller.music_player.stop_playback()
	
	Controller.create_pattern()
	Controller.create_pattern()
	_check(Controller.current_song.patterns.size() == 3, "3 patterns")
	# Initial: pattern 0 at (0,0), pattern 1 at (1,0), pattern 2 at (1,2).
	pm._commit_cell_changes({ Vector2i(0, 0): 0, Vector2i(1, 0): 1, Vector2i(1, 2): 2 })
	var base := _cells()
	_check(base.size() == 3 && _arr().timeline_length == 2, "setup: %s len %d" % [base, _arr().timeline_length])
	
	Controller.set_editor_focus(Controller.EditorFocus.ARRANGEMENT)
	_key(KEY_A, true)
	_check(pm._selection.size() == 3, "select all placements")
	
	# Nudges accumulate.
	_key(KEY_RIGHT); _key(KEY_RIGHT)
	_key(KEY_DOWN)
	_check(_arr().get_pattern(2, 1) == 0 && _arr().get_pattern(3, 3) == 2 && _arr().get_pattern(0, 0) == -1, "moved: %s" % [_cells()])
	_check(_arr().timeline_length == 4, "timeline grew: %d" % _arr().timeline_length)
	Controller.state_manager.undo_state_change()
	_check(_cells() == base && _arr().timeline_length == 2, "one undo reverts nudges: %s" % [_cells()])
	
	# Edge refusal.
	pm._selection.set_keys([Vector2i(0, 0)] as Array[Vector2i])
	_key(KEY_LEFT)
	_check(_cells() == base, "left edge refused")
	_key(KEY_UP)
	_check(_cells() == base, "top edge refused")
	
	# Delete clears cells; patterns stay.
	pm._selection.set_keys([Vector2i(1, 0), Vector2i(1, 2)] as Array[Vector2i])
	_key(KEY_DELETE)
	_check(_cells().size() == 1 && Controller.current_song.patterns.size() == 3, "delete clears cells only")
	_check(_arr().timeline_length == 1, "timeline shrank")
	Controller.state_manager.undo_state_change()
	_check(_cells() == base, "undo delete")
	
	# Copy / paste ghost with Enter.
	pm._selection.set_keys([Vector2i(1, 0), Vector2i(1, 2)] as Array[Vector2i])
	_key(KEY_C, true)
	_check(Controller.arrangement_clipboard.size() == 2, "copied 2")
	_key(KEY_V, true)
	_check(pm._ghost != null, "paste ghost")
	pm._ghost.anchor_cell = Vector2i(5, 0)
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	_check(_arr().get_pattern(6, 0) == 1 && _arr().get_pattern(6, 2) == 2 && _arr().timeline_length == 7, "pasted: %s" % [_cells()])
	Controller.state_manager.undo_state_change()
	
	# Cut + undo.
	pm._selection.set_keys([Vector2i(0, 0)] as Array[Vector2i])
	_key(KEY_X, true)
	_check(_arr().get_pattern(0, 0) == -1, "cut")
	Controller.state_manager.undo_state_change()
	_check(_cells() == base, "undo cut")
	
	# Ctrl+D with no selection duplicates hovered placement: simulate via method with no cursor -> no-op.
	pm._selection.clear()
	pm._duplicate_placements()
	_check(pm._ghost == null, "duplicate w/o selection and no hover is no-op")
	pm._selection.set_keys([Vector2i(0, 0)] as Array[Vector2i])
	_key(KEY_D, true)
	_check(pm._ghost != null, "duplicate ghost"); _check(Controller.arrangement_clipboard.size() == 1, "duplicate keeps clipboard (holds the cut item)")
	_key(KEY_ESCAPE)
	_check(pm._ghost == null && _cells() == base, "esc cancels")
	
	# Drag move with overlap onto own old position.
	pm._selection.set_keys([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	pm._press_cell = Vector2i(0, 0)
	pm._press_copies = false
	pm._press_makes_variant = false
	pm._start_dragging()
	pm._ghost.anchor_cell = Vector2i(1, 0)
	pm._commit_ghost()
	_check(_arr().get_pattern(0, 0) == -1 && _arr().get_pattern(1, 0) == 0 && _arr().get_pattern(2, 0) == 1, "drag moved with overlap: %s" % [_cells()])
	Controller.state_manager.undo_state_change()
	_check(_cells() == base, "undo drag")
	
	# Ctrl+drag copies.
	pm._selection.set_keys([Vector2i(0, 0)] as Array[Vector2i])
	pm._press_cell = Vector2i(0, 0)
	pm._press_copies = true
	pm._start_dragging()
	pm._ghost.anchor_cell = Vector2i(4, 4)
	pm._commit_ghost()
	_check(_arr().get_pattern(0, 0) == 0 && _arr().get_pattern(4, 4) == 0, "ctrl drag copies")
	Controller.state_manager.undo_state_change()
	
	# Alt+drag creates a variant.
	var before_patterns := Controller.current_song.patterns.size()
	pm._press_cell = Vector2i(0, 0)
	pm._press_copies = false
	pm._press_makes_variant = true
	pm._start_dragging()
	pm._ghost.anchor_cell = Vector2i(3, 3)
	pm._commit_ghost()
	_check(Controller.current_song.patterns.size() == before_patterns + 1 && _arr().get_pattern(3, 3) == before_patterns, "alt drag variant")
	_check(_arr().get_pattern(0, 0) == 0, "variant keeps source")
	Controller.state_manager.undo_state_change()
	_check(Controller.current_song.patterns.size() == before_patterns && _cells() == base, "undo variant")
	
	# Dock drop still accepted.
	var dock_data := ItemDock.ItemDragData.new()
	dock_data.source_id = Controller.DragSources.PATTERN_DOCK
	_check(pm._can_drop_data(Vector2.ZERO, dock_data), "dock drop accepted")
	
	# Undo clears selection.
	pm._select_all_placements()
	_key(KEY_Z, true)
	_check(pm._selection.is_empty(), "undo clears selection")
	
	# Hidden view releases focus.
	Controller.navigate_to(Menu.NavigationTarget.FILE)
	await get_tree().process_frame
	_check(Controller.editor_focus == Controller.EditorFocus.NONE, "focus released when hidden")
	
	print("PHASE4 TESTS: %d failures" % _failures)
	get_tree().quit()
