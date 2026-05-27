# settings_ui.gd
extends CanvasLayer

# ================= 节点引用 =================
@onready var text_speed_slider: HSlider = $VBoxContainerL/SpeedContainer/TextSpeedContainer/TextSpeed
@onready var auto_speed_slider: HSlider = $VBoxContainerL/SpeedContainer/AutoSpeedContainer/AutoSpeed
@onready var bgm_volume_slider: HSlider = $VBoxContainerR/VolumeContainer/BGMVolumeContainer/BGMVolume
@onready var sfx_volume_slider: HSlider = $VBoxContainerR/VolumeContainer/SFXVolumeContainer/SFXVolume
@onready var voice_volume_slider: HSlider = $VBoxContainerR/VolumeContainer/VoiceVolumeContainer/VoiceVolume
@onready var fullscreen_check: CheckButton = $VBoxContainerL/FullscreenContainer/Fullscreen
@onready var ui_sound_toggle: CheckButton = $VBoxContainerR/VolumeContainer/SFXContainer/SFXToggle
@onready var clear_save_btn = $VBoxContainerL/LockContainer/ClearSaveContainer/ClearSave

# ================= 初始化 =================
func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_load_settings()
	_connect_signals()
	
	UIManager.panel_opened.connect(_on_panel_opened)


func _connect_signals() -> void:
	text_speed_slider.value_changed.connect(_on_text_speed_changed)
	auto_speed_slider.value_changed.connect(_on_auto_speed_changed)
	bgm_volume_slider.value_changed.connect(_on_bgm_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	if clear_save_btn:
		clear_save_btn.pressed.connect(_on_reset_unlocks)
	if ui_sound_toggle:
		ui_sound_toggle.toggled.connect(_on_ui_sound_toggled)


# ================= 设置读写 =================
func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		var saved_speed = config.get_value("dialogue", "text_speed", 0.05)
		var slider_value = text_speed_slider.max_value + text_speed_slider.min_value - saved_speed
		text_speed_slider.value = clamp(slider_value, text_speed_slider.min_value, text_speed_slider.max_value)
		auto_speed_slider.value = config.get_value("dialogue", "auto_speed", 2.0)
		bgm_volume_slider.value = config.get_value("audio", "bgm_volume", 0.0)
		sfx_volume_slider.value = config.get_value("audio", "sfx_volume", 0.0)
		voice_volume_slider.value = config.get_value("audio", "voice_volume", 0.0)
		fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
	else:
		text_speed_slider.value = 0.05
		auto_speed_slider.value = 2.0
		bgm_volume_slider.value = 0.0
		sfx_volume_slider.value = 0.0
		voice_volume_slider.value = 0.0
		fullscreen_check.button_pressed = false


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("dialogue", "text_speed", GameManager.text_speed)
	config.set_value("dialogue", "auto_speed", auto_speed_slider.value)
	config.set_value("audio", "bgm_volume", bgm_volume_slider.value)
	config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	config.set_value("audio", "voice_volume", voice_volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.save("user://settings.cfg")


# ================= 信号回调 =================
func _on_text_speed_changed(value: float) -> void:
	var actual_speed = text_speed_slider.max_value + text_speed_slider.min_value - value
	if GameManager:
		GameManager.text_speed = actual_speed
	var scene = get_tree().current_scene
	if scene and scene.has_method("update_text_speed"):
		scene.update_text_speed(actual_speed)
	_save_settings()
	

func _on_auto_speed_changed(value: float) -> void:
	GameManager.set_variable("auto_speed", value)
	_save_settings()


func _on_bgm_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), value)
	_save_settings()


func _on_sfx_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), value)
	_save_settings()


func _on_voice_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), value)
	_save_settings()


func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


func _on_reset_unlocks() -> void:
	if GameManager:
		GameManager.reset_all_unlocks()
		
		
func _on_ui_sound_toggled(button_pressed: bool) -> void:
	if SFXManager:
		SFXManager.set_enabled(button_pressed)
		
		
func _on_panel_opened(panel_name: String) -> void:
	if panel_name == "SettingsUI":
		if ui_sound_toggle and SFXManager:
			ui_sound_toggle.button_pressed = SFXManager.enabled
