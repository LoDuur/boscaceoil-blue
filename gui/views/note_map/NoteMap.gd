###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

@tool
class_name NoteMap extends Control

const CENTER_OCTAVE := 3
const SMALLEST_PATTERN_SIZE := 8 # Must be power-of-2!

const GUTTER_CDEFGAB_SIZE := 50
const GUTTER_DOREMI_SIZE := 64

## Pointer distance, in pixels, before a press on a note turns into a drag.
const DRAG_THRESHOLD := 4.0
## Distance from a grid edge, in pixels, that scrolls the grid while dragging.
const AUTOSCROLL_MARGIN := 24.0
const AUTOSCROLL_INTERVAL := 0.06
## Maximum number of moved notes previewed at once.
const MAX_PREVIEWED_NOTES := 8

enum Interaction {
	NONE,
	DRAWING_ADD,
	DRAWING_REMOVE,
	MARQUEE,
	PRESSING_NOTE,
	DRAGGING,
}

## Current edited pattern.
var current_pattern: Pattern = null
## Current instrument of the edited pattern.
var current_instrument: Instrument = null
## Number of notes in a row.
var pattern_size: int = 1
## Number of notes in a bar.
var bar_size: int = 1

## Current scale layout.
var _scale_layout: Array[int] = []
## Mapping between note values (in C key) and their row indices, based on the current scale.
var _note_value_row_map: Dictionary = {}
var _note_row_value_map: Dictionary = {}

## Window-dependent horizontal size of a note, based on pattern_size.
var _note_width: float = 0
## Offset, in number of note rows.
var _scroll_offset: int = 0
## Window-size dependent limit, based on Pattern.MAX_NOTE_VALUE and the current scale.
var _max_scroll_offset: int = -1

var _note_rows: Array[NoteRow] = []
var _octave_rows: Array[OctaveRow] = []
var _active_notes: Array[ActiveNote] = []
var _note_cursor_visible: bool = false
var _note_cursor_size: int = 1

var _interaction: Interaction = Interaction.NONE

## Selected notes, keyed by Vector2i(value, position).
var _selection: GridSelection = GridSelection.new()
## Selection before a marquee started; marquee selection is additive.
var _marquee_base: Array[Vector2i] = []
## Marquee corners, as Vector2i(tick, absolute row).
var _marquee_start_cell: Vector2i = Vector2i(-1, -1)
var _marquee_end_cell: Vector2i = Vector2i(-1, -1)

var _press_position: Vector2 = Vector2.ZERO
var _press_cell: Vector2i = Vector2i(-1, -1)
var _press_note_key: Vector2i = Vector2i(-1, -1)
var _press_was_selected: bool = false
var _press_copies: bool = false

## Pending placement from a paste, a duplicate, or a drag.
var _ghost: GhostPlacement = null
## Keys of the notes being dragged, as Vector2i(value, position).
var _drag_source_keys: Array[Vector2i] = []
var _ghost_hover_cell: Vector2i = Vector2i(-1, -1)
var _autoscroll_timer: float = 0.0

@onready var _gutter: NoteMapGutter = $NoteMapGutter
@onready var _scrollbar: NoteMapScrollbar = $NoteMapScrollbar
@onready var _overlay: NoteMapOverlay = $NoteMapOverlay


