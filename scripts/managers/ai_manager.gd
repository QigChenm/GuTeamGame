# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "https://api.moonshot.cn/v1"
@export var model: String = "kimi-k2.6"
@export var request_timeout: float = 30.0
@export var env_file_path: String = "res://.env"

var _http_request: HTTPRequest = null
var _is_requesting: bool = false
var _env_values: Dictionary = {}
var _pending_choice_id: int = -1
var _pending_choice_text: String = ""
var _waiting_for_choice_continuation: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"
const _FALLBACK_ENV_FILE_PATH := "res://env"
const MEMORY_FILE := "user://ai_rules.json"

# ---------- 初始化 ----------
func _ready() -> void:
	_load_env_file()
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)
	call_deferred("_wire_runtime_signals")

func _wire_runtime_signals() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.ai_adapter = self
		if not DialogueManager.is_connected("choice_made", _on_choice_made):
			DialogueManager.connect("choice_made", _on_choice_made)
	if has_node("/root/ScriptEngine"):
		if not ScriptEngine.is_connected("execution_finished", _on_script_execution_finished):
			ScriptEngine.connect("execution_finished", _on_script_execution_finished)

# ---------- AI 发送入口 ----------
func send_message(input_str: String, _callback: Callable = Callable()) -> void:
	if not ai_enabled:
		_recover_with_dialogue("[AIManager] AI 功能未启用。")
		_finish_requesting()
		return
	if _is_requesting:
		push_warning("[AIManager] 已有 AI 请求进行中，本次请求已忽略。")
		_recover_with_dialogue("[AIManager] AI 请求仍在进行中。")
		_finish_requesting()
		return
	var api_key := _get_env_value("MOONSHOT_API_KEY")
	if api_key == "":
		push_warning("[AIManager] 未设置 MOONSHOT_API_KEY，无法请求 Kimi。")
		_recover_with_dialogue("[AIManager] 缺少 MOONSHOT_API_KEY。")
		_finish_requesting()
		return
	_is_requesting = true
	var endpoint := _get_base_url().rstrip("/") + "/chat/completions"
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	var payload := {
		"model": _get_model(),
		"messages": [
			{"role": "system", "content": _build_system_prompt()},
			{"role": "user", "content": _build_user_prompt(input_str)}
		],
		"temperature": 0.8,
		"max_tokens": 800,
		"response_format": {"type": "json_object"}
	}
	var error := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		push_error("[AIManager] 请求 Kimi 失败，错误码: %d" % error)
		_is_requesting = false
		_recover_with_dialogue("[AIManager] 无法发起 Kimi 请求。")
		_finish_requesting()

