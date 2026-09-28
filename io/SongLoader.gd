###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

class_name SongLoader extends RefCounted


static func load(path: String) -> Song:
	if path.get_extension() != Song.FILE_EXTENSION:
		printerr("SongLoader: The song file must have a .%s extension." % [ Song.FILE_EXTENSION ])
		return null
	
	var file := FileAccess.open(path, FileAccess.READ)
	var error := FileAccess.get_open_error()
	if error != OK:
		printerr("SongLoader: Failed to load and open the song file at '%s' (code %d)." % [ path, error ])
		return null
	
	var file_contents := file.get_as_text()
	var reader := SongFileReader.new(path, file_contents)
	
	# TODO: Add a validation step after loading, to update song data and remove invalid bits.
	
	if reader.get_version() == 1:
		return _load_v1(reader)
	if reader.get_version() == 2:
		return _load_v2(reader)
	if reader.get_version() == 3:
		return _load_v3(reader)
	if reader.get_version() == 4:
		return _load_v4(reader)
	
	printerr("SongLoader: The song file at '%s' has unsupported version %d." % [ path, reader.get_version() ])
	return null


# Original release; due to a bug it never saved the instrument volume.
static func _load_v1(reader: SongFileReader) -> Song:
	var song := Song.new()
	song.format_version = reader.get_version()
	song.filename = reader.get_path()
	
	# Basic information.

	song.bpm = reader.read_int()
	song.pattern_size = reader.read_int()
	song.bar_size = reader.read_int()
	
	# Instruments.
	
	var instrument_count := reader.read_int()
	for i in instrument_count:
		var voice_index := reader.read_int()
		var voice_data := Controller.voice_manager.get_voice_data_at(voice_index)
		var instrument := Controller.instance_instrument_by_voice(voice_data)
		
		instrument.voice_index = voice_index
		reader.read_int() # Empty read, we can determine the type by voice data.
		reader.read_int() # Empty read, we use the color palette from reference data.
		instrument.lp_cutoff = reader.read_int()
		instrument.lp_resonance = reader.read_int()
		instrument.update_filter()
		
		song.instruments.push_back(instrument)
	
	# Patterns.
	
	var pattern_count := reader.read_int()
	for i in pattern_count:
		var pattern := Pattern.new()
		
		pattern.key = reader.read_int()
		pattern.scale = reader.read_int()
		pattern.instrument_idx = reader.read_int()
		reader.read_int() # Empty read, we can determine the color palette by the instrument.
		
		var note_amount := reader.read_int()
		for j in note_amount:
			var note_value := reader.read_int()
			var note_length := reader.read_int()
			var note_position := reader.read_int()
			reader.read_int() # Empty read, this value is unused.
			pattern.add_note(note_value, note_position, note_length, false)
		
		pattern.sort_notes()
		pattern.reindex_active_notes()
		
		_skip_legacy_filter_block(reader, song)
		
		song.patterns.push_back(pattern)
	
	# Arrangement.
	
	song.arrangement.timeline_length = reader.read_int()
	song.arrangement.set_loop(reader.read_int(), reader.read_int())
	
	for i in song.arrangement.timeline_length:
		var channels := song.arrangement.timeline_bars[i]
		for j in Arrangement.CHANNEL_NUMBER:
			channels[j] = reader.read_int()
		song.arrangement.timeline_bars[i] = channels
	
	var remainder := reader.get_read_remainder()
	if remainder > 0:
		printerr("SongLoader: Invalid song file at '%s' contains excessive data (%d)." % [ reader.get_path(), remainder ])
	
	return song