func _ready() -> void:
	set_physics_process(false)
	
	_update_gutter_size()
	_update_song_sizes()
	_update_playback_cursor()
	_edit_current_pattern()

	resized.connect(_update_song_sizes)
	resized.connect(_update_playback_cursor)
	resized.connect(_update_whole_grid)

	_gutter.resized.connect(_update_song_sizes)
	_gutter.resized.connect(_update_playback_cursor)
	_gutter.resized.connect(_update_whole_grid)
	
	mouse_entered.connect(_show_note_cursor)
	mouse_exited.connect(_hide_note_cursor)

	_gutter.note_preview_requested.connect(_preview_note_at_cursor)
	_scrollbar.shifted_up.connect(_change_scroll_offset.bind(1))
	_scrollbar.shifted_down.connect(_change_scroll_offset.bind(-1))
	_scrollbar.centered.connect(_center_scroll_offset)
	
	if not Engine.is_editor_hint():
		Controller.settings_manager.note_format_changed.connect(_update_gutter_size)
		
		Controller.song_loaded.connect(_update_song_sizes)
		Controller.song_loaded.connect(_edit_current_pattern)
		Controller.song_sizes_changed.connect(_update_song_sizes)
		Controller.song_pattern_changed.connect(_edit_current_pattern)
		
		Controller.music_player.playback_tick.connect(_update_playback_cursor)
		Controller.music_player.playback_stopped.connect(_update_playback_cursor)
		
		Controller.editor_focus_changed.connect(_update_focus_state)
		Controller.history_navigated.connect(_selection.clear)
		Controller.ghost_cancel_requested.connect(_cancel_ghost)
		Controller.pattern_notes_transformed.connect(_remap_selection)
		
		_selection.changed.connect(_on_selection_changed)


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	
	if what == NOTIFICATION_DRAG_END || what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _interaction == Interaction.DRAGGING:
			_cancel_ghost()
		_interaction = Interaction.NONE
		_stop_marquee()
		_update_processing_state()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		if mb.pressed && (mb.button_index == MOUSE_BUTTON_WHEEL_UP || mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if not _note_cursor_visible:
				return
			
			var wheel_delta := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if mb.is_command_or_control_pressed():
				_adjust_note_cursor(wheel_delta)
			else:
				_change_scroll_offset(wheel_delta)
			return
		
		if mb.pressed && (mb.button_index == MOUSE_BUTTON_LEFT || mb.button_index == MOUSE_BUTTON_RIGHT):
			Controller.set_editor_focus(Controller.EditorFocus.NOTES)
			if _note_cursor_visible:
				_handle_press(mb)
		
		elif not mb.pressed:
			_handle_release(mb)
	
	elif event is InputEventMouseMotion:
		if _interaction == Interaction.PRESSING_NOTE && get_local_mouse_position().distance_to(_press_position) > DRAG_THRESHOLD:
			_start_dragging()


func _handle_press(mb: InputEventMouseButton) -> void:
	if not Controller.current_song || not current_pattern:
		return
	
	# A pending placement takes over the mouse: left click places, right click cancels.
	if _ghost && not _ghost.is_drag():
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_follow_ghost_to_cursor()
			_commit_ghost()
		else:
			_cancel_ghost()
		return
	
	if _interaction == Interaction.DRAGGING:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_ghost()
		return
	
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_start_drawing_notes(Interaction.DRAWING_REMOVE)
		return
	
	var cell := _get_grid_cell_at_cursor()
	if cell.x < 0:
		return
	var note := _find_note_at_cell(cell)
	var note_key := Vector2i(note.x, note.y)
	var on_note := note.x >= 0
	
	if mb.alt_pressed:
		# Force-draw, even on top of another note's body.
		_selection.clear()
		_start_drawing_notes(Interaction.DRAWING_ADD)
	
	elif mb.shift_pressed:
		if on_note:
			_selection.toggle(note_key)
		else:
			_start_marquee(cell)
	
	elif mb.is_command_or_control_pressed():
		_set_cursor_size_at_cursor()
		if on_note && _selection.has(note_key):
			_start_pressing_note(cell, note_key, true)
	
	elif on_note:
		if not _selection.has(note_key):
			_selection.set_keys([ note_key ])
		_start_pressing_note(cell, note_key, false)
	
	else:
		_selection.clear()
		_start_drawing_notes(Interaction.DRAWING_ADD)


func _handle_release(mb: InputEventMouseButton) -> void:
	match _interaction:
		Interaction.DRAWING_ADD, Interaction.DRAWING_REMOVE:
			if mb.button_index == MOUSE_BUTTON_LEFT || mb.button_index == MOUSE_BUTTON_RIGHT:
				_stop_drawing_notes()
		
		Interaction.MARQUEE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_stop_marquee()
		
		Interaction.PRESSING_NOTE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				# A click on a note of a bigger selection narrows it to that note.
				if _press_was_selected && not _press_copies && _selection.size() > 1:
					_selection.set_keys([ _press_note_key ])
				_interaction = Interaction.NONE
				_update_processing_state()
		
		Interaction.DRAGGING:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_follow_ghost_to_cursor()
				_commit_ghost()


func _shortcut_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() || Controller.is_song_editing_locked():
		return
	if not is_visible_in_tree():
		return
	
	var focused := Controller.editor_focus == Controller.EditorFocus.NOTES
	
	if (_note_cursor_visible || focused) && event.is_action_pressed("bosca_notemap_cursor_bigger", true, true):
		_adjust_note_cursor(1)
		get_viewport().set_input_as_handled()
		return
	if (_note_cursor_visible || focused) && event.is_action_pressed("bosca_notemap_cursor_smaller", true, true):
		_adjust_note_cursor(-1)
		get_viewport().set_input_as_handled()
		return
	
	if not focused:
		return
	
	if _handle_editing_shortcut(event):
		get_viewport().set_input_as_handled()


## Keyboard editing for the focused note editor. Returns true when handled.
func _handle_editing_shortcut(event: InputEvent) -> bool:
	if not Controller.current_song || not current_pattern:
		return false
	
	if event.is_action_pressed("bosca_cancel", false, true):
		if _ghost:
			_cancel_ghost()
			return true
		if not _selection.is_empty():
			_selection.clear()
			return true
		return false
	
	if event.is_action_pressed("bosca_confirm", false, true):
		if _ghost && not _ghost.is_drag():
			_commit_ghost()
			return true
		return false
	
	# Arrows nudge a pending placement, or move the selection.
	var move_delta := _get_move_delta(event)
	if move_delta != Vector2i.ZERO:
		if _ghost:
			if not _ghost.is_drag() && _ghost.nudge(move_delta):
				_update_ghost_notes()
			return true
		if _selection.is_empty():
			return false # Fall back to scrolling.
		
		_move_selected_notes(move_delta)
		return true
	
	if _interaction == Interaction.DRAGGING:
		return false
	
	if event.is_action_pressed("bosca_select_all", false, true):
		_select_all_notes()
	elif event.is_action_pressed("bosca_copy", false, true):
		_copy_selected_notes()
	elif event.is_action_pressed("bosca_cut", false, true):
		_cut_selected_notes()
	elif event.is_action_pressed("bosca_paste", false, true):
		_paste_notes()
	elif event.is_action_pressed("bosca_duplicate", false, true):
		_duplicate_selected_notes()
	elif event.is_action_pressed("bosca_delete", false, true):
		_delete_selected_notes()
	elif event.is_action_pressed("bosca_notemap_resize_shorter", true, true):
		_resize_selected_notes(-1)
	elif event.is_action_pressed("bosca_notemap_resize_longer", true, true):
		_resize_selected_notes(1)
	elif event.is_action_pressed("bosca_notemap_shift_up", true, true):
		Controller.shift_current_pattern_notes(1)
	elif event.is_action_pressed("bosca_notemap_shift_down", true, true):
		Controller.shift_current_pattern_notes(-1)
	elif event.is_action_pressed("bosca_notemap_shift_octave_up", true, true):
		Controller.shift_current_pattern_notes(_get_octave_rows())
	elif event.is_action_pressed("bosca_notemap_shift_octave_down", true, true):
		Controller.shift_current_pattern_notes(-_get_octave_rows())
	elif event.is_action_pressed("bosca_notemap_shift_left", true, true):
		Controller.rotate_current_pattern_notes(-1)
	elif event.is_action_pressed("bosca_notemap_shift_right", true, true):
		Controller.rotate_current_pattern_notes(1)
	else:
		return false
	
	return true


func _get_move_delta(event: InputEvent) -> Vector2i:
	var big_step := Vector2i(bar_size, _get_octave_rows())
	
	if event.is_action_pressed("bosca_edit_move_up", true, true):
		return Vector2i(0, 1)
	if event.is_action_pressed("bosca_edit_move_down", true, true):
		return Vector2i(0, -1)
	if event.is_action_pressed("bosca_edit_move_left", true, true):
		return Vector2i(-1, 0)
	if event.is_action_pressed("bosca_edit_move_right", true, true):
		return Vector2i(1, 0)
	if event.is_action_pressed("bosca_edit_move_up_big", true, true):
		return Vector2i(0, big_step.y)
	if event.is_action_pressed("bosca_edit_move_down_big", true, true):
		return Vector2i(0, -big_step.y)
	if event.is_action_pressed("bosca_edit_move_left_big", true, true):
		return Vector2i(-big_step.x, 0)
	if event.is_action_pressed("bosca_edit_move_right_big", true, true):
		return Vector2i(big_step.x, 0)
	
	return Vector2i.ZERO


func _get_octave_rows() -> int:
	if not current_pattern:
		return Pattern.OCTAVE_SIZE
	return current_pattern.get_octave_rows(current_instrument)


func _physics_process(delta: float) -> void:
	_process_note_cursor()
	_process_note_drawing()
	_process_marquee()
	_process_ghost()
	_process_autoscroll(delta)


func _update_processing_state() -> void:
	set_physics_process(_note_cursor_visible || _interaction != Interaction.NONE || _ghost != null)


func _draw() -> void:
	var available_rect := get_available_rect()
	# Point of origin is at the bottom.
	var origin := Vector2(available_rect.position.x, available_rect.size.y)
	var note_height := get_theme_constant("note_height", "NoteMap")
	var border_width := get_theme_constant("border_width", "NoteMap")
	
	# Instrument-dependent colors.
	var note_base_color := get_theme_color("note_color", "NoteMap")
	var note_sharp_color := get_theme_color("note_sharp_color", "NoteMap")
	var light_border_color := get_theme_color("border_color", "NoteMap")
	var dark_border_color := get_theme_color("border_dark_color", "NoteMap")

	# Draw the rows.
	for note in _note_rows:
		var note_position := note.grid_position - Vector2(0, note_height)
		var note_size := Vector2(available_rect.size.x, note_height)
		var note_color := note_sharp_color if note.sharp else note_base_color
		draw_rect(Rect2(note_position, note_size), note_color)

	# Draw horizontal lines.
	for note in _note_rows:
		var border_size := Vector2(available_rect.size.x, border_width)
		draw_rect(Rect2(note.grid_position, border_size), dark_border_color)

	# Draw vertical lines.
	var col_index := 0
	var last_col_x := 0.0
	while col_index < (pattern_size + 1):
		var col_position := origin + Vector2(_note_width * col_index, -available_rect.size.y)
		var border_size := Vector2(border_width, available_rect.size.y)

		var thick_bar := col_index % bar_size == 0
		if thick_bar:
			var border_thick_size := border_size + Vector2(border_width, 0)
			var border_dark_position := col_position + Vector2(border_width, 0)
			
			draw_rect(Rect2(col_position, border_thick_size), light_border_color)
			draw_rect(Rect2(border_dark_position, border_size), dark_border_color)
		else:
			draw_rect(Rect2(col_position, border_size), light_border_color)
		
		col_index += 1
		last_col_x = col_position.x
	
	# Draw an extra cover on top of inactive bars.
	if last_col_x < available_rect.end.x:
		var cover_position := Vector2(last_col_x, origin.y - available_rect.size.y)
		var cover_size := Vector2(available_rect.end.x - last_col_x, available_rect.size.y)
		var cover_alpha := float(get_theme_constant("border_cover_opacity", "NoteMap")) / 100.0
		var cover_color := Color(light_border_color, cover_alpha)
		
		draw_rect(Rect2(cover_position, cover_size), cover_color)


func get_available_rect() -> Rect2:
	var available_rect := Rect2(Vector2.ZERO, size)
	if not is_inside_tree():
		return available_rect
	
	if _gutter:
		available_rect.position.x += _gutter.size.x
		available_rect.size.x -= _gutter.size.x
	if _scrollbar:
		available_rect.size.x -= _scrollbar.size.x
	
	return available_rect


# Scrolling.

func _update_max_scroll_offset() -> void:
	var available_rect := get_available_rect()
	var note_height := get_theme_constant("note_height", "NoteMap")
	var notes_on_screen := floori(available_rect.size.y / note_height)
	_max_scroll_offset = maxi(0, _note_row_value_map.size() - notes_on_screen)
	_scroll_offset = clampi(_scroll_offset, 0, _max_scroll_offset)


func _change_scroll_offset(delta: int) ->  void:
	_scroll_offset = clampi(_scroll_offset + delta, 0, _max_scroll_offset)
	_update_scrollables()


func _center_scroll_offset() -> void:
	var note_offset := _scroll_offset
	
	if current_pattern && current_pattern.note_amount > 0:
		var available_rect := get_available_rect()
		var note_height := get_theme_constant("note_height", "NoteMap")
		var notes_on_screen := floori(available_rect.size.y / note_height)
	
		var central_note_index := current_pattern.active_note_span[floori(current_pattern.active_note_span.size() / 2.0)]
		note_offset = _note_value_row_map[central_note_index] - roundi(notes_on_screen / 2.0)
	else:
		var scale_size := _scale_layout.size()
		note_offset = scale_size * CENTER_OCTAVE - 2
	
	_scroll_offset = clampi(note_offset, 0, _max_scroll_offset)
	_update_scrollables()


func _reset_scroll_offset() -> void:
	_scroll_offset = 0
	_update_scrollables()


# Editing and state visualization.

func _edit_current_pattern() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	if current_pattern:
		current_pattern.key_changed.disconnect(_update_whole_grid)
		current_pattern.scale_changed.disconnect(_update_whole_grid_and_center)
		current_pattern.instrument_changed.disconnect(_update_pattern_instrument)
		current_pattern.notes_changed.disconnect(_update_active_notes)
	
	var next_pattern := Controller.get_current_pattern()
	if next_pattern != current_pattern:
		_selection.clear()
		# A drag belongs to the pattern it started in; a paste ghost carries over.
		if _ghost && _ghost.is_drag():
			_cancel_ghost()
	
	current_pattern = next_pattern
	current_instrument = null

	if current_pattern:
		current_pattern.key_changed.connect(_update_whole_grid)
		current_pattern.scale_changed.connect(_update_whole_grid_and_center)
		current_pattern.instrument_changed.connect(_update_pattern_instrument)
		current_pattern.notes_changed.connect(_update_active_notes)
		
		current_instrument = Controller.current_song.instruments[current_pattern.instrument_idx]
	
	theme = Controller.get_instrument_theme(current_instrument)
	_update_whole_grid_and_center()
	_update_playback_cursor()


func _update_note_maps() -> void:
	_note_value_row_map.clear()
	_note_row_value_map.clear()
	
	if current_instrument && current_instrument.type == Instrument.InstrumentType.INSTRUMENT_DRUMKIT:
		var drumkit_instrument := current_instrument as DrumkitInstrument
		
		# For drumkits scale has no effect.
		for note_value in drumkit_instrument.voices.size():
			_note_value_row_map[note_value] = note_value
			_note_row_value_map[note_value] = note_value
		
		return

	_scale_layout = Scale.get_scale_layout(current_pattern.scale if current_pattern else Scale.SCALE_NORMAL)
	var scale_size := _scale_layout.size()
	var scale_index := 0
	var next_valid_note := 0
	var row_index := 0

	for note_value in Pattern.MAX_NOTE_VALUE:
		if next_valid_note != note_value:
			_note_value_row_map[note_value] = -1
			continue
		
		_note_value_row_map[note_value] = row_index
		_note_row_value_map[row_index] = note_value
		
		row_index += 1
		next_valid_note += _scale_layout[scale_index]
		scale_index += 1
		if scale_index >= scale_size:
			scale_index = 0


func _update_song_sizes() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	pattern_size = Controller.current_song.pattern_size
	bar_size = Controller.current_song.bar_size
	
	var available_rect := get_available_rect()
	
	# Round it up to the closes power-of-two, but no smaller than SMALLEST_PATTERN_SIZE.
	var effective_pattern_size := SMALLEST_PATTERN_SIZE
	while effective_pattern_size < pattern_size:
		effective_pattern_size <<= 1
	
	_note_width = available_rect.size.x / effective_pattern_size
	_overlay.note_unit_width = _note_width
	
	_adjust_note_cursor(0)
	_update_active_notes()
	queue_redraw()


func _update_scrollables() -> void:
	_update_grid_layout()
	_update_active_notes()


func _update_whole_grid() -> void:
	_refresh_edit_bounds()
	_update_note_maps()
	_update_max_scroll_offset()
	_update_scrollables()


func _update_whole_grid_and_center() -> void:
	_refresh_edit_bounds()
	_update_note_maps()
	_update_max_scroll_offset()
	_center_scroll_offset()


func _update_whole_grid_and_reset_scroll() -> void:
	_refresh_edit_bounds()
	_update_note_maps()
	_update_max_scroll_offset()
	_reset_scroll_offset()


func _update_pattern_instrument() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song || not current_pattern:
		return
	
	var old_instrument_type := current_instrument.type if current_instrument else -1
	current_instrument = Controller.current_song.instruments[current_pattern.instrument_idx]
	theme = Controller.get_instrument_theme(current_instrument)
	
	if current_instrument.type == Instrument.InstrumentType.INSTRUMENT_DRUMKIT:
		_update_whole_grid_and_reset_scroll()
	elif old_instrument_type != current_instrument.type:
		_update_whole_grid_and_center()
	else:
		queue_redraw()
		_overlay.queue_redraw()


func _update_playback_cursor() -> void:
	if Engine.is_editor_hint():
		return
	
	# Only display the cursor when it's the current pattern that's playing.
	if not current_pattern || not current_pattern.is_playing:
		_overlay.playback_cursor_position = -1
		_overlay.queue_redraw()
		return
	
	var available_rect := get_available_rect()
	var playback_note_index := Controller.music_player.get_pattern_time()
	
	# If the player is stopped, park the cursor all the way to the left.
	# This is normally unreachable by playback, as when playing at index 0 we want
	# to display the cursor to the right of the first note.
	if playback_note_index < 0:
		_overlay.playback_cursor_position = available_rect.position.x
		_overlay.queue_redraw()
		return
	
	_overlay.playback_cursor_position = available_rect.position.x + playback_note_index * _note_width
	_overlay.queue_redraw()


# Grid layout and coordinates.

func _get_cell_at_cursor() -> Vector2i:
	return _get_cell_at_position(get_local_mouse_position())


func _get_cell_at_position(at_position: Vector2) -> Vector2i:
	var available_rect: Rect2 = get_available_rect()
	var note_height := get_theme_constant("note_height", "NoteMap")
	
	if not available_rect.has_point(at_position):
		return Vector2i(-1, -1)
	
	var position_normalized := at_position - available_rect.position
	var cell_indexed := Vector2i(0, 0)
	cell_indexed.x = clampi(floori(position_normalized.x / _note_width), 0, pattern_size - 1)
	cell_indexed.y = clampi(floori((available_rect.size.y - position_normalized.y) / note_height), 0, _note_rows.size() - 1)
	return cell_indexed


func _get_cell_position(cell_indexed: Vector2i) -> Vector2:
	var available_rect := get_available_rect()
	var note_height := get_theme_constant("note_height", "NoteMap")
	
	return Vector2(
		available_rect.position.x + cell_indexed.x * _note_width,
		available_rect.size.y - (cell_indexed.y + 1) * note_height + available_rect.position.y
	)


func _update_grid_layout() -> void:
	# Reset collections.
	_note_rows.clear()
	_octave_rows.clear()

	var drumkit_instrument: DrumkitInstrument
	if current_instrument && current_instrument.type == Instrument.InstrumentType.INSTRUMENT_DRUMKIT:
		drumkit_instrument = current_instrument as DrumkitInstrument

	# Get reference data.
	var available_rect := get_available_rect()
	var scrollbar_available_rect: Rect2 = _scrollbar.get_available_rect()
	var note_height := get_theme_constant("note_height", "NoteMap")
	# Point of origin is at the bottom.
	var origin := Vector2(0, available_rect.size.y)

	var scale_size := _scale_layout.size()
	var current_key := current_pattern.key if current_pattern else 0

	# Iterate through all the notes and complete collections.
	
	var filled_height := 0
	var target_height := available_rect.size.y + Pattern.OCTAVE_SIZE * note_height # Give it some buffer.
	var row_index := 0
	var first_octave_index := -1
	var last_octave_index := -1
	
	# Keep rendering until we fill the screen, or reach the end of notes.
	while (row_index + _scroll_offset) < _note_row_value_map.size() && filled_height < target_height:
		var note_index: int = _note_row_value_map[row_index + _scroll_offset]
		var note_in_key := note_index % Pattern.OCTAVE_SIZE + current_key
		if note_in_key < 0:
			note_in_key = Pattern.OCTAVE_SIZE + note_in_key
		elif note_in_key >= Pattern.OCTAVE_SIZE:
			note_in_key = note_in_key - Pattern.OCTAVE_SIZE

		# Create data for a row of the grid, corresponding to one note value.
		
		var note := NoteRow.new()
		note.note_index = note_index
		note.label = Note.get_note_name(note_in_key)
		note.sharp = Note.is_note_sharp(note_in_key)
		note.position = origin - Vector2(0, row_index * note_height)
		note.grid_position = note.position + available_rect.position
		note.label_position = note.position + Vector2(0, -6)

		if drumkit_instrument:
			note.label = drumkit_instrument.get_note_name(note_index)
			note.sharp = (note_index + 1) % 2

		_note_rows.push_back(note)
		
		# Create data for octane rows that group spans of notes visually.
		# We do this as we go through notes, so we only create octaves which have visible notes
		# in them. Each unique octave is only created once.
		
		@warning_ignore("integer_division")
		var octave_index := note_index / Pattern.OCTAVE_SIZE
		if not drumkit_instrument && octave_index != last_octave_index:
			last_octave_index = octave_index
			if first_octave_index == -1:
				first_octave_index = octave_index
			
			var octave_ref_note := (last_octave_index - first_octave_index + 1) * scale_size - _scroll_offset % scale_size - 1
			
			var octave := OctaveRow.new()
			octave.octave_index = octave_index
			octave.position = origin - Vector2(0, octave_ref_note * note_height)
			octave.label_position = octave.position
			
			# Make the label position sticky.
			var prev_octave_position := origin - Vector2(0, (octave_ref_note - scale_size) * note_height)
			if (octave.position.y - note_height) < scrollbar_available_rect.position.y:
				if (prev_octave_position.y - note_height) > (scrollbar_available_rect.position.y + note_height):
					octave.label_position.y = scrollbar_available_rect.position.y + note_height
				else:
					octave.label_position.y = prev_octave_position.y - note_height
			
			octave.label_position += Vector2(0, -6)
			
			_octave_rows.push_back(octave)
		
		# Update counters.
		
		filled_height += note_height
		row_index += 1
	
	# Update children with the new data.
	_gutter.note_rows = _note_rows
	_scrollbar.octave_rows = _octave_rows
	_overlay.octave_rows = _octave_rows
	
	queue_redraw()
	_gutter.queue_redraw()
	_scrollbar.queue_redraw()
	_overlay.queue_redraw()


func _update_active_notes() -> void:
	# Reset the collection
	_active_notes.clear()
	if not current_pattern:
		_overlay.active_notes = _active_notes
		return
	
	# Notes removed or hidden by another edit leave the selection.
	_selection.retain(_is_note_key_selectable)

	for i in current_pattern.note_amount:
		var note_data := current_pattern.notes[i]
		if not current_pattern.is_note_valid(note_data, pattern_size):
			continue # Outside of the pattern bounds, or too short to play.
		
		var note_value_normalized := note_data.x - current_pattern.key # Shift to its C-key equivalent.
		if note_value_normalized < 0 || note_value_normalized >= _note_value_row_map.size():
			continue # Outside of the valid note range.
		
		var row_index: int = _note_value_row_map[note_value_normalized]
		if row_index < 0:
			continue # Doesn't fit the scale.
		
		var note := ActiveNote.new()
		note.note_value = note_value_normalized
		note.note_index = note_data.y
		note.cell_index = Vector2i(note_data.y, row_index - _scroll_offset)
		note.position = _get_cell_position(note.cell_index)
		note.length = note_data.z
		
		var note_key := Vector2i(note_data.x, note_data.y)
		note.selected = _selection.has(note_key)
		note.dimmed = _ghost && _ghost.source == GhostPlacement.Source.DRAG_MOVE && _drag_source_keys.has(note_key)
		_active_notes.push_back(note)
	
	# Update children with the new data.
	_overlay.active_notes = _active_notes
	_update_ghost_notes()
	_overlay.queue_redraw()


func _update_gutter_size() -> void:
	if Engine.is_editor_hint():
		_gutter.custom_minimum_size.x = GUTTER_CDEFGAB_SIZE
		return
	
	var note_format := Controller.settings_manager.get_note_format()
	if note_format == SettingsManager.NoteFormat.FORMAT_DOREMI:
		_gutter.custom_minimum_size.x = GUTTER_DOREMI_SIZE
	else:
		_gutter.custom_minimum_size.x = GUTTER_CDEFGAB_SIZE


# Note cursor and drawing.

func _show_note_cursor() -> void:
	_note_cursor_visible = true
	_process_note_cursor()
	_update_processing_state()


func _hide_note_cursor() -> void:
	_note_cursor_visible = false
	_update_processing_state()
	_process_note_cursor()


func _adjust_note_cursor(delta: int) -> void:
	_note_cursor_size = clamp(_note_cursor_size + delta, 1, Pattern.MAX_NOTE_LENGTH)
	_overlay.note_cursor_size = _note_cursor_size
	_overlay.queue_redraw()


func _resize_note_cursor(value: int) -> void:
	_note_cursor_size = clamp(value, 1, Pattern.MAX_NOTE_LENGTH)
	_overlay.note_cursor_size = _note_cursor_size
	_overlay.queue_redraw()


func _set_cursor_size_at_cursor() -> void:
	if not Controller.current_song || not current_pattern:
		return

	var note_indexed := _get_cell_at_cursor()
	if note_indexed.x < 0 || note_indexed.y < 0:
		return
	var note_value_index := note_indexed.y + _scroll_offset
	if note_value_index >= _note_row_value_map.size():
		return
	
	var note_value: int = _note_row_value_map[note_value_index] + current_pattern.key
	var note_data := current_pattern.get_note(note_value, note_indexed.x)
	
	if current_pattern.is_note_valid(note_data, Controller.current_song.pattern_size):
		_resize_note_cursor(note_data.z)
	else:
		_resize_note_cursor(1)


func _process_note_cursor() -> void:
	# The ghost replaces the cursor while it's active.
	if not _note_cursor_visible || _ghost:
		_overlay.note_cursor_position = Vector2(-1, -1)
		_overlay.queue_redraw()
		return
	
	var note_indexed := _get_cell_at_cursor()
	if note_indexed.x >= 0 && note_indexed.y >= 0:
		_overlay.note_cursor_position = _get_cell_position(note_indexed)
	else:
		_overlay.note_cursor_position = Vector2(-1, -1)
	
	_overlay.queue_redraw()


func _start_drawing_notes(mode: Interaction) -> void:
	_interaction = mode
	_update_processing_state()
	_process_note_drawing()


func _stop_drawing_notes() -> void:
	_interaction = Interaction.NONE
	_update_processing_state()


func _process_note_drawing() -> void:
	if _interaction == Interaction.DRAWING_ADD:
		_add_note_at_cursor()
	elif _interaction == Interaction.DRAWING_REMOVE:
		_remove_note_at_cursor()


func _add_note_at_cursor() -> void:
	if not Controller.current_song || not current_pattern:
		return

	var note_indexed := _get_cell_at_cursor()
	if note_indexed.x < 0 || note_indexed.y < 0:
		return
	var note_value_index := note_indexed.y + _scroll_offset
	if note_value_index >= _note_row_value_map.size():
		return
	
	var note_value: int = _note_row_value_map[note_value_index] + current_pattern.key
	if current_pattern.has_note(note_value, note_indexed.x, true):
		return # Space is already occupied.
	if current_pattern.note_amount >= Pattern.MAX_NOTES_IN_PATTERN:
		return
	
	var note_data := Vector3i(note_value, note_indexed.x, _note_cursor_size)
	
	var pattern_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.PATTERN, Controller.current_pattern_index)
	pattern_state.add_do_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.add_note(note_data.x, note_data.y, note_data.z)
	)
	pattern_state.add_undo_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.remove_note(note_data.x, note_data.y, true)
	)
	
	Controller.state_manager.commit_state_change(pattern_state)


