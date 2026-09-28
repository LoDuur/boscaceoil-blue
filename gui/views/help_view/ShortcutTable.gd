###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## Single source of the shortcut reference shown on the Help page.
## Keyboard entries reference action names from project.godot, so the page
## always renders the real bindings. Mouse gestures are literal text.
class_name ShortcutTable extends RefCounted


static func get_sections() -> Array[Section]:
	var sections: Array[Section] = []
	var section: Section = null
	
	section = Section.new("GENERAL", 0)
	section.action("bosca_new", "Create new song")
	section.action("bosca_open", "Load existing song")
	section.action("bosca_save", "Save current song")
	section.action("bosca_save_as", "Save as a copy")
	section.action("bosca_export", "Export song as WAV")
	section.action("bosca_undo", "Undo last action")
	section.action("bosca_redo", "Redo last action")
	section.action("bosca_toggle_fullscreen", "Toggle fullscreen")
	sections.push_back(section)
	
	section = Section.new("PLAYBACK", 0)
	section.action("bosca_playstop", "Play/Stop")
	section.action("bosca_pause", "Pause/Resume")
	sections.push_back(section)
	
	section = Section.new("PATTERN EDITOR", 0)
	section.text("MOUSE WHEEL", "Scroll pattern view")
	section.text("LEFT CLICK", "Draw a note / select a note")
	section.text("DRAG NOTE", "Move selected notes")
	section.text("CTRL + DRAG NOTE", "Copy selected notes")
	section.text("SHIFT + LEFT CLICK", "Add/remove a note from selection")
	section.text("SHIFT + DRAG", "Select notes in an area")
	section.text("ALT + LEFT CLICK", "Draw on top of another note")
	section.text("RIGHT CLICK", "Erase the note at the cursor")
	section.text("CTRL + LEFT CLICK", "Set cursor to the note's length")
	section.text("CTRL + MOUSE WHEEL", "Change cursor size")
	section.action("bosca_notemap_cursor_bigger", "Make cursor bigger")
	section.action("bosca_notemap_cursor_smaller", "Make cursor smaller")
	sections.push_back(section)
	
	section = Section.new("EDITING (CLICK AN EDITOR FIRST)", 0)
	section.action("bosca_select_all", "Select everything")
	section.action("bosca_copy", "Copy selection")
	section.action("bosca_cut", "Cut selection")
	section.action("bosca_paste", "Paste (click to place)")
	section.action("bosca_duplicate", "Duplicate selection (click to place)")
	section.action("bosca_delete", "Delete selection")
	section.action("bosca_confirm", "Place pasted items")
	section.action("bosca_cancel", "Cancel placing / clear selection")
	section.text("ARROWS", "Move selection (or scroll)")
	section.text("SHIFT + ARROWS", "Move selection by a bar/octave")
	sections.push_back(section)
	
	section = Section.new("NOTES", 0)
	section.action("bosca_notemap_resize_shorter", "Shorten selected notes")
	section.action("bosca_notemap_resize_longer", "Lengthen selected notes")
	section.action("bosca_notemap_shift_up", "Shift all notes up")
	section.action("bosca_notemap_shift_down", "Shift all notes down")
	section.action("bosca_notemap_shift_octave_up", "Shift all notes up an octave")
	section.action("bosca_notemap_shift_octave_down", "Shift all notes down an octave")
	section.action("bosca_notemap_shift_left", "Shift all notes earlier (wraps)")
	section.action("bosca_notemap_shift_right", "Shift all notes later (wraps)")
	sections.push_back(section)
	
	section = Section.new("ARRANGEMENT", 1)
	section.text("MOUSE WHEEL", "Scroll arrangement grid")
	section.action("bosca_patternmap_left", "Scroll it left")
	section.action("bosca_patternmap_right", "Scroll it right")
	section.text("SHIFT + MOUSE WHEEL", "Change grid scale")
	section.text("LEFT CLICK", "Select a pattern and edit it")
	section.text("DRAG PATTERN", "Move selected patterns")
	section.text("CTRL + DRAG PATTERN", "Copy selected patterns")
	section.text("ALT + DRAG/CLICK", "Create a pattern variant")
	section.text("SHIFT + LEFT CLICK", "Add/remove from selection")
	section.text("SHIFT + DRAG", "Select patterns in an area")
	section.text("RIGHT CLICK", "Remove the pattern")
	section.action("bosca_patternmap_make_variant", "Variant of the pattern under cursor")
	section.action("bosca_duplicate", "Duplicate (or the pattern under cursor)")
	sections.push_back(section)
	
	section = Section.new("TIMELINE", 1)
	section.text("LEFT CLICK", "Select and play the bar")
	section.text("DOUBLE CLICK", "Select and play to the end")
	section.text("MIDDLE CLICK", "Insert an empty bar")
	section.text("SHIFT + LEFT CLICK", "Insert an empty bar")
	section.text("RIGHT CLICK", "Remove the bar")
	section.action("ui_copy", "Copy selected bars")
	section.action("ui_paste", "Paste copied bars")
	sections.push_back(section)
	
	return sections


class Section:
	var title: String = ""
	## Page column the section is placed in.
	var column: int = 0
	var entries: Array[Entry] = []
	
	
	func _init(title_: String, column_: int) -> void:
		title = title_
		column = column_
	
	
	func action(action_name: String, description: String, hide_on_web: bool = false) -> void:
		entries.push_back(Entry.new(action_name, true, description, hide_on_web))
	
	
	func text(key_text: String, description: String) -> void:
		entries.push_back(Entry.new(key_text, false, description, false))


class Entry:
	var key: String = ""
	var is_action: bool = true
	var description: String = ""
	var hide_on_web: bool = false
	
	
	func _init(key_: String, is_action_: bool, description_: String, hide_on_web_: bool) -> void:
		key = key_
		is_action = is_action_
		description = description_
		hide_on_web = hide_on_web_
