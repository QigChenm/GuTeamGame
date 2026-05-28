# dialogue_scene.gd
extends Control

# ================= 信号 =================
signal continue_pressed
signal choice_selected(choice_id: int)
signal long_dialogue_finished

# ================= 属性 =================
@export var custom_font: Font

# ---------- UI 节点引用 ----------
@onready var background: TextureRect = $Background
@onready var char_left: CharacterDisplay = $SpriteLeft
@onready var char_right: CharacterDisplay = $SpriteRight
@onready var dialogue_box: TextureRect = $DialogueBox
@onready var portrait: TextureRect = $DialogueBox/CharacterNameRect/Portrait
@onready var character_name_rect: TextureRect = $DialogueBox/CharacterNameRect
@onready var name_label: RichTextLabel = $DialogueBox/CharacterNameRect/CharacterName
@onready var text_label: RichTextLabel = $DialogueBox/DialogueText
@onready var click_indicator: Label = $DialogueBox/ClickIndicator
@onready var choice_panel: VBoxContainer = $ChoicePanel
@onready var choice_buttons: Array[TextureButton] = [
	$ChoicePanel/Choice1, $ChoicePanel/Choice2, $ChoicePanel/Choice3
]
@onready var background_node: TextureRect = $Background
@onready var weather_layer: Control = $WeatherLayer
@onready var cg_display: TextureRect = $CGLayer/CGDisplay
@onready var fullscreen_text: RichTextLabel = $LongDialogueLayer/TextureRect/FullscreenText
@onready var long_close_btn: TextureButton = $LongDialogueLayer/TextureRect/CloseButton
@onready var long_dialogue_container:TextureRect = $LongDialogueLayer/TextureRect

# ---------- 状态变量 ----------
var is_waiting_for_input: bool = false
var current_choices: Array = []

# 打字机效果
var typewriter_tween: Tween = null
var typewriter_timer: Timer = null
var long_typewriter_timer: Timer = null
var long_typewriter_tween: Tween = null
var long_skip_timer: Timer = null
var skip_advance_timer: Timer = null
var is_typewriter_playing: bool = false
var _full_text: String = ""
var _typing_speed: float = 0.05

# HUD 与面板实例
var hud_instance: CanvasLayer = null
var save_hint_tween: Tween = null
var choice_labels: Array[Label] = []

# 自动模式
var auto_advance_timer: Timer = null
var auto_mode_paused_by_choice: bool = false
var skip_mode_paused_by_choice: bool = false
var _current_line_recorded: bool = false


# ================= 初始化 =================
func _ready() -> void:
	_init_ui_basics()
	_register_systems()
	_instantiate_hud()
	_instantiate_panels()
	_connect_uimanager_signals()
	_start_game_flow()
	_enable_input()


# ================= 基础 UI 设置 =================
func _init_ui_basics() -> void:
	choice_panel.hide()
	for i in range(choice_buttons.size()):
		choice_buttons[i].pressed.connect(_on_choice_pressed.bind(i + 1))
	for btn in choice_buttons:
		var label = btn.get_node_or_null("Label") as Label
		choice_labels.append(label)
		btn.mouse_entered.connect(Callable(self, "_on_choice_mouse_entered").bind(btn))
		btn.mouse_exited.connect(Callable(self, "_on_choice_mouse_exited").bind(btn))


# ================= 系统注册（舞台、背景、天气、CG、UI元素） =================
func _register_systems() -> void:
	if char_left is CharacterDisplay:
		CharacterManager.register_sprite("left", char_left)
	else:
		print("[DialogueScene] 错误：SpriteLeft 类型不正确！")
	if char_right is CharacterDisplay:
		CharacterManager.register_sprite("right", char_right)
	else:
		print("[DialogueScene] 错误：SpriteRight 类型不正确！")

	if background_node:
		BackgroundManager.register_background(background_node)
		print("[DialogueScene] 背景节点已注册。")
	else:
		print("[DialogueScene] 错误：未找到背景节点！")

	if weather_layer:
		ParticleManager.register_weather_layer(weather_layer)
		print("[DialogueScene] 天气层已注册。")
	else:
		print("[DialogueScene] 错误：未找到 WeatherLayer 节点！")

	if cg_display:
		CGManager.register_cg_display(cg_display)
		print("[DialogueScene] CG显示层已注册。")
	else:
		print("[DialogueScene] 错误：未找到 CG 层节点！")

	UIManager.register_ui_element("CharacterNameRect", character_name_rect)
	UIManager.register_ui_element("DialogueBox", dialogue_box)
	print("[DialogueScene] 核心UI元素已注册。")