# Second version; includes instrument volume, global swing.
static func _load_v2(reader: SongFileReader) -> Song:
	var song := Song.new()
	song.format_version = reader.get_version()
	song.filename = reader.get_path()
	
	# Basic information.

	song.swing = reader.read_int()
	song.bpm = reader.read_int()
	song.pattern_size = reader.read_int()
	song.bar_size = reader.read_int()
	
	# Instruments.
	
	var instrument_count := reader.read_int()
	for i in instrument_count:
		var voice_index := reader.read_int()
		var voice_data := Controller.voice_manager.get_voice_data_at(voice_index)
		var instrument := Controller.instance_instrument_by_voice(voice_data)
		
		instrument.voice_index = voice_index
		reader.read_int() # Empty read, we can determine the type by voice data.
		reader.read_int() # Empty read, we use the color palette from reference data.
		instrument.lp_cutoff = reader.read_int()
		instrument.lp_resonance = reader.read_int()
		instrument.volume = reader.read_int()
		instrument.update_filter()
		
		song.instruments.push_back(instrument)
	
	# Patterns.
	
	var pattern_count := reader.read_int()
	for i in pattern_count:
		var pattern := Pattern.new()
		
		pattern.key = reader.read_int()
		pattern.scale = reader.read_int()
		pattern.instrument_idx = reader.read_int()
		reader.read_int() # Empty read, we can determine the color palette by the instrument.
		
		var note_amount := reader.read_int()
		for j in note_amount:
			var note_value := reader.read_int()
			var note_length := reader.read_int()
			var note_position := reader.read_int()
			reader.read_int() # Empty read, this value is unused.
			pattern.add_note(note_value, note_position, note_length, false)
		
		pattern.sort_notes()
		pattern.reindex_active_notes()
		
		_skip_legacy_filter_block(reader, song)
		
		song.patterns.push_back(pattern)
	
	# Arrangement.
	
	song.arrangement.timeline_length = reader.read_int()
	song.arrangement.set_loop(reader.read_int(), reader.read_int())
	
	for i in song.arrangement.timeline_length:
		var channels := song.arrangement.timeline_bars[i]
		for j in Arrangement.CHANNEL_NUMBER:
			channels[j] = reader.read_int()
		song.arrangement.timeline_bars[i] = channels
	
	var remainder := reader.get_read_remainder()
	if remainder > 0:
		printerr("SongLoader: Invalid song file at '%s' contains excessive data (%d)." % [ reader.get_path(), remainder ])
	
	return song


# Third version; includes global effects, patterns can go up to 32 notes.
static func _load_v3(reader: SongFileReader) -> Song:
	var song := Song.new()
	song.format_version = reader.get_version()
	song.filename = reader.get_path()
	
	# Basic information.

	song.swing = reader.read_int()
	song.global_effect = reader.read_int()
	song.global_effect_power = reader.read_int()

	song.bpm = reader.read_int()
	song.pattern_size = reader.read_int()
	song.bar_size = reader.read_int()
	
	# Instruments.
	
	var instrument_count := reader.read_int()
	for i in instrument_count:
		var voice_index := reader.read_int()
		var voice_data := Controller.voice_manager.get_voice_data_at(voice_index)
		var instrument := Controller.instance_instrument_by_voice(voice_data)
		
		instrument.voice_index = voice_index
		reader.read_int() # Empty read, we can determine the type by voice data.
		reader.read_int() # Empty read, we use the color palette from reference data.
		instrument.lp_cutoff = reader.read_int()
		instrument.lp_resonance = reader.read_int()
		instrument.volume = reader.read_int()
		instrument.update_filter()
		
		song.instruments.push_back(instrument)
	
	# Patterns.
	
	var pattern_count := reader.read_int()
	for i in pattern_count:
		var pattern := Pattern.new()
		
		pattern.key = reader.read_int()
		pattern.scale = reader.read_int()
		pattern.instrument_idx = reader.read_int()
		reader.read_int() # Empty read, we can determine the color palette by the instrument.
		
		var note_amount := reader.read_int()
		for j in note_amount:
			var note_value := reader.read_int()
			var note_length := reader.read_int()
			var note_position := reader.read_int()
			reader.read_int() # Empty read, this value is unused.
			pattern.add_note(note_value, note_position, note_length, false)
		
		pattern.sort_notes()
		pattern.reindex_active_notes()
		
		_skip_legacy_filter_block(reader, song)
		
		song.patterns.push_back(pattern)
	
	# Arrangement.
	
	song.arrangement.timeline_length = reader.read_int()
	song.arrangement.set_loop(reader.read_int(), reader.read_int())
	
	for i in song.arrangement.timeline_length:
		var channels := song.arrangement.timeline_bars[i]
		for j in Arrangement.CHANNEL_NUMBER:
			channels[j] = reader.read_int()
		song.arrangement.timeline_bars[i] = channels
	
	var remainder := reader.get_read_remainder()
	if remainder > 0:
		printerr("SongLoader: Invalid song file at '%s' contains excessive data (%d)." % [ reader.get_path(), remainder ])
	
	return song