func _remove_note_at_cursor() -> void:
	if not Controller.current_song || not current_pattern:
		return

	var note_indexed := _get_cell_at_cursor()
	if note_indexed.x < 0 || note_indexed.y < 0:
		return
	var note_value_index := note_indexed.y + _scroll_offset
	if note_value_index >= _note_row_value_map.size():
		return
	
	var note_value: int = _note_row_value_map[note_value_index] + current_pattern.key
	if not current_pattern.has_note(note_value, note_indexed.x, true):
		return # Space is empty.
	
	var note_data := Vector3i(note_value, note_indexed.x, 0)
	note_data.z = current_pattern.get_note_length(note_data.x, note_data.y)
	
	var pattern_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.PATTERN, Controller.current_pattern_index)
	pattern_state.add_do_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.remove_note(note_data.x, note_data.y, true)
	)
	pattern_state.add_undo_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.add_note(note_data.x, note_data.y, note_data.z)
	)
	
	Controller.state_manager.commit_state_change(pattern_state)


func _preview_note_at_cursor(row_index: int) -> void:
	if not Controller.current_song || not current_pattern:
		return

	var note := _note_rows[row_index]
	var note_value := note.note_index + current_pattern.key
	Controller.preview_pattern_note(note_value, _note_cursor_size)