# ================= HUD 实例化与按钮绑定 =================
func _instantiate_hud() -> void:
	var hud_scene = load("res://scenes/hud.tscn")
	if not hud_scene:
		return
	hud_instance = hud_scene.instantiate()
	add_child(hud_instance)

	# 获取所有按钮引用
	var settings_btn = hud_instance.get_node_or_null("ButtonBar/SettingsButton")
	var affection_btn = hud_instance.get_node_or_null("TopBar/AffectionButton")
	var save_btn = hud_instance.get_node_or_null("ButtonBar/SaveButton")
	var load_btn = hud_instance.get_node_or_null("ButtonBar/LoadButton")
	var return_btn = hud_instance.get_node_or_null("ReturnButton")
	var return_to_menu_btn = hud_instance.get_node_or_null("ReturnToMenuButton")
	var home_btn = hud_instance.get_node_or_null("ButtonBar/HomeButton")
	var backlog_btn = hud_instance.get_node_or_null("ButtonBar/BacklogButton")
	var quick_save_btn = hud_instance.get_node_or_null("QuickSaveButton")
	var quick_load_btn = hud_instance.get_node_or_null("QuickLoadButton")
	var auto_btn = hud_instance.get_node_or_null("ButtonBar/AutoButton")
	var skip_btn = hud_instance.get_node_or_null("ButtonBar/SkipButton")
	var feedback_btn = hud_instance.get_node_or_null("TopBar/FeedbackButton")

	# 连接信号
	if settings_btn:
		settings_btn.pressed.connect(func(): UIManager.open_panel("SettingsUI"))
	if affection_btn:
		affection_btn.pressed.connect(_on_affection_button_pressed)
	if save_btn:
		save_btn.pressed.connect(_on_save_button_pressed)
	if load_btn:
		load_btn.pressed.connect(_on_load_button_pressed)
	if home_btn:
		home_btn.pressed.connect(_on_home_button_pressed)
	if backlog_btn:
		backlog_btn.pressed.connect(_on_backlog_button_pressed)
	if quick_save_btn:
		quick_save_btn.pressed.connect(_on_quick_save_pressed)
	if quick_load_btn:
		quick_load_btn.pressed.connect(_on_quick_load_pressed)
	if auto_btn:
		auto_btn.pressed.connect(_on_auto_button_pressed)
	if skip_btn:
		skip_btn.pressed.connect(_on_skip_button_pressed)
	if long_close_btn:
		long_close_btn.pressed.connect(_on_long_close_pressed)
	if return_btn:
		UIManager.set_return_button(return_btn)
		return_btn.pressed.connect(UIManager.close_current_panel)
	if return_to_menu_btn:
		UIManager.set_return_to_menu_button(return_to_menu_btn)
		return_to_menu_btn.pressed.connect(_on_return_to_menu_pressed)
	if feedback_btn:
		feedback_btn.pressed.connect(_on_feedback_button_pressed)

	# 将所有功能按钮注册到 UIManager（以便统一显隐管理）
	var all_buttons: Array[TextureButton] = []
	for btn in [settings_btn, feedback_btn, auto_btn, skip_btn, quick_save_btn, quick_load_btn, backlog_btn, home_btn, affection_btn, save_btn, load_btn]:
		if btn:
			all_buttons.append(btn)
	UIManager.register_hud_action_buttons(all_buttons)


