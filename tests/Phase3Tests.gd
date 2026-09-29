extends Node

var _failures := 0
var _statuses: Array[String] = []
var nm: NoteMap = null

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

func _pattern() -> Pattern:
	return Controller.get_current_pattern()

func _snap() -> Array[Vector3i]:
	var s := _pattern().get_notes_snapshot()
	s.sort()
	return s

func _set_notes(notes: Array[Vector3i]) -> void:
	Controller.commit_pattern_notes(Controller.current_pattern_index, notes)

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

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	Controller.status_updated.connect(func(_l: int, m: String) -> void: _statuses.push_back(m))
	nm = _find(main, "NoteMap")
	_check(nm != null, "NoteMap found")
	Controller.music_player.stop_playback()
	
	# Default song: pattern 0, chromatic, key C. Rows == values.
	var base: Array[Vector3i] = [Vector3i(60, 0, 1), Vector3i(62, 2, 2), Vector3i(64, 4, 1), Vector3i(65, 6, 1), Vector3i(67, 8, 3)]
	_set_notes(base)
	Controller.set_editor_focus(Controller.EditorFocus.NOTES)
	
	# Select all via keyboard.
	_key(KEY_A, true)
	_check(nm._selection.size() == 5, "ctrl+a selects all: %d" % nm._selection.size())
	
	# Arrow nudges accumulate into one undo step.
	_key(KEY_RIGHT); _key(KEY_RIGHT); _key(KEY_RIGHT)
	var moved := _snap()
	_check(moved[0] == Vector3i(60, 3, 1), "moved right 3: %s" % [moved])
	_check(nm._selection.size() == 5, "selection follows move")
	Controller.state_manager.undo_state_change()
	_check(_snap() == base, "one undo reverts all nudges: %s" % [_snap()])
	
	# Edge refusal.
	nm._selection.set_keys([Vector2i(60, 0), Vector2i(62, 2)] as Array[Vector2i])
	_key(KEY_LEFT)
	_check(_snap() == base, "move at edge refused")
	
	# Shift+arrows: octave up (12 rows chromatic).
	_key(KEY_UP, false, true)
	_check(_pattern().has_note(72, 0, true) && _pattern().has_note(74, 2, true), "shift+up moves an octave")
	Controller.state_manager.undo_state_change()
	
	# Copy / cut / undo restores exactly.
	nm._select_all_notes()
	_key(KEY_C, true)
	_check(Controller.note_clipboard.size() == 5, "copied 5")
	_key(KEY_X, true)
	_check(_pattern().note_amount == 0, "cut removed")
	Controller.state_manager.undo_state_change()
	_check(_snap() == base, "undo cut restores exactly")
	
	# Duplicate leaves clipboard unchanged.
	nm._selection.set_keys([Vector2i(60, 0)] as Array[Vector2i])
	_key(KEY_D, true)
	_check(nm._ghost != null && nm._ghost.source == GhostPlacement.Source.DUPLICATE, "duplicate ghost")
	_check(Controller.note_clipboard.size() == 5, "duplicate kept clipboard")
	_key(KEY_ESCAPE)
	_check(nm._ghost == null && _snap() == base, "esc cancels ghost, no change")
	
	# Paste into another pattern with ghost, nudge and commit with Enter.
	Controller.create_and_edit_pattern()
	await get_tree().process_frame
	_check(Controller.current_pattern_index == 1, "switched to new pattern")
	_key(KEY_V, true)
	_check(nm._ghost != null, "paste ghost")
	_check(_pattern().note_amount == 0, "nothing written before commit")
	nm._ghost.anchor_cell = Vector2i(0, 50)
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	_check(_pattern().note_amount == 5 && _pattern().has_note(50, 1, true), "paste committed at nudged anchor: %s" % [_snap()])
	_check(nm._selection.size() == 5, "pasted notes selected")
	
	# Pattern full.
	var many: Array[Vector3i] = []
	for i in 120:
		many.push_back(Vector3i(20 + i / 16, i % 16, 1))
	_set_notes(many)
	var twenty: Array[Vector3i] = []
	for i in 20:
		twenty.push_back(Vector3i(i % 16, 80 + i / 16, 1))
	Controller.note_clipboard.store(twenty)
	_statuses.clear()
	nm._paste_notes()
	nm._ghost.anchor_cell = Vector2i(0, 80)
	nm._commit_ghost()
	_check(_pattern().note_amount == 128, "filled to 128: %d" % _pattern().note_amount)
	_check(_statuses.any(func(m: String) -> bool: return m.begins_with("PATTERN FULL — 12 NOTES SKIPPED")), "full status: %s" % [_statuses])
	
	# Oversized ghost drops items.
	var tall: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 200, 1)]
	_set_notes([] as Array[Vector3i])
	Controller.note_clipboard.store(tall)
	_statuses.clear()
	nm._paste_notes()
	nm._commit_ghost()
	_check(_pattern().note_amount == 1 && _statuses.any(func(m: String) -> bool: return m == "1 NOTE DIDN'T FIT"), "overflow dropped: %s" % [_statuses])
	
	# Rotation: 16 presses on a 16-tick pattern returns the original.
	_set_notes(base)
	for i in 16:
		_key(KEY_RIGHT, true)
	_check(_snap() == base, "16 rotations identity")
	_key(KEY_RIGHT, true)
	_check(_pattern().has_note(60, 1, true), "rotation moved")
	
	# Vertical all-notes shift is atomic at the edge.
	_set_notes([Vector3i(103, 0, 1), Vector3i(50, 1, 1)] as Array[Vector3i])
	_statuses.clear()
	_key(KEY_UP, true)
	_check(_pattern().has_note(103, 0, true) && _pattern().has_note(50, 1, true), "edge shift refused")
	_check(_statuses.has("CAN'T SHIFT — NOTES AT THE EDGE"), "edge status")
	_key(KEY_DOWN, true)
	_check(_pattern().has_note(102, 0, true) && _pattern().has_note(49, 1, true), "shift down works")
	
	# Resize.
	_set_notes(base)
	nm._selection.set_keys([Vector2i(60, 0)] as Array[Vector2i])
	_key(KEY_RIGHT, false, false, true)
	_key(KEY_RIGHT, false, false, true)
	_check(_pattern().get_note_length(60, 0) == 3, "alt+right lengthens")
	Controller.state_manager.undo_state_change()
	_check(_pattern().get_note_length(60, 0) == 1, "resize accumulated into one undo")
	
	# Delete.
	nm._selection.set_keys([Vector2i(62, 2), Vector2i(64, 4)] as Array[Vector2i])
	_key(KEY_DELETE)
	_check(_pattern().note_amount == 3 && nm._selection.is_empty(), "delete removes selection")
	Controller.state_manager.undo_state_change()
	
	# Drag move and copy through the drag state machine.
	nm._selection.set_keys([Vector2i(60, 0), Vector2i(62, 2)] as Array[Vector2i])
	nm._press_cell = Vector2i(0, 60)
	nm._press_copies = false
	nm._start_dragging()
	_check(nm._ghost.source == GhostPlacement.Source.DRAG_MOVE, "drag move ghost")
	nm._ghost.anchor_cell = nm._ghost.clamp_anchor(Vector2i(5, 40))
	nm._commit_ghost()
	_check(_pattern().has_note(40, 5, true) && _pattern().has_note(42, 7, true) && not _pattern().has_note(60, 0, true), "drag moved: %s" % [_snap()])
	Controller.state_manager.undo_state_change()
	_check(_snap() == base, "one undo reverts drag")
	nm._selection.set_keys([Vector2i(60, 0)] as Array[Vector2i])
	nm._press_cell = Vector2i(0, 60)
	nm._press_copies = true
	nm._start_dragging()
	nm._ghost.anchor_cell = Vector2i(10, 30)
	nm._commit_ghost()
	_check(_pattern().has_note(60, 0, true) && _pattern().has_note(30, 10, true), "drag copied")
	Controller.state_manager.undo_state_change()
	
	# Drag cancel.
	nm._selection.set_keys([Vector2i(60, 0)] as Array[Vector2i])
	nm._press_cell = Vector2i(0, 60)
	nm._start_dragging()
	_key(KEY_ESCAPE)
	_check(nm._ghost == null && _snap() == base, "esc cancels drag")
	
	# Undo/redo clear the selection.
	nm._select_all_notes()
	_key(KEY_Z, true)
	_check(nm._selection.is_empty(), "undo clears selection")
	
	# Focus routing: arrangement focus ignores note shortcuts.
	_set_notes(base)
	Controller.set_editor_focus(Controller.EditorFocus.ARRANGEMENT)
	nm._selection.clear()
	_key(KEY_A, true)
	_check(nm._selection.is_empty(), "unfocused note map ignores ctrl+a")
	Controller.set_editor_focus(Controller.EditorFocus.NOTES)
	
	# Drumkit pattern: rows are drum items.
	var kit := Controller.voice_manager.get_first_voice_data("DRUMKIT")
	Controller._set_current_instrument_by_voice(kit)
	await get_tree().process_frame
	_set_notes([Vector3i(0, 0, 1), Vector3i(3, 4, 1)] as Array[Vector3i])
	nm._select_all_notes()
	_check(nm._selection.size() == 2, "drum notes selectable")
	_key(KEY_UP)
	_check(_pattern().has_note(1, 0, true) && _pattern().has_note(4, 4, true), "drum rows move: %s" % [_snap()])
	_key(KEY_UP, true)
	_check(_pattern().has_note(2, 0, true), "drum ctrl+up shift")
	var rows := (Controller.get_current_instrument() as DrumkitInstrument).voices.size()
	_key(KEY_UP, false, true)
	_check(_pattern().has_note(10, 0, true) || rows <= 13, "drum shift+up = 8 rows")
	
	print("PHASE3 TESTS: %d failures" % _failures)
	get_tree().quit()