# Fourth version; instruments are typed and can be custom, patterns have no
# instrument recording block. See SongSaver for the layout. Unlike older
# loaders, structural errors (unknown voices, dangling indices) fail the load.
static func _load_v4(reader: SongFileReader) -> Song:
	var song := Song.new()
	song.format_version = reader.get_version()
	song.filename = reader.get_path()
	
	# Basic information.
	
	song.swing = reader.read_int()
	song.global_effect = reader.read_int()
	song.global_effect_power = reader.read_int()
	
	song.bpm = reader.read_int()
	song.pattern_size = reader.read_int()
	song.bar_size = reader.read_int()
	
	# Instruments.
	
	var instrument_count := reader.read_int()
	if instrument_count < 1 || instrument_count > Song.MAX_INSTRUMENT_COUNT:
		return _fail(reader, "invalid instrument count %d" % [ instrument_count ])
	
	for i in instrument_count:
		var instrument_type := reader.read_int()
		var instrument: Instrument = null
		
		match instrument_type:
			Instrument.InstrumentType.INSTRUMENT_SINGLE, Instrument.InstrumentType.INSTRUMENT_DRUMKIT:
				var voice_index := reader.read_int()
				var voice_data := Controller.voice_manager.get_voice_data_at(voice_index)
				if not voice_data:
					return _fail(reader, "unknown voice %d" % [ voice_index ])
				
				instrument = Controller.instance_instrument_by_voice(voice_data)
				if instrument.type != instrument_type:
					return _fail(reader, "voice %d doesn't match instrument type %d" % [ voice_index, instrument_type ])
				reader.read_int() # The color palette comes from the voice data.
			
			Instrument.InstrumentType.INSTRUMENT_CUSTOM:
				var custom_instrument := CustomInstrument.new()
				if not custom_instrument.read_fields(reader.read_int):
					return _fail(reader, "invalid custom instrument %d" % [ i ])
				instrument = custom_instrument
			
			_:
				return _fail(reader, "unknown instrument type %d" % [ instrument_type ])
		
		instrument.lp_cutoff = reader.read_int()
		instrument.lp_resonance = reader.read_int()
		instrument.volume = reader.read_int()
		instrument.update_filter()
		
		song.instruments.push_back(instrument)
	
	# Patterns.
	
	var pattern_count := reader.read_int()
	if pattern_count < 1 || pattern_count > Song.MAX_PATTERN_COUNT:
		return _fail(reader, "invalid pattern count %d" % [ pattern_count ])
	
	for i in pattern_count:
		var pattern := Pattern.new()
		
		pattern.key = reader.read_int()
		pattern.scale = reader.read_int()
		var instrument_idx := reader.read_int()
		if instrument_idx < 0 || instrument_idx >= instrument_count:
			return _fail(reader, "pattern %d uses unknown instrument %d" % [ i, instrument_idx ])
		pattern.instrument_idx = instrument_idx
		reader.read_int() # Unused.
		
		var note_amount := reader.read_int()
		if note_amount < 0 || note_amount > Pattern.MAX_NOTES_IN_PATTERN:
			return _fail(reader, "pattern %d has invalid note amount %d" % [ i, note_amount ])
		
		for j in note_amount:
			var note_value := reader.read_int()
			var note_length := reader.read_int()
			var note_position := reader.read_int()
			reader.read_int() # Unused.
			
			if note_value < 0 || note_position < 0 || note_length < 1 || note_length > Pattern.MAX_NOTE_LENGTH:
				return _fail(reader, "pattern %d has invalid note (%d, %d, %d)" % [ i, note_value, note_position, note_length ])
			pattern.add_note(note_value, note_position, note_length, false)
		
		pattern.sort_notes()
		pattern.reindex_active_notes()
		song.patterns.push_back(pattern)
	
	# Arrangement.
	
	var timeline_length := reader.read_int()
	if timeline_length < 0 || timeline_length > Arrangement.BAR_NUMBER:
		return _fail(reader, "invalid timeline length %d" % [ timeline_length ])
	song.arrangement.timeline_length = timeline_length
	
	var loop_start := reader.read_int()
	var loop_end := reader.read_int()
	if loop_start < 0 || loop_end <= loop_start || loop_end > Arrangement.BAR_NUMBER:
		return _fail(reader, "invalid loop %d-%d" % [ loop_start, loop_end ])
	song.arrangement.set_loop(loop_start, loop_end)
	
	for i in timeline_length:
		var channels := song.arrangement.timeline_bars[i]
		for j in Arrangement.CHANNEL_NUMBER:
			var pattern_idx := reader.read_int()
			if pattern_idx < -1 || pattern_idx >= pattern_count:
				return _fail(reader, "bar %d references unknown pattern %d" % [ i, pattern_idx ])
			channels[j] = pattern_idx
		song.arrangement.timeline_bars[i] = channels
	
	var remainder := reader.get_read_remainder()
	if remainder > 0 || reader.is_end_overrun():
		return _fail(reader, "unexpected length of data")
	
	return song