# ================= 面板实例化与注册 =================
func _instantiate_panels() -> void:
	_load_and_register("AffectionUI", "res://scenes/affection_ui.tscn")
	_load_and_register("SaveUI", "res://scenes/save_ui.tscn")
	_load_and_register("LoadUI", "res://scenes/load_ui.tscn")
	_load_and_register("SettingsUI", "res://scenes/settings_ui.tscn")
	_load_and_register("BacklogUI", "res://scenes/backlog_ui.tscn")
	_load_and_register("GalleryUI", "res://scenes/gallery_ui.tscn", func(panel): panel.custom_font = custom_font)
	_load_and_register("TipUI", "res://scenes/tip_ui.tscn")
	_load_and_register("AboutUI", "res://scenes/intro_ui.tscn")


func _load_and_register(panel_name: String, scene_path: String, callback: Callable = Callable()) -> void:
	var scene = load(scene_path)
	if not scene:
		return
	var instance = scene.instantiate()
	add_child(instance)
	UIManager.register_panel(panel_name, instance)
	if callback.is_valid():
		callback.call(instance)


# ================= UIManager 信号连接 =================
func _connect_uimanager_signals() -> void:
	if not UIManager.has_signal("panel_opened"):
		return
	UIManager.panel_opened.connect(_on_panel_opened)
	UIManager.panel_closed.connect(_on_panel_closed)


# ================= 启动游戏流程 =================
func _start_game_flow() -> void:
	if GameManager.open_settings_on_load:
		GameManager.open_settings_on_load = false
		call_deferred("_open_settings_from_menu")
	elif GameManager.open_gallery_on_load:
		GameManager.open_gallery_on_load = false
		call_deferred("_open_gallery_from_menu")
	elif SaveManager.continue_mode:
		SaveManager.continue_mode = false
		call_deferred("_open_load_panel_on_continue")
	elif GameManager.open_about_on_load:
		GameManager.open_about_on_load = false
		call_deferred("_open_about_from_menu")
	else:
		if GameManager.current_scene == "":
			GameManager.start_new_game()
		DialogueManager.start_dialogue()


# ================= 启用输入 =================
func _enable_input() -> void:
	set_process_input(true)


# ================= 对话显示 =================
func display_dialogue(data: Dictionary) -> void:
	_current_line_recorded = false
	choice_panel.hide()
	_kill_typewriter()

	var character = data.get("character", "")
	var display_name = "[b]" + _resolve_character_name(character) + "[/b]"
	name_label.text = display_name
	if character == "":
		character_name_rect.hide()
		portrait.hide()
	else:
		character_name_rect.show()
		if GameManager.character_database.has(character):
			portrait.texture = GameManager.character_database[character].portrait
			portrait.show()

	_full_text = data.get("text", "")
	text_label.text = _full_text
	text_label.visible_characters = 0

	var speed = data.get("speed", GameManager.text_speed)
	var total_chars = _full_text.length()
	is_typewriter_playing = true

	var character_id = character

	if GameManager.is_skip_mode:
		_stop_auto_timer()
		text_label.visible_characters = total_chars
		is_typewriter_playing = false
		_record_dialogue_history(display_name, character_id)
		_start_skip_advance_timer()
		is_waiting_for_input = true
		click_indicator.hide()
	else:
		_start_typewriter_timer(total_chars, speed, func():
			is_typewriter_playing = false
			if GameManager.is_auto_mode:
				_start_auto_timer()
				click_indicator.hide()
			else:
				_stop_auto_timer()
				is_waiting_for_input = true
				click_indicator.show()
			_record_dialogue_history(display_name, character_id)
		)

	dialogue_box.show()
	text_label.show()

func _resolve_character_name(character: String) -> String:
	if character != "" and GameManager.character_database.has(character):
		return GameManager.character_database[character].display_name
	return character


func _kill_typewriter() -> void:
	if typewriter_tween and typewriter_tween.is_running():
		typewriter_tween.kill()
	is_typewriter_playing = false
	_stop_typewriter()
	if auto_advance_timer:
		auto_advance_timer.stop()
		auto_advance_timer.queue_free()
		auto_advance_timer = null


func _record_dialogue_history(display_name: String, character_id: String = "") -> void:
	if _current_line_recorded or not GameManager:
		return
	_current_line_recorded = true
	GameManager.dialogue_history.append({
		"character": display_name,
		"text": _full_text,
		"type": "dialogue",
		"id": character_id
	})


