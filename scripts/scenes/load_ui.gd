# load_ui.gd
extends CanvasLayer

const MAX_PAGES = 9
const SLOTS_PER_PAGE = 6
const MAX_SLOTS = 20

var _current_page: int = 0
var _slot_buttons: Array[TextureButton] = []
var _page_buttons: Array[TextureButton] = []

@onready var slot_grid: GridContainer = $SlotGrid
@onready var left_arrow: TextureButton = $PageNav/LeftArrow
@onready var right_arrow: TextureButton = $PageNav/RightArrow
@onready var page_buttons_grid: GridContainer = $PageNav/PageButtons
@onready var switch_btn: TextureButton = $SwitchButton

var _pending_delete_slot: int = -1

func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	# 从主界面进入读档时，隐藏切换按钮
	if SaveManager.continue_mode:
		switch_btn.visible = false
	else:
		switch_btn.visible = true

	_slot_buttons.clear()
	for child in slot_grid.get_children():
		if child is TextureButton:
			child.pressed.connect(_on_slot_pressed.bind(_slot_buttons.size()))
			var del_btn = child.get_node_or_null("DeleteBtn") as TextureButton
			if del_btn:
				del_btn.pressed.connect(_on_delete_pressed.bind(_slot_buttons.size()))
			_slot_buttons.append(child)

	_page_buttons.clear()
	for child in page_buttons_grid.get_children():
		if child is TextureButton:
			var page_num = child.get_meta("page", -1)
			if page_num >= 0:
				child.pressed.connect(_on_page_button_pressed.bind(page_num))
				_page_buttons.append(child)

	left_arrow.pressed.connect(_on_left_arrow)
	right_arrow.pressed.connect(_on_right_arrow)
	switch_btn.pressed.connect(_on_switch_pressed)

	_refresh_page()

func _refresh_page() -> void:
	for i in range(_slot_buttons.size()):
		var slot_index = _current_page * SLOTS_PER_PAGE + i
		var btn = _slot_buttons[i]
		var thumbnail = btn.get_node_or_null("Thumbnail") as TextureRect
		var info_bg = btn.get_node_or_null("InfoBg") as TextureRect
		var info_label = btn.get_node_or_null("Info") as Label
		var del_btn = btn.get_node_or_null("DeleteBtn") as TextureButton

		if slot_index < MAX_SLOTS:
			var info = SaveManager.get_save_info(slot_index)
			if info.get("exists", false):
				if thumbnail:
					var thumb_path = info.get("thumbnail", "")
					if thumb_path != "" and FileAccess.file_exists(thumb_path):
						var img = Image.load_from_file(thumb_path)
						if img:
							thumbnail.texture = ImageTexture.create_from_image(img)
					else:
						thumbnail.texture = null
				if info_label:
					info_label.text = "No.%03d  %s %s" % [slot_index + 1, info.get("date", ""), info.get("time", "")]
				if info_bg:
					info_bg.visible = true
				if del_btn:
					del_btn.visible = true
					del_btn.disabled = false
			else:
				if thumbnail:
					thumbnail.texture = null
				if info_label:
					info_label.text = "空白存档"
				if info_bg:
					info_bg.visible = false
				if del_btn:
					del_btn.visible = false
			btn.disabled = false
		else:
			btn.disabled = true

	for child in page_buttons_grid.get_children():
		if child is TextureButton:
			var page = child.get_meta("page", -1)
			if page >= 0 and page < MAX_PAGES:
				child.modulate = Color.YELLOW if page == _current_page else Color.WHITE

	left_arrow.disabled = (_current_page == 0)
	right_arrow.disabled = (_current_page == MAX_PAGES - 1)

