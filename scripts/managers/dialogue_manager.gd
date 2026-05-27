# dialogue_manager.gd
extends Node

# ================= 信号 =================
signal dialogue_finished()
signal line_finished
signal choice_made(choice_id: int)

# ================= 属性 =================
var ai_adapter = null
var dialogue_queue: Array = []
var is_requesting = false
var ui_is_ready = false
var _scene_instance: Control = null
var _first_response: bool = false


# ================= 初始化 =================
func _ready() -> void:
	call_deferred("_cache_scene_instance")


func _cache_scene_instance() -> void:
	_scene_instance = get_tree().current_scene as Control


# ================= 旧版对话启动流程（保留用于未来 AI 接入） =================
func start_dialogue() -> void:
	dialogue_queue.clear()
	_first_response = true
	await request_ai_response("__start__")


func request_next() -> void:
	if dialogue_queue.is_empty():
		await request_ai_response("__continue__")
	else:
		show_next_line()


func submit_choice(choice_id: int) -> void:
	await request_ai_response("__choice__:" + str(choice_id))


func request_ai_response(input_str: String) -> void:
	if ai_adapter and ai_adapter.has_method("send_message"):
		is_requesting = true
		await ai_adapter.send_message(input_str, _on_ai_response)
	else:
		# 测试用命令序列（未接入 AI 时自动执行）
		var test_script = [
			{"type": "play_audio", "audio_id": "spring_forest", "crossfade": 1.5},
			{"type": "change_background", "background": "gulou_spring", "transition": "fade"},
			{"type": "long_dialogue", "text": "这是南京大学鼓楼校区北大楼前。[br]什，什么，南京哪个大学？哦，是南京大学啊，我还以为是南京大学呢。[br]刚刚路过了两个男大学生，听到了一些对话：“南京古代是吴国的首都，所以南京大学又称wj大学。你品，你细品。”[br]不得不说，在这所校园里，天天都会有神奇的事情发生。[br]正如上文所说，一名普通南大学子开始了和他妹妹美好的校园生活……[br]这还是我们参加竞赛的初衷吗，不是说好了要做一个解决当代大学生生活压力的AI智能游戏吗？——from a developer"},
			{"type": "particle_play", "effect_id": "petal"},
			{"type": "set_characters", "left": {"id": "sister", "expression": "happy", "entrance_animation": "slide_left"}, "entrance_animation": "fade"},
			{"type": "show_dialogue", "character": "sister", "text": "哥哥，你终于来了！[color=#FFB6C1]今天天气真好呀～[/color]"},
			{"type": "set_expression", "character": "sister", "expression": "happy"},
			{"type": "show_dialogue", "character": "sister", "text": "我们去哪里玩呢？"},
			{"type": "show_choices", "prompt": "选择目的地", "choices": [
				{"id": 1, "text": "公园散步"},
				{"id": 2, "text": "图书馆看书"},
				{"id": 3, "text": "咖啡馆聊天"}
			]},
			{"type": "add_affection", "character": "sister", "delta": 10},
			{"type": "set_flag", "flag": "first_date", "value": true},
			{"type": "show_dialogue", "character": "sister", "text": "嗯！[shake rate=15 level=3]好开心！[/shake]"},
			{"type": "character_action", "character": "sister", "action": "bounce"},
			{"type": "show_dialogue", "character": "", "text": "两人一起度过了愉快的下午..."},
			{"type": "wait", "duration": 1.0},
			{"type": "clear_stage"},
			{"type": "particle_stop", "effect_id": "petal"},
			{"type": "change_background", "background": "gulou_winter", "transition": "fade"},
			{"type": "particle_play", "effect_id": "snow"},
			{"type": "set_characters", "right": {"id": "sister", "expression": "default", "entrance_animation": "slide_right"}, "entrance_animation": "none"},
			{"type": "show_dialogue", "character": "sister", "text": "但是...天快黑了，我得回家了。"},
			{"type": "set_expression", "character": "sister", "expression": "sad"},
			{"type": "character_action", "character": "sister", "action": "shake"},
			{"type": "show_dialogue", "character": "sister", "text": "哥哥，明天还能见面吗？"},
			{"type": "show_choices", "choices": [
				{"id": 1, "text": "当然可以！"},
				{"id": 2, "text": "我看看时间..."}
			]},
			{"type": "add_affection", "character": "sister", "delta": 20},
			{"type": "set_expression", "character": "sister", "expression": "happy"},
			{"type": "show_dialogue", "character": "sister", "text": "太好了！[rainbow freq=0.5 sat=0.8 val=1.0]一言为定！[/rainbow]"},
			{"type": "play_audio", "audio_id": "love_piano", "crossfade": 2.0},
			{"type": "cg_play", "cg_id": "heroine_smile", "script_data": [
				{"action": "pan", "start": {"x": -80, "y": 0}, "end": {"x": 0, "y": 0}, "duration": 2.5},
				{"action": "zoom", "start": {"scale": 1.15}, "end": {"scale": 1.0}, "duration": 2.5}
			]},
			{"type": "unlock_cg", "cg_id": "heroine_smile"},
			{"type": "unlock_bgm", "bgm_id": "spring_forest"},
			{"type": "unlock_bgm", "bgm_id": "love_piano"},
			{"type": "set_variable", "variable": "ending_flag", "value": 1},
			{"type": "show_dialogue", "character": "", "text": "就这样，两人的故事翻开了新的一页..."},
			{"type": "set_ui_state", "element": "DialogueBox", "state": "hidden"},
			{"type": "stop_audio", "audio_id": "love_piano", "fade_out": 1.0},
			{"type": "end_scene"}
		]
		ScriptEngine.execute_commands(test_script)