# ================= 选项显示 =================
func display_choices(choices: Array) -> void:
	if GameManager.is_skip_mode:
		skip_mode_paused_by_choice = true
		GameManager.is_skip_mode = false
		GameManager.skip_mode_changed.emit(false)
		_stop_auto_timer()
	_pause_auto_for_choices()
	is_waiting_for_input = false
	click_indicator.hide()
	current_choices = choices

	for i in range(choice_buttons.size()):
		if i < choices.size():
			var btn = choice_buttons[i]
			var label = choice_labels[i]
			if label:
				label.text = choices[i].get("text", "")
				label.add_theme_color_override("font_color", Color("#34859B"))
			choice_buttons[i].disabled = false
			choice_buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP
			choice_buttons[i].visible = true
			choice_buttons[i].modulate.a = 1.0
			choice_buttons[i].scale = Vector2.ONE
		else:
			choice_buttons[i].visible = false

	choice_panel.show()
	choice_panel.z_index = 10
	choice_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# 轻微弹入动画
	for i in range(min(choices.size(), choice_buttons.size())):
		var btn = choice_buttons[i]
		var t = create_tween()
		t.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1)
		t.tween_property(btn, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)


func _pause_auto_for_choices() -> void:
	if not GameManager.is_auto_mode:
		return
	auto_mode_paused_by_choice = true
	GameManager.is_auto_mode = false
	GameManager.auto_mode_changed.emit(false)
	_stop_auto_timer()


# ================= 选项点击 =================
func _on_choice_pressed(choice_id: int) -> void:
	_record_choice(choice_id)
	choice_panel.hide()
	if skip_mode_paused_by_choice:
		skip_mode_paused_by_choice = false
		GameManager.is_skip_mode = true
		GameManager.skip_mode_changed.emit(true)
	choice_selected.emit(choice_id)
	_restore_auto_after_choice()


func _on_choice_mouse_entered(btn: TextureButton) -> void:
	var idx = choice_buttons.find(btn)
	if idx != -1 and idx < choice_labels.size():
		var label = choice_labels[idx]
		if label:
			label.add_theme_color_override("font_color", Color("#B24F4F"))


func _on_choice_mouse_exited(btn: TextureButton) -> void:
	var idx = choice_buttons.find(btn)
	if idx != -1 and idx < choice_labels.size():
		var label = choice_labels[idx]
		if label:
			label.add_theme_color_override("font_color", Color("#34859B"))


func _record_choice(choice_id: int) -> void:
	var choice_text = ""
	for c in current_choices:
		if str(c.get("id", "")) == str(choice_id):
			choice_text = c.get("text", "")
			break
	if choice_text != "":
		GameManager.dialogue_history.append({
			"character": "玩家",
			"text": choice_text,
			"type": "choice",
			"id": ""
		})


func _restore_auto_after_choice() -> void:
	if not auto_mode_paused_by_choice:
		return
	auto_mode_paused_by_choice = false
	GameManager.is_auto_mode = true
	GameManager.auto_mode_changed.emit(true)


# ================= 自动模式与播放速度核心 =================
func _on_typewriter_tick(total_chars: int, on_finished: Callable) -> void:
	if not is_instance_valid(text_label):
		_stop_typewriter()
		return
	
	var current = text_label.visible_characters
	if current < total_chars:
		text_label.visible_characters = current + 1
	else:
		_stop_typewriter()
		if on_finished.is_valid():
			on_finished.call()


func _on_auto_button_pressed() -> void:
	GameManager.is_auto_mode = !GameManager.is_auto_mode
	GameManager.auto_mode_changed.emit(GameManager.is_auto_mode)
	auto_mode_paused_by_choice = false
	_stop_auto_timer()

	if GameManager.is_auto_mode:
		if is_waiting_for_input:
			_start_auto_timer()
	else:
		if not is_typewriter_playing and not is_waiting_for_input:
			is_waiting_for_input = true
			click_indicator.show()


