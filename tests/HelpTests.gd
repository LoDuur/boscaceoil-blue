extends Node

func _collect(node: Node, out: Array) -> void:
	if node is ShortcutLine:
		out.push_back(node)
	for c in node.get_children():
		_collect(c, out)

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var lines: Array = []
	_collect(main, lines)
	var bad := 0
	for line: ShortcutLine in lines:
		var key_text: String = line.get_node("KeyLabel").text
		if key_text == "[UNBOUND]":
			bad += 1
			print("UNBOUND: ", line.key_text)
	print("HELP LINES: %d, unbound %d" % [lines.size(), bad])
	for line: ShortcutLine in lines.slice(0, 12):
		print("  ", line.get_node("KeyLabel").text, " — ", line.description_text)
	get_tree().quit()
