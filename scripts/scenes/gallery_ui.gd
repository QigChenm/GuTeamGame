# gallery_ui.gd
extends CanvasLayer

@export var custom_font: Font

# 页面容器
@onready var cg_page: Control = $CGPage
@onready var music_page: Control = $MusicPage

# CG 区域
@onready var cg_grid: GridContainer = $CGPage/CGGrid
@onready var cg_left_arrow: TextureButton = $CGPage/PageNav/LeftArrow
@onready var cg_right_arrow: TextureButton = $CGPage/PageNav/RightArrow
@onready var cg_page_buttons_grid: GridContainer = $CGPage/PageNav/PageButtons

# 音乐区域
@onready var music_list: ItemList = $MusicPage/MusicList
@onready var play_btn: TextureButton = $MusicPage/PlayBtn
@onready var stop_btn: TextureButton = $MusicPage/StopBtn
@onready var now_playing: RichTextLabel = $MusicPage/NowPlaying
@onready var preview_player: AudioStreamPlayer = $PreviewPlayer

# 切换按钮
@onready var cg_tab_btn: TextureButton = $HBoxContainer/CGTabBtn
@onready var music_tab_btn: TextureButton = $HBoxContainer/MusicTabBtn

const SLOT_WIDTH = 524
const SLOT_HEIGHT = 300

var _cg_slots: Array[TextureRect] = []
var _cg_page_buttons: Array[TextureButton] = []
var _current_cg_page: int = 0
var _cg_preview_popup: Popup = null
var _cg_data_ids: Array = []
const CG_SLOTS_PER_PAGE = 6

func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_init_preview_player()
	_apply_fonts()
	_collect_cg_slots()
	_collect_cg_page_buttons()
	_connect_signals()
	_refresh_cg_page()
	_refresh_music_page()

	if AudioManager:
		print("[GalleryUI] 音频数据库大小：%d" % AudioManager.audio_database.size())


func _init_preview_player() -> void:
	if not preview_player:
		preview_player = AudioStreamPlayer.new()
		preview_player.name = "PreviewPlayer"
		preview_player.bus = "Music"
		preview_player.process_mode = PROCESS_MODE_ALWAYS
		add_child(preview_player)
	else:
		preview_player.bus = "Music"
		preview_player.process_mode = PROCESS_MODE_ALWAYS


func _apply_fonts() -> void:
	pass


func _collect_cg_slots() -> void:
	_cg_slots.clear()
	for child in cg_grid.get_children():
		if child is TextureRect:
			_cg_slots.append(child)
			# 强制开启鼠标检测，确保能接收点击
			child.mouse_filter = Control.MOUSE_FILTER_STOP


func _collect_cg_page_buttons() -> void:
	_cg_page_buttons.clear()
	for child in cg_page_buttons_grid.get_children():
		if child is TextureButton:
			var page_num = child.get_meta("page", -1)
			if page_num >= 0:
				child.pressed.connect(_on_cg_page_button_pressed.bind(page_num))
				_cg_page_buttons.append(child)
	cg_left_arrow.pressed.connect(_on_cg_left_arrow)
	cg_right_arrow.pressed.connect(_on_cg_right_arrow)