func _on_skip_button_pressed() -> void:
	GameManager.is_skip_mode = !GameManager.is_skip_mode
	GameManager.skip_mode_changed.emit(GameManager.is_skip_mode)
	skip_mode_paused_by_choice = false

	if hud_instance:
		var btn = hud_instance.get_node_or_null("TopBar/SkipButton")
		if btn:
			btn.modulate = Color.YELLOW if GameManager.is_skip_mode else Color.WHITE

	if GameManager.is_skip_mode:
		if long_dialogue_container.visible:
			fullscreen_text.visible_characters = fullscreen_text.text.length()
			if long_typewriter_tween and long_typewriter_tween.is_running():
				long_typewriter_tween.kill()
			if long_skip_timer:
				long_skip_timer.stop()
				long_skip_timer.queue_free()
			long_skip_timer = Timer.new()
			add_child(long_skip_timer)
			long_skip_timer.one_shot = true
			long_skip_timer.wait_time = 1.0
			long_skip_timer.timeout.connect(_on_long_close_pressed)
			long_skip_timer.start()
		elif is_waiting_for_input:
			_start_skip_advance_timer()
	else:
		_stop_skip_advance_timer()
		if long_skip_timer:
			long_skip_timer.stop()
			long_skip_timer.queue_free()
			long_skip_timer = null


func _start_typewriter_timer(total_chars: int, speed: float, on_finished: Callable) -> void:
	_stop_typewriter()
	text_label.visible_characters = 1
	typewriter_timer = Timer.new()
	typewriter_timer.name = "TypewriterTimer"
	add_child(typewriter_timer)
	typewriter_timer.wait_time = speed
	typewriter_timer.timeout.connect(_on_typewriter_tick.bind(total_chars, on_finished))
	typewriter_timer.start()


func _stop_typewriter() -> void:
	if typewriter_timer:
		typewriter_timer.stop()
		typewriter_timer.queue_free()
		typewriter_timer = null


func update_text_speed(new_speed: float) -> void:
	if typewriter_timer and not typewriter_timer.is_stopped():
		typewriter_timer.wait_time = new_speed
	if long_typewriter_timer and not long_typewriter_timer.is_stopped():
		long_typewriter_timer.wait_time = new_speed


func _start_auto_timer() -> void:
	_stop_auto_timer()
	if not GameManager.is_auto_mode and not GameManager.is_skip_mode:
		return
	auto_advance_timer = Timer.new()
	add_child(auto_advance_timer)
	auto_advance_timer.one_shot = true
	var auto_delay = GameManager.get_variable("auto_speed")
	if auto_delay == null:
		auto_delay = 2.0 / GameManager.auto_speed if GameManager.auto_speed > 0 else 2.0
	if GameManager.is_skip_mode:
		auto_delay /= 3.0
	auto_advance_timer.wait_time = auto_delay
	auto_advance_timer.timeout.connect(_on_auto_advance_timeout)
	auto_advance_timer.start()
	click_indicator.hide()


func _stop_auto_timer() -> void:
	if auto_advance_timer:
		auto_advance_timer.stop()
		auto_advance_timer.queue_free()
		auto_advance_timer = null


func _start_skip_advance_timer() -> void:
	_stop_skip_advance_timer()
	if not GameManager.is_skip_mode:
		return
	skip_advance_timer = Timer.new()
	add_child(skip_advance_timer)
	skip_advance_timer.one_shot = true
	skip_advance_timer.wait_time = 0.3
	skip_advance_timer.timeout.connect(func():
		if is_waiting_for_input and GameManager.is_skip_mode:
			is_waiting_for_input = false
			click_indicator.hide()
			continue_pressed.emit()
	)
	skip_advance_timer.start()


func _stop_skip_advance_timer() -> void:
	if skip_advance_timer:
		skip_advance_timer.stop()
		skip_advance_timer.queue_free()
		skip_advance_timer = null


func _on_auto_advance_timeout() -> void:
	if not GameManager.is_auto_mode:
		return
	continue_pressed.emit()


# ================= 继续与输入处理 =================
func _gui_input(event: InputEvent) -> void:
	if get_tree().paused or not is_waiting_for_input:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_continue_clicked()
		return
	if event.is_action_pressed("ui_accept"):
		accept_event()
		_on_continue_clicked()
		return


func _on_continue_clicked() -> void:
	is_waiting_for_input = false
	click_indicator.hide()
	_stop_auto_timer()
	if SFXManager and SFXManager.has_method("play_continue_sfx"):
		SFXManager.play_continue_sfx()
	continue_pressed.emit()