# Grid cells and notes.
# Editing works on cells as Vector2i(tick, absolute row), independent of the
# scroll offset. Notes are identified by Vector2i(value, position).

func _get_row_count() -> int:
	return _note_row_value_map.size()


func _get_edit_bounds() -> Rect2i:
	return Rect2i(0, 0, pattern_size, _get_row_count())


func _refresh_edit_bounds() -> void:
	if _ghost:
		_ghost.bounds = _get_edit_bounds()


func _get_grid_cell_at_cursor() -> Vector2i:
	var cell := _get_cell_at_cursor()
	if cell.x < 0 || cell.y < 0:
		return Vector2i(-1, -1)
	
	var row := cell.y + _scroll_offset
	if row >= _get_row_count():
		return Vector2i(-1, -1)
	return Vector2i(cell.x, row)


## Like _get_grid_cell_at_cursor(), but snaps a pointer outside the grid to its
## nearest edge, for drags and marquees.
func _get_grid_cell_at_cursor_clamped() -> Vector2i:
	var available_rect := get_available_rect()
	var mouse_position := get_local_mouse_position()
	var inner_rect := available_rect.grow(-1.0)
	mouse_position = mouse_position.clamp(inner_rect.position, inner_rect.end)
	
	var cell := _get_cell_at_position(mouse_position)
	if cell.x < 0 || cell.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(cell.x, mini(cell.y + _scroll_offset, _get_row_count() - 1))