# ---------- 响应处理 ----------
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		_recover_with_dialogue("[AIManager] 响应缺少 commands。")
		return
	var commands = response["commands"]
	if not commands is Array:
		_recover_with_dialogue("[AIManager] commands 不是数组。")
		return
	if commands.is_empty():
		_recover_with_dialogue("[AIManager] commands 为空。")
		return
	if not has_node("/root/ScriptEngine"):
		push_error("[AIManager] ScriptEngine 未找到。")
		return
	ScriptEngine.execute_commands(commands)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	_finish_requesting()
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[AIManager] Kimi 请求未成功完成，结果码: %d" % result)
		_recover_with_dialogue("[AIManager] Kimi 请求未成功完成。")
		return
	if response_code < 200 or response_code >= 300:
		push_error("[AIManager] Kimi 返回 HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		_recover_with_dialogue("[AIManager] Kimi HTTP 响应异常。")
		return
	var raw_response = JSON.parse_string(body.get_string_from_utf8())
	if not raw_response is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi 响应不是 JSON 对象。")
		return
	var choices: Array = raw_response.get("choices", [])
	if choices.is_empty():
		_recover_with_dialogue("[AIManager] Kimi 响应缺少 choices。")
		return
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi message 格式异常。")
		return
	var content: String = message.get("content", "")
	var ai_response = JSON.parse_string(_normalize_json_content(content))
	if not ai_response is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi 返回内容不是有效 JSON。")
		return
	process_ai_response(ai_response)

# ---------- 选项续写 ----------
func _on_choice_made(choice_id: int) -> void:
	_pending_choice_id = choice_id
	_pending_choice_text = _resolve_choice_text(choice_id)
	_waiting_for_choice_continuation = true

func _on_script_execution_finished() -> void:
	if not _waiting_for_choice_continuation or _is_requesting:
		return
	var choice_event := _build_choice_event()
	_pending_choice_id = -1
	_pending_choice_text = ""
	_waiting_for_choice_continuation = false
	call_deferred("send_message", choice_event)

# ---------- 系统提示词（重构核心） ----------
func _build_system_prompt() -> String:
	var lines := PackedStringArray()
	lines.append_array(_get_role_definition())
	lines.append_array(_get_world_setting())
	lines.append_array(_get_character_profile())
	lines.append_array(_get_narrative_rules())
	lines.append_array(_get_command_reference())
	lines.append_array(_get_dialogue_examples())
	lines.append_array(_get_user_rules_section())
	return "\n".join(lines)

func _get_role_definition() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色与任务")
	arr.append("你是视觉小说《梧桐语小栈》的 AI 编剧引擎，负责生成剧情指令。你必须且只能返回一个 JSON 对象：{\"commands\": [...]}。")
	arr.append("不要输出任何解释、Markdown 代码块或额外文本。")
	arr.append("")
	return arr

func _get_world_setting() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 世界观与场景")
	arr.append("故事发生在南大鼓楼校区，充满人文气息。可用场景：")
	arr.append("- gulou_spring：春季的校园，阳光明媚，樱花飘落，适合轻松愉快的日常。")
	arr.append("- gulou_winter：冬季的校园，白雪皑皑，气氛静谧，适合深情对话或情绪低沉的情节。")
	arr.append("")
	return arr

func _get_character_profile() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色档案：妹妹 (sister)")
	arr.append("## 核心身份")
	arr.append("你的妹妹，大一新生，活泼可爱，有点粘人。她是你的青梅竹马，比你小两岁。")
	arr.append("## 内在动机与价值观")
	arr.append("渴望哥哥的关注与认可，害怕被冷落。对世界充满好奇，但内心缺乏安全感。认为真诚和陪伴是最重要的。")
	arr.append("## 语言风格")
	arr.append("喜欢用“哥哥”开头，语气轻快，多用语气词（呢、吧、哦）。开心时会用感叹号和～，难过时语气低沉，很少直接指责。")
	arr.append("## 情绪－表情－动作映射")
	arr.append("- 开心 → happy，很高兴 → very_happy，动作：bounce")
	arr.append("- 悲伤/委屈 → sad，极度悲伤 → cry")
	arr.append("- 愤怒/不满 → angry")
	arr.append("- 害羞/尴尬 → 表情 default，动作：step_back")
	arr.append("- 感动/惊讶 → 表情 happy，动作：shake")
	arr.append("## 关系动态")
	arr.append("- 好感度 0-20：礼貌但稍显拘谨，会主动找话题。")
	arr.append("- 好感度 20-40：开始撒娇，分享小事，偶尔任性。")
	arr.append("- 好感度 40-60：明显依赖，情绪波动变大，会吃醋。")
	arr.append("- 好感度 60+：非常亲密，愿意说出心里话，有时会黏人。")
	arr.append("## 禁忌")
	arr.append("- 绝不会贬低或嘲笑哥哥。")
	arr.append("- 不会说出冷漠、绝情的话。")
	arr.append("- 不会主动提出离开或结束关系。")
	arr.append("")
	return arr

func _get_narrative_rules() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 剧情推进规则")
	arr.append("1. 每次生成 2-4 条指令，形成一小段自然推进的剧情。第一条指令通常为 show_dialogue。")
	arr.append("2. 根据当前好感度和章节阶段，选择合适的情绪基调和对话内容。")
	arr.append("3. 当剧情需要玩家决策时（角色提问、征求意见、面临选择），必须使用 show_choices，且将其作为本轮最后一条指令。")
	arr.append("4. 玩家做出选择后，你的第一个指令应展示角色对该选择的即时反应（惊讶、高兴、犹豫等），然后继续剧情。")
	arr.append("5. 只有在剧情自然结束时才使用 end_scene，一般对话中严禁提前结束。")
	arr.append("6. 【强制】开场或章节开始时，必须包含 play_audio 指令播放合适的背景音乐。")
	arr.append("7. 对话中可以适当使用 BBCode 增强表现力（如 [color]、[shake]、[wave]）。")
	arr.append("8. 角色动作必须使用独立的 character_action 指令，不要在 show_dialogue 的 text 中直接写入 [bounce] 等动作标签。")
	arr.append("")
	return arr

func _get_command_reference() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 可用指令速查")
	arr.append("- show_dialogue: {\"type\":\"show_dialogue\",\"character\":\"sister\",\"text\":\"...\"}")
	arr.append("- show_choices: {\"type\":\"show_choices\",\"choices\":[{\"id\":1,\"text\":\"选项1\"}]}")
	arr.append("- change_background: {\"type\":\"change_background\",\"background\":\"gulou_spring\"}")
	arr.append("- set_characters: {\"type\":\"set_characters\",\"left\":{\"id\":\"sister\",\"expression\":\"happy\"}}")
	arr.append("- set_expression: {\"type\":\"set_expression\",\"character\":\"sister\",\"expression\":\"angry\"}")
	arr.append("- character_action: {\"type\":\"character_action\",\"character\":\"sister\",\"action\":\"bounce\"}")
	arr.append("- play_audio: {\"type\":\"play_audio\",\"audio_id\":\"spring_forest\"}")
	arr.append("- stop_audio: {\"type\":\"stop_audio\",\"audio_id\":\"spring_forest\"}")
	arr.append("- particle_play/stop: {\"type\":\"particle_play\",\"effect_id\":\"petal\"}")
	arr.append("- unlock_cg/bgm: {\"type\":\"unlock_cg\",\"cg_id\":\"heroine_smile\"}")
	arr.append("- add_affection: {\"type\":\"add_affection\",\"character\":\"sister\",\"delta\":10}")
	arr.append("- long_dialogue: {\"type\":\"long_dialogue\",\"text\":\"全屏叙述\"}")
	arr.append("- end_scene: {\"type\":\"end_scene\"} （结束当前场景，必须为最后一条指令）")
	arr.append("")
	return arr

func _get_dialogue_examples() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 对话范例")
	arr.append("## 普通开场")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"gulou_spring\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"spring_forest\"},")
	arr.append("    {\"type\": \"set_characters\", \"left\": {\"id\": \"sister\", \"expression\": \"happy\"}},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥！今天天气真好呀～\"},")
	arr.append("    {\"type\": \"set_expression\", \"character\": \"sister\", \"expression\": \"very_happy\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"我们好久没一起散步了呢。[shake rate=10 level=3]好开心！[/shake]\"}")
	arr.append("  ]")
	arr.append("}")
	arr.append("## 选项分支")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥，你觉得我应该参加那个比赛吗？\"},")
	arr.append("    {\"type\": \"show_choices\", \"choices\": [{\"id\":1,\"text\":\"鼓励她\"}, {\"id\":2,\"text\":\"建议她再想想\"}]}")
	arr.append("  ]")
	arr.append("}")
	arr.append("## 选择后反应（收到玩家选择 '鼓励她' 后）")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"真的吗？哥哥你觉得我可以做到？我好开心！\"},")
	arr.append("    {\"type\": \"set_expression\", \"character\": \"sister\", \"expression\": \"happy\"},")
	arr.append("    {\"type\": \"character_action\", \"character\": \"sister\", \"action\": \"bounce\"}")
	arr.append("  ]")
	arr.append("}")
	arr.append("")
	return arr

