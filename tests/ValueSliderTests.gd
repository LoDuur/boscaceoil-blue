extends Node

var _failures := 0
var _emitted := 0

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

func _make(min_v: int, max_v: int, live: bool) -> ValueSlider:
	var slider: ValueSlider = load("res://gui/widgets/ValueSlider.tscn").instantiate()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.emit_while_dragging = live
	add_child(slider)
	slider.value_changed.connect(func() -> void: _emitted += 1)
	return slider

func _ready() -> void:
	# Setting the value from code is silent and clamped.
	var s := _make(10, 450, false)
	s.value = 120
	_check(s.value == 120 && s._slider.value == 120 && s._label.text == "120", "silent set shows value")
	s.value = 9999
	_check(s.value == 450, "value clamps to max")
	_check(_emitted == 0, "programmatic set never emits")
	
	# A drag reports once, when it ends.
	s._slider_drag_started()
	for v: int in [130, 140, 150]:
		s._slider.value = v
	_check(_emitted == 0, "no emission during a drag")
	s._slider_drag_ended(true)
	_check(_emitted == 1 && s.value == 150, "one emission at drag end (%d)" % _emitted)
	
	# Keyboard-style changes settle into a single report.
	_emitted = 0
	s._slider.value = 151
	s._slider.value = 152
	s._slider.value = 153
	_check(_emitted == 0, "settling edits are held back")
	await get_tree().create_timer(ValueSlider.SETTLE_DELAY + 0.15).timeout
	_check(_emitted == 1 && s.value == 153, "held key reports once (%d)" % _emitted)
	
	# Live mode reports every value.
	_emitted = 0
	var live := _make(0, 63, true)
	live._slider_drag_started()
	live._slider.value = 10
	live._slider.value = 20
	live._slider_drag_ended(true)
	_check(_emitted == 2 && live.value == 20, "live mode emits per change, not again at the end (%d)" % _emitted)
	
	# Ranges applied in scene file order (value before range) still end up in range.
	var late: ValueSlider = load("res://gui/widgets/ValueSlider.tscn").instantiate()
	late.value = 16
	late.min_value = 1
	late.max_value = 32
	add_child(late)
	_check(late.value == 16 && late._slider.max_value == 32, "value survives late range: %d" % late.value)
	
	# Readout width doesn't change with the value.
	var w := late._label.custom_minimum_size.x
	late.value = 3
	_check(is_equal_approx(w, late._label.custom_minimum_size.x), "readout width is stable")
	
	# The wheel must not change the value, and a click hands arrow keys back from the editors.
	_check(not s._slider.scrollable, "slider ignores the wheel")
	Controller.set_editor_focus(Controller.EditorFocus.NOTES)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	s._slider_gui_input(press)
	_check(Controller.editor_focus == Controller.EditorFocus.NONE, "click releases editor focus")
	
	# Real views on the main scene.
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Controller.music_player.stop_playback()
	_check(_find(main, "Stepper.gd") == null, "no Stepper left in the scene tree")
	var file_view := _find(main, "FileView.gd")
	var bpm: ValueSlider = file_view._bpm_slider
	var pattern_size: ValueSlider = file_view._pattern_size_slider
	var bar_size: ValueSlider = file_view._bar_size_slider
	_check(bpm.min_value == 10 && bpm.max_value == 450 && pattern_size.max_value == 32 && bar_size.min_value == 1, "file view ranges")
	_check(bpm.value == Controller.current_song.bpm, "BPM slider shows the song's BPM")
	
	var history_before: int = Controller.state_manager._state_history.size()
	bpm._slider_drag_started()
	for v: int in [140, 150, 160, 170]:
		bpm._slider.value = v
	_check(Controller.current_song.bpm == 120, "song untouched mid-drag")
	bpm._slider_drag_ended(true)
	_check(Controller.current_song.bpm == 170, "BPM set at drag end")
	_check(Controller.state_manager._state_history.size() == history_before + 1, "BPM drag is one undo step")
	Controller.state_manager.undo_state_change()
	await get_tree().process_frame
	_check(Controller.current_song.bpm == 120 && bpm.value == 120, "undo restores BPM and slider")
	
	pattern_size._slider_drag_started()
	pattern_size._slider.value = 24
	pattern_size._slider_drag_ended(true)
	_check(Controller.current_song.pattern_size == 24, "pattern size set")
	bar_size._slider_drag_started()
	bar_size._slider.value = 8
	bar_size._slider_drag_ended(true)
	_check(Controller.current_song.bar_size == 8, "bar size set")
	
	var advanced := _find(main, "AdvancedView.gd")
	var swing: ValueSlider = advanced._swing_slider
	_check(swing.min_value == -10 && swing.max_value == 10, "swing range")
	swing._slider_drag_started()
	swing._slider.value = -4
	swing._slider_drag_ended(true)
	_check(Controller.current_song.swing == -4, "swing set")
	
	# The pads are untouched: still PadSliders, still editing filter and volume.
	var settings := _find(main, "InstrumentSettings.gd")
	_check(settings._lowpass_slider is PadSlider && settings._volume_slider is PadSlider, "filter and volume pads are still pads")
	
	print("VALUESLIDER TESTS: %d failures" % _failures)
	get_tree().quit()