func _get_note_cell(note_data: Vector3i) -> Vector2i:
	if not current_pattern || not current_pattern.is_note_valid(note_data, pattern_size):
		return Vector2i(-1, -1)
	
	var value_normalized := note_data.x - current_pattern.key
	if not _note_value_row_map.has(value_normalized):
		return Vector2i(-1, -1)
	var row: int = _note_value_row_map[value_normalized]
	if row < 0:
		return Vector2i(-1, -1)
	
	return Vector2i(note_data.y, row)


func _get_row_value(row: int) -> int:
	return _note_row_value_map[row] + current_pattern.key


## Finds the note covering the cell; a note starting on the cell wins over
## overlapping tails, and the latest-starting tail wins among those.
func _find_note_at_cell(cell: Vector2i) -> Vector3i:
	var found := Vector3i(-1, -1, -1)
	if not current_pattern || cell.y < 0 || cell.y >= _get_row_count():
		return found
	
	var value := _get_row_value(cell.y)
	for i in current_pattern.note_amount:
		var note_data := current_pattern.notes[i]
		if note_data.x != value || not current_pattern.is_note_valid(note_data, pattern_size):
			continue
		if cell.x < note_data.y || cell.x >= (note_data.y + note_data.z):
			continue
		
		if note_data.y == cell.x:
			return note_data
		if note_data.y > found.y:
			found = note_data
	
	return found


