###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

## A group of items waiting to be placed on a grid: the result of a paste, a
## duplicate, or a drag in progress. Items are relative to the anchor cell.
class_name GhostPlacement extends RefCounted

enum Source {
	PASTE,
	DUPLICATE,
	DRAG_MOVE,
	DRAG_COPY,
}

## Per-item fit status, see is_valid_at().
const FIT_NONE := 0
const FIT_FREE := 1
const FIT_CONFLICT := 2

## Items as Vector3i(dx, dy, payload), relative to the anchor.
var items: Array[Vector3i] = []
## Absolute cell of the group's anchor (its minimum X and Y).
var anchor_cell: Vector2i = Vector2i.ZERO
var source: Source = Source.PASTE
## Offset from the anchor to the item under the pointer when a drag started.
## Keeps the grabbed item under the pointer; zero for paste and duplicate.
var grab_offset: Vector2i = Vector2i.ZERO
## Valid cells of the target grid.
var bounds: Rect2i = Rect2i()
## Keys of the source items for drags, as absolute cells.
var source_cells: Array[Vector2i] = []


func _init(items_: Array[Vector3i], source_: Source, bounds_: Rect2i) -> void:
	items = items_
	source = source_
	bounds = bounds_


func is_drag() -> bool:
	return source == Source.DRAG_MOVE || source == Source.DRAG_COPY


## Size of the group in cells, from the anchor to the furthest item.
func get_extent() -> Vector2i:
	var extent := Vector2i.ZERO
	for item in items:
		extent.x = maxi(extent.x, item.x + 1)
		extent.y = maxi(extent.y, item.y + 1)
	return extent


## Clamps an anchor so the whole group stays in bounds. When the group is
## bigger than the grid on some axis, it is pinned to the grid's start on that
## axis, and overflowing items are dropped on commit.
func clamp_anchor(cell: Vector2i) -> Vector2i:
	var extent := get_extent()
	var clamped := cell
	clamped.x = clampi(clamped.x, bounds.position.x, maxi(bounds.position.x, bounds.end.x - extent.x))
	clamped.y = clampi(clamped.y, bounds.position.y, maxi(bounds.position.y, bounds.end.y - extent.y))
	return clamped


## Moves the group so the grabbed item sits at the given cell. Returns true if
## the anchor changed.
func follow_cell(cell: Vector2i) -> bool:
	var next_anchor := clamp_anchor(cell - grab_offset)
	if next_anchor == anchor_cell:
		return false
	
	anchor_cell = next_anchor
	return true


func nudge(delta: Vector2i) -> bool:
	var next_anchor := clamp_anchor(anchor_cell + delta)
	if next_anchor == anchor_cell:
		return false
	
	anchor_cell = next_anchor
	return true


func get_item_cell(item: Vector3i, at_anchor: Vector2i) -> Vector2i:
	return at_anchor + Vector2i(item.x, item.y)


## Per-item fit mask for the group placed at the given anchor: FIT_NONE when
## the item falls outside the grid, FIT_CONFLICT when it would overwrite an
## occupied cell (as reported by is_occupied), FIT_FREE otherwise.
func is_valid_at(cell: Vector2i, is_occupied: Callable) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(items.size())
	
	for i in items.size():
		var item_cell := get_item_cell(items[i], cell)
		if not bounds.has_point(item_cell):
			mask[i] = FIT_NONE
		elif is_occupied.call(item_cell):
			mask[i] = FIT_CONFLICT
		else:
			mask[i] = FIT_FREE
	
	return mask