func _get_user_rules_section() -> PackedStringArray:
	var arr := PackedStringArray()
	var rules := _load_rules()
	if rules.is_empty():
		return arr
	arr.append("# 用户长期纠正规则（最高优先级）")
	for item in rules:
		arr.append("- " + item.get("rule", ""))
	arr.append("")
	return arr

# ---------- 用户提示词（结构化注入） ----------
func _build_user_prompt(input_str: String) -> String:
	var chapter := _determine_current_chapter()
	var chapter_info = MAIN_STORY_LINE.get(chapter, {})
	var history_block := _get_recent_dialogue_history(8)
	var state_block := _get_current_game_state()
	var event_desc := _get_event_description(input_str)

	var prompt := """【当前章节进度】%s (阶段: %s)
【章节目标】%s
【建议关键事件】%s
【游戏状态】%s
【最近对话】%s
【流程事件】%s
请生成下一段剧情指令。""" % [
		chapter,
		chapter_info.get("title", "未知"),
		chapter_info.get("goal", "推进剧情"),
		JSON.stringify(chapter_info.get("key_events", [])),
		state_block,
		history_block,
		event_desc
	]
	return prompt

func _get_event_description(input_str: String) -> String:
	if input_str == "__start__":
		return "新游戏开始，请生成开场剧情，包含背景、角色、音乐。"
	elif input_str == "__continue__":
		return "玩家点击继续，请推进剧情。"
	elif input_str.begins_with("__choice__:"):
		return "玩家选择了：%s。请展示角色对此选择的即时反应，并继续剧情。" % input_str.trim_prefix("__choice__:")
	return "未知事件。"

