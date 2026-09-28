###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

@tool
class_name PatternMap extends Control

const PATTERN_WIDTH_MIN := 0.5
const PATTERN_WIDTH_MAX := 1.0
const PATTERN_WIDTH_STEP := 0.05

## Pointer distance, in pixels, before a press on a placement turns into a drag.
const DRAG_THRESHOLD := 4.0
## Distance from a grid edge, in pixels, that scrolls the grid while dragging.
const AUTOSCROLL_MARGIN := 24.0
const AUTOSCROLL_INTERVAL := 0.08
## Cells moved by Shift+arrows.
const BIG_STEP := 4

enum Interaction {
	NONE,
	MARQUEE,
	PRESSING,
	DRAGGING,
}

## Currently edited arrangement for the song.
var current_arrangement: Arrangement = null
## Currently edited pattern.
var current_pattern: Pattern = null

var _hovering: bool = false

## Control-size-dependent vertical size of a pattern.
var _pattern_height: float = 0
## Controllable scale for the horizontal size of a pattern.
var _pattern_width_scale: float = 1.0
var _pattern_width: float = 0
## Offset, in number of timeline bars/pattern columns.
var _scroll_offset: int = 0
## Window-size dependent limit.
var _max_scroll_offset: int = -1
## Whether to follow the playback cursor with scroll or not.
var _following_playback_cursor: bool = false

var _interaction: Interaction = Interaction.NONE
## Selected placements, keyed by Vector2i(bar, channel).
var _selection: GridSelection = GridSelection.new()
var _marquee_base: Array[Vector2i] = []
var _marquee_start_cell: Vector2i = Vector2i(-1, -1)
var _marquee_end_cell: Vector2i = Vector2i(-1, -1)

var _press_position: Vector2 = Vector2.ZERO
var _press_cell: Vector2i = Vector2i(-1, -1)
var _press_was_selected: bool = false
var _press_copies: bool = false
var _press_makes_variant: bool = false

## Pending placement from a paste, a duplicate, or a drag.
var _ghost: GhostPlacement = null
var _ghost_hover_cell: Vector2i = Vector2i(-1, -1)
var _autoscroll_timer: float = 0.0

var _arrangement_channels: Array[ArrangementChannel] = []
var _arrangement_bars: Array[ArrangementBar] = []
var _active_patterns: Array[ActivePattern] = []

# Theme cache.

var _row_odd_color: Color = Color.WHITE
var _row_even_color: Color = Color.WHITE
var _border_width: int = 0
var _border_color: Color = Color.WHITE
var _border_cover_opacity: float = 1.0

var _pattern_base_width: int = 0
var _pattern_label_offset: Vector2 = Vector2.ZERO
var _item_gutter_width: float = 0.0
var _note_border_width: int = 0

@onready var _track: Control = %PatternMapTrack
@onready var _timeline: Control = %PatternMapTimeline
@onready var _items: Control = %PatternMapItems
@onready var _overlay: Control = %PatternMapOverlay
@onready var _scrollbar: Control = %PatternMapScrollbar


func _ready() -> void:
	set_physics_process(false)
	
	_update_theme()

	theme_changed.connect(_update_theme)
	theme_changed.connect(_update_pattern_sizes)
	theme_changed.connect(_update_playback_cursor)
	theme_changed.connect(_update_whole_grid)
	
	_update_pattern_sizes()
	_update_playback_cursor()
	_edit_current_arrangement()
	
	resized.connect(_update_pattern_sizes)
	resized.connect(_update_playback_cursor)
	resized.connect(_update_whole_grid)
	
	mouse_entered.connect(_start_hovering)
	mouse_exited.connect(_stop_hovering)
	
	if not Engine.is_editor_hint():
		_scrollbar.set_button_offset(_timeline.size.y, -_track.size.y)
		
		_track.loop_changed.connect(_change_arrangement_loop)
		_track.loop_changed_to_end.connect(_change_arrangement_loop_to_end)
		_track.bar_inserted.connect(_insert_timeline_bar)
		_track.bar_removed.connect(_remove_timeline_bar)
		_track.bars_copied.connect(_copy_timeline_bars)
		_track.bars_pasted.connect(_paste_timeline_bars)
		
		_scrollbar.shifted_right.connect(_change_scroll_offset.bind(1))
		_scrollbar.shifted_left.connect(_change_scroll_offset.bind(-1))
		_track.shifted_right.connect(_change_scroll_offset.bind(1))
		_track.shifted_left.connect(_change_scroll_offset.bind(-1))
		
		Controller.song_loaded.connect(_edit_current_arrangement)
		Controller.song_pattern_changed.connect(_edit_current_pattern)
		Controller.song_sizes_changed.connect(_update_active_patterns)
		
		Controller.music_player.playback_tick.connect(_update_playback_cursor)
		Controller.music_player.playback_stopped.connect(_update_playback_cursor)
		# Exporting always follows the playback; otherwise it's the user's choice.
		Controller.music_player.export_started.connect(func() -> void: _following_playback_cursor = true)
		Controller.music_player.export_ended.connect(func() -> void: _following_playback_cursor = Controller.follow_playback)
		Controller.follow_playback_changed.connect(func() -> void: _following_playback_cursor = Controller.follow_playback)
		
		Controller.editor_focus_changed.connect(_update_focus_state)
		Controller.history_navigated.connect(_selection.clear)
		Controller.ghost_cancel_requested.connect(_cancel_ghost)
		visibility_changed.connect(_release_focus_when_hidden)
		
		_selection.changed.connect(_on_selection_changed)


