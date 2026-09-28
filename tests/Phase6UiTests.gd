extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _find(node: Node, cls: String) -> Node:
	if node.get_script() and node.get_script().resource_path.ends_with(cls):
		return node
	for c in node.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Controller.navigate_to(Menu.NavigationTarget.INSTRUMENT)
	await get_tree().process_frame
	Controller.music_player.stop_playback()
	var settings := _find(main, "InstrumentSettings.gd")
	var dock := _find(main, "InstrumentDock.gd")
	var custom_button := dock.get_node_or_null("AddCustomItem") as SquishyButton
	_check(custom_button != null, "NEW CUSTOM button exists")
	var before := Controller.current_song.instruments.size()
	custom_button.pressed.emit()
	await get_tree().process_frame
	_check(Controller.current_song.instruments.size() == before + 1, "NEW CUSTOM adds exactly one instrument: %d" % Controller.current_song.instruments.size())
	_check(Controller.get_current_instrument() is CustomInstrument, "new one is custom and selected")
	var panel: Control = settings._sound_panel
	_check(panel.visible, "sound panel visible for custom")
	_check(settings._category_picker.get_selected() != null && settings._category_picker.get_selected().text == "CUSTOM", "category shows CUSTOM")
	# Edit through the panel's stepper.
	var stepper: Stepper = panel._steppers["attack_rate"]
	stepper.value = 20
	stepper.value_changed.emit()
	_check((Controller.get_current_instrument() as CustomInstrument).get_field("attack_rate") == 20, "stepper edits field")
	# Mode switch hides/shows dual rows.
	panel._commit_field("osc_mode", 1)
	await get_tree().process_frame
	_check(panel._row_nodes["wave2"][1].visible, "dual rows shown")
	Controller.state_manager.undo_state_change()
	await get_tree().process_frame
	_check(not panel._row_nodes["wave2"][1].visible, "undo hides dual rows")
	# Back to a preset via category picker.
	Controller.set_current_instrument_by_category("CHIPTUNE")
	await get_tree().process_frame
	_check(not panel.visible, "panel hidden for presets")
	_check(settings._instrument_picker.placeholder_text == "Instrument Name", "placeholder restored")
	print("PHASE6 UI TESTS: %d failures" % _failures)
	get_tree().quit()
