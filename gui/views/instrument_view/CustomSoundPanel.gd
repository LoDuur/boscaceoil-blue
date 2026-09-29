###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## Editor for the sound and identity of a custom instrument. Edits go through
## the Controller as undoable changes; the panel only mirrors the instrument.
extends VBoxContainer

const VALUE_SLIDER_SCENE := preload("res://gui/widgets/ValueSlider.tscn")
const OPTION_PICKER_SCENE := preload("res://gui/widgets/OptionPicker.tscn")

const PALETTE_ORDER: Array[int] = [
	CustomColorPalette.PALETTE_BLUE,
	CustomColorPalette.PALETTE_PURPLE,
	CustomColorPalette.PALETTE_RED,
	CustomColorPalette.PALETTE_ORANGE,
	CustomColorPalette.PALETTE_GREEN,
	CustomColorPalette.PALETTE_CYAN,
	CustomColorPalette.PALETTE_GRAY,
]

## Slider rows: field -> label.
const OSCILLATOR_SLIDERS := {
	"dual_connection": "LINK",
	"dual_balance": "BALANCE",
	"dual_detune": "DETUNE",
}
const ENVELOPE_SLIDERS := {
	"attack_rate": "ATTACK",
	"decay_rate": "DECAY",
	"sustain_level": "SUSTAIN",
	"sustain_rate": "SUS. RATE",
	"release_rate": "RELEASE",
	"total_level": "ATTEN.",
	"vibrato_depth": "VIBRATO",
}
## Fields only used with two oscillators.
const DUAL_FIELDS: Array[String] = [ "wave2", "dual_connection", "dual_balance", "dual_detune" ]

var instrument_index: int = -1
var _instrument: CustomInstrument = null

var _name_edit: LineEdit = null
var _palette_buttons: Array[Button] = []
var _save_button: Button = null
var _mode_picker: OptionPicker = null
var _wave_pickers: Dictionary = {} # field -> OptionPicker
var _sliders: Dictionary = {} # field -> ValueSlider
var _row_nodes: Dictionary = {} # field -> Array[Control]
var _envelope_preview: EnvelopePreview = null


func _ready() -> void:
	_build()


func _build() -> void:
	# Identity.

	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 6)
	add_child(identity_row)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(110, 0)
	_name_edit.max_length = CustomInstrument.MAX_NAME_LENGTH
	_name_edit.placeholder_text = "Instrument name"
	_name_edit.text_submitted.connect(func(_text: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	identity_row.add_child(_name_edit)

	for palette in PALETTE_ORDER:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.toggle_mode = true
		swatch.tooltip_text = "Instrument color"
		swatch.pressed.connect(_commit_palette.bind(palette))

		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = Controller.instrument_themes[palette].get_color("item_color", "InstrumentDock")
		var swatch_pressed_style := swatch_style.duplicate() as StyleBoxFlat
		swatch_pressed_style.set_border_width_all(3)
		swatch_pressed_style.border_color = Color.WHITE
		for style_name: String in [ "normal", "hover", "focus", "disabled" ]:
			swatch.add_theme_stylebox_override(style_name, swatch_style)
		swatch.add_theme_stylebox_override("pressed", swatch_pressed_style)
		swatch.add_theme_stylebox_override("hover_pressed", swatch_pressed_style)

		identity_row.add_child(swatch)
		_palette_buttons.push_back(swatch)

	_save_button = Button.new()
	_save_button.text = "SAVE"
	_save_button.tooltip_text = "Save this instrument to the library, to reuse it in other songs"
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_save_to_library)
	identity_row.add_child(_save_button)

	# Parameters.

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.theme_type_variation = &"HBoxSpaced"
	scroll.add_child(columns)

	var oscillator_grid := _add_grid(columns)

	_mode_picker = _add_picker(oscillator_grid, "MODE", "osc_mode", [ [ "Single", CustomInstrument.OscillatorMode.SINGLE ], [ "Dual", CustomInstrument.OscillatorMode.DUAL ] ])
	_wave_pickers["wave1"] = _add_picker(oscillator_grid, "WAVE 1", "wave1", CustomInstrument.WAVEFORMS)
	_wave_pickers["wave2"] = _add_picker(oscillator_grid, "WAVE 2", "wave2", CustomInstrument.WAVEFORMS)
	for field: String in OSCILLATOR_SLIDERS:
		_add_slider(oscillator_grid, OSCILLATOR_SLIDERS[field], field)

	var envelope_column := VBoxContainer.new()
	columns.add_child(envelope_column)
	var envelope_grid := _add_grid(envelope_column)
	for field: String in ENVELOPE_SLIDERS:
		_add_slider(envelope_grid, ENVELOPE_SLIDERS[field], field)

	_envelope_preview = EnvelopePreview.new()
	_envelope_preview.custom_minimum_size = Vector2(120, 36)
	envelope_column.add_child(_envelope_preview)


func _add_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)
	return grid


