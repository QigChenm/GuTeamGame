# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "https://api.moonshot.cn/v1"
@export var model: String = "kimi-k2.6"
@export var request_timeout: float = 30.0

var _http_request: HTTPRequest = null
var _is_requesting: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)

	if has_node("/root/DialogueManager"):
		DialogueManager.ai_adapter = self


## DialogueManager 的 AI 适配器入口。callback 保留兼容签名，命令由 AIManager 直接分发。
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

	var api_key := OS.get_environment("MOONSHOT_API_KEY")
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
		"max_tokens": 1200,
		"response_format": {"type": "json_object"}
	}

	var error := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		push_error("[AIManager] 请求 Kimi 失败，错误码: %d" % error)
		_is_requesting = false
		_recover_with_dialogue("[AIManager] 无法发起 Kimi 请求。")
		_finish_requesting()

## 处理 AI 返回的响应数据，将其中的命令列表交给 ScriptEngine 执行
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		_recover_with_dialogue("[AIManager] 响应缺少 commands。")
		return
	var commands = response["commands"]
	if not commands is Array:
		push_warning("[AIManager] 响应中的 'commands' 不是数组，已忽略。")
		_recover_with_dialogue("[AIManager] commands 不是数组。")
		return
	if commands.is_empty():
		push_warning("[AIManager] 响应中的 'commands' 为空，已忽略。")
		_recover_with_dialogue("[AIManager] commands 为空。")
		return
	if not has_node("/root/ScriptEngine"):
		push_error("[AIManager] ScriptEngine 未找到，无法执行命令。")
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
		push_error("[AIManager] Kimi 响应不是 JSON 对象。")
		_recover_with_dialogue("[AIManager] Kimi 响应不是 JSON 对象。")
		return

	var choices: Array = raw_response.get("choices", [])
	if choices.is_empty():
		push_error("[AIManager] Kimi 响应缺少 choices。")
		_recover_with_dialogue("[AIManager] Kimi 响应缺少 choices。")
		return

	if not choices[0] is Dictionary:
		push_error("[AIManager] Kimi choices[0] 不是对象。")
		_recover_with_dialogue("[AIManager] Kimi choices 格式异常。")
		return

	var first_choice: Dictionary = choices[0]
	var message = first_choice.get("message", {})
	if not message is Dictionary:
		push_error("[AIManager] Kimi message 不是对象。")
		_recover_with_dialogue("[AIManager] Kimi message 格式异常。")
		return

	var message_dict: Dictionary = message
	var content: String = message_dict.get("content", "")
	var ai_response = JSON.parse_string(_normalize_json_content(content))
	if not ai_response is Dictionary:
		push_error("[AIManager] Kimi 返回内容不是有效 JSON。")
		_recover_with_dialogue("[AIManager] Kimi 返回内容不是有效 JSON。")
		return

	process_ai_response(ai_response)


func _get_base_url() -> String:
	var env_base_url := OS.get_environment("MOONSHOT_BASE_URL")
	if env_base_url != "":
		return env_base_url
	return base_url


func _get_model() -> String:
	var env_model := OS.get_environment("MOONSHOT_MODEL")
	if env_model != "":
		return env_model
	return model


func _finish_requesting() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.is_requesting = false


func _build_system_prompt() -> String:
	var lines := PackedStringArray([
		"你是视觉小说游戏的 AI 编剧接口。",
		"你必须只返回 JSON 对象，格式为 {\"commands\": [...]}，不要输出 Markdown、代码块或解释。",
		"commands 中每个对象都必须包含 type 字段。",
		"可用角色: sister。表情: default, happy, very_happy, sad, cry, angry。动作: breathe, shake, bounce, nod, step_back, shrug。",
		"可用背景: gulou_spring, gulou_winter。",
		"可用音频: spring_forest, love_piano。",
		"可用粒子: petal, snow。",
		"可用 CG: heroine_smile。",
		"可用 type: show_dialogue, show_choices, cg_play, cg_hide, change_background, set_characters, clear_stage, character_action, set_expression, play_audio, stop_audio, particle_play, particle_stop, set_ui_state, set_variable, add_affection, set_flag, unlock_cg, unlock_bgm, reset_unlocks, wait, jump, end_scene。",
		"show_dialogue 必须包含 character 和 text。旁白 character 使用空字符串。",
		"show_choices 必须包含 choices，choices 内每项包含 id 和 text。",
		"不要在 end_scene 后继续输出指令。"
	])
	return "\n".join(lines)


func _build_user_prompt(input_str: String) -> String:
	var event_description := input_str
	if input_str == "__start__":
		event_description = "新游戏开始"
	elif input_str == "__continue__":
		event_description = "玩家请求继续剧情"
	elif input_str.begins_with("__choice__:"):
		event_description = "玩家选择了选项 ID: " + input_str.trim_prefix("__choice__:")
	return "流程事件: %s\n请生成一段可执行的视觉小说 commands JSON。" % event_description


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
	if not has_node("/root/ScriptEngine"):
		return
	ScriptEngine.execute_commands([
		{
			"type": "show_dialogue",
			"character": "",
			"text": _FALLBACK_TEXT
		}
	])