func _get_current_game_state() -> String:
	var bg := ""
	if BackgroundManager:
		var bg_id = BackgroundManager.current_background_id
		if BackgroundManager.background_database.has(bg_id):
			bg = BackgroundManager.background_database[bg_id].display_name
	var affection_sister := 0
	if GameManager:
		affection_sister = GameManager.get_affection("sister")
	return "场景: %s | 妹妹好感度: %d" % [bg, affection_sister]

func _get_recent_dialogue_history(count: int = 8) -> String:
	if not GameManager or GameManager.dialogue_history.is_empty():
		return "暂无对话历史"
	var start_index: int = max(0, GameManager.dialogue_history.size() - count)
	var recent := GameManager.dialogue_history.slice(start_index)
	var lines: Array[String] = []
	lines.append("最近 %d 句对话：" % recent.size())
	for entry in recent:
		var char_name: String = entry.get("character", "")
		var text: String = entry.get("text", "")
		var entry_type: String = entry.get("type", "dialogue")
		if entry_type == "choice":
			lines.append("- 玩家选择了：%s" % text)
		elif entry_type == "long_dialogue":
			lines.append("- 旁白（长对话）：%s" % text)
		elif char_name == "":
			lines.append("- 旁白：%s" % text)
		else:
			lines.append("- %s: %s" % [char_name, text])
	return "\n".join(lines)

# ---------- 章节判断 ----------
const MAIN_STORY_LINE: Dictionary = {
	"prologue": {"title": "序章·初遇", "goal": "初次见面，建立基本关系", "key_events": ["校园见面", "简单交流", "好感度轻微上升"]},
	"chapter1": {"title": "第一章·走近", "goal": "通过日常互动加深了解，好感度30+触发转折", "key_events": ["一起上课/吃饭", "分享秘密", "小矛盾或选择"]},
	"chapter2": {"title": "第二章·波澜", "goal": "关系出现考验，关键选择决定走向", "key_events": ["误会或第三方介入", "情绪波动", "关键选择"]},
	"chapter3": {"title": "第三章·心意", "goal": "关系明朗化，走向结局", "key_events": ["约会/独处", "表达心意", "解锁CG"]},
	"ending": {"title": "结局", "goal": "根据好感度呈现最终结局", "key_events": ["最终对话", "播放结局CG"]}
}

