# script_engine.gd
extends Node

# ================= 信号 =================
signal execution_finished

# ================= 常量 =================
const MAX_RETRIES = 5
const RETRY_TIMEOUT = 1.5

const _VALIDATION_RULES: Dictionary = {
	"cg_play": {
		"forbidden_next": ["show_dialogue", "show_choices", "change_background",
						   "set_characters", "character_action", "particle_play",
						   "set_expression", "clear_stage", "wait", "play_audio"],
		"reason": "CG 显示期间不应穿插其他视觉指令，请使用 cg_hide 后再操作。"
	},
	"end_scene": {
		"forbidden_next": ["*"],
		"reason": "end_scene 后不应有任何指令。"
	},
	"clear_stage": {
		"forbidden_next": ["set_characters"],
		"reason": "clear_stage 后紧跟 set_characters 是无意义的，请直接使用 set_characters。"
	},
	"show_choices": {
		"forbidden_next": ["show_choices"],
		"reason": "连续两个选项会让玩家困惑，请合并或分开。"
	},
	"change_background": {
		"forbidden_next": ["change_background"],
		"reason": "连续两次背景切换，中间没有内容，请检查逻辑。"
	}
}

const _AFFECTION_EXPRESSION_RULES = [
	{
		"positive_expressions": ["happy", "very_happy", "smile", "laugh"],
		"negative_expressions": ["sad", "angry", "cry", "annoyed"],
		"min_affection_for_positive": 10,
		"max_affection_for_negative": -5
	}
]

# ================= 状态 =================
var _commands: Array = []
var _current_index: int = 0
var _is_running: bool = false
var _retry_count: int = 0
var _current_cmd: Dictionary = {}
var _timeout_timer: Timer = null
var _command_pending: bool = false
var _interaction_pending: bool = false


# ================= 启动与流程控制 =================
func execute_commands(commands: Array) -> void:
	if _is_running:
		print("[ScriptEngine] 警告：已有脚本在运行，忽略新请求。")
		return
	if commands.is_empty():
		print("[ScriptEngine] 警告：命令列表为空。")
		return

	_commands = _validate_command_sequence(commands)
	_current_index = 0
	_is_running = true
	_command_pending = false
	_interaction_pending = false
	_execute_next()


