# ui_manager.gd
extends Node

# ================= 属性 =================
var _return_button: TextureButton = null
var _return_to_menu_button: TextureButton = null
var _return_to_menu_active: bool = false
var _hud_action_buttons: Array[TextureButton] = []
var _panel_entry_buttons: Dictionary = {}
var _ui_elements: Dictionary = {}
var _panels: Dictionary = {}
var _current_panel: String = ""

# ================= 信号 =================
signal ui_state_changed(element: String, state: String)
signal all_ui_hidden
signal all_ui_shown
signal panel_opened(panel_name: String)
signal panel_closed(panel_name: String)
signal game_pause_changed(is_paused: bool)


# ================= UI 元素注册与控制 =================
func register_ui_element(element_name: String, node: Control) -> void:
	if not node:
		print("[UIManager] 错误：尝试注册空的UI元素 '%s'。" % element_name)
		return
	_ui_elements[element_name] = node
	print("[UIManager] UI元素已注册：%s" % element_name)


func set_ui_state(element: String, state: String, animation: String = "fade", duration: float = 0.3) -> void:
	if not _ui_elements.has(element):
		print("[UIManager] 错误：UI元素 '%s' 未注册。" % element)
		return

	var node: Control = _ui_elements[element]
	if not is_instance_valid(node):
		print("[UIManager] 错误：UI元素 '%s' 实例无效。" % element)
		return

	match state:
		"visible", "show":
			_show_element(node, animation, duration)
		"hidden", "hide", "invisible":
			_hide_element(node, animation, duration)
	ui_state_changed.emit(element, state)


func set_all_ui_visibility(visible: bool, animation: String = "fade", duration: float = 0.3) -> void:
	var elements_to_animate: Array[Control] = []
	for node in _ui_elements.values():
		if is_instance_valid(node):
			elements_to_animate.append(node)

	if elements_to_animate.is_empty():
		if visible:
			all_ui_shown.emit()
		else:
			all_ui_hidden.emit()
		return

	var tween = create_tween()
	tween.set_parallel(true)
	for node in elements_to_animate:
		if visible:
			node.modulate.a = 0.0
			node.show()
			tween.tween_property(node, "modulate:a", 1.0, duration)
		else:
			tween.tween_property(node, "modulate:a", 0.0, duration)

	tween.set_parallel(false)
	tween.tween_callback(func():
		if not visible:
			for node in elements_to_animate:
				if is_instance_valid(node):
					node.hide()
		if visible:
			all_ui_shown.emit()
		else:
			all_ui_hidden.emit()
	)


func _show_element(node: Control, animation: String, duration: float) -> void:
	match animation:
		"fade":
			node.modulate.a = 0.0
			node.show()
			var tween = create_tween()
			tween.tween_property(node, "modulate:a", 1.0, duration)
		_:
			node.show()


func _hide_element(node: Control, animation: String, duration: float) -> void:
	match animation:
		"fade":
			var tween = create_tween()
			tween.tween_property(node, "modulate:a", 0.0, duration)
			tween.tween_callback(func(): 
				if is_instance_valid(node):
					node.hide()
			)
		_:
			node.hide()


# ================= 面板管理 =================
func register_panel(panel_name: String, panel_node: Node) -> void:
	if not panel_node:
		print("[UIManager] 错误：尝试注册空的面板 '%s'。" % panel_name)
		return
	_panels[panel_name] = panel_node
	panel_node.visible = false
	print("[UIManager] UI面板已注册：%s" % panel_name)


func open_panel(panel_name: String) -> void:
	if not _panels.has(panel_name):
		print("[UIManager] 错误：未找到面板 '%s'。" % panel_name)
		return

	if _current_panel != "":
		close_panel(_current_panel, false)

	var panel: Node = _panels[panel_name]
	panel.visible = true

	_set_buttons_visible(false)
	if SaveManager.continue_mode:
		show_return_to_menu_button()
	else:
		hide_return_to_menu_button()
		if _return_button:
			_return_button.visible = true

	get_tree().paused = true
	if _return_button:
		_return_button.visible = true
	_current_panel = panel_name
	panel_opened.emit(panel_name)
	game_pause_changed.emit(true)
	print("[UIManager] 面板已打开：%s，游戏已暂停。" % panel_name)