func _add_label(grid: GridContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	return label


func _add_picker(grid: GridContainer, label_text: String, field: String, entries: Array) -> OptionPicker:
	var label := _add_label(grid, label_text)

	var picker: OptionPicker = OPTION_PICKER_SCENE.instantiate()
	picker.custom_minimum_size = Vector2(90, 0)
	grid.add_child(picker)

	for entry: Array in entries:
		var item := OptionListPopup.Item.new()
		item.text = entry[0]
		item.id = entry[1]
		picker.options.push_back(item)
	picker.commit_options()
	picker.selected.connect(func() -> void:
		var item := picker.get_selected()
		if item:
			_commit_field(field, item.id)
	)

	_row_nodes[field] = [ label, picker ]
	return picker


func _add_slider(grid: GridContainer, label_text: String, field: String) -> void:
	var label := _add_label(grid, label_text)

	var slider: ValueSlider = VALUE_SLIDER_SCENE.instantiate()
	slider.min_value = CustomInstrument.FIELDS[field][0]
	slider.max_value = CustomInstrument.FIELDS[field][1]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.slider_width = 60.0
	# Edits of a field merge into one undo step, so they can apply live and be heard as they're made.
	slider.emit_while_dragging = true
	grid.add_child(slider)
	slider.value_changed.connect(func() -> void: _commit_field(field, slider.value))

	_sliders[field] = slider
	_row_nodes[field] = [ label, slider ]


# Sync with the instrument.

func edit_instrument(index: int, instrument: CustomInstrument) -> void:
	instrument_index = index
	_instrument = instrument
	refresh()


func refresh() -> void:
	if not _instrument || not is_node_ready():
		return

	if not _name_edit.has_focus():
		_name_edit.text = _instrument.display_name
	for i in PALETTE_ORDER.size():
		_palette_buttons[i].set_pressed_no_signal(PALETTE_ORDER[i] == _instrument.palette)

	_select_picker_item(_mode_picker, _instrument.get_field("osc_mode"))
	for field: String in _wave_pickers:
		_select_picker_item(_wave_pickers[field], _instrument.get_field(field))
	for field: String in _sliders:
		(_sliders[field] as ValueSlider).value = _instrument.get_field(field)

	var is_dual := _instrument.get_field("osc_mode") == CustomInstrument.OscillatorMode.DUAL
	for field in DUAL_FIELDS:
		for node: Control in _row_nodes[field]:
			node.visible = is_dual

	_envelope_preview.attack_rate = _instrument.get_field("attack_rate")
	_envelope_preview.decay_rate = _instrument.get_field("decay_rate")
	_envelope_preview.sustain_level = _instrument.get_field("sustain_level")
	_envelope_preview.sustain_rate = _instrument.get_field("sustain_rate")
	_envelope_preview.release_rate = _instrument.get_field("release_rate")
	_envelope_preview.queue_redraw()


func _select_picker_item(picker: OptionPicker, id: int) -> void:
	for item in picker.options:
		if item.id == id:
			picker.set_selected(item)
			return
	picker.clear_selected()


# Edits.

func _commit_field(field: String, value: int) -> void:
	if not _instrument || _instrument.get_field(field) == value:
		return
	Controller.set_custom_instrument_field(instrument_index, field, value)


func _commit_name() -> void:
	if not _instrument:
		return
	Controller.set_custom_instrument_name(instrument_index, _name_edit.text)
	_name_edit.text = _instrument.display_name


func _commit_palette(palette: int) -> void:
	if not _instrument:
		return
	Controller.set_custom_instrument_palette(instrument_index, palette)
	refresh()


func _save_to_library() -> void:
	if not _instrument:
		return

	var path := CustomInstrumentLibrary.save_instrument(_instrument)
	if path.is_empty():
		Controller.update_status("FAILED TO SAVE INSTRUMENT TO LIBRARY", Controller.StatusLevel.ERROR)
	else:
		Controller.update_status("INSTRUMENT SAVED TO LIBRARY", Controller.StatusLevel.SUCCESS)


## A static sketch of the amplitude envelope. Rates are SiOPM rates (higher is
## faster); the shape is illustrative, not a time-accurate plot.
class EnvelopePreview extends Control:
	var attack_rate: int = 63
	var decay_rate: int = 0
	var sustain_level: int = 0
	var sustain_rate: int = 0
	var release_rate: int = 28


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))

		var rate_max := float(CustomInstrument.RATE_MAX)
		var segment := size.x / 4.0
		# Slower rates take a longer segment of the width.
		var attack_width := segment * (1.0 - attack_rate / rate_max)
		var decay_width := segment * (1.0 - decay_rate / rate_max)
		var release_width := segment * (1.0 - release_rate / rate_max)
		var hold_width := size.x - attack_width - decay_width - release_width

		# Sustain level is an attenuation: 0 holds the peak, 15 is near silent.
		var sustain_height := size.y * (1.0 - sustain_level / float(CustomInstrument.SUSTAIN_LEVEL_MAX))
		var sustain_end_height := sustain_height * (1.0 - sustain_rate / rate_max)

		var points := PackedVector2Array([
			Vector2(0, size.y),
			Vector2(attack_width, 0),
			Vector2(attack_width + decay_width, size.y - sustain_height),
			Vector2(attack_width + decay_width + hold_width, size.y - sustain_end_height),
			Vector2(size.x, size.y),
		])
		draw_polyline(points, Color(1, 1, 0.75), 2.0)
