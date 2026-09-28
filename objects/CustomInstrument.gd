###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## An oscillator-based instrument built from scratch. Its fields are the source
## of truth; the voice is rebuilt from them and is never shared with presets.
class_name CustomInstrument extends Instrument

const CATEGORY := "CUSTOM"
const MAX_NAME_LENGTH := 24
const DEFAULT_NAME := "Custom"

enum OscillatorMode {
	SINGLE,
	DUAL,
}

## Curated waveforms, label -> SiONPulseGeneratorType value (gdsion src/sion_enums.h).
const WAVEFORMS := [
	[ "Sine", 0 ],
	[ "Saw", 1 ],
	[ "Triangle", 4 ],
	[ "Triangle 8-bit", 3 ],
	[ "Square", 5 ],
	[ "White Noise", 6 ],
	[ "Pulse Noise", 17 ],
	[ "Konami", 7 ],
	[ "Sync Low", 8 ],
	[ "Sync High", 9 ],
	[ "VC6 Saw", 11 ],
]

# Parameter ranges, established from the GDSiON 0.7-beta8 source.

## SiOPMOperator::set_*_rate() mask the value with 63 (chip/channels/siopm_operator.cpp:26-44).
const RATE_MAX := 63
## SiOPMOperator::set_sustain_level() masks with 15 but indexes a 16-entry table with
## the raw value, so it must stay in range (chip/channels/siopm_operator.cpp:47-49).
const SUSTAIN_LEVEL_MAX := 15
## SiOPMOperator::set_total_level() clamps to [0, 127] (chip/channels/siopm_operator.cpp:64).
const TOTAL_LEVEL_MAX := 127
## SiONVoice::set_analog_like() accepts connection types 0-3 (src/sion_voice.cpp:289)
## and clamps the balance to [-64, 64] (src/sion_voice.cpp:293).
const CONNECTION_MAX := 3
const BALANCE_LIMIT := 64
## The second oscillator's detune becomes a pitch index shift (chip/channels/siopm_operator.cpp:469),
## where a semitone is 64 steps (pitch index >> 6 is the note, siopm_operator.cpp:478).
## SiON doesn't bound it; the control is limited to one semitone either way.
const DETUNE_LIMIT := 64
## Constant vibrato swings the pitch index by +/- depth (chip/channels/siopm_channel_fm.cpp:742);
## limited to one semitone (64 steps).
const VIBRATO_DEPTH_MAX := 64

## Serialized fields, in their fixed file order: name -> [ min, max, default ].
## vibrato_delay, tremolo_depth and tremolo_delay are reserved and always 0:
## vibrato delay only applies through SiON's modulation envelope, whose time
## unit isn't established, and tremolo needs amplitude modulation enabled per
## operator (siopm_operator.cpp:113-126). They are kept so a later version can
## use them without changing the file layout.
const FIELDS := {
	"osc_mode":        [ 0, OscillatorMode.DUAL, OscillatorMode.SINGLE ],
	"wave1":           [ 0, 511, 5 ],
	"wave2":           [ 0, 511, 1 ],
	"dual_connection": [ 0, CONNECTION_MAX, 0 ],
	"dual_balance":    [ -BALANCE_LIMIT, BALANCE_LIMIT, 0 ],
	"dual_detune":     [ -DETUNE_LIMIT, DETUNE_LIMIT, 8 ],
	"attack_rate":     [ 0, RATE_MAX, 63 ],
	"decay_rate":      [ 0, RATE_MAX, 0 ],
	"sustain_rate":    [ 0, RATE_MAX, 0 ],
	"release_rate":    [ 0, RATE_MAX, 28 ],
	"sustain_level":   [ 0, SUSTAIN_LEVEL_MAX, 0 ],
	"total_level":     [ 0, TOTAL_LEVEL_MAX, 0 ],
	"vibrato_depth":   [ 0, VIBRATO_DEPTH_MAX, 0 ],
	"vibrato_delay":   [ 0, 0, 0 ],
	"tremolo_depth":   [ 0, 0, 0 ],
	"tremolo_delay":   [ 0, 0, 0 ],
}

var display_name: String = DEFAULT_NAME:
	set(value):
		display_name = CustomInstrument.sanitize_name(value)
var palette: int = CustomColorPalette.PALETTE_CYAN:
	set(value):
		palette = CustomColorPalette.validate(value)

## Values of FIELDS, by name.
var _values: Dictionary = {}
var _voice: SiONVoice = null
var _voice_dirty: bool = true


func _init() -> void:
	super(null)
	type = InstrumentType.INSTRUMENT_CUSTOM
	for field: String in FIELDS:
		_values[field] = FIELDS[field][2]


# Identity.

func _get_category() -> String:
	return CATEGORY


func _get_name() -> String:
	return display_name


func _get_color_palette() -> int:
	return palette


static func sanitize_name(value: String) -> String:
	var sanitized := value.strip_edges().substr(0, MAX_NAME_LENGTH)
	return sanitized if not sanitized.is_empty() else DEFAULT_NAME


# Parameters.

static func is_wave_valid(wave: int) -> bool:
	for entry: Array in WAVEFORMS:
		if entry[1] == wave:
			return true
	return false


static func clamp_field(field: String, value: int) -> int:
	if not FIELDS.has(field):
		return 0

	var clamped := clampi(value, FIELDS[field][0], FIELDS[field][1])
	if (field == "wave1" || field == "wave2") && not is_wave_valid(clamped):
		return FIELDS[field][2]
	return clamped


