# main_menu.gd
extends Control

# ================= 节点引用 =================
@onready var new_game_btn: TextureButton = $VBoxContainer/NewGameButton
@onready var continue_btn: TextureButton = $VBoxContainer/ContinueButton
@onready var settings_btn: TextureButton = $VBoxContainer/SettingsButton
@onready var quit_btn: TextureButton = $VBoxContainer/QuitButton
@onready var gallery_btn = $VBoxContainer/GalleryButton
@onready var about_btn = $VBoxContainer/InfoButton
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var mute_button: TextureButton = $MuteButton

var is_muted: bool = true

# ================= 初始化 =================
func _ready() -> void:
	bgm_player.volume_db = -20
	bgm_player.play()
	var fade_in = create_tween()
	fade_in.tween_property(bgm_player, "volume_db", 0.0, 1.5)
	var white_rect = ColorRect.new()
	white_rect.color = Color.WHITE
	white_rect.modulate.a = 1.0
	white_rect.size = get_viewport().get_visible_rect().size
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.add_child(white_rect)
	add_child(canvas_layer)
	
	var fade_tween = create_tween()
	fade_tween.tween_property(white_rect, "modulate:a", 0.0, 2.0)
	fade_tween.tween_callback(func():
		canvas_layer.queue_free()
	)
	
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)
	gallery_btn.pressed.connect(_on_gallery)
	about_btn.pressed.connect(_on_about)
	mute_button.pressed.connect(_on_mute_pressed)
	
	if bgm_player and not bgm_player.playing:
		bgm_player.play()
	var ginkgo_particles = preload("res://assets/particles/Ginkgo.tscn").instantiate()
	add_child(ginkgo_particles)

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


func _on_about():
	GameManager.open_about_on_load = true
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_quit() -> void:
	get_tree().quit()

# ================= 辅助功能 =================
func _on_mute_pressed() -> void:
	is_muted = !is_muted
	if bgm_player:
		bgm_player.playing = is_muted
