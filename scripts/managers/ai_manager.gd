# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "https://api.moonshot.cn/v1"
@export var model: String = "kimi-k2.6"
@export var request_timeout: float = 30.0

var _http_request: HTTPRequest = null
var _is_requesting: bool = false

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
		_finish_requesting()
		return

	if _is_requesting:
		push_warning("[AIManager] 已有 AI 请求进行中，本次请求已忽略。")
		_finish_requesting()
		return

	var api_key := OS.get_environment("MOONSHOT_API_KEY")
	if api_key == "":
		push_warning("[AIManager] 未设置 MOONSHOT_API_KEY，无法请求 Kimi。")
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
		_finish_requesting()

## 处理 AI 返回的响应数据，将其中的命令列表交给 ScriptEngine 执行
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		return
	var commands = response["commands"]
	if not commands is Array:
		push_warning("[AIManager] 响应中的 'commands' 不是数组，已忽略。")
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
		return
	if response_code < 200 or response_code >= 300:
		push_error("[AIManager] Kimi 返回 HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return

	var raw_response = JSON.parse_string(body.get_string_from_utf8())
	if not raw_response is Dictionary:
		push_error("[AIManager] Kimi 响应不是 JSON 对象。")
		return

	var choices: Array = raw_response.get("choices", [])
	if choices.is_empty():
		push_error("[AIManager] Kimi 响应缺少 choices。")
		return

	var message: Dictionary = choices[0].get("message", {})
	var content: String = message.get("content", "")
	var ai_response = JSON.parse_string(content)
	if not ai_response is Dictionary:
		push_error("[AIManager] Kimi 返回内容不是有效 JSON。")
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
	return "你是视觉小说游戏的 AI 编剧接口。你必须只返回 JSON 对象，格式为 {\"commands\": [...]}，不要输出 Markdown 或解释。commands 里的每一项都必须包含 type 字段。"


func _build_user_prompt(input_str: String) -> String:
	return "玩家输入或流程事件: %s\n请生成一段可执行的视觉小说 commands JSON。" % input_str