func _update_theme() -> void:
	_row_odd_color = get_theme_color("row_odd_color", "PatternMap")
	_row_even_color = get_theme_color("row_even_color", "PatternMap")
	_border_width = get_theme_constant("border_width", "PatternMap")
	_border_color = get_theme_color("border_color", "PatternMap")
	_border_cover_opacity = float(get_theme_constant("border_cover_opacity", "PatternMap")) / 100.0
	
	_pattern_base_width = get_theme_constant("pattern_width", "PatternMap")
	_pattern_label_offset.x = get_theme_constant("pattern_label_offset_x", "PatternMap")
	_pattern_label_offset.y = get_theme_constant("pattern_label_offset_y", "PatternMap")
	
	var font := get_theme_default_font()
	var font_size := get_theme_font_size("pattern_font_size", "PatternMap")
	var item_gutter_size := font.get_string_size("00", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(20, 0)
	_item_gutter_width = item_gutter_size.x
	
	_note_border_width = get_theme_constant("note_border_width", "PatternMap")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# On mouse button press.
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if mb.shift_pressed:
					_resize_pattern_width(1)
				else:
					_change_scroll_offset(-1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if mb.shift_pressed:
					_resize_pattern_width(-1)
				else:
					_change_scroll_offset(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
				_change_scroll_offset(-1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				_change_scroll_offset(1)
			
			elif mb.button_index == MOUSE_BUTTON_LEFT || mb.button_index == MOUSE_BUTTON_RIGHT:
				Controller.set_editor_focus(Controller.EditorFocus.ARRANGEMENT)
				_handle_press(mb)
		
		# On mouse button release.
		else:
			_handle_release(mb)
	
	elif event is InputEventMouseMotion:
		if _interaction == Interaction.PRESSING && get_local_mouse_position().distance_to(_press_position) > DRAG_THRESHOLD:
			_start_dragging()


func _handle_press(mb: InputEventMouseButton) -> void:
	if not current_arrangement || not Controller.current_song:
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
		_clear_pattern_at_cursor()
		return
	
	var cell := _get_grid_cell_at_cursor()
	if cell.x < 0:
		return
	var occupied := current_arrangement.has_pattern(cell.x, cell.y)
	
	if not occupied:
		if mb.shift_pressed:
			_start_marquee(cell)
		else:
			_selection.clear()
		return
	
	# Clicking a placement also opens its pattern in the pattern editor.
	_select_pattern_at_cursor()
	
	if mb.shift_pressed:
		_selection.toggle(cell)
		return
	
	_press_was_selected = _selection.has(cell)
	if not _press_was_selected:
		_selection.set_keys([ cell ])
	
	_interaction = Interaction.PRESSING
	_press_position = get_local_mouse_position()
	_press_cell = cell
	_press_copies = mb.is_command_or_control_pressed()
	_press_makes_variant = mb.alt_pressed
	_update_processing_state()


func _handle_release(mb: InputEventMouseButton) -> void:
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	
	match _interaction:
		Interaction.MARQUEE:
			_stop_marquee()
		
		Interaction.PRESSING:
			_interaction = Interaction.NONE
			_update_processing_state()
			
			if _press_makes_variant:
				# Alt+click replaces the placement with a new variant of its pattern.
				_clone_pattern_at_cursor()
			elif _press_was_selected && not _press_copies && _selection.size() > 1:
				# A click on a placement of a bigger selection narrows it to that placement.
				_selection.set_keys([ _press_cell ])
		
		Interaction.DRAGGING:
			_follow_ghost_to_cursor()
			_commit_ghost()


func _shortcut_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() || Controller.is_song_editing_locked():
		return
	if not is_visible_in_tree():
		return
	
	if _hovering:
		if event.is_action_pressed("bosca_patternmap_scale_bigger", true, true):
			_resize_pattern_width(1)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("bosca_patternmap_scale_smaller", true, true):
			_resize_pattern_width(-1)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("bosca_patternmap_make_variant", false, true):
			_clone_pattern_at_cursor()
			get_viewport().set_input_as_handled()
			return
	
	if Controller.editor_focus != Controller.EditorFocus.ARRANGEMENT:
		return
	
	if _handle_editing_shortcut(event):
		get_viewport().set_input_as_handled()


## Keyboard editing for the focused arrangement. Returns true when handled.
func _handle_editing_shortcut(event: InputEvent) -> bool:
	if not current_arrangement || not Controller.current_song:
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
				_update_ghost_items()
			return true
		if _selection.is_empty():
			return false # Fall back to scrolling.
		
		_move_selected_placements(move_delta)
		return true
	
	if _interaction == Interaction.DRAGGING:
		return false
	
	if event.is_action_pressed("bosca_select_all", false, true):
		_select_all_placements()
	elif event.is_action_pressed("bosca_copy", false, true):
		_copy_selected_placements()
	elif event.is_action_pressed("bosca_cut", false, true):
		_cut_selected_placements()
	elif event.is_action_pressed("bosca_paste", false, true):
		_paste_placements()
	elif event.is_action_pressed("bosca_duplicate", false, true):
		_duplicate_placements()
	elif event.is_action_pressed("bosca_delete", false, true):
		_delete_selected_placements()
	else:
		return false
	
	return true


func _get_move_delta(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("bosca_edit_move_up", true, true):
		return Vector2i(0, -1)
	if event.is_action_pressed("bosca_edit_move_down", true, true):
		return Vector2i(0, 1)
	if event.is_action_pressed("bosca_edit_move_left", true, true):
		return Vector2i(-1, 0)
	if event.is_action_pressed("bosca_edit_move_right", true, true):
		return Vector2i(1, 0)
	if event.is_action_pressed("bosca_edit_move_up_big", true, true):
		return Vector2i(0, -BIG_STEP)
	if event.is_action_pressed("bosca_edit_move_down_big", true, true):
		return Vector2i(0, BIG_STEP)
	if event.is_action_pressed("bosca_edit_move_left_big", true, true):
		return Vector2i(-BIG_STEP, 0)
	if event.is_action_pressed("bosca_edit_move_right_big", true, true):
		return Vector2i(BIG_STEP, 0)
	
	return Vector2i.ZERO


func _physics_process(delta: float) -> void:
	_process_pattern_cursor()
	_process_scrollbar_hover()
	_process_marquee()
	_process_ghost()
	_process_autoscroll(delta)


func _update_processing_state() -> void:
	set_physics_process(_hovering || _interaction != Interaction.NONE || _ghost != null)


func _draw() -> void:
	var available_rect := get_available_rect()
	
	# Draw the background.
	draw_rect(Rect2(Vector2.ZERO, size), _row_odd_color)

	# Draw the rows.
	for channel in _arrangement_channels:
		var row_position := channel.grid_position
		var row_size := Vector2(available_rect.size.x, _pattern_height)
		var row_color := _row_even_color if channel.channel_index % 2 else _row_odd_color
		draw_rect(Rect2(row_position, row_size), row_color)

	# Draw vertical lines.
	var last_col_x := 0.0
	for bar in _arrangement_bars:
		var col_position := bar.grid_position
		var border_size := Vector2(_border_width, available_rect.size.y)
		draw_rect(Rect2(col_position, border_size), _border_color)
		
		last_col_x = col_position.x + _pattern_width
	
	# Draw an extra cover on top of inactive bars.
	if last_col_x < available_rect.end.x:
		var col_position := Vector2(last_col_x, available_rect.position.y)
		
		# Also draw the final bar line.
		var border_size := Vector2(_border_width, available_rect.size.y)
		draw_rect(Rect2(col_position, border_size), _border_color)
		
		var cover_position := col_position + Vector2(_border_width, 0)
		var cover_size := Vector2(available_rect.end.x - last_col_x, available_rect.size.y)
		var cover_color := Color(_border_color, _border_cover_opacity)
		draw_rect(Rect2(cover_position, cover_size), cover_color)


func get_available_rect() -> Rect2:
	var available_rect := Rect2(Vector2.ZERO, size)
	if not is_inside_tree():
		return available_rect
	
	if _track:
		available_rect.size.y -= _track.size.y
	if _timeline:
		available_rect.size.y -= _timeline.size.y
		available_rect.position.y += _timeline.size.y

	return available_rect


# Scrolling.

func _change_scroll_offset(delta: int) ->  void:
	_scroll_offset = clampi(_scroll_offset + delta, 0, _max_scroll_offset)
	
	_update_scrollbar()
	_update_playback_cursor()
	_update_whole_grid()


func _update_max_scroll_offset() -> void:
	var available_rect := get_available_rect()
	var bars_on_screen := floori(available_rect.size.x / _pattern_width)
	_max_scroll_offset = Arrangement.BAR_NUMBER - bars_on_screen

	_scroll_offset = clampi(_scroll_offset, 0, _max_scroll_offset)
	_update_scrollbar()
	queue_redraw()


func _update_scrollbar() -> void:
	if Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	
	_scrollbar.can_scroll_left = _scroll_offset > 0
	_scrollbar.can_scroll_right = _scroll_offset < _max_scroll_offset
	
	_track.can_scroll_left = _scrollbar.can_scroll_left
	_track.can_scroll_right = _scrollbar.can_scroll_right
	
	_timeline.scroll_offset = _scroll_offset
	
	_scrollbar.queue_redraw()
	_timeline.queue_redraw()
	_track.queue_redraw()


# State visualization.

func _update_pattern_sizes() -> void:
	_update_pattern_height()
	_resize_pattern_width(0)


func _update_pattern_height() -> void:
	var available_rect := get_available_rect()
	_pattern_height = available_rect.size.y / Arrangement.CHANNEL_NUMBER
	
	_overlay.pattern_height = _pattern_height
	
	queue_redraw()
	_overlay.queue_redraw()


func _update_whole_grid() -> void:
	_update_max_scroll_offset()
	_update_grid_layout()
	_update_active_patterns()
	_update_active_loop()


func _update_whole_grid_and_reset_scroll() -> void:
	_update_max_scroll_offset()
	_scroll_offset = 0
	_update_scrollbar()
	_update_grid_layout()
	_update_active_patterns()
	_update_active_loop()


func _update_playback_cursor() -> void:
	if Engine.is_editor_hint():
		return
	
	if not Controller.current_song || not current_arrangement:
		_overlay.playback_cursor_position = -1
		_overlay.queue_redraw()
		return
	
	var available_rect := get_available_rect()
	var reference_bar := -1
	var extra_notes := 0
	
	if Controller.music_player.is_stopped():
		# If the player is stopped, park the cursor on the left end of the loop range.
		# This is normally unreachable by playback, as when playing at index 0 we want
		# to display the cursor to the right of the first note.
		reference_bar = current_arrangement.loop_start
	
	elif Controller.music_player.is_playing_residue():
		# When exporting and playing residual notes, continue moving the cursor beyond
		# the last bar.
		reference_bar = current_arrangement.loop_end
		extra_notes = Controller.music_player.get_residue_time()
	
	else:
		reference_bar = current_arrangement.current_bar_idx
		extra_notes = Controller.music_player.get_pattern_time()
	
	# If following cursor enabled, update scroll offset when passing roughly 3/4ths
	# of the visible bar.
	if _following_playback_cursor:
		var bars_on_screen := floori(available_rect.size.x / _pattern_width)
		var threshold_bar := int(bars_on_screen * 3.0 / 4.0)
		
		if reference_bar < _scroll_offset || reference_bar > (_scroll_offset + threshold_bar):
			_scroll_offset = reference_bar
			_update_scrollbar()
			_update_whole_grid()
	
	var pattern_size := Controller.current_song.pattern_size
	var note_width := _pattern_width / float(pattern_size)
	var note_count := (reference_bar - _scroll_offset) * pattern_size + extra_notes
	
	_overlay.playback_cursor_position = available_rect.position.x + note_count * note_width
	_overlay.queue_redraw()


# Grid layout and coordinates.

func _get_cell_at_cursor() -> Vector2i:
	return _get_cell_at_position(get_local_mouse_position())


func _get_cell_at_position(at_position: Vector2) -> Vector2i:
	var available_rect: Rect2 = get_available_rect()
	
	if not available_rect.has_point(at_position):
		return Vector2i(-1, -1)
	
	var position_normalized := at_position - available_rect.position
	var cell_indexed := Vector2i(0, 0)
	cell_indexed.x = clampi(floori(position_normalized.x / _pattern_width), 0, _arrangement_bars.size() - 1)
	cell_indexed.y = clampi(floori(position_normalized.y / _pattern_height), 0, Arrangement.CHANNEL_NUMBER - 1)
	return cell_indexed


func _get_cell_position(cell_indexed: Vector2i) -> Vector2:
	var available_rect := get_available_rect()
	
	return Vector2(
		available_rect.position.x + cell_indexed.x * _pattern_width,
		available_rect.position.y + cell_indexed.y * _pattern_height
	)


func _resize_pattern_width(value_sign: int) -> void:
	if not is_inside_tree():
		return
	
	_pattern_width_scale = clampf(_pattern_width_scale + value_sign * PATTERN_WIDTH_STEP, PATTERN_WIDTH_MIN, PATTERN_WIDTH_MAX)
	_pattern_width = _pattern_base_width * _pattern_width_scale

	_track.pattern_width = _pattern_width
	_timeline.pattern_width = _pattern_width
	_overlay.pattern_width = _pattern_width
	
	_update_playback_cursor()
	_update_whole_grid()


func _update_grid_layout() -> void:
	# Reset collections.
	_arrangement_channels.clear()
	_arrangement_bars.clear()

	# Get reference data.
	var available_rect := get_available_rect()

	# Iterate through all the patterns and complete collections.

	# HACK: Starting with 4.3 beta 3 this condition can happen on first import.
	# This breaks CI and creates hurdles for new contributors. So adding guards to avoid infinite looping.
	# Bisection points to https://github.com/godotengine/godot/pull/92609.
	if _pattern_width > 0:
		var filled_width := 0.0
		var index := 0
		
		while filled_width < (available_rect.size.x + 2 * _pattern_width): # Give it some buffer.
			var bar_index: int = index + _scroll_offset
			if bar_index >= Arrangement.BAR_NUMBER:
				break

			# Create bar column data.
			var bar := ArrangementBar.new()
			bar.bar_index = bar_index
			bar.position = Vector2(index * _pattern_width, 0)
			bar.grid_position = bar.position + available_rect.position

			_arrangement_bars.push_back(bar)
			
			# Update counters.
			filled_width += _pattern_width
			index += 1
	
	for i in Arrangement.CHANNEL_NUMBER:
		var channel := ArrangementChannel.new()
		channel.channel_index = i
		channel.position = Vector2(0, i * _pattern_height)
		channel.grid_position = channel.position + available_rect.position
		channel.label_position = channel.position + Vector2(0, -6)
		
		_arrangement_channels.push_back(channel)
	
	# Update children with the new data.
	_track.arrangement_bars = _arrangement_bars
	
	queue_redraw()
	_track.queue_redraw()
	_timeline.queue_redraw()
	_items.queue_redraw()
	_overlay.queue_redraw()


func _update_active_patterns() -> void:
	if Engine.is_editor_hint():
		return
	
	_active_patterns.clear()
	
	if Controller.current_song:
		var available_rect := get_available_rect()
		
		for i in Controller.current_song.patterns.size():
			var active_pattern := ActivePattern.new()
			active_pattern.pattern_index = i
			
			var pattern := Controller.current_song.patterns[i]
			var instrument := Controller.current_song.instruments[pattern.instrument_idx]
			
			var item_theme := Controller.get_instrument_theme(instrument)
			active_pattern.main_color = item_theme.get_color("item_color", "InstrumentDock")
			active_pattern.gutter_color = item_theme.get_color("item_gutter_color", "InstrumentDock")
			
			active_pattern.item_position = Vector2(0, 0)
			active_pattern.item_size = Vector2(_pattern_width, _pattern_height)
			
			active_pattern.label_underline_area = Rect2(
				active_pattern.item_position + Vector2(0, 3.0 * active_pattern.item_size.y / 5.0),
				Vector2(_item_gutter_width - _note_border_width, 2.0 * active_pattern.item_size.y / 5.0)
			)
			active_pattern.label_position = active_pattern.item_position + _pattern_label_offset + Vector2(0, active_pattern.item_size.y)

			active_pattern.notes_area = Rect2(
				active_pattern.item_position + Vector2(_item_gutter_width + _note_border_width, _note_border_width),
				Vector2(active_pattern.item_size.x - _item_gutter_width - 2 * _note_border_width, active_pattern.item_size.y - 2 * _note_border_width)
			)
			
			if pattern.note_amount > 0:
				var pattern_size := Controller.current_song.pattern_size

				var note_span := pattern.get_active_note_span_size()
				var note_width := active_pattern.notes_area.size.x / pattern_size
				var note_height := active_pattern.notes_area.size.y / note_span
				
				var note_origin := active_pattern.notes_area.position
				var note_span_height := active_pattern.notes_area.size.y
				
				# If the span is too small, adjust everything to center the notes.
				if note_height > _note_border_width:
					note_height = _note_border_width
					note_span_height = note_height * note_span
					note_origin.y += (active_pattern.notes_area.size.y - note_span_height) / 2.0
				
				var note_value_offset := pattern.active_note_span[0]
				for j in pattern.note_amount:
					var note := pattern.notes[j]
					if not pattern.is_note_valid(note, pattern_size):
						continue
					
					var note_index := note.x - note_value_offset
					var note_position := note_origin + Vector2(note_width * note.y, note_span_height - note_height * (note_index + 1))
					var note_size := Vector2(note_width * note.z, note_height)
					
					active_pattern.notes.push_back(Rect2(note_position, note_size))
			
			_active_patterns.push_back(active_pattern)
		
		if current_arrangement:
			for i in current_arrangement.timeline_bars.size():
				var bar := current_arrangement.timeline_bars[i]
				
				for j in bar.size():
					var pattern_index := bar[j]
					if pattern_index < 0:
						continue
					
					var active_pattern := _active_patterns[pattern_index]
					var pattern_position := _get_cell_position(Vector2i(i - _scroll_offset, j))
					if pattern_position.x < 0 || pattern_position.x > available_rect.size.x:
						continue # Skip patterns outside of the visible area.
					
					active_pattern.grid_positions.push_back(pattern_position)
	
	_items.active_patterns = _active_patterns
	_items.queue_redraw()
	
	# Placements cleared by another edit leave the selection.
	_selection.retain(_is_placement_key_valid)
	_update_selection_visuals()
	if _ghost:
		_update_ghost_items()


func _update_active_loop() -> void:
	if Engine.is_editor_hint():
		return
	if not current_arrangement:
		return
	
	_track.loop_start_index = current_arrangement.loop_start
	_track.loop_end_index = current_arrangement.loop_end
	
	_track.queue_redraw()


# Hovering.

func _start_hovering() -> void:
	_hovering = true
	_process_pattern_cursor()
	_process_scrollbar_hover()
	_update_processing_state()


func _stop_hovering() -> void:
	_hovering = false
	_update_processing_state()
	_process_pattern_cursor()
	_process_scrollbar_hover()


func _process_scrollbar_hover() -> void:
	_scrollbar.test_mouse_position()


# Pattern cursor and drawing.

func _process_pattern_cursor() -> void:
	# The ghost replaces the cursor while it's active.
	if not _hovering || _ghost:
		_overlay.pattern_cursor_position = Vector2(-1, -1)
		_overlay.queue_redraw()
		return
	
	var cell_indexed := _get_cell_at_cursor()
	if cell_indexed.x >= 0 && cell_indexed.y >= 0:
		_overlay.pattern_cursor_position = _get_cell_position(cell_indexed)
	else:
		_overlay.pattern_cursor_position = Vector2(-1, -1)
	
	_overlay.queue_redraw()


# Dragging from the pattern dock uses Godot's drag-and-drop; drags inside the
# grid are handled by the interaction state machine above.

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ItemDock.ItemDragData && (data as ItemDock.ItemDragData).source_id == Controller.DragSources.PATTERN_DOCK


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_at_position, data):
		var item_data := data as ItemDock.ItemDragData
		_set_pattern_at_cursor(item_data.item_index)


# Editing.

func _edit_current_arrangement() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	if current_arrangement:
		current_arrangement.patterns_changed.disconnect(_update_active_patterns)
		current_arrangement.loop_changed.disconnect(_update_active_loop)
		current_arrangement.loop_changed.disconnect(_update_playback_cursor)
	
	if current_pattern:
		current_pattern.key_changed.disconnect(_update_active_patterns)
		current_pattern.scale_changed.disconnect(_update_active_patterns)
		current_pattern.instrument_changed.disconnect(_update_active_patterns)
		current_pattern.notes_changed.disconnect(_update_active_patterns)
	
	current_arrangement = Controller.current_song.arrangement
	current_pattern = Controller.get_current_pattern()
	_selection.clear()

	if current_arrangement:
		current_arrangement.patterns_changed.connect(_update_active_patterns)
		current_arrangement.loop_changed.connect(_update_active_loop)
		current_arrangement.loop_changed.connect(_update_playback_cursor)
	
	if current_pattern:
		current_pattern.key_changed.connect(_update_active_patterns)
		current_pattern.scale_changed.connect(_update_active_patterns)
		current_pattern.instrument_changed.connect(_update_active_patterns)
		current_pattern.notes_changed.connect(_update_active_patterns)
	
	_update_whole_grid_and_reset_scroll()
	_update_playback_cursor()


func _edit_current_pattern() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	if current_pattern:
		current_pattern.key_changed.disconnect(_update_active_patterns)
		current_pattern.scale_changed.disconnect(_update_active_patterns)
		current_pattern.instrument_changed.disconnect(_update_active_patterns)
		current_pattern.notes_changed.disconnect(_update_active_patterns)
	
	current_pattern = Controller.get_current_pattern()
	
	if current_pattern:
		current_pattern.key_changed.connect(_update_active_patterns)
		current_pattern.scale_changed.connect(_update_active_patterns)
		current_pattern.instrument_changed.connect(_update_active_patterns)
		current_pattern.notes_changed.connect(_update_active_patterns)
	
	_update_active_patterns()


func _get_pattern_at_cursor() -> int:
	return _get_pattern_at_position(get_local_mouse_position())


func _get_pattern_at_position(at_position: Vector2) -> int:
	if not current_arrangement:
		return -1
	
	var cell := _get_cell_at_position(at_position)
	var bar_index := cell.x + _scroll_offset
	if bar_index < 0 || bar_index >= current_arrangement.timeline_length:
		return -1
	if cell.y < 0 || cell.y >= Arrangement.CHANNEL_NUMBER:
		return -1
	
	return current_arrangement.timeline_bars[bar_index][cell.y]


func _set_pattern_at_cursor(pattern_idx: int) -> void:
	if not current_arrangement || not Controller.current_song:
		return
	
	var cell := _get_cell_at_cursor()
	var bar_index := cell.x + _scroll_offset
	if bar_index < 0 || bar_index >= Arrangement.BAR_NUMBER:
		return
	if cell.y < 0 || cell.y >= Arrangement.CHANNEL_NUMBER:
		return
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_setget_property(current_arrangement, "pattern", pattern_idx,
		# Getter.
		func() -> int:
			return current_arrangement.get_pattern(bar_index, cell.y)
			,
		# Setter.
		func(value: int) -> void:
			if value == -1:
				current_arrangement.clear_pattern(bar_index, cell.y)
			else:
				current_arrangement.set_pattern(bar_index, cell.y, value)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _select_pattern_at_cursor() -> void:
	if not current_arrangement || not Controller.current_song:
		return
	
	var pattern_idx := _get_pattern_at_cursor()
	if pattern_idx < 0:
		return
	
	Controller.edit_pattern(pattern_idx)


func _clear_pattern_at_cursor() -> void:
	if not current_arrangement || not Controller.current_song:
		return
	
	var pattern_idx := _get_pattern_at_cursor()
	if pattern_idx < 0:
		return
	
	var cell := _get_cell_at_cursor()
	var bar_index := cell.x + _scroll_offset
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_setget_property(current_arrangement, "pattern", -1,
		# Getter.
		func() -> int:
			return current_arrangement.get_pattern(bar_index, cell.y)
			,
		# Setter.
		func(value: int) -> void:
			if value == -1:
				current_arrangement.clear_pattern(bar_index, cell.y)
			else:
				current_arrangement.set_pattern(bar_index, cell.y, value)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _clone_pattern_at_cursor() -> void:
	var cell := _get_grid_cell_at_cursor()
	if cell.x < 0:
		return
	
	_clone_pattern_at_cell(_get_pattern_at_cursor(), cell)


## Places a new variant (a copy) of the pattern at the cell.
func _clone_pattern_at_cell(pattern_idx: int, cell: Vector2i) -> void:
	if not current_arrangement || not Controller.current_song:
		return
	if pattern_idx < 0 || not Controller.can_clone_pattern(pattern_idx):
		return
	
	var bar_index := cell.x
	var old_value := current_arrangement.get_pattern(bar_index, cell.y)
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	var state_context := arrangement_state.get_context()
	state_context["id"] = -1
	
	arrangement_state.add_do_action(func() -> void:
		state_context.id = Controller.clone_pattern_nocheck(pattern_idx)
		current_arrangement.set_pattern(bar_index, cell.y, state_context.id)
	)
	arrangement_state.add_undo_action(func() -> void:
		if old_value == -1:
			current_arrangement.clear_pattern(bar_index, cell.y)
		else:
			current_arrangement.set_pattern(bar_index, cell.y, old_value)
		
		Controller.delete_pattern_nocheck(state_context.id)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


# Grid cells and placements.
# Editing works on cells as Vector2i(bar, channel), independent of the scroll
# offset.

func _get_edit_bounds() -> Rect2i:
	return Rect2i(0, 0, Arrangement.BAR_NUMBER, Arrangement.CHANNEL_NUMBER)


func _get_grid_cell_at_cursor() -> Vector2i:
	var cell := _get_cell_at_cursor()
	if cell.x < 0 || cell.y < 0:
		return Vector2i(-1, -1)
	
	var bar_index := cell.x + _scroll_offset
	if bar_index >= Arrangement.BAR_NUMBER:
		return Vector2i(-1, -1)
	return Vector2i(bar_index, cell.y)


## Like _get_grid_cell_at_cursor(), but snaps a pointer outside the grid to its
## nearest edge, for drags and marquees.
func _get_grid_cell_at_cursor_clamped() -> Vector2i:
	var inner_rect := get_available_rect().grow(-1.0)
	var mouse_position := get_local_mouse_position().clamp(inner_rect.position, inner_rect.end)
	
	var cell := _get_cell_at_position(mouse_position)
	if cell.x < 0 || cell.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(mini(cell.x + _scroll_offset, Arrangement.BAR_NUMBER - 1), cell.y)


func _is_placement_key_valid(key: Vector2i) -> bool:
	return current_arrangement != null && current_arrangement.has_pattern(key.x, key.y)


## Placements as Vector3i(bar, channel, pattern index).
func _get_all_placements() -> Array[Vector3i]:
	var placements: Array[Vector3i] = []
	if not current_arrangement:
		return placements
	
	for bar_index in current_arrangement.timeline_length:
		for channel in Arrangement.CHANNEL_NUMBER:
			var pattern_index := current_arrangement.get_pattern(bar_index, channel)
			if pattern_index >= 0:
				placements.push_back(Vector3i(bar_index, channel, pattern_index))
	return placements


func _get_selected_placements() -> Array[Vector3i]:
	var placements: Array[Vector3i] = []
	if not current_arrangement:
		return placements
	
	for key in _selection.get_keys():
		var pattern_index := current_arrangement.get_pattern(key.x, key.y)
		if pattern_index >= 0:
			placements.push_back(Vector3i(key.x, key.y, pattern_index))
	
	placements.sort()
	return placements


static func _get_placement_keys(placements: Array[Vector3i]) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for placement in placements:
		keys.push_back(Vector2i(placement.x, placement.y))
	return keys


static func _pluralize_patterns(amount: int) -> String:
	return "PATTERN" if amount == 1 else "PATTERNS"


## Changes placements as one undoable change, as Vector2i(bar, channel) ->
## pattern index (-1 clears). With an accumulation id, repeated calls within a
## short window merge into a single undo step.
func _commit_cell_changes(changes: Dictionary, accum_id: String = "") -> void:
	if changes.is_empty():
		return
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT, -1, accum_id)
	var state_context := arrangement_state.get_context()
	if not state_context.has("before"):
		state_context["before"] = {}
		state_context["after"] = {}
	
	for cell: Vector2i in changes:
		if not state_context.before.has(cell):
			state_context.before[cell] = current_arrangement.get_pattern(cell.x, cell.y)
		state_context.after[cell] = changes[cell]
	
	arrangement_state.add_do_action(func() -> void:
		Controller.current_song.arrangement.apply_cell_changes(state_context.after)
	)
	arrangement_state.add_undo_action(func() -> void:
		Controller.current_song.arrangement.apply_cell_changes(state_context.before)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


## Places items at cells, overwriting occupied ones, after clearing the given
## source cells. Returns the placed items.
func _place_items(placed: Array[Vector3i], cleared_cells: Array[Vector2i], accum_id: String = "") -> Array[Vector3i]:
	var changes := {}
	for cell in cleared_cells:
		changes[cell] = -1
	for item in placed:
		changes[Vector2i(item.x, item.y)] = item.z
	
	# Skip no-op changes, e.g. a drag released where it started.
	var effective_changes := {}
	for cell: Vector2i in changes:
		if current_arrangement.get_pattern(cell.x, cell.y) != changes[cell]:
			effective_changes[cell] = changes[cell]
	
	_commit_cell_changes(effective_changes, accum_id)
	return placed


# Selection.

func _on_selection_changed() -> void:
	_update_selection_visuals()
	_update_arrow_capture()
	
	if _interaction != Interaction.MARQUEE:
		_report_selection_size()


func _report_selection_size() -> void:
	if _selection.size() > 1:
		Controller.update_status("%d PATTERNS SELECTED" % [ _selection.size() ], Controller.StatusLevel.INFO)


func _update_arrow_capture() -> void:
	if Engine.is_editor_hint():
		return
	Controller.set_editor_arrow_capture(Controller.EditorFocus.ARRANGEMENT, not _selection.is_empty() || _ghost != null)


func _update_focus_state() -> void:
	_overlay.focused = Controller.editor_focus == Controller.EditorFocus.ARRANGEMENT
	_overlay.queue_redraw()


func _release_focus_when_hidden() -> void:
	if not is_visible_in_tree() && Controller.editor_focus == Controller.EditorFocus.ARRANGEMENT:
		Controller.set_editor_focus(Controller.EditorFocus.NONE)


func _update_selection_visuals() -> void:
	var selected_positions := PackedVector2Array()
	var dimmed_positions := PackedVector2Array()
	var available_rect := get_available_rect()
	
	var dimmed_keys: Array[Vector2i] = []
	if _ghost && _ghost.source == GhostPlacement.Source.DRAG_MOVE:
		dimmed_keys = _ghost.source_cells
	
	for key in _selection.get_keys():
		var cell_position := _get_cell_position(Vector2i(key.x - _scroll_offset, key.y))
		if cell_position.x >= available_rect.position.x && cell_position.x < available_rect.end.x:
			selected_positions.push_back(cell_position)
	for key in dimmed_keys:
		var cell_position := _get_cell_position(Vector2i(key.x - _scroll_offset, key.y))
		if cell_position.x >= available_rect.position.x && cell_position.x < available_rect.end.x:
			dimmed_positions.push_back(cell_position)
	
	_overlay.selected_positions = selected_positions
	_overlay.dimmed_positions = dimmed_positions
	_overlay.queue_redraw()


func _select_all_placements() -> void:
	_selection.set_keys(_get_placement_keys(_get_all_placements()))


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
	_overlay.marquee_rect = Rect2(-1, -1, 0, 0)
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
	for placement in _get_all_placements():
		if cell_rect.has_point(Vector2i(placement.x, placement.y)):
			next_keys.push_back(Vector2i(placement.x, placement.y))
	_selection.set_keys(next_keys)
	
	var top_left := _get_cell_position(Vector2i(cell_rect.position.x - _scroll_offset, cell_rect.position.y))
	var pixel_size := Vector2(cell_rect.size.x * _pattern_width, cell_rect.size.y * _pattern_height)
	_overlay.marquee_rect = Rect2(top_left, pixel_size).intersection(get_available_rect())
	_overlay.queue_redraw()


# Ghost placement and dragging.

func _start_ghost(items: Array[Vector3i], source: GhostPlacement.Source, anchor: Vector2i) -> void:
	_ghost = GhostPlacement.new(GridClipboard.to_relative(items), source, _get_edit_bounds())
	_ghost.anchor_cell = _ghost.clamp_anchor(anchor)
	_ghost_hover_cell = Vector2i(-1, -1)
	
	_update_arrow_capture()
	_update_processing_state()
	_update_ghost_items()


func _cancel_ghost() -> void:
	if not _ghost:
		return
	
	_ghost = null
	_press_makes_variant = false
	if _interaction == Interaction.DRAGGING:
		_interaction = Interaction.NONE
	
	_update_arrow_capture()
	_update_processing_state()
	_update_ghost_items()


func _follow_ghost_to_cursor() -> void:
	if not _ghost:
		return
	
	var cell := _get_grid_cell_at_cursor_clamped() if _ghost.is_drag() else _get_grid_cell_at_cursor()
	if cell.x < 0 || cell == _ghost_hover_cell:
		return
	
	_ghost_hover_cell = cell
	if _ghost.follow_cell(cell):
		_update_ghost_items()


func _process_ghost() -> void:
	if _ghost:
		_follow_ghost_to_cursor()


func _update_ghost_items() -> void:
	var ghost_items: Array[GhostItem] = []
	
	if _ghost && current_arrangement && Controller.current_song:
		var ignored_cells := _ghost.source_cells if _ghost.source == GhostPlacement.Source.DRAG_MOVE else ([] as Array[Vector2i])
		var is_occupied := func(cell: Vector2i) -> bool:
			return current_arrangement.has_pattern(cell.x, cell.y) && not ignored_cells.has(cell)
		var fit_mask := _ghost.is_valid_at(_ghost.anchor_cell, is_occupied)
		var available_rect := get_available_rect()
		
		for i in _ghost.items.size():
			var item := _ghost.items[i]
			if fit_mask[i] == GhostPlacement.FIT_NONE || item.z < 0 || item.z >= _active_patterns.size():
				continue
			
			var cell := _ghost.get_item_cell(item, _ghost.anchor_cell)
			var cell_position := _get_cell_position(Vector2i(cell.x - _scroll_offset, cell.y))
			if cell_position.x < available_rect.position.x || cell_position.x >= available_rect.end.x:
				continue
			
			var ghost_item := GhostItem.new()
			ghost_item.position = cell_position
			ghost_item.color = _active_patterns[item.z].main_color
			ghost_item.label = "%d%s" % [ item.z + 1, "*" if _press_makes_variant else "" ]
			ghost_item.conflict = fit_mask[i] == GhostPlacement.FIT_CONFLICT
			ghost_items.push_back(ghost_item)
	
	_overlay.ghost_items = ghost_items
	_process_pattern_cursor()
	_update_selection_visuals()


func _start_dragging() -> void:
	var items: Array[Vector3i] = []
	var source := GhostPlacement.Source.DRAG_COPY if _press_copies else GhostPlacement.Source.DRAG_MOVE
	
	if _press_makes_variant:
		# Alt+drag makes a variant of the grabbed pattern only.
		var pattern_index := current_arrangement.get_pattern(_press_cell.x, _press_cell.y)
		if pattern_index >= 0:
			items.push_back(Vector3i(_press_cell.x, _press_cell.y, pattern_index))
		source = GhostPlacement.Source.DRAG_COPY
	else:
		items = _get_selected_placements()
	
	if items.is_empty():
		_interaction = Interaction.NONE
		_update_processing_state()
		return
	
	_interaction = Interaction.DRAGGING
	
	var group_anchor := Vector2i(items[0].x, items[0].y)
	for item in items:
		group_anchor = Vector2i(mini(group_anchor.x, item.x), mini(group_anchor.y, item.y))
	
	_start_ghost(items, source, group_anchor)
	_ghost.grab_offset = _press_cell - group_anchor
	_ghost.source_cells.assign(_get_placement_keys(items))
	_update_ghost_items()


func _commit_ghost() -> void:
	if not _ghost || not current_arrangement || not Controller.current_song:
		return
	
	var ghost := _ghost
	var makes_variant := _press_makes_variant
	_cancel_ghost()
	
	if makes_variant:
		var target_cell := ghost.get_item_cell(ghost.items[0], ghost.anchor_cell)
		_clone_pattern_at_cell(ghost.items[0].z, target_cell)
		return
	
	var bounds := _get_edit_bounds()
	var placed: Array[Vector3i] = []
	var dropped := 0
	var pattern_count := Controller.current_song.patterns.size()
	for item in ghost.items:
		var cell := ghost.get_item_cell(item, ghost.anchor_cell)
		# Patterns may have been deleted since they were copied.
		if not bounds.has_point(cell) || item.z >= pattern_count:
			dropped += 1
			continue
		placed.push_back(Vector3i(cell.x, cell.y, item.z))
	
	var cleared_cells: Array[Vector2i] = []
	if ghost.source == GhostPlacement.Source.DRAG_MOVE:
		cleared_cells = ghost.source_cells
	
	_place_items(placed, cleared_cells)
	_selection.set_keys(_get_placement_keys(placed))
	
	if dropped > 0:
		Controller.update_status("%d %s DIDN'T FIT" % [ dropped, _pluralize_patterns(dropped) ], Controller.StatusLevel.WARNING)


func _process_autoscroll(delta: float) -> void:
	if _interaction != Interaction.DRAGGING && _interaction != Interaction.MARQUEE:
		_autoscroll_timer = 0.0
		return
	
	_autoscroll_timer -= delta
	if _autoscroll_timer > 0.0:
		return
	
	var available_rect := get_available_rect()
	var mouse_x := get_local_mouse_position().x
	if mouse_x < available_rect.position.x + AUTOSCROLL_MARGIN:
		_change_scroll_offset(-1)
		_autoscroll_timer = AUTOSCROLL_INTERVAL
	elif mouse_x > available_rect.end.x - AUTOSCROLL_MARGIN:
		_change_scroll_offset(1)
		_autoscroll_timer = AUTOSCROLL_INTERVAL


# Clipboard and keyboard editing.

func _copy_selected_placements() -> void:
	var placements := _get_selected_placements()
	if placements.is_empty():
		return
	
	Controller.arrangement_clipboard.store(placements)
	Controller.update_status("%d %s COPIED" % [ placements.size(), _pluralize_patterns(placements.size()) ], Controller.StatusLevel.INFO)


func _cut_selected_placements() -> void:
	if _selection.is_empty():
		return
	
	_copy_selected_placements()
	_delete_selected_placements()


func _paste_placements() -> void:
	if Controller.arrangement_clipboard.is_empty():
		return
	
	var anchor := _get_grid_cell_at_cursor()
	if anchor.x < 0:
		anchor = Vector2i(_scroll_offset, 0) # Top-left of the visible grid.
	_start_ghost(Controller.arrangement_clipboard.get_items(), GhostPlacement.Source.PASTE, anchor)


func _duplicate_placements() -> void:
	var items := _get_selected_placements()
	var anchor := _get_grid_cell_at_cursor()
	
	# Without a selection, duplicate the placement under the cursor.
	if items.is_empty():
		if anchor.x < 0 || not current_arrangement.has_pattern(anchor.x, anchor.y):
			return
		items.push_back(Vector3i(anchor.x, anchor.y, current_arrangement.get_pattern(anchor.x, anchor.y)))
	
	if anchor.x < 0:
		anchor = Vector2i(items[0].x, items[0].y)
	_start_ghost(items, GhostPlacement.Source.DUPLICATE, anchor)


func _delete_selected_placements() -> void:
	var placements := _get_selected_placements()
	if placements.is_empty():
		return
	
	var changes := {}
	for placement in placements:
		changes[Vector2i(placement.x, placement.y)] = -1
	_commit_cell_changes(changes)
	_selection.clear()


func _move_selected_placements(delta: Vector2i) -> void:
	var placements := _get_selected_placements()
	if placements.is_empty():
		return
	
	# The whole selection moves, or nothing does.
	var bounds := _get_edit_bounds()
	var moved: Array[Vector3i] = []
	for placement in placements:
		var cell := Vector2i(placement.x, placement.y) + delta
		if not bounds.has_point(cell):
			Controller.update_status("CAN'T MOVE — SELECTION AT THE EDGE", Controller.StatusLevel.WARNING)
			return
		moved.push_back(Vector3i(cell.x, cell.y, placement.z))
	
	# Key repeat accumulates into one undo step.
	_place_items(moved, _get_placement_keys(placements), "arrangement_nudge")
	_selection.set_keys(_get_placement_keys(moved))
	_scroll_to_bar(moved[0].x if delta.x < 0 else moved[moved.size() - 1].x)


## Scrolls just enough to bring the bar into view.
func _scroll_to_bar(bar_index: int) -> void:
	var bars_on_screen := maxi(1, floori(get_available_rect().size.x / _pattern_width))
	if bar_index < _scroll_offset:
		_change_scroll_offset(bar_index - _scroll_offset)
	elif bar_index >= _scroll_offset + bars_on_screen:
		_change_scroll_offset(bar_index - _scroll_offset - bars_on_screen + 1)


func _change_arrangement_loop(starts_at: int, ends_at: int) -> void:
	if not current_arrangement:
		return
	
	var old_loop_start := current_arrangement.loop_start
	var old_loop_end := current_arrangement.loop_end
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_do_action(func() -> void:
		current_arrangement.set_loop(starts_at, ends_at)
		if Controller.music_player.is_stopped():
			Controller.current_song.reset_arrangement()
	)
	arrangement_state.add_undo_action(func() -> void:
		current_arrangement.set_loop(old_loop_start, old_loop_end)
		if Controller.music_player.is_stopped():
			Controller.current_song.reset_arrangement()
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _change_arrangement_loop_to_end(starts_at: int) -> void:
	if not current_arrangement:
		return
	
	var ends_at := starts_at + 1
	if starts_at < current_arrangement.timeline_length:
		ends_at = current_arrangement.timeline_length
	
	var old_loop_start := current_arrangement.loop_start
	var old_loop_end := current_arrangement.loop_end
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_do_action(func() -> void:
		current_arrangement.set_loop(starts_at, ends_at)
		if Controller.music_player.is_stopped():
			Controller.current_song.reset_arrangement()
	)
	arrangement_state.add_undo_action(func() -> void:
		current_arrangement.set_loop(old_loop_start, old_loop_end)
		if Controller.music_player.is_stopped():
			Controller.current_song.reset_arrangement()
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _insert_timeline_bar(at_index: int) -> void:
	if not current_arrangement:
		return
	
	var bar_index := at_index + _scroll_offset
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_do_action(func() -> void:
		current_arrangement.insert_bar(bar_index)
	)
	arrangement_state.add_undo_action(func() -> void:
		current_arrangement.remove_bar(bar_index)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _remove_timeline_bar(at_index: int) -> void:
	if not current_arrangement:
		return
	if current_arrangement.timeline_length <= 0:
		return
	
	var bar_index := at_index + _scroll_offset
	var bar_patterns := current_arrangement.timeline_bars[bar_index].duplicate()
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	arrangement_state.add_do_action(func() -> void:
		current_arrangement.remove_bar(bar_index)
	)
	arrangement_state.add_undo_action(func() -> void:
		current_arrangement.insert_bar(bar_index)
		
		for i: int in bar_patterns.size():
			current_arrangement.set_pattern(bar_index, i, bar_patterns[i])
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


func _copy_timeline_bars() -> void:
	if not current_arrangement:
		return
	
	current_arrangement.copy_bar_range(current_arrangement.loop_start, current_arrangement.loop_end)
	Controller.update_status("SELECTED BARS COPIED", Controller.StatusLevel.INFO)


func _paste_timeline_bars(at_index: int) -> void:
	if not current_arrangement:
		return
	
	var copied_data := current_arrangement.get_copied_bar_range().duplicate()
	if copied_data.is_empty():
		return
	
	var bar_index := at_index + _scroll_offset
	
	var arrangement_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.ARRANGEMENT)
	var state_context := arrangement_state.get_context()
	state_context["affected"] = 0
	
	arrangement_state.add_do_action(func() -> void:
		state_context.affected = current_arrangement.paste_bar_range(bar_index, copied_data)
	)
	arrangement_state.add_undo_action(func() -> void:
		for i: int in range(state_context.affected, 0, -1): # Iterate backwards, so deletions are cheaper.
			current_arrangement.remove_bar(bar_index + i - 1)
	)
	
	Controller.state_manager.commit_state_change(arrangement_state)


class ArrangementChannel:
	var channel_index: int = -1
	var position: Vector2 = Vector2.ZERO
	var grid_position: Vector2 = Vector2.ZERO
	var label_position: Vector2 = Vector2.ZERO


class ArrangementBar:
	var bar_index: int = -1
	var position: Vector2 = Vector2.ZERO
	var grid_position: Vector2 = Vector2.ZERO


class GhostItem:
	var position: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var label: String = ""
	## Would overwrite an existing placement.
	var conflict: bool = false


class ActivePattern:
	var pattern_index: int = -1
	var main_color: Color = Color.BLACK
	var gutter_color: Color = Color.BLACK
	
	var item_position: Vector2 = Vector2.ZERO
	var item_size: Vector2 = Vector2.ZERO
	var label_underline_area: Rect2 = Rect2()
	var label_position: Vector2 = Vector2.ZERO
	var notes_area: Rect2 = Rect2()
	var notes: Array[Rect2] = []
	
	var grid_positions: PackedVector2Array = PackedVector2Array()