func _connect_signals() -> void:
	cg_tab_btn.pressed.connect(_on_cg_tab_pressed)
	music_tab_btn.pressed.connect(_on_music_tab_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	music_list.item_activated.connect(_on_music_item_activated)
	GameManager.cg_unlocked.connect(_on_cg_unlocked)
	GameManager.bgm_unlocked.connect(_on_bgm_unlocked)
	UIManager.panel_opened.connect(_on_gallery_opened)
	UIManager.panel_closed.connect(_on_gallery_closed)


func _on_cg_tab_pressed() -> void:
	cg_page.visible = true
	music_page.visible = false
	_refresh_cg_page()


func _on_music_tab_pressed() -> void:
	cg_page.visible = false
	music_page.visible = true
	_refresh_music_page()


# ================= CG 鉴赏 =================
func _refresh_cg_page() -> void:
	_cg_data_ids.clear()
	if CGManager:
		_cg_data_ids = CGManager.cg_database.keys()
	var total_pages = max(1, ceil(float(_cg_data_ids.size()) / CG_SLOTS_PER_PAGE))
	_current_cg_page = clamp(_current_cg_page, 0, total_pages - 1)

	for i in range(_cg_slots.size()):
		var global_idx = _current_cg_page * CG_SLOTS_PER_PAGE + i
		var slot = _cg_slots[i]
		var thumbnail = slot.get_node_or_null("Thumbnail") as TextureRect
		var info_bg = slot.get_node_or_null("InfoBg") as TextureRect
		var info_label = slot.get_node_or_null("Info") as Label

		# 先断开之前可能绑定的 gui_input 信号，避免重复绑定
		_disconnect_slot_input(slot)

		if global_idx < _cg_data_ids.size():
			var cg_id = _cg_data_ids[global_idx]
			var is_unlocked = GameManager.is_cg_unlocked(cg_id)
			slot.visible = true
			if is_unlocked:
				var data: CGData = CGManager.cg_database[cg_id]
				if thumbnail:
					var original_img = data.texture.get_image()
					if original_img:
						var scale = min(float(SLOT_WIDTH) / original_img.get_width(),
										float(SLOT_HEIGHT) / original_img.get_height())
						var new_width = int(original_img.get_width() * scale)
						var new_height = int(original_img.get_height() * scale)
						original_img.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
						thumbnail.texture = ImageTexture.create_from_image(original_img)
				if info_label:
					info_label.text = data.display_name if data.display_name != "" else cg_id
				if info_bg:
					info_bg.visible = true
				# 绑定点击预览信号
				slot.gui_input.connect(_on_cg_slot_clicked.bind(cg_id), CONNECT_ONE_SHOT)
			else:
				if thumbnail:
					thumbnail.texture = null
				if info_label:
					info_label.text = "???（未解锁）"
				if info_bg:
					info_bg.visible = false
		else:
			slot.visible = false

	# 更新页码按钮
	for i in range(_cg_page_buttons.size()):
		var btn = _cg_page_buttons[i]
		btn.visible = i < total_pages
		if i < total_pages:
			btn.modulate = Color.YELLOW if i == _current_cg_page else Color.WHITE
	cg_left_arrow.disabled = (_current_cg_page == 0)
	cg_right_arrow.disabled = (_current_cg_page >= total_pages - 1)


func _disconnect_slot_input(slot: Control) -> void:
	# 辅助方法：清除所有已连接的 gui_input 信号（避免累积）
	for connection in slot.gui_input.get_connections():
		slot.gui_input.disconnect(connection.callable)


func _on_cg_slot_clicked(event: InputEvent, cg_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		_show_cg_preview(cg_id)


func _show_cg_preview(cg_id: String) -> void:
	if not _cg_preview_popup:
		_cg_preview_popup = Popup.new()
		_cg_preview_popup.name = "CGPreviewPopup"
		_cg_preview_popup.process_mode = PROCESS_MODE_ALWAYS

		var bg = ColorRect.new()
		bg.name = "Background"
		bg.color = Color(0, 0, 0, 0.7)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		bg.gui_input.connect(_on_preview_background_clicked)
		_cg_preview_popup.add_child(bg)

		var img = TextureRect.new()
		img.name = "PreviewImage"
		img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.anchor_left = 0.5
		img.anchor_right = 0.5
		img.anchor_top = 0.5
		img.anchor_bottom = 0.5
		img.offset_left = -600
		img.offset_right = 600
		img.offset_top = -400
		img.offset_bottom = 400
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cg_preview_popup.add_child(img)

		add_child(_cg_preview_popup)

	var preview_image = _cg_preview_popup.get_node("PreviewImage") as TextureRect
	preview_image.texture = CGManager.cg_database[cg_id].texture
	_cg_preview_popup.show()


func _on_preview_background_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_cg_preview_popup.hide()


func _on_cg_page_button_pressed(page: int) -> void:
	_current_cg_page = page
	_refresh_cg_page()


func _on_cg_left_arrow() -> void:
	if _current_cg_page > 0:
		_current_cg_page -= 1
		_refresh_cg_page()


func _on_cg_right_arrow() -> void:
	var total_pages = max(1, ceil(float(_cg_data_ids.size()) / CG_SLOTS_PER_PAGE))
	if _current_cg_page < total_pages - 1:
		_current_cg_page += 1
		_refresh_cg_page()


# ================= 音乐鉴赏 =================
func _refresh_music_page() -> void:
	music_list.clear()
	if not AudioManager:
		return
	for audio_id in AudioManager.audio_database.keys():
		var data: AudioData = AudioManager.audio_database[audio_id]
		if data.audio_type != AudioData.AudioType.BGM:
			continue
		var is_unlocked = GameManager.is_bgm_unlocked(audio_id)
		var display_name = "？？？" if not is_unlocked else (data.display_name if "display_name" in data and data.display_name != "" else audio_id)
		var idx = music_list.add_item(display_name)
		music_list.set_item_metadata(idx, audio_id)
		music_list.set_item_disabled(idx, not is_unlocked)


func _play_selected_music() -> void:
	var selected = music_list.get_selected_items()
	if selected.is_empty():
		return
	var idx = selected[0]
	var audio_id = music_list.get_item_metadata(idx)
	if not GameManager.is_bgm_unlocked(audio_id):
		now_playing.text = "曲目未解锁"
		return
	if not AudioManager or not AudioManager.audio_database.has(audio_id):
		now_playing.text = "无法播放：音频数据不存在"
		return
	var audio_data: AudioData = AudioManager.audio_database[audio_id]
	if audio_data.stream:
		preview_player.stream = audio_data.stream
		preview_player.play()
		now_playing.text = "[wave amp=40.0 freq=3.0]正在播放：%s[/wave]" % music_list.get_item_text(idx)


func _on_play_pressed() -> void:
	_play_selected_music()


func _on_music_item_activated(_idx: int) -> void:
	_play_selected_music()


func _on_stop_pressed() -> void:
	preview_player.stop()
	now_playing.text = "已停止"


# ================= 背景音乐暂停/恢复 =================
func _on_gallery_opened(panel_name: String) -> void:
	if panel_name != "GalleryUI":
		return
	if AudioManager:
		var bgm_player = AudioManager.get_bgm_player()
		if bgm_player and bgm_player.playing:
			bgm_player.stream_paused = true


func _on_gallery_closed(panel_name: String) -> void:
	if panel_name != "GalleryUI":
		return
	preview_player.stop()
	now_playing.text = ""
	if AudioManager:
		var bgm_player = AudioManager.get_bgm_player()
		if bgm_player and bgm_player.stream_paused:
			bgm_player.stream_paused = false


# ================= 解锁刷新 =================
func _on_cg_unlocked(_cg_id: String) -> void:
	if cg_page.visible:
		_refresh_cg_page()


func _on_bgm_unlocked(_bgm_id: String) -> void:
	if music_page.visible:
		_refresh_music_page()
