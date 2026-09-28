extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _ready() -> void:
	Controller.io_manager.create_new_song(true)
	Controller.music_player.stop_playback()
	
	# Voice building, single and dual.
	var single := CustomInstrument.new()
	var v1 := single.build_voice()
	_check(v1 != null && v1.get_channel_params().get_operator_count() == 1, "single voice ops")
	_check(v1.get_channel_params().get_operator_params(0).pulse_generator_type == 5, "square wave")
	_check(v1.get_channel_params().get_operator_params(0).release_rate == 28, "release rate")
	var dual := CustomInstrument.new()
	dual.set_field("osc_mode", CustomInstrument.OscillatorMode.DUAL)
	dual.set_field("dual_balance", 32)
	dual.set_field("total_level", 10)
	var v2 := dual.build_voice()
	var cp := v2.get_channel_params()
	_check(cp.get_operator_count() == 2 && cp.is_analog_like(), "dual analog-like")
	_check(cp.get_operator_params(0).total_level != cp.get_operator_params(1).total_level, "balance survives envelope: %d %d" % [cp.get_operator_params(0).total_level, cp.get_operator_params(1).total_level])
	_check(cp.get_operator_params(1).detune2 == 8, "detune")
	
	# Shared preset isolation: editing custom doesn't touch presets.
	var sq_preset := Controller.voice_manager.get_voice_preset("square")
	var before_rr: int = sq_preset.get_channel_params().get_operator_params(0).release_rate
	single.set_field("release_rate", 5)
	single.update_filter()
	single.get_note_voice(0)
	_check(sq_preset.get_channel_params().get_operator_params(0).release_rate == before_rr, "preset untouched")
	_check(single.get_note_voice(0) != sq_preset, "own voice")
	
	# Clamping.
	single.set_field("sustain_level", 99)
	_check(single.get_field("sustain_level") == 15, "clamp sustain level")
	single.set_field("wave1", 10)
	_check(single.get_field("wave1") == 5, "invalid wave falls back to default")
	single.set_field("tremolo_depth", 40)
	_check(single.get_field("tremolo_depth") == 0, "reserved stays 0")
	
	# Controller flow: create, edit (accumulated), undo.
	var count := Controller.current_song.instruments.size()
	Controller.create_custom_instrument()
	var idx := Controller.current_instrument_index
	_check(Controller.current_song.instruments.size() == count + 1 && Controller.get_current_instrument() is CustomInstrument, "created custom")
	Controller.set_custom_instrument_field(idx, "attack_rate", 50)
	Controller.set_custom_instrument_field(idx, "attack_rate", 40)
	Controller.set_custom_instrument_field(idx, "attack_rate", 30)
	var ci := Controller.get_current_instrument() as CustomInstrument
	_check(ci.get_field("attack_rate") == 30, "field set")
	Controller.state_manager.undo_state_change()
	_check(ci.get_field("attack_rate") == 63, "one undo for accumulated edits: %d" % ci.get_field("attack_rate"))
	Controller.set_custom_instrument_name(idx, "  Soft Pluck with a very long name that overflows  ")
	_check(ci.display_name == "Soft Pluck with a very l", "name sanitized: '%s'" % ci.display_name)
	Controller.set_custom_instrument_palette(idx, ColorPalette.PALETTE_RED)
	_check(ci.color_palette == ColorPalette.PALETTE_RED && ci.category == "CUSTOM", "identity")
	
	# Randomize never leaves custom; 200 rolls stay in range.
	for i in 200:
		Controller.randomize_current_instrument()
		var cur := Controller.get_current_instrument()
		if not (cur is CustomInstrument):
			_check(false, "randomize switched away from custom")
			break
		var c := cur as CustomInstrument
		_check(c.get_field("attack_rate") >= 40 && c.get_field("total_level") <= 24, "safe ranges")
	
	# Round trip with 2 custom + 2 preset instruments.
	var song := Controller.current_song
	song.instruments.clear()
	song.instruments.push_back(Controller.instance_instrument_by_voice(Controller.voice_manager.get_voice_data("MIDI", "Grand Piano")))
	song.instruments.push_back(Controller.instance_instrument_by_voice(Controller.voice_manager.get_first_voice_data("DRUMKIT")))
	var c1 := CustomInstrument.new()
	c1.display_name = "Grüße ♪"
	c1.palette = ColorPalette.PALETTE_GRAY
	c1.set_field("osc_mode", 1)
	c1.set_field("dual_detune", -12)
	c1.volume = 100
	song.instruments.push_back(c1)
	var c2 := CustomInstrument.new()
	c2.set_field("vibrato_depth", 20)
	song.instruments.push_back(c2)
	var n_custom := song.instruments.filter(func(x: Instrument) -> bool: return x is CustomInstrument).size()
	_check(song.instruments.size() == 4 && n_custom == 2, "2 custom + 2 preset: %d" % n_custom)
	for p in song.patterns:
		p.instrument_idx = 0
	_check(SongSaver.save(song, "user://test_custom_a.ceol"), "save")
	var loaded := SongLoader.load("user://test_custom_a.ceol")
	_check(loaded != null, "load")
	if loaded:
		_check(SongSaver.save(loaded, "user://test_custom_b.ceol"), "save b")
		_check(FileAccess.get_file_as_string("user://test_custom_a.ceol") == FileAccess.get_file_as_string("user://test_custom_b.ceol"), "byte identical with custom")
		var lc := loaded.instruments[2] as CustomInstrument
		_check(lc != null && lc.display_name == "Grüße ♪" && lc.get_field("dual_detune") == -12 && lc.volume == 100, "custom fields survive")
	
	# Library. Only files created here are touched; an existing library stays intact.
	var baseline := CustomInstrumentLibrary.load_entries()
	var path := CustomInstrumentLibrary.save_instrument(c1)
	_check(path.begins_with("user://custom_instruments/gr-e-") && path.ends_with(".json"), "library path %s" % path)
	var suffix := str(Time.get_ticks_usec())
	var broken_path := CustomInstrumentLibrary.LIBRARY_PATH.path_join("test_broken_%s.json" % suffix)
	var garbage_path := CustomInstrumentLibrary.LIBRARY_PATH.path_join("test_garbage_%s.json" % suffix)
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	broken.store_string('{"schema": 1, "name": "X", "color_palette": 3, "osc_mode": 1, "wave1": "square"}')
	broken.close()
	var garbage := FileAccess.open(garbage_path, FileAccess.WRITE)
	garbage.store_string('not json')
	garbage.close()
	var result := CustomInstrumentLibrary.load_entries()
	_check(result.entries.size() == baseline.entries.size() + 1, "library gained one entry")
	_check(result.skipped_count == baseline.skipped_count + 2, "library skipped the two invalid files")
	var saved_entries := result.entries.filter(func(entry: CustomInstrumentLibrary.Entry) -> bool: return entry.path == path)
	_check(saved_entries.size() == 1 && saved_entries[0].instrument.to_dict() == c1.to_dict(), "library round trip")
	for created_path: String in [ path, broken_path, garbage_path ]:
		DirAccess.remove_absolute(created_path)
	
	# Remove the scratch files this suite wrote.
	for scratch_file in DirAccess.get_files_at("user://"):
		if scratch_file.begins_with("test_"):
			DirAccess.remove_absolute("user://".path_join(scratch_file))
	
	print("PHASE6 TESTS: %d failures" % _failures)
	get_tree().quit()