func _on_ai_response(data: Dictionary) -> void:
	is_requesting = false
	AIManager.process_ai_response(data)
	dialogue_queue.append(data)
	if not is_waiting_for_ui_input():
		show_next_line()


# ================= ScriptEngine 调用接口 =================
func display_line(data: Dictionary) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("display_dialogue"):
		_scene_instance.display_dialogue(data)
		if not _scene_instance.is_connected("continue_pressed", _on_continue):
			_scene_instance.connect("continue_pressed", _on_continue, CONNECT_ONE_SHOT)


func display_options(choices: Array) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("display_choices"):
		_scene_instance.display_choices(choices)
		if not _scene_instance.is_connected("choice_selected", _on_choice):
			_scene_instance.connect("choice_selected", _on_choice, CONNECT_ONE_SHOT)


# ================= 信号回调 =================
func _on_continue() -> void:
	print("[DialogueManager] 玩家点击继续，发射 line_finished")
	line_finished.emit()


func _on_choice(choice_id: int) -> void:
	print("[DialogueManager] 玩家选择选项 %d，发射 choice_made" % choice_id)
	choice_made.emit(choice_id)


# ================= 辅助方法 =================
func show_next_line() -> void:
	if dialogue_queue.is_empty():
		return
	var data = dialogue_queue.pop_front()
	var scene = get_dialogue_scene()
	if scene:
		scene.display_dialogue(data)
		if data.has("choices") and data.choices.size() > 0:
			scene.display_choices(data.choices)


func get_dialogue_scene() -> Control:
	var root = get_tree().current_scene
	if root is Control:
		return root
	return null


func is_waiting_for_ui_input() -> bool:
	var scene = get_dialogue_scene()
	if scene and scene.has_method("is_waiting"):
		return scene.is_waiting_for_input
	return false


func display_long_dialogue(text: String) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("show_long_dialogue"):
		_scene_instance.show_long_dialogue(text)
		if not _scene_instance.is_connected("long_dialogue_finished", _on_long_dialogue_finished):
			_scene_instance.connect("long_dialogue_finished", _on_long_dialogue_finished, CONNECT_ONE_SHOT)


func _on_long_dialogue_finished() -> void:
	print("[DialogueManager] 长对话结束，发射 line_finished")
	line_finished.emit()
