# sfx_manager.gd
extends Node

const SETTINGS_PATH = "user://settings.cfg"

# ================= 音效资源 =================
var sfx_option: AudioStream
var sfx_continue: AudioStream
var sfx_settings: AudioStream
var sfx_generic: AudioStream

# ================= 内部播放器 =================
var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var enabled: bool = true

func _enter_tree() -> void:
	sfx_option = load("res://assets/audio/sfx/interface_audio/select_005.ogg")
	sfx_continue = load("res://assets/audio/sfx/interface_audio/bong_001.ogg")
	sfx_settings = load("res://assets/audio/sfx/interface_audio/switch_001.ogg")
	sfx_generic = load("res://assets/audio/sfx/ui_audio/mouseclick1.ogg")

	# 创建播放器
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	add_child(_player)

	var stream = AudioStreamPolyphonic.new()
	stream.polyphony = 32
	_player.stream = stream
	_player.play()
	_playback = _player.get_stream_playback()
	
	_load_enabled_state()

	# 监听所有新加入场景树的节点
	get_tree().node_added.connect(_on_node_added)

	print("[SFXManager] UI音效管理器已就绪，四种音效已加载。")
	
	
func _load_enabled_state() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		enabled = config.get_value("audio", "ui_sound_enabled", true)
	else:
		enabled = true


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		_player.volume_db = 0.0
		_player.stream_paused = false
	else:
		_player.volume_db = -80.0
		_player.stream_paused = true
	var config = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "ui_sound_enabled", enabled)
	config.save(SETTINGS_PATH)
	print("[SFXManager] 按钮音效已%s" % ("启用" if enabled else "禁用"))


func _on_node_added(node: Node) -> void:
	# 只处理按钮类节点
	if not (node is Button or node is TextureButton):
		return

	# 根据按钮名称分配音效
	if node.name in ["Choice1", "Choice2", "Choice3"]:
		if not node.pressed.is_connected(_play_option):
			node.pressed.connect(_play_option)
		print("[SFXManager] 为选项按钮 '%s' 绑定音效A" % node.name)
	elif node.name == "SettingsButton":
		if not node.pressed.is_connected(_play_settings):
			node.pressed.connect(_play_settings)
		print("[SFXManager] 为设置按钮绑定音效C")
	else:
		if not node.pressed.is_connected(_play_generic):
			node.pressed.connect(_play_generic)
		print("[SFXManager] 为通用按钮 '%s' 绑定音效D" % node.name)


# ================= 播放函数 =================
func _play_option() -> void:
	if not enabled:
		return
	if sfx_option:
		_playback.play_stream(sfx_option, 0, 0, randf_range(0.95, 1.05))


func _play_settings() -> void:
	if not enabled:
		return
	if sfx_settings:
		_playback.play_stream(sfx_settings, 0, 0, randf_range(0.95, 1.05))


func _play_generic() -> void:
	if not enabled:
		return
	if sfx_generic:
		_playback.play_stream(sfx_generic, 0, 0, randf_range(0.95, 1.05))


func play_continue_sfx() -> void:
	if not enabled:
		return
	if sfx_continue:
		_playback.play_stream(sfx_continue, 0, 0, randf_range(0.95, 1.05))
		print("[SFXManager] 播放对话继续音效")
