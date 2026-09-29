###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

extends PanelContainer

var current_instrument: Instrument = null

## Item id offsets in the instrument picker for the CUSTOM category.
const SONG_CUSTOM_ID_BASE := 2000000
const LIBRARY_CUSTOM_ID_BASE := 3000000

var _library_entries: Array[CustomInstrumentLibrary.Entry] = []

@onready var _instrument_label: Label = %InstrumentLabel

@onready var _category_picker: OptionPicker = %CategoryPicker
@onready var _instrument_picker: OptionPicker = %InstrumentPicker
@onready var _prev_instrument_button: Button = %PrevInstrument
@onready var _next_instrument_button: Button = %NextInstrument
@onready var _randomize_instrument_button: Button = %RandomizeInstrument

@onready var _lowpass_slider: PadSlider = %LowPassSlider
@onready var _volume_slider: PadSlider = %VolumeSlider
@onready var _sound_panel: Control = %SoundPanel


func _ready() -> void:
	_set_category_options()
	_category_picker.selected.connect(_category_selected)
	_instrument_picker.selected.connect(_instrument_selected)
	_prev_instrument_button.pressed.connect(_instrument_picker.select_previous)
	_next_instrument_button.pressed.connect(_instrument_picker.select_next)
	_randomize_instrument_button.pressed.connect(_instrument_randomized)
	
	_lowpass_slider.changed.connect(_instrument_filter_changed)
	_volume_slider.changed.connect(_instrument_volume_changed)
	
	_edit_current_instrument()
	
	if not Engine.is_editor_hint():
		Controller.song_loaded.connect(_edit_current_instrument)
		Controller.song_instrument_changed.connect(_edit_current_instrument)
		# Keeps the pads in sync with undo/redo.
		Controller.state_manager.state_changed.connect(_update_sliders)
		Controller.state_manager.state_changed.connect(_update_sound_panel)


# Data.

func _edit_current_instrument() -> void:
	if Engine.is_editor_hint():
		return
	if not Controller.current_song:
		return
	
	var next_instrument := Controller.get_current_instrument()
	if next_instrument == current_instrument:
		return
	
	# Update the label.
	_instrument_label.text = "INSTRUMENT %d" % [ Controller.current_instrument_index + 1 ]
	
	# Update the instrument reference and pickers.
	
	var category_changed := true
	if next_instrument && current_instrument && next_instrument.category == current_instrument.category:
		category_changed = false
	
	current_instrument = next_instrument
	theme = Controller.get_current_instrument_theme()
	
	if category_changed:
		_update_selected_category()
		_set_instrument_options()
	else:
		_update_selected_instrument()
	
	_update_sliders()
	_update_sound_panel()


func _update_sound_panel() -> void:
	var custom_instrument := current_instrument as CustomInstrument
	_sound_panel.visible = custom_instrument != null
	if custom_instrument:
		_sound_panel.edit_instrument(Controller.current_instrument_index, custom_instrument)


# Instrument editing.

func _set_category_options() -> void:
	var categories := Controller.voice_manager.get_categories()
	var category_id := 0
	for category in categories:
		var item := OptionListPopup.Item.new()
		item.id = category_id
		item.text = category
		
		_category_picker.options.push_back(item)
		category_id += 1
	
	var custom_item := OptionListPopup.Item.new()
	custom_item.id = category_id
	custom_item.text = CustomInstrument.CATEGORY
	_category_picker.options.push_back(custom_item)
	_category_picker.commit_options()


func _set_instrument_options() -> void:
	_instrument_picker.options = []
	_instrument_picker.clear_selected()
	
	if not current_instrument:
		_instrument_picker.commit_options()
		return
	
	if current_instrument is CustomInstrument:
		_set_custom_instrument_options()
		return
	
	# Update the instrument picker.
	
	_instrument_picker.placeholder_text = "Instrument Name"
	var sub_categories := Controller.voice_manager.get_sub_categories(current_instrument.category)
	var sub_category_id := 1000000
	var selected_item: OptionListPopup.Item = null
	for subcat in sub_categories:
		if subcat.name.is_empty(): # This is a top-level subcategory.
			for instrument in subcat.voices:
				var item := OptionListPopup.Item.new()
				item.id = instrument.index
				item.text = instrument.name
				
				if item.id == current_instrument.voice_index:
					selected_item = item
				_instrument_picker.options.push_back(item)
		
		else: # And this is an actual sublist.
			var sublist_options: Array[OptionListPopup.Item] = []
			for instrument in subcat.voices:
				var item := OptionListPopup.Item.new()
				item.id = instrument.index
				item.text = instrument.name
				
				if item.id == current_instrument.voice_index:
					selected_item = item
				sublist_options.push_back(item)
			
			var sublist := OptionListPopup.Item.new()
			sublist.id = sub_category_id
			sublist.text = subcat.name
			sublist.is_sublist = true
			sublist.sublist_options = sublist_options
			
			_instrument_picker.options.push_back(sublist)
			sub_category_id += 1
	
	_instrument_picker.commit_options()
	_instrument_picker.set_selected(selected_item)