func get_field(field: String) -> int:
	return _values.get(field, 0)


func set_field(field: String, value: int) -> void:
	if not FIELDS.has(field):
		printerr("CustomInstrument: Unknown field '%s'." % [ field ])
		return

	var clamped := clamp_field(field, value)
	if _values[field] == clamped:
		return

	_values[field] = clamped
	_voice_dirty = true


func copy_from(other: CustomInstrument) -> void:
	display_name = other.display_name
	palette = other.palette
	for field: String in FIELDS:
		set_field(field, other.get_field(field))
	volume = other.volume
	lp_cutoff = other.lp_cutoff
	lp_resonance = other.lp_resonance


func duplicate_instrument() -> CustomInstrument:
	var copy := CustomInstrument.new()
	copy.copy_from(self)
	return copy


# Voice.

func build_voice() -> SiONVoice:
	var voice: SiONVoice = null

	if get_field("osc_mode") == OscillatorMode.DUAL:
		voice = SiONVoice.new()
		voice.set_analog_like(get_field("dual_connection"), get_field("wave1"), get_field("wave2"), get_field("dual_balance"), get_field("dual_detune"))

		# set_envelope() would overwrite the per-operator levels that encode the
		# balance, so the envelope is applied to each operator instead.
		var channel_params := voice.get_channel_params()
		for i in channel_params.get_operator_count():
			var op_params := channel_params.get_operator_params(i)
			op_params.attack_rate = get_field("attack_rate")
			op_params.decay_rate = get_field("decay_rate")
			op_params.sustain_rate = get_field("sustain_rate")
			op_params.release_rate = get_field("release_rate")
			op_params.sustain_level = get_field("sustain_level")
			op_params.total_level = clampi(op_params.total_level + get_field("total_level"), 0, TOTAL_LEVEL_MAX)
	else:
		voice = SiONVoice.create(SiONDriver.MODULE_GENERIC_PG, get_field("wave1"))
		voice.set_envelope(get_field("attack_rate"), get_field("decay_rate"), get_field("sustain_rate"), get_field("release_rate"), get_field("sustain_level"), get_field("total_level"))

	voice.set_pitch_modulation(get_field("vibrato_depth"))
	return voice


## Rebuilds the voice at most once per change, when it's next needed.
func _ensure_voice() -> SiONVoice:
	if _voice_dirty || not _voice:
		_voice = build_voice()
		_voice_dirty = false
		_apply_filter(lp_cutoff, lp_resonance, volume)
	return _voice


func get_note_voice(_note: int) -> SiONVoice:
	return _ensure_voice()


# Filter state.

func update_filter() -> void:
	var voice := _ensure_voice()
	if voice.velocity != volume || voice.get_channel_params().filter_cutoff != lp_cutoff || voice.get_channel_params().filter_resonance != lp_resonance:
		_apply_filter(lp_cutoff, lp_resonance, volume)


func change_filter_to(cutoff_: int, resonance_: int, volume_: int) -> void:
	_ensure_voice()
	_apply_filter(cutoff_, resonance_, volume_)


func _apply_filter(cutoff_: int, resonance_: int, volume_: int) -> void:
	_voice.update_volumes = true
	_voice.velocity = volume_
	_voice.set_filter_envelope(0, cutoff_, resonance_)


# Serialization.

## Fields in file order, followed by the palette and the name as UTF-8 bytes.
func write_fields(write_int: Callable) -> void:
	for field: String in FIELDS:
		write_int.call(get_field(field))
	write_int.call(palette)

	var name_bytes := display_name.to_utf8_buffer()
	write_int.call(name_bytes.size())
	for byte in name_bytes:
		write_int.call(byte)


## Reads what write_fields() wrote. Returns false on invalid data.
func read_fields(read_int: Callable) -> bool:
	for field: String in FIELDS:
		var value: int = read_int.call()
		if value != clamp_field(field, value):
			printerr("CustomInstrument: Invalid value %d for '%s'." % [ value, field ])
			return false
		set_field(field, value)

	var palette_value: int = read_int.call()
	if palette_value != CustomColorPalette.validate(palette_value):
		return false
	palette = palette_value

	var name_length: int = read_int.call()
	if name_length < 0 || name_length > MAX_NAME_LENGTH * 4:
		return false
	var name_bytes := PackedByteArray()
	for i in name_length:
		var byte: int = read_int.call()
		if byte < 0 || byte > 255:
			return false
		name_bytes.push_back(byte)
	display_name = name_bytes.get_string_from_utf8()
	return true


func to_dict() -> Dictionary:
	var data := { "name": display_name, "color_palette": palette }
	for field: String in FIELDS:
		data[field] = get_field(field)
	return data


## Builds an instrument from library data. Returns null if any field is
## missing, mistyped or out of range.
static func from_dict(data: Dictionary) -> CustomInstrument:
	var instrument := CustomInstrument.new()

	if not (data.get("name") is String):
		return null
	instrument.display_name = data["name"]

	var number_fields: Array = [ "color_palette" ] + FIELDS.keys()
	for field: String in number_fields:
		var raw: Variant = data.get(field)
		if not (raw is float || raw is int) || float(raw) != floorf(float(raw)):
			return null
		var value := int(raw)

		if field == "color_palette":
			if value != CustomColorPalette.validate(value):
				return null
			instrument.palette = value
		else:
			if value != clamp_field(field, value):
				return null
			instrument.set_field(field, value)

	return instrument
