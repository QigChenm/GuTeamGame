extends CanvasLayer

@export var custom_font: Font

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var history_text: RichTextLabel = $ScrollContainer/RichTextLabel

const PORTRAIT_WIDTH = 64
const PORTRAIT_HEIGHT = 64

func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	if history_text:
		history_text.bbcode_enabled = true
		history_text.scroll_active = false
		history_text.fit_content = true
		if custom_font:
			history_text.add_theme_font_override("normal_font", custom_font)
		history_text.add_theme_font_size_override("normal_font_size", 24)
		history_text.add_theme_constant_override("line_separation", 8)

func refresh_history() -> void:
	if not history_text:
		return

	history_text.clear()

	var entries = GameManager.dialogue_history
	if entries.is_empty():
		history_text.append_text("[center][color=#888888]暂无对话记录[/color][/center]")
		return

	for i in range(entries.size()):
		var entry = entries[i]
		var type = entry.get("type", "dialogue")
		var character: String = entry.get("character", "")
		var text: String = entry.get("text", "")
		var char_id: String = entry.get("id", "")  # 优先使用ID

		_append_entry(type, character, text, char_id)

		if i < entries.size() - 1:
			history_text.append_text("[color=#444444]──────────────────────────────[/color]\n")

	await get_tree().process_frame
	var scroll = scroll_container.get_v_scroll_bar()
	if scroll:
		scroll.value = scroll.max_value

func _append_entry(type: String, character: String, text: String, char_id: String = "") -> void:
	if type == "choice":
		history_text.append_text("[color=#34859B][b]→ 玩家:[/b] %s[/color]\n" % text)
		return

	if type == "long_dialogue":
		history_text.append_text("[color=#AAAAAA][i]%s[/i][/color]\n" % text)
		return

	# 普通对话：获取角色数据
	var display_name = ""
	var portrait_path = ""

	var char_data: CharacterData = null
	if char_id != "" and GameManager.character_database.has(char_id):
		char_data = GameManager.character_database[char_id]
	else:
		# 回退：通过显示名查找
		var found_id = _find_character_id(character)
		if found_id != "" and GameManager.character_database.has(found_id):
			char_data = GameManager.character_database[found_id]

	if char_data:
		display_name = char_data.display_name if char_data.display_name != "" else character
		if char_data.portrait:
			portrait_path = char_data.portrait.resource_path

	if display_name != "":
		if portrait_path != "":
			history_text.append_text("[img=%dx%d]%s[/img] " % [PORTRAIT_WIDTH, PORTRAIT_HEIGHT, portrait_path])
		history_text.append_text("[color=#FFD700][b]%s:[/b][/color] " % display_name)
	history_text.append_text("[color=#E57373]%s[/color]\n" % text)

func _find_character_id(display_name: String) -> String:
	for char_id in GameManager.character_database:
		if GameManager.character_database[char_id].display_name == display_name:
			return char_id
	return ""