## The CUSTOM list offers definitions to copy into the current instrument: the
## song's other custom instruments, then the user library.
func _set_custom_instrument_options() -> void:
	_instrument_picker.placeholder_text = "Load a custom definition"
	
	var song_items: Array[OptionListPopup.Item] = []
	for i in Controller.current_song.instruments.size():
		var instrument := Controller.current_song.instruments[i]
		if instrument is CustomInstrument && i != Controller.current_instrument_index:
			var item := OptionListPopup.Item.new()
			item.id = SONG_CUSTOM_ID_BASE + i
			item.text = "%d %s" % [ i + 1, instrument.name ]
			song_items.push_back(item)
	
	var library_result := CustomInstrumentLibrary.load_entries()
	_library_entries = library_result.entries
	if library_result.skipped_count > 0:
		Controller.update_status("%d LIBRARY INSTRUMENTS SKIPPED (INVALID FILES)" % [ library_result.skipped_count ], Controller.StatusLevel.WARNING)
	
	var library_items: Array[OptionListPopup.Item] = []
	for i in _library_entries.size():
		var item := OptionListPopup.Item.new()
		item.id = LIBRARY_CUSTOM_ID_BASE + i
		item.text = _library_entries[i].instrument.display_name
		library_items.push_back(item)
	
	for group: Array in [ [ "In this song", song_items, SONG_CUSTOM_ID_BASE - 1 ], [ "Library", library_items, LIBRARY_CUSTOM_ID_BASE - 1 ] ]:
		var sublist := OptionListPopup.Item.new()
		sublist.id = group[2]
		sublist.text = group[0]
		sublist.is_sublist = true
		sublist.sublist_options.assign(group[1])
		_instrument_picker.options.push_back(sublist)
	
	_instrument_picker.commit_options()


func _update_selected_category() -> void:
	_category_picker.clear_selected()
	
	if not current_instrument:
		return
	
	for category_item in _category_picker.options:
		if category_item.text == current_instrument.category:
			_category_picker.set_selected(category_item)
			break


func _update_selected_instrument() -> void:
	_instrument_picker.clear_selected()
	
	if not current_instrument:
		return
	if current_instrument is CustomInstrument:
		_set_instrument_options() # The list depends on the edited slot.
		return
	
	for linked_instrument_item in _instrument_picker.get_linked_options():
		if linked_instrument_item.value.id == current_instrument.voice_index:
			_instrument_picker.set_selected(linked_instrument_item.value)
			break


func _instrument_randomized() -> void:
	if Engine.is_editor_hint():
		return
		
	Controller.randomize_current_instrument()


func _category_selected() -> void:
	if Engine.is_editor_hint():
		return
	
	var category_name := _category_picker.get_selected().text
	if category_name == CustomInstrument.CATEGORY:
		if not (current_instrument is CustomInstrument):
			Controller.set_current_instrument_custom()
		return
	
	Controller.set_current_instrument_by_category(category_name)


func _instrument_selected() -> void:
	if Engine.is_editor_hint():
		return
	
	var category_name := _category_picker.get_selected().text
	var selected_item := _instrument_picker.get_selected()
	if category_name == CustomInstrument.CATEGORY:
		_custom_definition_selected(selected_item.id)
		return
	
	Controller.set_current_instrument(category_name, selected_item.text)


func _custom_definition_selected(item_id: int) -> void:
	var source: CustomInstrument = null
	if item_id >= LIBRARY_CUSTOM_ID_BASE:
		var entry_index := item_id - LIBRARY_CUSTOM_ID_BASE
		if entry_index < _library_entries.size():
			source = _library_entries[entry_index].instrument
	elif item_id >= SONG_CUSTOM_ID_BASE:
		source = Controller.current_song.instruments[item_id - SONG_CUSTOM_ID_BASE] as CustomInstrument
	
	if source:
		Controller.set_current_instrument_custom(source)


func _instrument_filter_changed() -> void:
	if not Controller.current_song || not current_instrument:
		return
	
	var slider_value := _lowpass_slider.get_current_value()
	
	var instrument_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.INSTRUMENT, Controller.current_instrument_index, "instrument_lp_filter")
	instrument_state.add_indexed_property(Controller.current_song.instruments, instrument_state.reference_id, "lp_cutoff", slider_value.x)
	instrument_state.add_indexed_property(Controller.current_song.instruments, instrument_state.reference_id, "lp_resonance", slider_value.y)
	
	Controller.state_manager.commit_state_change(instrument_state)


func _instrument_volume_changed() -> void:
	if not Controller.current_song || not current_instrument:
		return
	
	var slider_value := _volume_slider.get_current_value()
	
	var instrument_state := Controller.state_manager.create_state_change(StateManager.StateChangeType.INSTRUMENT, Controller.current_instrument_index, "instrument_volume")
	instrument_state.add_indexed_property(Controller.current_song.instruments, instrument_state.reference_id, "volume", slider_value.y)
	
	Controller.state_manager.commit_state_change(instrument_state)


func _update_sliders() -> void:
	if not current_instrument:
		return
	
	_lowpass_slider.set_current_value(Vector2i(current_instrument.lp_cutoff, current_instrument.lp_resonance))
	_volume_slider.set_current_value(Vector2i(0, current_instrument.volume))
