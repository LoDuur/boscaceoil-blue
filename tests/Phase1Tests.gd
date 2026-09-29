extends Node
# Headless checks for Phase 1: random pool, v3 legacy block load, export helpers.

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _ready() -> void:
	Controller.io_manager.create_new_song(true)
	var vm := Controller.voice_manager
	# Random pool: 500 rolls, never drumkit / percussion, never the excluded voice.
	var exclude := vm.get_random_voice_data()
	for i in 500:
		var v := vm.get_random_voice_data(exclude)
		_check(not (v is VoiceManager.DrumkitData), "drumkit rolled: %s" % v.name)
		_check(not v.voice_preset.begins_with("midi.percus"), "percus rolled: %s" % v.name)
		_check(not VoiceManager.RANDOM_EXCLUDED_PRESETS.has(v.voice_preset), "noise drum rolled: %s" % v.name)
		_check(v != exclude, "excluded voice repeated")
		exclude = v
	
	# RANDOM button / ADD NEW path via Controller.
	for i in 100:
		var before := Controller.get_current_instrument().voice_index
		Controller.randomize_current_instrument()
		var after := Controller.get_current_instrument()
		_check(after.voice_index != before, "randomize kept the same voice")
		_check(after.type != Instrument.InstrumentType.INSTRUMENT_DRUMKIT, "randomize made a drumkit")
	
	# v3 file with a legacy filter block: build text by hand.
	var parts := PackedInt32Array([3, 0, 0, 0, 120, 16, 4])
	parts.append_array([1, 0, 0, 0, 128, 0, 256]) # 1 instrument
	parts.append_array([1, 0, 0, 0, 0, 1, 60, 1, 0, 0]) # 1 pattern, 1 note
	parts.append(1) # legacy block on
	for j in 48:
		parts.append(7)
	parts.append_array([1, 0, 1, 0, -1, -1, -1, -1, -1, -1, -1])
	var text := ""
	for p in parts:
		text += "%d," % p
	var path := "user://test_legacy_test.ceol"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var song := SongLoader.load(path)
	_check(song != null, "legacy song failed to load")
	if song:
		_check(song.dropped_legacy_filter_data, "legacy block not flagged")
		_check(song.patterns.size() == 1 && song.patterns[0].note_amount == 1, "pattern misread")
		_check(song.arrangement.get_pattern(0, 0) == 0, "arrangement misaligned after skipping block")
		_check(not song.arrangement.is_empty(), "is_empty wrong")
	
	var empty := Song.create_default_song()
	_check(empty.arrangement.is_empty() == (empty.arrangement.get_pattern(0, 0) == -1), "is_empty on default song")
	
	# Remove the scratch files this suite wrote.
	for scratch_file in DirAccess.get_files_at("user://"):
		if scratch_file.begins_with("test_"):
			DirAccess.remove_absolute("user://".path_join(scratch_file))
	
	print("PHASE1 TESTS: %d failures" % _failures)
	get_tree().quit()
