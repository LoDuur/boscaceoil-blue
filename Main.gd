###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

extends MarginContainer

var _default_window_title: String = ""

@onready var _pattern_editor: Control = %PatternEditor
@onready var _locked_indicator: Control = %LockedIndicator


func _enter_tree() -> void:
	Controller.window_manager.register_window()
	
	_default_window_title = get_window().title


func _ready() -> void:
	Controller.window_manager.restore_window()
	
	_pattern_editor.visible = true
	_locked_indicator.visible = false
	Controller.io_manager.initialize_song()
	_edit_current_song()
	
	if not Engine.is_editor_hint():
		Controller.song_loaded.connect(_edit_current_song)
		Controller.song_saved.connect(_update_window_title)
		
		Controller.controls_locked.connect(_show_locked_indicator)
		Controller.controls_unlocked.connect(_hide_locked_indicator)


# Window decorations.

func _edit_current_song() -> void:
	if Engine.is_editor_hint():
		return
	
	_update_window_title()
	if Controller.current_song:
		Controller.current_song.song_changed.connect(_update_window_title)


func _update_window_title() -> void:
	if Engine.is_editor_hint():
		return
	
	if not Controller.current_song:
		get_window().title = _default_window_title
		return
	
	var song_name := "<New Song>" if Controller.current_song.filename.is_empty() else Controller.current_song.filename.get_file()
	var song_dirty := "* " if Controller.current_song.is_dirty() else ""
	
	get_window().title = "%s%s - %s" % [ song_dirty, song_name, _default_window_title ]


# Editor locking.

func _show_locked_indicator(message: String) -> void:
	_pattern_editor.visible = false
	_locked_indicator.message = message
	_locked_indicator.visible = true


func _hide_locked_indicator() -> void:
	_pattern_editor.visible = true
	_locked_indicator.visible = false

