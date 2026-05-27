# main_menu.gd
extends Control

# ================= 节点引用 =================
@onready var new_game_btn: TextureButton = $VBoxContainer/NewGameButton
@onready var continue_btn: TextureButton = $VBoxContainer/ContinueButton
@onready var settings_btn: TextureButton = $VBoxContainer/SettingsButton
@onready var quit_btn: TextureButton = $VBoxContainer/QuitButton
@onready var gallery_btn = $VBoxContainer/GalleryButton


# ================= 初始化 =================
func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)
	gallery_btn.pressed.connect(_on_gallery)

	continue_btn.disabled = not SaveManager.has_any_save()


# ================= 按钮回调 =================
func _on_new_game() -> void:
	if ScriptEngine:
		ScriptEngine.hard_reset()

	if get_tree().paused:
		get_tree().paused = false

	GameManager.start_new_game()

	if has_node("/root/BackgroundManager"):
		var bg_manager = get_node("/root/BackgroundManager")
		bg_manager.current_background_id = ""

	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_continue() -> void:
	SaveManager.continue_mode = true
	GameManager.dialogue_history.clear()
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_settings() -> void:
	GameManager.open_settings_on_load = true
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_gallery():
	GameManager.open_gallery_on_load = true
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_quit() -> void:
	get_tree().quit()