func _is_note_key_selectable(key: Vector2i) -> bool:
	if not current_pattern:
		return false
	
	var note_data := current_pattern.get_note(key.x, key.y, true)
	return _get_note_cell(note_data).x >= 0


func _get_selectable_notes() -> Array[Vector3i]:
	var selectable: Array[Vector3i] = []
	if not current_pattern:
		return selectable
	
	for note_data in current_pattern.get_notes_snapshot():
		if _get_note_cell(note_data).x >= 0:
			selectable.push_back(note_data)
	return selectable


func _get_selected_notes() -> Array[Vector3i]:
	var selected: Array[Vector3i] = []
	for note_data in _get_selectable_notes():
		if _selection.has(Vector2i(note_data.x, note_data.y)):
			selected.push_back(note_data)
	return selected


## Converts notes to Vector3i(tick, row, length) grid items.
func _notes_to_grid_items(notes: Array[Vector3i]) -> Array[Vector3i]:
	var items: Array[Vector3i] = []
	for note_data in notes:
		var cell := _get_note_cell(note_data)
		items.push_back(Vector3i(cell.x, cell.y, note_data.z))
	return items


static func _get_note_keys(notes: Array[Vector3i]) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for note_data in notes:
		keys.push_back(Vector2i(note_data.x, note_data.y))
	return keys


static func _are_notes_equal(a: Array[Vector3i], b: Array[Vector3i]) -> bool:
	if a.size() != b.size():
		return false
	
	var sorted_a := a.duplicate()
	var sorted_b := b.duplicate()
	sorted_a.sort()
	sorted_b.sort()
	return sorted_a == sorted_b


## Places notes into the pattern, overwriting notes that start at the same
## cells, as one undoable change. Returns the placed notes, which may be fewer
## than requested if the pattern is full.
func _place_notes(base_notes: Array[Vector3i], placed_notes: Array[Vector3i], accum_id: String = "") -> Array[Vector3i]:
	var placed_keys := {}
	for note_data in placed_notes:
		placed_keys[Vector2i(note_data.x, note_data.y)] = true
	
	var next_notes: Array[Vector3i] = []
	for note_data in base_notes:
		if not placed_keys.has(Vector2i(note_data.x, note_data.y)):
			next_notes.push_back(note_data)
	
	var capacity := Pattern.MAX_NOTES_IN_PATTERN - next_notes.size()
	var skipped := maxi(0, placed_notes.size() - capacity)
	var fitting_notes: Array[Vector3i] = placed_notes.slice(0, placed_notes.size() - skipped)
	next_notes.append_array(fitting_notes)
	
	if not _are_notes_equal(next_notes, current_pattern.get_notes_snapshot()):
		Controller.commit_pattern_notes(Controller.current_pattern_index, next_notes, accum_id)
	
	if skipped > 0:
		Controller.update_status("PATTERN FULL — %d %s SKIPPED" % [ skipped, _pluralize_notes(skipped) ], Controller.StatusLevel.WARNING)
	return fitting_notes


static func _pluralize_notes(amount: int) -> String:
	return "NOTE" if amount == 1 else "NOTES"


# Selection.

func _on_selection_changed() -> void:
	for active_note in _active_notes:
		var note_key := Vector2i(active_note.note_value + current_pattern.key, active_note.note_index) if current_pattern else Vector2i(-1, -1)
		active_note.selected = _selection.has(note_key)
	_overlay.queue_redraw()
	
	_update_arrow_capture()
	if _interaction != Interaction.MARQUEE:
		_report_selection_size()