func close_panel(panel_name: String, unpause: bool = true) -> void:
	if not _panels.has(panel_name):
		return

	var panel: Node = _panels[panel_name]
	panel.visible = false

	if unpause:
		_set_buttons_visible(true)
		if SaveManager.continue_mode:
			show_return_to_menu_button()
		else:
			hide_return_to_menu_button()
			if _return_button:
				_return_button.visible = false
		if _return_to_menu_active:
			show_return_to_menu_button()
		else:
			if _return_button:
				_return_button.visible = false

		await get_tree().create_timer(0.05).timeout
		get_tree().paused = false
		_current_panel = ""
		panel_closed.emit(panel_name)
		game_pause_changed.emit(false)
		print("[UIManager] 面板已关闭：%s，游戏已恢复。" % panel_name)
	else:
		if _panel_entry_buttons.has(panel_name):
			for btn in _panel_entry_buttons[panel_name]:
				if btn != null and btn is TextureButton:
					btn.visible = true
		_current_panel = ""
		panel_closed.emit(panel_name)


func close_current_panel() -> void:
	if _current_panel != "":
		close_panel(_current_panel)


func register_panel_entry_button(panel_name: String, button: TextureButton) -> void:
	if not button:
		return
	if not _panel_entry_buttons.has(panel_name):
		_panel_entry_buttons[panel_name] = []
	_panel_entry_buttons[panel_name].append(button)


# ================= HUD 按钮管理 =================
func register_hud_action_buttons(buttons: Array[TextureButton]) -> void:
	_hud_action_buttons = buttons


func set_return_button(button: TextureButton) -> void:
	_return_button = button
	if _return_button:
		_return_button.visible = false
		_return_button.process_mode = PROCESS_MODE_ALWAYS


func set_return_to_menu_button(button: TextureButton) -> void:
	_return_to_menu_button = button
	if _return_to_menu_button:
		_return_to_menu_button.visible = false
		_return_to_menu_button.process_mode = PROCESS_MODE_ALWAYS


func show_return_to_menu_button() -> void:
	_return_to_menu_active = true
	if _return_to_menu_button and is_instance_valid(_return_to_menu_button):
		_return_to_menu_button.visible = true
	if _return_button and is_instance_valid(_return_button):
		_return_button.visible = false


func hide_return_to_menu_button() -> void:
	_return_to_menu_active = false
	if _return_to_menu_button and is_instance_valid(_return_to_menu_button):
		_return_to_menu_button.visible = false


func _set_buttons_visible(visible: bool) -> void:
	for btn in _hud_action_buttons:
		if is_instance_valid(btn):
			btn.visible = visible
	for buttons in _panel_entry_buttons.values():
		for btn in buttons:
			if is_instance_valid(btn):
				btn.visible = visible


func get_return_button_rect() -> Rect2:
	if _return_button and is_instance_valid(_return_button):
		return Rect2(_return_button.global_position, _return_button.size)
	return Rect2()


func get_return_to_menu_button_rect() -> Rect2:
	if _return_to_menu_button and is_instance_valid(_return_to_menu_button):
		return Rect2(_return_to_menu_button.global_position, _return_to_menu_button.size)
	return Rect2()


# ================= CG 专用按钮控制 =================
func hide_hud_buttons_for_cg() -> void:
	for btn in _hud_action_buttons:
		if is_instance_valid(btn):
			btn.visible = false
	if has_node("/root/DialogueScene") and has_node("/root/DialogueScene/HUD/ButtonBar/SettingsButton"):
		var settings_btn = get_node("/root/DialogueScene/HUD/ButtonBar/SettingsButton")
		if is_instance_valid(settings_btn):
			settings_btn.visible = true
	if _return_button and is_instance_valid(_return_button):
		_return_button.visible = false


func restore_hud_buttons_after_cg() -> void:
	for btn in _hud_action_buttons:
		if is_instance_valid(btn):
			btn.visible = true
	if _return_button and is_instance_valid(_return_button):
		_return_button.visible = false
