###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## User library of custom instrument definitions, stored as JSON files in
## user://custom_instruments/<slug>-<uuid>.json.
class_name CustomInstrumentLibrary extends RefCounted

const LIBRARY_PATH := "user://custom_instruments"
const SCHEMA_VERSION := 1


## Saves the instrument definition. Returns the file path, or an empty string on failure.
static func save_instrument(instrument: CustomInstrument) -> String:
	var error := DirAccess.make_dir_recursive_absolute(LIBRARY_PATH)
	if error != OK:
		printerr("CustomInstrumentLibrary: Failed to create '%s' (code %d)." % [ LIBRARY_PATH, error ])
		return ""
	
	var data := instrument.to_dict()
	data["schema"] = SCHEMA_VERSION
	
	var path := LIBRARY_PATH.path_join("%s-%s.json" % [ _slugify(instrument.display_name), _generate_uuid() ])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("CustomInstrumentLibrary: Failed to open '%s' for writing (code %d)." % [ path, FileAccess.get_open_error() ])
		return ""
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return path


## Loads every valid definition, sorted by name. Files that fail to parse or
## validate are skipped and counted in the result.
static func load_entries() -> LoadResult:
	var result := LoadResult.new()
	if not DirAccess.dir_exists_absolute(LIBRARY_PATH):
		return result
	
	for file_name in DirAccess.get_files_at(LIBRARY_PATH):
		if file_name.get_extension() != "json":
			continue
		
		var path := LIBRARY_PATH.path_join(file_name)
		var instrument := _load_file(path)
		if not instrument:
			printerr("CustomInstrumentLibrary: Skipped invalid definition at '%s'." % [ path ])
			result.skipped_count += 1
			continue
		
		var entry := Entry.new()
		entry.path = path
		entry.instrument = instrument
		result.entries.push_back(entry)
	
	result.entries.sort_custom(func(a: Entry, b: Entry) -> bool:
		return a.instrument.display_name.naturalnocasecmp_to(b.instrument.display_name) < 0
	)
	return result


static func _load_file(path: String) -> CustomInstrument:
	var contents := FileAccess.get_file_as_string(path)
	if contents.is_empty():
		return null
	
	var json := JSON.new()
	if json.parse(contents) != OK || not (json.data is Dictionary):
		return null
	
	var data: Dictionary = json.data
	var schema: Variant = data.get("schema")
	if not (schema is float || schema is int) || int(schema) != SCHEMA_VERSION:
		return null
	
	return CustomInstrument.from_dict(data)


static func _slugify(value: String) -> String:
	var slug := ""
	for character in value.to_lower():
		slug += character if (character >= "a" && character <= "z") || (character >= "0" && character <= "9") else "-"
	
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	slug = slug.trim_prefix("-").trim_suffix("-")
	return slug if not slug.is_empty() else "instrument"


## RFC 4122 version 4 UUID.
static func _generate_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [ hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12) ]


class Entry:
	var path: String = ""
	var instrument: CustomInstrument = null


class LoadResult:
	var entries: Array[Entry] = []
	var skipped_count: int = 0