func _report_selection_size() -> void:
	if _selection.size() > 1:
		Controller.update_status("%d NOTES SELECTED" % [ _selection.size() ], Controller.StatusLevel.INFO)


func _update_arrow_capture() -> void:
	if Engine.is_editor_hint():
		return
	Controller.set_editor_arrow_capture(Controller.EditorFocus.NOTES, not _selection.is_empty() || _ghost != null)


func _update_focus_state() -> void:
	_overlay.focused = Controller.editor_focus == Controller.EditorFocus.NOTES
	_overlay.queue_redraw()


## Carries the selection over a whole-pattern transform (shift or rotation).
func _remap_selection(pattern_index: int, before: Array[Vector3i], after: Array[Vector3i]) -> void:
	if pattern_index != Controller.current_pattern_index || _selection.is_empty():
		return
	
	var next_keys: Array[Vector2i] = []
	for i in mini(before.size(), after.size()):
		if _selection.has(Vector2i(before[i].x, before[i].y)):
			next_keys.push_back(Vector2i(after[i].x, after[i].y))
	_selection.set_keys(next_keys)


func _select_all_notes() -> void:
	_selection.set_keys(_get_note_keys(_get_selectable_notes()))


func _start_pressing_note(cell: Vector2i, note_key: Vector2i, copies: bool) -> void:
	_interaction = Interaction.PRESSING_NOTE
	_press_position = get_local_mouse_position()
	_press_cell = cell
	_press_note_key = note_key
	_press_was_selected = _selection.has(note_key)
	_press_copies = copies
	_update_processing_state()


# Marquee.

func _start_marquee(cell: Vector2i) -> void:
	_interaction = Interaction.MARQUEE
	_marquee_base = _selection.get_keys()
	_marquee_start_cell = cell
	_marquee_end_cell = cell
	_update_processing_state()
	_process_marquee()


func _stop_marquee() -> void:
	if _interaction == Interaction.MARQUEE:
		_interaction = Interaction.NONE
		_update_processing_state()
		_report_selection_size()
	
	_marquee_start_cell = Vector2i(-1, -1)
	_overlay.note_selecting_rect = Rect2(-1, -1, 0, 0)
	_overlay.queue_redraw()


func _process_marquee() -> void:
	if _interaction != Interaction.MARQUEE:
		return
	
	var cell := _get_grid_cell_at_cursor_clamped()
	if cell.x >= 0:
		_marquee_end_cell = cell
	
	var cell_rect := Rect2i(_marquee_start_cell, Vector2i.ZERO).expand(_marquee_end_cell)
	cell_rect.size += Vector2i(1, 1) # Far edges are inclusive.
	
	var next_keys := _marquee_base.duplicate()
	for note_data in _get_selectable_notes():
		if cell_rect.has_point(_get_note_cell(note_data)):
			next_keys.push_back(Vector2i(note_data.x, note_data.y))
	_selection.set_keys(next_keys)
	
	# Visualize the marquee snapped to cells, in on-screen coordinates.
	var note_height := get_theme_constant("note_height", "NoteMap")
	var top_left := _get_cell_position(Vector2i(cell_rect.position.x, cell_rect.end.y - 1 - _scroll_offset))
	var pixel_size := Vector2(cell_rect.size.x * _note_width, cell_rect.size.y * note_height)
	_overlay.note_selecting_rect = Rect2(top_left, pixel_size).intersection(get_available_rect())
	_overlay.queue_redraw()


# Ghost placement and dragging.

func _start_ghost(items: Array[Vector3i], source: GhostPlacement.Source, anchor: Vector2i) -> void:
	_ghost = GhostPlacement.new(GridClipboard.to_relative(items), source, _get_edit_bounds())
	_ghost.anchor_cell = _ghost.clamp_anchor(anchor)
	_ghost_hover_cell = Vector2i(-1, -1)
	
	_update_arrow_capture()
	_update_processing_state()
	_update_active_notes()


func _cancel_ghost() -> void:
	if not _ghost:
		return
	
	_ghost = null
	_drag_source_keys.clear()
	if _interaction == Interaction.DRAGGING:
		_interaction = Interaction.NONE
	
	_update_arrow_capture()
	_update_processing_state()
	_update_active_notes()


func _follow_ghost_to_cursor() -> void:
	if not _ghost:
		return
	
	var cell := _get_grid_cell_at_cursor_clamped() if _ghost.is_drag() else _get_grid_cell_at_cursor()
	if cell.x < 0 || cell == _ghost_hover_cell:
		return
	
	_ghost_hover_cell = cell
	if _ghost.follow_cell(cell):
		_update_ghost_notes()


func _process_ghost() -> void:
	if _ghost:
		_follow_ghost_to_cursor()


func _update_ghost_notes() -> void:
	var ghost_notes: Array[GhostNote] = []
	
	if _ghost && current_pattern:
		var ignored_keys := _drag_source_keys if _ghost.source == GhostPlacement.Source.DRAG_MOVE else ([] as Array[Vector2i])
		var is_occupied := func(cell: Vector2i) -> bool:
			var key := Vector2i(_get_row_value(cell.y), cell.x)
			return current_pattern.has_note(key.x, key.y, true) && not ignored_keys.has(key)
		var fit_mask := _ghost.is_valid_at(_ghost.anchor_cell, is_occupied)
		
		for i in _ghost.items.size():
			if fit_mask[i] == GhostPlacement.FIT_NONE:
				continue
			
			var cell := _ghost.get_item_cell(_ghost.items[i], _ghost.anchor_cell)
			var visible_row := cell.y - _scroll_offset
			if visible_row < 0 || visible_row >= _note_rows.size():
				continue
			
			var ghost_note := GhostNote.new()
			ghost_note.position = _get_cell_position(Vector2i(cell.x, visible_row))
			ghost_note.length = _ghost.items[i].z
			ghost_note.conflict = fit_mask[i] == GhostPlacement.FIT_CONFLICT
			ghost_notes.push_back(ghost_note)
	
	_overlay.ghost_notes = ghost_notes
	_process_note_cursor()
	_overlay.queue_redraw()


func _start_dragging() -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		_interaction = Interaction.NONE
		_update_processing_state()
		return
	
	var items := _notes_to_grid_items(selected_notes)
	var source := GhostPlacement.Source.DRAG_COPY if _press_copies else GhostPlacement.Source.DRAG_MOVE
	_drag_source_keys = _get_note_keys(selected_notes)
	_interaction = Interaction.DRAGGING
	
	var group_anchor := Vector2i(items[0].x, items[0].y)
	for item in items:
		group_anchor = Vector2i(mini(group_anchor.x, item.x), mini(group_anchor.y, item.y))
	
	_start_ghost(items, source, group_anchor)
	_ghost.grab_offset = _press_cell - group_anchor
	_ghost.source_cells.assign(items.map(func(item: Vector3i) -> Vector2i: return Vector2i(item.x, item.y)))


