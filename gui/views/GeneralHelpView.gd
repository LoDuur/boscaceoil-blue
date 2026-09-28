###################################################
# Part of Bosca Ceoil Blue                        #
# Copyright (c) 2025 Yuri Sizov and contributors  #
# Provided under MIT                              #
###################################################

extends MarginContainer

const SHORTCUT_LINE_SCENE := preload("res://gui/views/help_view/ShortcutLine.tscn")

@onready var _navigate_back_button: BackButton = %NavigateBack
@onready var _columns: Array[VBoxContainer] = [ %LeftList, %RightList ]


func _ready() -> void:
	_navigate_back_button.pressed.connect(Controller.navigate_to.bind(Menu.NavigationTarget.FILE))
	_build_shortcut_list()


func _build_shortcut_list() -> void:
	for section in ShortcutTable.get_sections():
		var column := _columns[clampi(section.column, 0, _columns.size() - 1)]
		
		var section_box := VBoxContainer.new()
		section_box.theme_type_variation = &"CreditsSectionBox"
		column.add_child(section_box)
		
		var title_label := Label.new()
		title_label.theme_type_variation = &"CreditsLabelHeaderPanel"
		title_label.text = section.title
		section_box.add_child(title_label)
		
		var entry_list := VBoxContainer.new()
		entry_list.theme_type_variation = &"CreditsBox"
		section_box.add_child(entry_list)
		
		for entry in section.entries:
			var line: ShortcutLine = SHORTCUT_LINE_SCENE.instantiate()
			line.key_is_action = entry.is_action
			line.key_text = entry.key
			line.description_text = entry.description
			line.hide_on_web = entry.hide_on_web
			entry_list.add_child(line)
