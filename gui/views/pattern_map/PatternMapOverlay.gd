###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

@tool
extends Control

var pattern_height: float = 0
var pattern_width: float = 0
var playback_cursor_position: float = -1
var pattern_cursor_position: Vector2 = Vector2i(-1, -1)

var selected_positions: PackedVector2Array = PackedVector2Array()
var dimmed_positions: PackedVector2Array = PackedVector2Array()
var ghost_items: Array[PatternMap.GhostItem] = []
var marquee_rect: Rect2 = Rect2(-1, -1, 0, 0)
## Whether the arrangement receives keyboard editing actions.
var focused: bool = false

const GHOST_OPACITY := 0.45
const DIMMED_COVER_COLOR := Color(0, 0, 0, 0.55)
const SELECTED_FILL_COLOR := Color(1, 1, 1, 0.18)


func _draw() -> void:
	var border_width := get_theme_constant("border_width", "PatternMap")
	var half_border_width := float(border_width) / 2.0
	
	var item_size := Vector2(pattern_width, pattern_height) - Vector2(border_width, border_width)
	var selection_outline_color := get_theme_color("selection_outline_color", "PatternMap")
	var selection_outline_width := get_theme_constant("selection_outline_width", "PatternMap")
	
	# Draw drag sources faded, and the selection.
	
	if pattern_width > 0:
		for cell_position in dimmed_positions:
			draw_rect(Rect2(cell_position + Vector2(half_border_width, half_border_width), item_size), DIMMED_COVER_COLOR)
		
		for cell_position in selected_positions:
			var item_rect := Rect2(cell_position + Vector2(half_border_width, half_border_width), item_size)
			draw_rect(item_rect, SELECTED_FILL_COLOR)
			draw_rect(item_rect.grow(-selection_outline_width / 2.0), selection_outline_color, false, selection_outline_width)
	
	# Draw the pending placement (paste, duplicate, or drag target).
	
	if pattern_width > 0 && not ghost_items.is_empty():
		var font := get_theme_default_font()
		var font_size := get_theme_font_size("pattern_font_size", "PatternMap")
		var font_color := get_theme_color("font_color", "Label")
		var label_offset := Vector2(get_theme_constant("pattern_label_offset_x", "PatternMap"), get_theme_constant("pattern_label_offset_y", "PatternMap"))
		var conflict_color := get_theme_color("ghost_conflict_color", "PatternMap")
		
		for ghost_item in ghost_items:
			var item_rect := Rect2(ghost_item.position + Vector2(half_border_width, half_border_width), item_size)
			var fill_color := conflict_color if ghost_item.conflict else Color(ghost_item.color, GHOST_OPACITY)
			draw_rect(item_rect, fill_color)
			draw_rect(item_rect.grow(-selection_outline_width / 2.0), Color(selection_outline_color, GHOST_OPACITY), false, selection_outline_width)
			draw_string(font, ghost_item.position + label_offset + Vector2(0, pattern_height), ghost_item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)
	
	# Draw the playback cursor.
	
	if playback_cursor_position >= 0:
		var playback_cursor_width := get_theme_constant("playback_cursor_width", "NoteMap")

		var cursor_position := Vector2(playback_cursor_position, 0)
		var cursor_size := Vector2(playback_cursor_width, size.y)
		var cursor_color := get_theme_color("playback_cursor_color", "NoteMap")
		
		var half_cursor_width := float(playback_cursor_width) / 2.0
		var cursor_bevel_position := Vector2(playback_cursor_position + half_cursor_width, 0)
		var cursor_bevel_size := Vector2(half_cursor_width, size.y)
		var cursor_bevel_color := get_theme_color("playback_cursor_bevel_color", "NoteMap")
		
		draw_rect(Rect2(cursor_position, cursor_size), cursor_color)
		draw_rect(Rect2(cursor_bevel_position, cursor_bevel_size), cursor_bevel_color)
	
	# Draw the pattern cursor.
	
	if pattern_width > 0 && pattern_cursor_position.x >= 0 && pattern_cursor_position.y >= 0:
		var pattern_position := pattern_cursor_position + Vector2(half_border_width, half_border_width)
		var pattern_size := Vector2(pattern_width, pattern_height) - Vector2(border_width, border_width)
		var pattern_cursor_color := get_theme_color("note_cursor_color", "NoteMap")
		var pattern_cursor_width := get_theme_constant("note_cursor_width", "NoteMap")

		draw_rect(Rect2(pattern_position, pattern_size), pattern_cursor_color, false, pattern_cursor_width)
	
	# Draw the marquee.
	
	if marquee_rect.position.x >= 0:
		var marquee_color := get_theme_color("note_cursor_color", "NoteMap")
		var marquee_width := get_theme_constant("note_cursor_width", "NoteMap")
		draw_rect(marquee_rect, marquee_color, false, marquee_width)
	
	# Mark the editor that receives keyboard editing actions.
	
	if focused:
		var focus_width := get_theme_constant("focus_border_width", "PatternMap")
		var focus_rect := Rect2(Vector2.ZERO, size).grow(-focus_width / 2.0)
		draw_rect(focus_rect, get_theme_color("focus_border_color", "PatternMap"), false, focus_width)