func _commit_ghost() -> void:
	if not _ghost || not current_pattern:
		return
	
	var ghost := _ghost
	var source_keys := _drag_source_keys.duplicate()
	_cancel_ghost()
	
	var bounds := _get_edit_bounds()
	var placed_notes: Array[Vector3i] = []
	var dropped := 0
	for item in ghost.items:
		var cell := ghost.get_item_cell(item, ghost.anchor_cell)
		if not bounds.has_point(cell):
			dropped += 1
			continue
		placed_notes.push_back(Vector3i(_get_row_value(cell.y), cell.x, item.z))
	
	var base_notes := current_pattern.get_notes_snapshot()
	if ghost.source == GhostPlacement.Source.DRAG_MOVE:
		base_notes = base_notes.filter(func(note_data: Vector3i) -> bool: return not source_keys.has(Vector2i(note_data.x, note_data.y)))
	
	var fitting_notes := _place_notes(base_notes, placed_notes)
	_selection.set_keys(_get_note_keys(fitting_notes))
	
	if dropped > 0:
		Controller.update_status("%d %s DIDN'T FIT" % [ dropped, _pluralize_notes(dropped) ], Controller.StatusLevel.WARNING)


func _process_autoscroll(delta: float) -> void:
	if _interaction != Interaction.DRAGGING && _interaction != Interaction.MARQUEE:
		_autoscroll_timer = 0.0
		return
	
	_autoscroll_timer -= delta
	if _autoscroll_timer > 0.0:
		return
	
	var available_rect := get_available_rect()
	var mouse_y := get_local_mouse_position().y
	if mouse_y < available_rect.position.y + AUTOSCROLL_MARGIN:
		_change_scroll_offset(1)
		_autoscroll_timer = AUTOSCROLL_INTERVAL
	elif mouse_y > available_rect.end.y - AUTOSCROLL_MARGIN:
		_change_scroll_offset(-1)
		_autoscroll_timer = AUTOSCROLL_INTERVAL


# Clipboard and keyboard editing.

func _copy_selected_notes() -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	Controller.note_clipboard.store(_notes_to_grid_items(selected_notes))
	Controller.update_status("%d %s COPIED" % [ selected_notes.size(), _pluralize_notes(selected_notes.size()) ], Controller.StatusLevel.INFO)


func _cut_selected_notes() -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	_copy_selected_notes()
	_delete_selected_notes()


func _paste_notes() -> void:
	if Controller.note_clipboard.is_empty():
		return
	
	var anchor := _get_grid_cell_at_cursor()
	if anchor.x < 0:
		anchor = Vector2i(0, _scroll_offset) # Bottom-left of the visible grid.
	_start_ghost(Controller.note_clipboard.get_items(), GhostPlacement.Source.PASTE, anchor)


func _duplicate_selected_notes() -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	var anchor := _get_grid_cell_at_cursor()
	var items := _notes_to_grid_items(selected_notes)
	if anchor.x < 0:
		anchor = Vector2i(items[0].x, items[0].y)
		for item in items:
			anchor = Vector2i(mini(anchor.x, item.x), mini(anchor.y, item.y))
	_start_ghost(items, GhostPlacement.Source.DUPLICATE, anchor)


func _delete_selected_notes() -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	var selected_keys := _get_note_keys(selected_notes)
	var next_notes: Array[Vector3i] = current_pattern.get_notes_snapshot().filter(func(note_data: Vector3i) -> bool:
		return not selected_keys.has(Vector2i(note_data.x, note_data.y))
	)
	Controller.commit_pattern_notes(Controller.current_pattern_index, next_notes)
	_selection.clear()


func _move_selected_notes(delta: Vector2i) -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	# The whole selection moves, or nothing does.
	var bounds := _get_edit_bounds()
	var moved_notes: Array[Vector3i] = []
	for note_data in selected_notes:
		var cell := _get_note_cell(note_data) + delta
		if not bounds.has_point(cell):
			Controller.update_status("CAN'T MOVE — SELECTION AT THE EDGE", Controller.StatusLevel.WARNING)
			return
		moved_notes.push_back(Vector3i(_get_row_value(cell.y), cell.x, note_data.z))
	
	var selected_keys := _get_note_keys(selected_notes)
	var base_notes: Array[Vector3i] = current_pattern.get_notes_snapshot().filter(func(note_data: Vector3i) -> bool:
		return not selected_keys.has(Vector2i(note_data.x, note_data.y))
	)
	
	# Key repeat accumulates into one undo step.
	var fitting_notes := _place_notes(base_notes, moved_notes, "notes_nudge_%d" % [ Controller.current_pattern_index ])
	_selection.set_keys(_get_note_keys(fitting_notes))
	
	if delta.y != 0 && not Controller.music_player.is_playing():
		var preview_values: Array[int] = []
		for note_data in fitting_notes:
			if preview_values.size() >= MAX_PREVIEWED_NOTES:
				break
			preview_values.push_back(note_data.x)
		Controller.preview_pattern_notes(preview_values, 1)


func _resize_selected_notes(delta: int) -> void:
	var selected_notes := _get_selected_notes()
	if selected_notes.is_empty():
		return
	
	var selected_keys := _get_note_keys(selected_notes)
	var next_notes: Array[Vector3i] = []
	for note_data in current_pattern.get_notes_snapshot():
		if selected_keys.has(Vector2i(note_data.x, note_data.y)):
			next_notes.push_back(Vector3i(note_data.x, note_data.y, clampi(note_data.z + delta, 1, Pattern.MAX_NOTE_LENGTH)))
		else:
			next_notes.push_back(note_data)
	
	if _are_notes_equal(next_notes, current_pattern.get_notes_snapshot()):
		return
	Controller.commit_pattern_notes(Controller.current_pattern_index, next_notes, "notes_resize_%d" % [ Controller.current_pattern_index ])


class NoteRow:
	var note_index: int = -1
	var label: String = ""
	var sharp: bool = false
	var position: Vector2 = Vector2.ZERO
	var grid_position: Vector2 = Vector2.ZERO
	var label_position: Vector2 = Vector2.ZERO


class OctaveRow:
	var octave_index: int = -1
	var position: Vector2 = Vector2.ZERO
	var label_position: Vector2 = Vector2.ZERO


class ActiveNote:
	var note_value: int = -1
	var note_index: int = -1
	var cell_index: Vector2i = Vector2i(-1, -1)
	var position: Vector2 = Vector2.ZERO
	var length: int = 1
	
	var selected: bool = false
	## Source of a move in progress, drawn faded.
	var dimmed: bool = false


class GhostNote:
	var position: Vector2 = Vector2.ZERO
	var length: int = 1
	## Would overwrite an existing note.
	var conflict: bool = false