func _execute_next() -> void:
	if _command_pending:
		return

	_clear_timeout()

	if _current_index >= _commands.size():
		_finish_script()
		return

	_current_cmd = _commands[_current_index]
	var type: String = _current_cmd.get("type", "")
	print("[ScriptEngine] 执行指令 (%d/%d): %s" % [_current_index + 1, _commands.size(), type])

	match type:
		# --- 交互指令（无超时，等待玩家） ---
		"show_dialogue":
			_command_pending = true
			_interaction_pending = true

			var show_waiting = _current_cmd.get("waiting_indicator", false)
			if show_waiting:
				var scene = DialogueManager.get_dialogue_scene()
				if scene and scene.has_method("show_waiting_indicator"):
					await scene.show_waiting_indicator()

			DialogueManager.display_line(_current_cmd)
			if not DialogueManager.is_connected("line_finished", _on_line_finished):
				DialogueManager.connect("line_finished", _on_line_finished, CONNECT_ONE_SHOT)
		
		
		"long_dialogue":
			_command_pending = true
			_interaction_pending = true

			CharacterManager.hide_all_characters()

			var scene_root = get_tree().current_scene
			if scene_root:
				var dlg_box = scene_root.get_node_or_null("DialogueBox")
				if dlg_box:
					dlg_box.hide()
				var name_rect = scene_root.get_node_or_null("CharacterNameRect")
				if name_rect:
					name_rect.hide()

			var text = _current_cmd.get("text", "")
			DialogueManager.display_long_dialogue(text)
			if not DialogueManager.is_connected("line_finished", _on_line_finished):
				DialogueManager.connect("line_finished", _on_line_finished, CONNECT_ONE_SHOT)


		"show_choices":
			_command_pending = true
			_interaction_pending = true
			DialogueManager.display_options(_current_cmd.get("choices", []))
			if not DialogueManager.is_connected("choice_made", _on_choice_made):
				DialogueManager.connect("choice_made", _on_choice_made, CONNECT_ONE_SHOT)

		"cg_play":
			_command_pending = true
			_interaction_pending = true
			if has_node("/root/CGManager"):
				var cg_mgr = get_node("/root/CGManager")
				cg_mgr.show_cg(_current_cmd.get("cg_id", ""), _current_cmd.get("script_data", []))
				if not cg_mgr.is_connected("cg_finished", _on_cg_done):
					cg_mgr.connect("cg_finished", _on_cg_done, CONNECT_ONE_SHOT)
			else:
				print("[ScriptEngine] CGManager 未找到，跳过 cg_play。")
				_command_pending = false
				_interaction_pending = false
				_advance_to_next()

		"cg_hide":
			_command_pending = true
			_interaction_pending = true
			if has_node("/root/CGManager"):
				var cg_mgr = get_node("/root/CGManager")
				cg_mgr.hide_cg()
				if not cg_mgr.is_connected("cg_finished", _on_cg_done):
					cg_mgr.connect("cg_finished", _on_cg_done, CONNECT_ONE_SHOT)
			else:
				print("[ScriptEngine] CGManager 未找到，跳过 cg_hide。")
				_command_pending = false
				_interaction_pending = false
				_advance_to_next()

		# --- 系统指令（带重试机制） ---
		"change_background":
			_command_pending = true
			_interaction_pending = false
			_start_retry_timeout()
			UIManager.set_all_ui_visibility(false, "fade", 0.3)
			if not UIManager.is_connected("all_ui_hidden", _on_ui_hidden_for_bg):
				UIManager.connect("all_ui_hidden", _on_ui_hidden_for_bg, CONNECT_ONE_SHOT)

		"character_action":
			_command_pending = true
			_interaction_pending = false
			_start_retry_timeout()
			CharacterManager.play_action(_current_cmd.get("character", ""), _current_cmd.get("action", ""))
			if not CharacterManager.is_connected("action_completed", _on_action_done):
				CharacterManager.connect("action_completed", _on_action_done, CONNECT_ONE_SHOT)

		"set_characters":
			_command_pending = true
			_interaction_pending = false
			_start_retry_timeout()
			var entrance_anim = _current_cmd.get("entrance_animation", "fade")
			CharacterManager.set_characters_on_stage(
				_current_cmd.get("left", null),
				_current_cmd.get("right", null),
				entrance_anim
			)
			if not CharacterManager.is_connected("entrances_completed", _on_entrances_completed):
				CharacterManager.connect("entrances_completed", _on_entrances_completed, CONNECT_ONE_SHOT)

		"clear_stage":
			_command_pending = true
			_interaction_pending = false
			_start_retry_timeout()
			CharacterManager.clear_stage()
			if not CharacterManager.is_connected("exits_completed", _on_exits_completed):
				CharacterManager.connect("exits_completed", _on_exits_completed, CONNECT_ONE_SHOT)

		# --- 同步指令（立即完成） ---
		"wait":
			var duration = _current_cmd.get("duration", 1.0)
			var timer = get_tree().create_timer(duration)
			timer.timeout.connect(_on_wait_complete, CONNECT_ONE_SHOT)

		"jump":
			print("[ScriptEngine] 执行跳转至: %s" % _current_cmd.get("target", ""))
			_advance_to_next()

		"end_scene":
			print("[ScriptEngine] 场景结束指令。")
			_finish_script()
			return

		"set_expression":
			CharacterManager.set_expression(_current_cmd.get("character", ""), _current_cmd.get("expression", "default"))
			_advance_to_next()

		"particle_play":
			ParticleManager.play_effect(_current_cmd.get("effect_id", ""))
			_advance_to_next()

		"particle_stop":
			if _current_cmd.has("effect_id"):
				ParticleManager.stop_effect(_current_cmd.get("effect_id", ""))
			else:
				ParticleManager.stop_all_effects()
			_advance_to_next()

		"set_ui_state":
			UIManager.set_ui_state(_current_cmd.get("element", ""), _current_cmd.get("state", ""))
			_advance_to_next()

		"set_variable":
			GameManager.set_variable(_current_cmd.get("variable", ""), _current_cmd.get("value", 0))
			_advance_to_next()

		"unlock_cg":
			var cg_id = _current_cmd.get("cg_id", "")
			if cg_id != "":
				GameManager.unlock_cg(cg_id)
			_advance_to_next()

		"unlock_bgm":
			var bgm_id = _current_cmd.get("bgm_id", "")
			if bgm_id != "":
				GameManager.unlock_bgm(bgm_id)
			_advance_to_next()

		"reset_unlocks":
			GameManager.reset_all_unlocks()
			_advance_to_next()

		"add_affection":
			GameManager.add_affection(_current_cmd.get("character", ""), _current_cmd.get("delta", 0))
			_advance_to_next()

		"set_flag":
			GameManager.set_flag(_current_cmd.get("flag", ""), _current_cmd.get("value", true))
			_advance_to_next()

		"play_audio":
			AudioManager.play_audio(_current_cmd.get("audio_id", ""), _current_cmd.get("crossfade", 0.5))
			_advance_to_next()

		"stop_audio":
			AudioManager.stop_audio(_current_cmd.get("audio_id", ""), _current_cmd.get("fade_out", 0.3))
			_advance_to_next()

		_:
			print("[ScriptEngine] 未知指令类型: %s，跳过。" % type)
			_advance_to_next()