# ================= HUD 按钮回调 =================
func _on_affection_button_pressed() -> void: UIManager.open_panel("AffectionUI")
func _on_save_button_pressed() -> void: UIManager.open_panel("SaveUI")
func _on_load_button_pressed() -> void: UIManager.open_panel("LoadUI")
func _on_feedback_button_pressed() -> void: _show_feedback_dialog()
func _on_backlog_button_pressed() -> void:
	var panel = UIManager._panels.get("BacklogUI")
	if panel and panel.has_method("refresh_history"):
		panel.refresh_history()
	UIManager.open_panel("BacklogUI")

func _on_quick_save_pressed() -> void:
	SaveManager.auto_save_to_latest_slot()
	
func _on_quick_load_pressed() -> void:
	if UIManager._current_panel != "":
		UIManager.close_current_panel()
	if get_tree().paused:
		get_tree().paused = false
	if long_dialogue_container.visible:
		hide_long_dialogue()
		if long_skip_timer:
			long_skip_timer.stop()
			long_skip_timer.queue_free()
			long_skip_timer = null
		long_dialogue_finished.emit()

	var slot = SaveManager.get_latest_slot()
	if SaveManager.has_save(slot):
		SaveManager.load_game(slot)
		print("[DialogueScene] 快速读档成功，槽位：%d" % slot)
	else:
		push_warning("[DialogueScene] 没有可用的存档。")


# ================= 返回主界面流程 =================
func _on_home_button_pressed() -> void:
	var tip_panel = UIManager._panels.get("TipUI")
	if not tip_panel:
		return

	tip_panel.show_tip("是否保存当前游戏进度？", "保存", "不保存",
		func(): _on_home_save_confirmed(),
		func(): _on_home_cancel_confirmed(),
		true,
		func(): _on_home_tip_closed()
	)

	_set_return_buttons_visible(false)


func _on_home_tip_closed() -> void:
	var tip_panel = UIManager._panels.get("TipUI")
	if tip_panel:
		tip_panel.hide_tip()
	if UIManager._return_button:
		UIManager._return_button.visible = false
	if UIManager._return_to_menu_button:
		UIManager._return_to_menu_button.visible = false


func _create_home_confirm_dialog() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.name = "HomeConfirmDialog"
	dialog.title = "提示"
	dialog.dialog_text = "是否保存当前游戏进度？"
	dialog.ok_button_text = "是（保存）"
	dialog.cancel_button_text = "否（不保存）"
	dialog.process_mode = PROCESS_MODE_ALWAYS
	dialog.min_size = Vector2(450, 200)

	if custom_font:
		dialog.add_theme_font_override("title_font", custom_font)
	dialog.add_theme_font_size_override("title_font_size", 30)
	dialog.add_theme_constant_override("title_margin_top", 15)

	var content_label = dialog.get_label()
	if content_label:
		if custom_font:
			content_label.add_theme_font_override("font", custom_font)
		content_label.add_theme_font_size_override("font_size", 30)

	var ok_btn = dialog.get_ok_button()
	var cancel_btn = dialog.get_cancel_button()
	if custom_font:
		ok_btn.add_theme_font_override("font", custom_font)
		cancel_btn.add_theme_font_override("font", custom_font)
	ok_btn.add_theme_font_size_override("font_size", 30)
	cancel_btn.add_theme_font_size_override("font_size", 30)

	var button_container = ok_btn.get_parent()
	if button_container is Container:
		button_container.add_theme_constant_override("separation", 10)

	for btn in [ok_btn, cancel_btn]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	dialog.confirmed.connect(_on_home_save_confirmed)
	dialog.canceled.connect(_on_home_cancel_confirmed)
	add_child(dialog)


func _on_home_save_confirmed() -> void:
	SaveManager.auto_save_to_latest_slot()
	await get_tree().create_timer(0.5).timeout
	var tip_panel = UIManager._panels.get("TipUI")
	if tip_panel:
		tip_panel.hide_tip()
	_return_to_main_menu()