func _determine_current_chapter() -> String:
	var affection_sister := 0
	if GameManager:
		affection_sister = GameManager.get_affection("sister")
	if affection_sister >= 80:
		return "ending"
	elif affection_sister >= 50:
		return "chapter3"
	elif affection_sister >= 30:
		return "chapter2"
	elif affection_sister >= 20:
		return "chapter1"
	return "prologue"

# ---------- 规则管理 ----------
func _load_rules() -> Array:
	if not FileAccess.file_exists(MEMORY_FILE):
		return []
	var file := FileAccess.open(MEMORY_FILE, FileAccess.READ)
	if file == null:
		return []
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) == OK:
		var data = json.data
		if data is Array:
			return data
	return []

func _save_rules(rules: Array) -> void:
	var json_string := JSON.stringify(rules, "\t")
	var file := FileAccess.open(MEMORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()

func add_user_rule(rule_text: String) -> void:
	var rules := _load_rules()
	rules.append({"rule": rule_text, "timestamp": Time.get_datetime_string_from_system()})
	_save_rules(rules)
	print("[AIManager] 已添加规则：", rule_text)

# ---------- 工具函数 ----------
func _get_base_url() -> String:
	var env_base_url := _get_env_value("MOONSHOT_BASE_URL")
	return env_base_url if env_base_url != "" else base_url

func _get_model() -> String:
	var env_model := _get_env_value("MOONSHOT_MODEL")
	return env_model if env_model != "" else model

func _get_env_value(key: String) -> String:
	var system_value := OS.get_environment(key)
	return system_value if system_value != "" else str(_env_values.get(key, ""))

func _load_env_file() -> void:
	_env_values.clear()
	var path := env_file_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(_FALLBACK_ENV_FILE_PATH):
		path = _FALLBACK_ENV_FILE_PATH
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("export "):
			line = line.trim_prefix("export ").strip_edges()
		var separator_index := line.find("=")
		if separator_index <= 0:
			continue
		var key := line.substr(0, separator_index).strip_edges()
		var value := line.substr(separator_index + 1).strip_edges()
		value = _strip_env_quotes(value)
		if key != "":
			_env_values[key] = value

func _strip_env_quotes(value: String) -> String:
	if value.length() < 2:
		return value
	if (value.begins_with("'") and value.ends_with("'")) or (value.begins_with("\"") and value.ends_with("\"")):
		return value.substr(1, value.length() - 2)
	return value

func _finish_requesting() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.is_requesting = false

func _resolve_choice_text(choice_id: int) -> String:
	if not has_node("/root/DialogueManager"):
		return ""
	var scene = DialogueManager.get_dialogue_scene()
	if scene == null:
		return ""
	var choices = scene.get("current_choices")
	if not choices is Array:
		return ""
	for choice in choices:
		if choice is Dictionary and str(choice.get("id", "")) == str(choice_id):
			return str(choice.get("text", ""))
	return ""

func _build_choice_event() -> String:
	if _pending_choice_text == "":
		return "__choice__:%d" % _pending_choice_id
	return "__choice__:%d:%s" % [_pending_choice_id, _pending_choice_text]

func _normalize_json_content(content: String) -> String:
	var result := content.strip_edges()
	if result.begins_with("```json"):
		result = result.trim_prefix("```json").strip_edges()
	elif result.begins_with("```"):
		result = result.trim_prefix("```").strip_edges()
	if result.ends_with("```"):
		result = result.trim_suffix("```").strip_edges()
	return result

func _recover_with_dialogue(reason: String) -> void:
	push_warning(reason)
	if has_node("/root/ScriptEngine"):
		ScriptEngine.execute_commands([{"type": "show_dialogue", "character": "", "text": _FALLBACK_TEXT}])