# ================= 超时与重试 =================
func _start_retry_timeout() -> void:
	_retry_count = 0
	_create_timeout_timer()


func _create_timeout_timer() -> void:
	_clear_timeout()
	_timeout_timer = Timer.new()
	add_child(_timeout_timer)
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = RETRY_TIMEOUT
	_timeout_timer.timeout.connect(_on_command_timeout)
	_timeout_timer.start()


func _clear_timeout() -> void:
	if _timeout_timer:
		_timeout_timer.stop()
		_timeout_timer.queue_free()
		_timeout_timer = null


func _on_command_timeout() -> void:
	_retry_count += 1
	if _retry_count <= MAX_RETRIES:
		print("[ScriptEngine] 系统指令 '%s' 超时，正在重试 (%d/%d)..." % [_current_cmd.get("type", ""), _retry_count, MAX_RETRIES])
		_command_pending = false
		_clear_timeout()
		_execute_next()
	else:
		print("[ScriptEngine] 系统指令 '%s' 重试 %d 次后仍失败，已跳过。" % [_current_cmd.get("type", ""), MAX_RETRIES])
		_command_pending = false
		_clear_timeout()
		_advance_to_next()


# ================= 信号回调 =================
func _on_ui_hidden_for_bg() -> void:
	BackgroundManager.change_background(_current_cmd.get("background", ""), _current_cmd.get("transition", "fade"), _current_cmd.get("duration", 0.5))
	if not BackgroundManager.is_connected("transition_finished", _on_background_done):
		BackgroundManager.connect("transition_finished", _on_background_done, CONNECT_ONE_SHOT)


func _on_line_finished() -> void:
	if not _interaction_pending: return
	_command_pending = false
	_interaction_pending = false
	_clear_timeout()
	_advance_to_next()


func _on_choice_made(choice_id: int) -> void:
	if not _interaction_pending: return
	_command_pending = false
	_interaction_pending = false
	_clear_timeout()
	print("[ScriptEngine] 玩家选择了选项: %d" % choice_id)
	GameManager.set_variable("last_choice", choice_id)
	_advance_to_next()


func _on_background_done() -> void:
	_command_pending = false
	_clear_timeout()
	var next_index = _current_index + 1
	var skip_ui_show = false
	if next_index < _commands.size():
		var next_cmd = _commands[next_index]
		if next_cmd.get("type", "") == "long_dialogue":
			skip_ui_show = true

	if skip_ui_show:
		_advance_to_next()
	else:
		UIManager.set_all_ui_visibility(true, "fade", 0.4)
		if not UIManager.is_connected("all_ui_shown", _on_ui_shown_after_bg):
			UIManager.connect("all_ui_shown", _on_ui_shown_after_bg, CONNECT_ONE_SHOT)


func _on_ui_shown_after_bg() -> void:
	_advance_to_next()


func _on_action_done() -> void:
	_command_pending = false
	_clear_timeout()
	_advance_to_next()


func _on_cg_done() -> void:
	_command_pending = false
	_clear_timeout()
	_advance_to_next()


func _on_wait_complete() -> void:
	_advance_to_next()


func _on_entrances_completed() -> void:
	_command_pending = false
	_clear_timeout()
	_advance_to_next()


func _on_exits_completed() -> void:
	_command_pending = false
	_clear_timeout()
	_advance_to_next()


# ================= 指令推进与间隔 =================
func _advance_to_next() -> void:
	_current_index += 1
	_schedule_next()