func _on_slot_pressed(idx: int) -> void:
	var slot = _current_page * SLOTS_PER_PAGE + idx
	if slot < MAX_SLOTS and SaveManager.has_save(slot):
		var scene = get_tree().current_scene
		if scene and scene.has_method("hide_long_dialogue"):
			scene.hide_long_dialogue()
		CharacterManager.clear_stage()
		SaveManager.load_game(slot)
		UIManager.close_panel("LoadUI")
		SaveManager.continue_mode = false
		UIManager.hide_return_to_menu_button()
		switch_btn.visible = true

func _on_delete_pressed(idx: int) -> void:
	_pending_delete_slot = _current_page * SLOTS_PER_PAGE + idx
	if SaveManager.has_save(_pending_delete_slot):
		var info = SaveManager.get_save_info(_pending_delete_slot)
		var time_str = ""
		if info.get("exists", false):
			time_str = "存档时间：" + info.get("date", "") + " " + info.get("time", "")
		else:
			time_str = "存档时间：未知"

		var tip_panel = UIManager._panels.get("TipUI")
		if tip_panel and tip_panel.has_method("show_tip"):
			tip_panel.show_tip("是否删除存档？\n" + time_str, "确认", "取消", false)

			if tip_panel.confirmed.is_connected(_on_delete_confirmed):
				tip_panel.confirmed.disconnect(_on_delete_confirmed)
			if tip_panel.canceled.is_connected(_on_delete_cancelled):
				tip_panel.canceled.disconnect(_on_delete_cancelled)

			tip_panel.confirmed.connect(_on_delete_confirmed, CONNECT_ONE_SHOT)
			tip_panel.canceled.connect(_on_delete_cancelled, CONNECT_ONE_SHOT)

		tip_panel.visible = true
		_set_return_buttons_visible(false)

func _on_delete_confirmed() -> void:
	if _pending_delete_slot >= 0:
		SaveManager.delete_save(_pending_delete_slot)
		_compact_slots(_pending_delete_slot)
		_pending_delete_slot = -1
		_refresh_page()
	_hide_tip()

func _on_delete_cancelled() -> void:
	_pending_delete_slot = -1
	_hide_tip()

func _hide_tip() -> void:
	var tip_panel = UIManager._panels.get("TipUI")
	if tip_panel:
		tip_panel.visible = false
	_set_return_buttons_visible(true)

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

func _compact_slots(deleted_slot: int) -> void:
	for i in range(deleted_slot + 1, MAX_SLOTS):
		if SaveManager.has_save(i):
			var src_path = SaveManager._get_save_path(i)
			var dst_path = SaveManager._get_save_path(i - 1)
			var file = FileAccess.open(src_path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				file.close()
				var dst_file = FileAccess.open(dst_path, FileAccess.WRITE)
				if dst_file:
					dst_file.store_string(content)
					dst_file.close()
			DirAccess.remove_absolute(src_path)

			var src_thumb = SaveManager._get_thumbnail_path(i)
			var dst_thumb = SaveManager._get_thumbnail_path(i - 1)
			if FileAccess.file_exists(src_thumb):
				var img = Image.load_from_file(src_thumb)
				if img:
					img.save_png(dst_thumb)
				DirAccess.remove_absolute(src_thumb)

	var last_path = SaveManager._get_save_path(MAX_SLOTS - 1)
	if FileAccess.file_exists(last_path):
		DirAccess.remove_absolute(last_path)
	var last_thumb = SaveManager._get_thumbnail_path(MAX_SLOTS - 1)
	if FileAccess.file_exists(last_thumb):
		DirAccess.remove_absolute(last_thumb)

func _on_page_button_pressed(page: int) -> void:
	_current_page = page
	_refresh_page()

func _on_left_arrow() -> void:
	if _current_page > 0:
		_current_page -= 1
		_refresh_page()

func _on_right_arrow() -> void:
	if _current_page < MAX_PAGES - 1:
		_current_page += 1
		_refresh_page()

func _on_switch_pressed() -> void:
	UIManager.close_panel("LoadUI", false)
	UIManager.open_panel("SaveUI")
