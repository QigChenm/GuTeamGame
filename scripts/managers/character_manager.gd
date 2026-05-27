# character_manager.gd
extends Node

# ================= 信号 =================
signal action_completed()
signal entrances_completed
signal exits_completed

# ================= 属性 =================
var _sprites: Dictionary = {}             # key = "left"/"right", value = CharacterDisplay 节点
var _active_roles: Dictionary = {}        # key = "left"/"right", value = {"character_id": String, "data": CharacterData}

# 入场计数器
var _pending_entrances: int = 0


# ================= 初始化 =================
func _ready() -> void:
	print("[CharacterManager] 就绪（等待场景注册舞台精灵）")


# ================= 注册 =================
func register_sprite(position: String, sprite: CharacterDisplay) -> void:
	if position != "left" and position != "right":
		print("[CharacterManager] 注册失败：位置必须是 'left' 或 'right'。")
		return
	_sprites[position] = sprite
	print("[CharacterManager] 已注册 %s 侧舞台精灵。" % position)


# ================= 角色放置与入场 =================
func set_characters_on_stage(left = null, right = null, entrance_animation: String = "fade") -> void:
	_pending_entrances = 0

	# 确定哪些位置需要保留角色
	var keep_left := false
	var keep_right := false
	if left != null:
		var id = left if typeof(left) != TYPE_DICTIONARY else left.get("id", "")
		keep_left = not id.is_empty()
	if right != null:
		var id = right if typeof(right) != TYPE_DICTIONARY else right.get("id", "")
		keep_right = not id.is_empty()

	# 移除不需要保留的位置上的旧角色
	if not keep_left and _active_roles.has("left"):
		_remove_role_silently("left", _active_roles["left"]["character_id"])
	if not keep_right and _active_roles.has("right"):
		_remove_role_silently("right", _active_roles["right"]["character_id"])

	# 处理左侧新角色
	if left != null:
		var left_id = left
		var left_expr := "default"
		var left_anim := entrance_animation
		if typeof(left) == TYPE_DICTIONARY:
			left_id = left.get("id", "")
			left_expr = left.get("expression", "default")
			left_anim = left.get("entrance_animation", entrance_animation)
		if not left_id.is_empty():
			if _active_roles.has("left"):
				_remove_role_silently("left", _active_roles["left"]["character_id"])
			_pending_entrances += 1
			_set_role("left", left_id, left_expr, left_anim)

	# 处理右侧新角色
	if right != null:
		var right_id = right
		var right_expr := "default"
		var right_anim := entrance_animation
		if typeof(right) == TYPE_DICTIONARY:
			right_id = right.get("id", "")
			right_expr = right.get("expression", "default")
			right_anim = right.get("entrance_animation", entrance_animation)
		if not right_id.is_empty():
			if _active_roles.has("right"):
				_remove_role_silently("right", _active_roles["right"]["character_id"])
			_pending_entrances += 1
			_set_role("right", right_id, right_expr, right_anim)

	# 没有角色需要入场时立即通知
	if _pending_entrances == 0:
		entrances_completed.emit()


func _set_role(position: String, character_id: String, initial_expression: String = "default", entrance_animation: String = "fade") -> void:
	if not _sprites.has(position):
		print("[CharacterManager] 错误：%s 侧精灵未注册，无法设置角色。" % position)
		_pending_entrances -= 1
		if _pending_entrances <= 0:
			entrances_completed.emit()
		return
	if not GameManager.character_database.has(character_id):
		print("[CharacterManager] 错误：角色 '%s' 不在数据库中。" % character_id)
		_pending_entrances -= 1
		if _pending_entrances <= 0:
			entrances_completed.emit()
		return

	var char_data: CharacterData = GameManager.character_database[character_id]
	var sprite: CharacterDisplay = _sprites[position]
	if not sprite:
		print("[CharacterManager] 错误：%s 侧精灵实例无效。" % position)
		_pending_entrances -= 1
		if _pending_entrances <= 0:
			entrances_completed.emit()
		return

	# 初始化角色数据（内部会设置 modulate.a = 0）
	sprite.initialize(char_data, position, initial_expression)
	_active_roles[position] = {"character_id": character_id, "data": char_data}

	if not sprite.is_connected("entrance_finished", _on_entrance_done):
		sprite.connect("entrance_finished", _on_entrance_done, CONNECT_ONE_SHOT)

	sprite.play_entrance_animation(entrance_animation)
	print("[CharacterManager] 角色 '%s' 已放置在 %s 侧，初始表情: %s" % [char_data.display_name, position, initial_expression])


func _on_entrance_done() -> void:
	_pending_entrances -= 1
	if _pending_entrances <= 0:
		_pending_entrances = 0
		entrances_completed.emit()