func _schedule_next() -> void:
	var interval = _get_interval()
	if interval > 0:
		var timer = get_tree().create_timer(interval)
		timer.timeout.connect(_execute_next, CONNECT_ONE_SHOT)
	else:
		var timer = get_tree().create_timer(0.0)
		timer.timeout.connect(_execute_next, CONNECT_ONE_SHOT)


func _get_interval() -> float:
	if _current_index >= _commands.size():
		return 0.0
	var next_cmd = _commands[_current_index]
	var type: String = next_cmd.get("type", "")
	match type:
		"set_characters": return 1.0
		"set_expression": return 0.5
		"show_dialogue": return 0.25
		"show_choices": return 0.3
		"change_background": return 0.1
		"character_action": return 0.15
		"cg_play": return 0.0
		"wait": return 0.0
		_: return 0.05


# ================= 脚本生命周期管理 =================
func _finish_script() -> void:
	_is_running = false
	_command_pending = false
	_interaction_pending = false
	_clear_timeout()
	print("[ScriptEngine] 脚本执行完毕。")
	execution_finished.emit()


func stop_execution() -> void:
	_is_running = false
	_commands.clear()
	_current_index = 0
	_command_pending = false
	_clear_timeout()
	print("[ScriptEngine] 脚本执行已停止。")


func hard_reset() -> void:
	print("[ScriptEngine] 执行硬重置...")
	stop_execution()
	_interaction_pending = false
	print("[ScriptEngine] 硬重置完成。")


# ================= 存档恢复接口 =================
func set_commands(commands: Array) -> void:
	_commands = commands.duplicate(true)
	_current_index = 0
	_is_running = false


func resume_with_commands(new_commands: Array) -> void:
	stop_execution()
	_commands = new_commands.duplicate(true)
	_is_running = false
	execute_commands(_commands)


func silently_set_commands(new_commands: Array) -> void:
	stop_execution()
	_commands = new_commands.duplicate(true)
	_is_running = false
	print("[ScriptEngine] 指令队列已静默替换，等待执行。")


func get_pending_commands() -> Array:
	if _current_index < _commands.size():
		return _commands.slice(_current_index)
	return []


# ================= 预检与验证 =================
func _validate_command_sequence(commands: Array) -> Array:
	if commands.is_empty():
		return commands

	var result: Array = []
	var simulated_affection: Dictionary = {}
	var prev_type = ""

	for i in range(commands.size()):
		var cmd = commands[i]
		var type: String = cmd.get("type", "")

		# 相邻指令合法性检查
		if i > 0:
			var rule = _VALIDATION_RULES.get(prev_type, null)
			if rule:
				var forbidden: Array = rule.get("forbidden_next", [])
				var reason: String = rule.get("reason", "未知原因")
				var is_forbidden: bool = ("*" in forbidden) or (type in forbidden)
				if is_forbidden:
					push_warning("[ScriptEngine] 命令合法性警告：'%s' 后不应跟随 '%s'。%s 已自动跳过该指令。" % [prev_type, type, reason])
					continue

		# 好感度模拟与表情匹配检查
		if type == "add_affection":
			var char = cmd.get("character", "")
			var delta = cmd.get("delta", 0)
			if not simulated_affection.has(char):
				simulated_affection[char] = GameManager.get_affection(char)
			simulated_affection[char] += delta

		elif type == "set_expression":
			var char = cmd.get("character", "")
			var expr = cmd.get("expression", "")
			if not simulated_affection.has(char):
				simulated_affection[char] = GameManager.get_affection(char)
			var aff = simulated_affection[char]
			for rule in _AFFECTION_EXPRESSION_RULES:
				if expr in rule["positive_expressions"] and aff < rule["min_affection_for_positive"]:
					push_warning("[ScriptEngine] 合规性警告：角色 '%s' 当前好感度 %d，使用正面表情 '%s' 可能不合理。" % [char, aff, expr])
				if expr in rule["negative_expressions"] and aff > rule["max_affection_for_negative"]:
					push_warning("[ScriptEngine] 合规性警告：角色 '%s' 当前好感度 %d，使用负面表情 '%s' 可能不合理。" % [char, aff, expr])

		result.append(cmd)
		prev_type = type

	if result.size() < commands.size():
		print("[ScriptEngine] 预检完成：%d 条指令中 %d 条被跳过。" % [commands.size(), commands.size() - result.size()])

	return result
