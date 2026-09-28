extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _build_song() -> Song:
	var song := Song.create_default_song()
	song.bpm = 133
	song.swing = -3
	song.global_effect = 2
	song.global_effect_power = 70
	var kit := Controller.voice_manager.get_first_voice_data("DRUMKIT")
	var drum := Controller.instance_instrument_by_voice(kit)
	drum.volume = 200
	song.instruments.push_back(drum)
	song.instruments[0].lp_cutoff = 90
	song.instruments[0].lp_resonance = 3
	var p2 := Pattern.new()
	p2.instrument_idx = 1
	p2.add_note(2, 3, 1)
	song.patterns.push_back(p2)
	song.patterns[0].key = 2
	song.patterns[0].scale = 1
	song.patterns[0].add_note(62, 0, 4)
	song.patterns[0].add_note(66, 5, 1)
	song.arrangement.set_pattern(0, 0, 0)
	song.arrangement.set_pattern(3, 5, 1)
	song.arrangement.set_loop(1, 3)
	return song

func _ready() -> void:
	var song := _build_song()
	var a := "user://test_rt_a.ceol"
	var b := "user://test_rt_b.ceol"
	_check(SongSaver.save(song, a), "save a")
	var loaded := SongLoader.load(a)
	_check(loaded != null, "load a")
	if loaded:
		_check(loaded.format_version == 4, "v4 header")
		_check(loaded.instruments.size() == 2 && loaded.instruments[1].type == Instrument.InstrumentType.INSTRUMENT_DRUMKIT, "instrument types")
		_check(loaded.instruments[1].volume == 200 && loaded.instruments[0].lp_cutoff == 90, "instrument values")
		_check(loaded.arrangement.get_pattern(3, 5) == 1 && loaded.arrangement.loop_start == 1, "arrangement")
		_check(SongSaver.save(loaded, b), "save b")
		_check(_read(a) == _read(b), "byte-identical round trip")
	
	# Rejections.
	var bad := {
		"unknown voice": "4,0,0,0,120,16,4,1,0,99999,0,128,0,256,1,0,0,0,0,0,1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,",
		"dangling pattern ref": "4,0,0,0,120,16,4,1,0,0,0,128,0,256,1,0,0,0,0,0,1,0,1,5,-1,-1,-1,-1,-1,-1,-1,",
		"truncated": "4,0,0,0,120,16,4,1,0,0,0,128,0,256,1,0,0,0,0,0,1,0,1,-1,-1,",
		"bad type": "4,0,0,0,120,16,4,1,7,0,0,128,0,256,1,0,0,0,0,0,1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,",
	}
	for case_name: String in bad:
		var f := FileAccess.open("user://test_bad.ceol", FileAccess.WRITE)
		f.store_string(bad[case_name])
		f.close()
		_check(SongLoader.load("user://test_bad.ceol") == null, "rejects %s" % case_name)
	var good := FileAccess.open("user://test_good.ceol", FileAccess.WRITE)
	good.store_string("4,0,0,0,120,16,4,1,0,0,0,128,0,256,1,0,0,0,0,0,1,0,1,-1,-1,-1,-1,-1,-1,-1,-1,")
	good.close()
	_check(SongLoader.load("user://test_good.ceol") != null, "accepts minimal v4")
	
	# v3 upgrade path: load legacy, save v4, reload.
	var v3 := "3,0,0,0,120,16,4,1,0,0,0,128,0,256,1,0,0,0,0,1,60,1,0,0,1," + ",".join(PackedStringArray(range(48).map(func(_i: int) -> String: return "7"))) + ",1,0,1,0,-1,-1,-1,-1,-1,-1,-1,"
	var f3 := FileAccess.open("user://test_legacy.ceol", FileAccess.WRITE)
	f3.store_string(v3)
	f3.close()
	var legacy := SongLoader.load("user://test_legacy.ceol")
	_check(legacy != null && legacy.format_version == 3 && legacy.dropped_legacy_filter_data, "v3 loads")
	if legacy:
		SongSaver.save(legacy, "user://test_legacy_up.ceol")
		var up := SongLoader.load("user://test_legacy_up.ceol")
		_check(up != null && up.format_version == 4 && up.patterns[0].note_amount == 1, "v3 -> v4 upgrade")
	
	# Remove the scratch files this suite wrote.
	for scratch_file in DirAccess.get_files_at("user://"):
		if scratch_file.begins_with("test_"):
			DirAccess.remove_absolute("user://".path_join(scratch_file))
	
	print("PHASE5 TESTS: %d failures" % _failures)
	get_tree().quit()