static func _fail(reader: SongFileReader, reason: String) -> Song:
	printerr("SongLoader: Invalid song file at '%s': %s." % [ reader.get_path(), reason ])
	return null


# Formats 1–3 store an optional per-pattern block of filter automation values
# (volume/cutoff/resonance for the first 16 notes). The feature was removed, so
# the block is consumed to keep the reader aligned, and its values are discarded.
static func _skip_legacy_filter_block(reader: SongFileReader, song: Song) -> void:
	var has_block := reader.read_int() == 1
	if not has_block:
		return
	
	for j in 16 * 3:
		reader.read_int()
	song.dropped_legacy_filter_data = true


class SongFileReader extends RefCounted:
	const SEPARATOR := ","

	var _path: String = ""
	var _contents: String = ""
	var _version: int = -1

	var _offset: int = 0
	var _end_reached: bool = true
	var _end_overrun: bool = false
	var _next_value: String = ""
	
	
	func _init(path: String, contents: String) -> void:
		_path = path
		_contents = contents
		if _contents.length() > 0:
			_offset = 0
			_end_reached = false
		
		_version = read_int()
	
	
	func get_path() -> String:
		return _path
	
	
	func get_version() -> int:
		return _version
	
	
	func read_int() -> int:
		_next_value = ""
		if _end_reached:
			_end_overrun = true
		
		while not _end_reached:
			var token := _contents[_offset]
			if token == SEPARATOR:
				break
			_next_value += token
			_offset += 1
			
			if _offset >= _contents.length():
				_end_reached = true
		
		if not _end_reached:
			_offset += 1 # Move past the separator.
			if _offset >= _contents.length():
				_end_reached = true
		
		return _next_value.to_int()
	
	
	## Whether more values were read than the file contains.
	func is_end_overrun() -> bool:
		return _end_overrun
	
	
	func get_read_remainder() -> int:
		return _contents.length() - _offset
