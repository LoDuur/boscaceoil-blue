###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

extends VBoxContainer

## Current edited pattern.
var current_pattern: Pattern = null

@onready var _instrument_picker: OptionPicker = %InstrumentPicker
@onready var _scale_picker: OptionPicker = %ScalePicker
@onready var _key_picker: OptionPicker = %KeyPicker

@onready var _note_shift_up: Button = %NoteShiftUp
@onready var _note_shift_down: Button = %NoteShiftDown
@onready var _note_shift_left: Button = %NoteShiftLeft
@onready var _note_shift_right: Button = %NoteShiftRight


func _ready() -> void:
	_update_scale_options()
	_update_key_options()
	
	_instrument_picker.selected.connect(_change_instrument)
	_scale_picker.selected.connect(_change_scale)
	_key_picker.selected.connect(_change_key)
	
	if not Engine.is_editor_hint():
		_note_shift_up.pressed.connect(Controller.shift_current_pattern_notes.bind(1))
		_note_shift_down.pressed.connect(Controller.shift_current_pattern_notes.bind(-1))
		_note_shift_left.pressed.connect(Controller.rotate_current_pattern_notes.bind(-1))
		_note_shift_right.pressed.connect(Controller.rotate_current_pattern_notes.bind(1))
	
	_edit_current_pattern()
	
	if not Engine.is_editor_hint():
		Controller.settings_manager.note_format_changed.connect(_update_key_options)
		
		Controller.song_loaded.connect(_edit_current_pattern)
		Controller.song_pattern_changed.connect(_edit_current_pattern)
		Controller.song_instrument_created.connect(_update_pattern_instrument)
		Controller.song_instrument_changed.connect(_update_pattern_instrument)


func _update_scale_options() -> void:
	_scale_picker.options = []
	
	var selected_item: OptionListPopup.Item = null
	for i in Scale.MAX:
		var item := OptionListPopup.Item.new()
		item.id = i
		item.text = Scale.get_scale_name(i)

		if current_pattern && current_pattern.scale == i:
			selected_item = item

		_scale_picker.options.push_back(item)
	
	_scale_picker.commit_options()
	_scale_picker.set_selected(selected_item)


func _update_key_options() -> void:
	_key_picker.options = []
	
	var selected_item: OptionListPopup.Item = null
	for i in Note.MAX:
		var item := OptionListPopup.Item.new()
		item.id = i
		item.text = Note.get_note_name(i)

		if current_pattern && current_pattern.key == i:
			selected_item = item
		
		_key_picker.options.push_back(item)
	
	_key_picker.commit_options()
	_key_picker.set_selected(selected_item)


func _edit_current_pattern() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	if current_pattern:
		current_pattern.instrument_changed.disconnect(_update_pattern_instrument)
		current_pattern.scale_changed.disconnect(_update_pattern_widgets)
		current_pattern.key_changed.disconnect(_update_pattern_widgets)
	
	current_pattern = Controller.get_current_pattern()
	
	if current_pattern:
		current_pattern.instrument_changed.connect(_update_pattern_instrument)
		current_pattern.scale_changed.connect(_update_pattern_widgets)
		current_pattern.key_changed.connect(_update_pattern_widgets)
	
	_update_pattern_instrument()
	_update_pattern_widgets()


func _update_pattern_instrument() -> void:
	_instrument_picker.options = []
	_instrument_picker.clear_selected()
	if not Controller.current_song:
		_instrument_picker.commit_options()
		return
	
	var instrument_index := 0
	var selected_item: OptionListPopup.Item = null
	var selected_instrument: Instrument = null
	for instrument in Controller.current_song.instruments:
		var item := OptionListPopup.Item.new()
		item.id = instrument_index
		item.text = "%d %s" % [ instrument_index + 1, instrument.name ]
		var instrument_theme := Controller.get_instrument_theme(instrument)
		item.background_color = instrument_theme.get_color("item_color", "InstrumentDock")
		
		if current_pattern && current_pattern.instrument_idx == instrument_index:
			selected_item = item
			selected_instrument = instrument
		
		_instrument_picker.options.push_back(item)
		instrument_index += 1
	
	_instrument_picker.commit_options()
	if selected_item:
		_instrument_picker.set_selected(selected_item)

	if selected_instrument:
		_scale_picker.get_parent().visible = selected_instrument.type != Instrument.InstrumentType.INSTRUMENT_DRUMKIT
		_key_picker.get_parent().visible = selected_instrument.type != Instrument.InstrumentType.INSTRUMENT_DRUMKIT


func _update_pattern_widgets() -> void:
	if current_pattern:
		_scale_picker.set_selected(_scale_picker.options[current_pattern.scale])
		_key_picker.set_selected(_key_picker.options[current_pattern.key])
	else:
		_scale_picker.clear_selected()
		_key_picker.clear_selected()


func _change_instrument() -> void:
	if not Controller.current_song || not current_pattern:
		return
	
	var selected_item := _instrument_picker.get_selected()
	if not selected_item:
		return
	
	var instrument_idx := selected_item.id
	var old_instrument_idx := current_pattern.instrument_idx
	
	var pattern_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.PATTERN, Controller.current_pattern_index)
	var state_context := pattern_state.get_context()
	state_context["affected"] = []
	state_context["key"] = 0
	
	pattern_state.add_do_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		var pattern_instrument := Controller.current_song.instruments[instrument_idx]
		
		state_context.key = reference_pattern.key # When changing to a drumkit, this is reset.
		state_context.affected = reference_pattern.change_instrument(instrument_idx, pattern_instrument)
		
		if not state_context.affected.is_empty():
			Controller.update_status_notes_dropped(state_context.affected.size())
	)
	pattern_state.add_undo_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		var pattern_instrument := Controller.current_song.instruments[old_instrument_idx]
		
		reference_pattern.change_instrument(old_instrument_idx, pattern_instrument)
		reference_pattern.restore_notes(state_context.affected)
		reference_pattern.change_key(state_context.key)
	)
	
	Controller.state_manager.commit_state_change(pattern_state)


func _change_scale() -> void:
	if not Controller.current_song || not current_pattern:
		return
	
	var selected_item := _scale_picker.get_selected()
	if not selected_item:
		return
	
	var scale_id := selected_item.id
	var old_scale_id := current_pattern.scale
	
	var pattern_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.PATTERN, Controller.current_pattern_index)
	var state_context := pattern_state.get_context()
	state_context["affected"] = []
	
	pattern_state.add_do_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		state_context.affected = reference_pattern.change_scale(scale_id)
		
		if not state_context.affected.is_empty():
			Controller.update_status_notes_dropped(state_context.affected.size())
	)
	pattern_state.add_undo_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.change_scale(old_scale_id)
		reference_pattern.restore_notes(state_context.affected)
	)
	
	Controller.state_manager.commit_state_change(pattern_state)


func _change_key() -> void:
	if not Controller.current_song || not current_pattern:
		return
	
	var selected_item := _key_picker.get_selected()
	if not selected_item:
		return
	
	var key_id := selected_item.id
	var old_key_id := current_pattern.key
	
	var pattern_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.PATTERN, Controller.current_pattern_index)
	pattern_state.add_do_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.change_key(key_id)
	)
	pattern_state.add_undo_action(func() -> void:
		var reference_pattern := Controller.current_song.patterns[pattern_state.reference_id]
		reference_pattern.change_key(old_key_id)
	)
	
	Controller.state_manager.commit_state_change(pattern_state)