func _on_home_cancel_confirmed() -> void:
	var tip_panel = UIManager._panels.get("TipUI")
	if tip_panel:
		tip_panel.hide_tip()
	_return_to_main_menu()


func _on_return_to_menu_pressed() -> void:
	UIManager.close_current_panel()
	await get_tree().process_frame
	UIManager.hide_return_to_menu_button()
	SaveManager.continue_mode = false
	if get_tree().paused:
		get_tree().paused = false
	clean_up_all_ui()
	_return_to_main_menu()


func _on_fullscreen_text_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_long_dialogue()
		long_dialogue_finished.emit()


func _on_long_typewriter_tick(total_chars: int) -> void:
	if not is_instance_valid(fullscreen_text):
		_stop_long_typewriter()
		return
	var current = fullscreen_text.visible_characters
	if current < total_chars:
		fullscreen_text.visible_characters = current + 1
	else:
		_stop_long_typewriter()
		
		
func _on_long_close_pressed() -> void:
	hide_long_dialogue()
	if long_skip_timer:
		long_skip_timer.stop()
		long_skip_timer.queue_free()
		long_skip_timer = null
	CharacterManager.show_all_characters()
	
	dialogue_box.visible = true
	text_label.visible = true
	character_name_rect.visible = true
	character_name_rect.modulate.a = 1.0
	dialogue_box.modulate.a = 1.0
	text_label.modulate.a = 1.0
	
	is_waiting_for_input = true
	click_indicator.visible = true
	click_indicator.modulate.a = 1.0
	
	var long_text = fullscreen_text.text
	if long_text != "":
		GameManager.dialogue_history.append({
			"character": "",
			"text": long_text,
			"type": "long_dialogue",
			"id": ""
		})
	
	long_dialogue_finished.emit()


func _return_to_main_menu() -> void:
	if AudioManager:
		AudioManager.stop_all()
	if ScriptEngine:
		ScriptEngine.hard_reset()
	if has_node("/root/ScriptEngine"):
		get_node("/root/ScriptEngine").stop_execution()
		get_node("/root/ScriptEngine").hard_reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================= 存档与读档 UI =================
func _open_load_panel_on_continue() -> void:
	UIManager.open_panel("LoadUI")
	UIManager.show_return_to_menu_button()
	SaveManager.continue_mode = true


func _open_settings_from_menu() -> void:
	UIManager.open_panel("SettingsUI")
	UIManager.show_return_to_menu_button()


func _open_gallery_from_menu() -> void:
	UIManager.open_panel("GalleryUI")
	UIManager.show_return_to_menu_button()
	UIManager.panel_closed.connect(_on_gallery_closed_from_menu, CONNECT_ONE_SHOT)
	

func _on_gallery_closed_from_menu(panel_name: String) -> void:
	if panel_name == "GalleryUI":
		if get_tree().paused:
			get_tree().paused = false
		GameManager.open_gallery_on_load = false
		_return_to_main_menu()


func _open_about_from_menu() -> void:
	UIManager.open_panel("AboutUI")
	UIManager.show_return_to_menu_button()


# ================= 面板回调 =================
func _on_panel_opened(_panel_name: String) -> void: pass
func _on_panel_closed(_panel_name: String) -> void: pass


# ================= 对话状态存取（存档用） =================
func get_dialogue_state() -> Dictionary:
	return {
		"character": name_label.text,
		"text": _full_text if is_typewriter_playing else text_label.text,
		"choices": current_choices if choice_panel.visible else []
	}


func restore_dialogue_state(data: Dictionary) -> void:
	var character: String = data.get("character", "")
	var text: String = data.get("text", "")
	var choices: Array = data.get("choices", [])

	_full_text = text
	text_label.text = text
	text_label.visible_characters = text.length()
	name_label.text = character
	if character == "":
		character_name_rect.hide()
	else:
		character_name_rect.show()

	if choices.size() > 0:
		display_choices(choices)
	else:
		choice_panel.hide()
		is_waiting_for_input = true
		click_indicator.show()

	dialogue_box.visible = true
	text_label.visible = true
	dialogue_box.modulate.a = 1.0
	text_label.modulate.a = 1.0
	if character != "":
		character_name_rect.visible = true
		character_name_rect.modulate.a = 1.0
	click_indicator.visible = true
	