# ================= 表情切换 =================
func set_expression(character_id: String, expression_id: String) -> void:
	var target_position := ""
	for pos in _active_roles:
		if _active_roles[pos]["character_id"] == character_id:
			target_position = pos
			break

	if target_position == "":
		print("[CharacterManager] 设置表情失败：角色 '%s' 不在舞台上。" % character_id)
		return

	var sprite: CharacterDisplay = _sprites.get(target_position)
	if not sprite:
		print("[CharacterManager] 设置表情失败：%s 侧精灵未注册。" % target_position)
		return

	sprite.set_expression(expression_id)
	print("[CharacterManager] 角色 '%s' 表情已切换为 %s" % [character_id, expression_id])


# ================= 舞台清理 =================
func hide_all_characters() -> void:
	for pos in _active_roles:
		var sprite: CharacterDisplay = _sprites.get(pos)
		if sprite:
			sprite.hide()  # 直接隐藏节点，但保留 _active_roles
	print("[CharacterManager] 所有角色已临时隐藏。")


func show_all_characters() -> void:
	for pos in _active_roles:
		var sprite: CharacterDisplay = _sprites.get(pos)
		if sprite:
			sprite.show()
			# 确保呼吸动画等继续
			sprite.start_idle()
	print("[CharacterManager] 所有角色已重新显示。")


func _clear_all_roles_without_animation() -> void:
	for pos in _sprites:
		var sprite: CharacterDisplay = _sprites[pos]
		sprite.hide_character()
	_active_roles.clear()


func clear_stage() -> void:
	_clear_all_roles_without_animation()
	exits_completed.emit()
	print("[CharacterManager] 舞台已立即清空。")


func _remove_role_silently(position: String, character_id: String) -> void:
	if _sprites.has(position):
		var sprite: CharacterDisplay = _sprites[position]
		sprite.hide_character()
	_active_roles.erase(position)
	print("[CharacterManager] 静默移除 %s 侧的旧角色 '%s'" % [position, character_id])


func remove_character(character_id: String) -> void:
	var target_pos := ""
	for pos in _active_roles:
		if _active_roles[pos]["character_id"] == character_id:
			target_pos = pos
			break
	if target_pos != "":
		var sprite: CharacterDisplay = _sprites[target_pos]
		sprite.hide_character()
		_active_roles.erase(target_pos)


# ================= 角色动作 =================
func play_action(character_id: String, action_name: String) -> void:
	var target_pos := ""
	for pos in _active_roles:
		if _active_roles[pos]["character_id"] == character_id:
			target_pos = pos
			break
	if target_pos == "":
		print("[CharacterManager] 播放动作失败：角色 '%s' 不在舞台上。" % character_id)
		action_completed.emit()
		return

	var sprite: CharacterDisplay = _sprites[target_pos]
	if not sprite.action_finished.is_connected(_on_character_action_finished):
		sprite.action_finished.connect(_on_character_action_finished.bind(character_id), CONNECT_ONE_SHOT)
	sprite.play_action(action_name)


func _on_character_action_finished(character_id: String) -> void:
	print("[CharacterManager] 角色 '%s' 的动作已完成。" % character_id)
	action_completed.emit()


# ================= 存档/读档 =================
func get_active_roles_data() -> Dictionary:
	var data := {
		"left": null,
		"right": null
	}
	for pos in _active_roles:
		var info = _active_roles[pos]
		var char_id = info.get("character_id", "")
		if char_id == "":
			continue
		var expr := "default"
		var sprite = _sprites.get(pos)
		if sprite:
			expr = sprite.current_expression
		data[pos] = {
			"id": char_id,
			"expression": expr
		}
	return data


func restore_characters(data: Dictionary) -> void:
	_clear_all_roles_without_animation()

	for pos in ["left", "right"]:
		var info = data.get(pos)
		if info == null or not info is Dictionary:
			continue
		var char_id: String = info.get("id", "")
		var expr: String = info.get("expression", "default")
		if char_id == "":
			continue
		if not GameManager.character_database.has(char_id):
			continue
		if not _sprites.has(pos):
			continue

		var char_data: CharacterData = GameManager.character_database[char_id]
		var sprite: CharacterDisplay = _sprites[pos]
		sprite.initialize(char_data, pos, expr)
		sprite.modulate.a = 1.0
		sprite.visible = true
		if sprite.animated_sprite:
			sprite.animated_sprite.visible = false
		_active_roles[pos] = {"character_id": char_id, "data": char_data}

	print("[CharacterManager] 角色恢复完成：活跃角色数 = %d" % _active_roles.size())


func restore_characters_by_position(positions_dict: Dictionary, expressions: Dictionary) -> void:
	_clear_all_roles_without_animation()
	for pos in positions_dict:
		var char_id = positions_dict[pos]
		var expr = expressions.get(char_id, "default")
		if not GameManager.character_database.has(char_id):
			continue
		var char_data: CharacterData = GameManager.character_database[char_id]
		var sprite: CharacterDisplay = _sprites[pos]
		sprite.initialize(char_data, pos, expr)
		_active_roles[pos] = {"character_id": char_id, "data": char_data}
		sprite.visible = true
		sprite.modulate.a = 1.0
