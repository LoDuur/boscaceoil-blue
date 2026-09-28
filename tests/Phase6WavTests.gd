extends Node

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

func _render(path: String) -> PackedByteArray:
	Controller.io_manager._export_wav_song_confirmed(path)
	await Controller.music_player.export_ended
	await get_tree().process_frame
	return FileAccess.get_file_as_bytes(path)

func _peak(wav: PackedByteArray) -> int:
	var peak := 0
	var i := 44
	while i + 1 < wav.size():
		peak = maxi(peak, absi(wav.decode_s16(i)))
		i += 2
	return peak

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Controller.music_player.stop_playback()
	var song := Controller.current_song
	var custom := CustomInstrument.new()
	custom.set_field("osc_mode", 1)
	custom.set_field("wave2", 5)
	song.instruments[0] = custom
	song.patterns[0].add_note(60, 0, 4)
	song.patterns[0].add_note(64, 4, 4)
	song.arrangement.set_pattern(0, 0, 0)
	song.arrangement.set_loop(0, 1)
	var first: PackedByteArray = await _render("user://test_custom_a.wav")
	_check(first.size() > 1000, "wav written: %d bytes" % first.size())
	_check(_peak(first) > 1000, "custom instrument is audible: peak %d" % _peak(first))
	_check(song.arrangement.loop_start == 0 && song.arrangement.loop_end == 1, "loop restored")
	
	SongSaver.save(song, "user://test_custom_wav.ceol")
	Controller.io_manager._load_ceol_song_confirmed("user://test_custom_wav.ceol")
	await get_tree().process_frame
	Controller.music_player.stop_playback()
	var second: PackedByteArray = await _render("user://test_custom_b.wav")
	_check(second.size() == first.size(), "same length after reload")
	_check(absi(_peak(second) - _peak(first)) <= _peak(first) / 20, "similar level after reload: %d vs %d" % [_peak(first), _peak(second)])
	print("identical bytes after reload: ", second == first)
	# Remove the scratch files this suite wrote.
	for scratch_file in DirAccess.get_files_at("user://"):
		if scratch_file.begins_with("test_"):
			DirAccess.remove_absolute("user://".path_join(scratch_file))
	
	print("PHASE6 WAV TESTS: %d failures" % _failures)
	get_tree().quit()