# ================= 长对话 =================
func show_long_dialogue(text: String) -> void:
	fullscreen_text.text = text
	long_dialogue_container.visible = true
	long_close_btn.visible = true

	if long_typewriter_tween and long_typewriter_tween.is_running():
		long_typewriter_tween.kill()

	var total_chars = text.length()

	if GameManager.is_skip_mode:
		fullscreen_text.visible_characters = total_chars
		if long_skip_timer:
			long_skip_timer.stop()
			long_skip_timer.queue_free()
		long_skip_timer = Timer.new()
		add_child(long_skip_timer)
		long_skip_timer.one_shot = true
		long_skip_timer.wait_time = 1.0
		long_skip_timer.timeout.connect(_on_long_close_pressed)
		long_skip_timer.start()
	else:
		fullscreen_text.visible_characters = 0
		var speed = GameManager.text_speed
		_start_long_typewriter_timer(total_chars, speed)


func _start_long_typewriter_timer(total_chars: int, speed: float) -> void:
	_stop_long_typewriter()
	fullscreen_text.visible_characters = 1
	long_typewriter_timer = Timer.new()
	long_typewriter_timer.name = "LongTypewriterTimer"
	add_child(long_typewriter_timer)
	long_typewriter_timer.wait_time = speed
	long_typewriter_timer.timeout.connect(_on_long_typewriter_tick.bind(total_chars))
	long_typewriter_timer.start()
	

func _stop_long_typewriter() -> void:
	if long_typewriter_timer:
		long_typewriter_timer.stop()
		long_typewriter_timer.queue_free()
		long_typewriter_timer = null


func hide_long_dialogue() -> void:
	long_dialogue_container.visible = false
	if long_typewriter_tween and long_typewriter_tween.is_running():
		long_typewriter_tween.kill()
	_stop_long_typewriter()
	if long_skip_timer:
		long_skip_timer.stop()
		long_skip_timer.queue_free()
		long_skip_timer = null


# ================= UI 截图与清理 =================
func _set_return_buttons_visible(visible: bool) -> void:
	if visible:
		if SaveManager.continue_mode:
			UIManager.show_return_to_menu_button()
		else:
			if UIManager._return_button:
				UIManager._return_button.visible = true
			if UIManager._return_to_menu_button:
				UIManager._return_to_menu_button.visible = false
	else:
		if UIManager._return_button:
			UIManager._return_button.visible = false
		if UIManager._return_to_menu_button:
			UIManager._return_to_menu_button.visible = false
			
			
func hide_all_ui_for_screenshot() -> void:
	if hud_instance:
		hud_instance.visible = false


func show_all_ui() -> void:
	if hud_instance:
		hud_instance.visible = true


func clean_up_all_ui() -> void:
	print("[DialogueScene] 正在清理所有动态UI...")
	if hud_instance and is_instance_valid(hud_instance):
		hud_instance.queue_free()
		hud_instance = null
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		if gm.affection_ui_instance and is_instance_valid(gm.affection_ui_instance):
			gm.affection_ui_instance.queue_free()
			gm.affection_ui_instance = null
	if has_node("HomeConfirmDialog"):
		var dialog = get_node("HomeConfirmDialog")
		if is_instance_valid(dialog):
			dialog.queue_free()
	print("[DialogueScene] 动态UI清理完成。")

# ================= 辅助功能 =================
func _show_feedback_dialog() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "纠正 AI 错误"
	dialog.process_mode = PROCESS_MODE_ALWAYS

	var line_edit = LineEdit.new()
	line_edit.name = "RuleInput"
	line_edit.placeholder_text = "输入纠正规则..."
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.add_child(line_edit)

	dialog.get_label().text = "请输入纠正指令："

	add_child(dialog)

	dialog.confirmed.connect(func():
		var text = line_edit.text.strip_edges()
		if text != "" and has_node("/root/AIManager"):
			get_node("/root/AIManager").add_user_rule(text)
			print("[DialogueScene] 规则已提交")
		dialog.queue_free()  # 用完后销毁
	)

	dialog.popup_centered()
