###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## An integer value edited with a regular slider, with a value readout.
##
## Setting `value` from code is silent, so a view can refresh itself from the
## song without writing the value back. `value_changed` is emitted for edits
## made by the user, and by default only once they settle, so a drag or a held
## arrow key produces one change instead of dozens. Views whose edits already
## merge into a single undo step can set `emit_while_dragging`.
@tool
class_name ValueSlider extends HBoxContainer

signal value_changed()

## Delay, in seconds, before a keyboard or click edit is reported.
const SETTLE_DELAY := 0.25

var _value: int = 0
@export var value: int = 0:
	get = _get_value,
	set = _set_value
@export var min_value: int = 0:
	set(next_value):
		min_value = next_value
		_update_slider()
@export var max_value: int = 1:
	set(next_value):
		max_value = next_value
		_update_slider()
@export var step: int = 1:
	set(next_value):
		step = maxi(1, next_value)
		_update_slider()
## Report every value the slider passes through while it's dragged.
@export var emit_while_dragging: bool = false
## Minimum width of the slider itself, in pixels.
@export var slider_width: float = 140.0:
	set(next_value):
		slider_width = next_value
		_update_slider()

var _dragging: bool = false
var _settle_timer: Timer = null

@onready var _slider: HSlider = $Slider
@onready var _label: Label = $Label


func _ready() -> void:
	_slider.scrollable = false # The wheel scrolls the surrounding panel instead.
	_slider.focus_mode = Control.FOCUS_CLICK
	_update_slider()
	
	if Engine.is_editor_hint():
		return
	
	_settle_timer = Timer.new()
	_settle_timer.one_shot = true
	_settle_timer.wait_time = SETTLE_DELAY
	_settle_timer.timeout.connect(value_changed.emit)
	add_child(_settle_timer)
	
	_slider.value_changed.connect(_slider_value_changed)
	_slider.drag_started.connect(_slider_drag_started)
	_slider.drag_ended.connect(_slider_drag_ended)
	_slider.gui_input.connect(_slider_gui_input)
	_slider.focus_entered.connect(_release_editor_focus)


func _update_slider() -> void:
	if not is_node_ready():
		return
	
	var upper_bound := maxi(min_value, max_value)
	_slider.min_value = min_value
	_slider.max_value = upper_bound
	_slider.step = step
	_slider.custom_minimum_size.x = slider_width
	
	_value = clampi(_value, min_value, upper_bound)
	_slider.set_value_no_signal(_value)
	_update_label()


func _update_label() -> void:
	if not is_node_ready():
		return
	
	_label.text = "%d" % _value
	
	# Reserve room for the widest value, so the slider doesn't shift as it changes.
	var widest := 0
	for number: int in [ _value, min_value, max_value ]:
		widest = maxi(widest, ("%d" % number).length())
	var label_font := _label.get_theme_font("font")
	var label_font_size := _label.get_theme_font_size("font_size")
	_label.custom_minimum_size.x = label_font.get_string_size("0".repeat(widest), HORIZONTAL_ALIGNMENT_RIGHT, -1, label_font_size).x


func _get_value() -> int:
	return _value


func _set_value(next_value: int) -> void:
	# Scene files apply properties in file order, so the range may not be known yet;
	# the value is clamped once the node is ready.
	_value = next_value
	if is_node_ready():
		_value = clampi(_value, min_value, maxi(min_value, max_value))
		_slider.set_value_no_signal(_value)
		_update_label()


# Editing.

func _slider_value_changed(next_value: float) -> void:
	_value = roundi(next_value)
	_update_label()
	
	if emit_while_dragging:
		value_changed.emit()
	elif not _dragging:
		# Keyboard and click edits: wait until they settle, so a held key is one change.
		_settle_timer.start()


func _slider_drag_started() -> void:
	_dragging = true
	_settle_timer.stop()


func _slider_drag_ended(changed: bool) -> void:
	_dragging = false
	if changed && not emit_while_dragging:
		_settle_timer.stop()
		value_changed.emit()


func _slider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton && event.pressed:
		_release_editor_focus()


## The note and arrangement editors keep the arrow keys while they're focused;
## clicking a slider hands the keys back to it.
func _release_editor_focus() -> void:
	Controller.set_editor_focus(Controller.EditorFocus.NONE)
