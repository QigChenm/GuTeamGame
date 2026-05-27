# cg_manager.gd
extends Node

# ================= 信号 =================
signal cg_finished

# ================= 常量 =================
const MIN_CG_DURATION = 2.0
const TRANSITION_DURATION = 0.5

# ================= 属性 =================
var cg_database: Dictionary = {}
var _cg_display: TextureRect = null
var _animation_player: AnimationPlayer = null
var _min_timer: Timer = null
var _animation_finished: bool = false
var _min_time_reached: bool = false
var _is_cg_active: bool = false
var _idle_tween: Tween = null
var auto_skip_timer: Timer = null


# ================= 初始化 =================
func _ready() -> void:
	_load_cg_database()


func _load_cg_database() -> void:
	var dir = DirAccess.open("res://assets/cg")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with("_cg_data.tres"):
				var resource = load("res://assets/cg/" + file_name)
				if resource is CGData and resource.cg_id != "":
					cg_database[resource.cg_id] = resource
			file_name = dir.get_next()
		dir.list_dir_end()


# ================= 注册 =================
func register_cg_display(display_node: TextureRect) -> void:
	_cg_display = display_node
	if _cg_display:
		_animation_player = _cg_display.get_node_or_null("CGAnimationPlayer") as AnimationPlayer
		if _animation_player:
			if not _animation_player.is_connected("animation_finished", _on_animation_finished):
				_animation_player.connect("animation_finished", _on_animation_finished)
			print("[CGManager] CG系统已注册。")


# ================= 公共接口 =================
func show_cg(cg_id: String, script_data: Array = []) -> void:
	UIManager.hide_hud_buttons_for_cg()

	if not _cg_display or not _animation_player:
		print("[CGManager] 错误：CG系统未就绪。")
		cg_finished.emit.call_deferred()
		return
	if not cg_database.has(cg_id):
		print("[CGManager] 错误：未找到CG '%s'。" % cg_id)
		cg_finished.emit.call_deferred()
		return

	BackgroundManager.perform_fade_out(TRANSITION_DURATION)
	if not BackgroundManager.fade_out_finished.is_connected(_on_scene_faded_out):
		BackgroundManager.fade_out_finished.connect(_on_scene_faded_out.bind(cg_id, script_data), CONNECT_ONE_SHOT)


func hide_cg() -> void:
	if _cg_display:
		_cg_display.hide()
		if _animation_player and _animation_player.is_playing():
			_animation_player.stop()
	if _idle_tween and _idle_tween.is_running():
		_idle_tween.kill()
	if _min_timer:
		_min_timer.stop()
		_min_timer.queue_free()
		_min_timer = null
	_is_cg_active = false
	set_process_input(false)
	UIManager.restore_hud_buttons_after_cg()
	cg_finished.emit.call_deferred()


func reset_state() -> void:
	if _cg_display:
		_cg_display.hide()
		_cg_display.scale = Vector2.ONE
		_cg_display.position = Vector2.ZERO
		_cg_display.rotation = 0.0
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
	if _min_timer:
		_min_timer.stop()
		_min_timer.queue_free()
		_min_timer = null
	_is_cg_active = false
	set_process_input(false)
	print("[CGManager] CG 状态已重置。")


# ================= 内部流程 =================
func _on_scene_faded_out(cg_id: String, script_data: Array) -> void:
	var cg_data: CGData = cg_database[cg_id]
	_cg_display.texture = cg_data.texture
	_cg_display.position = Vector2.ZERO
	_cg_display.rotation = 0.0
	_cg_display.scale = Vector2.ONE
	_cg_display.show()

	_animation_finished = false
	_min_time_reached = false
	_is_cg_active = true

	BackgroundManager.perform_fade_in(TRANSITION_DURATION)
	if not BackgroundManager.fade_in_finished.is_connected(_on_cg_reveal_fade_in):
		BackgroundManager.fade_in_finished.connect(_on_cg_reveal_fade_in.bind(cg_data, script_data), CONNECT_ONE_SHOT)


func _on_cg_reveal_fade_in(cg_data: CGData, script_data: Array) -> void:
	# 重置最小显示计时器
	if _min_timer:
		_min_timer.stop()
		_min_timer.queue_free()
	_min_timer = Timer.new()
	add_child(_min_timer)
	_min_timer.one_shot = true
	_min_timer.wait_time = MIN_CG_DURATION
	_min_timer.timeout.connect(_on_min_time_reached)
	_min_timer.start()

	if cg_data.animation_lib:
		_animation_player.add_animation_library("cg_lib", cg_data.animation_lib)
		_animation_player.play("cg_lib/default")
	elif not script_data.is_empty():
		_generate_and_play_animation(script_data)
	else:
		_start_random_motion()
		_on_animation_finished("random")

	_listen_for_player_input()
	_start_auto_skip_if_needed()


func _end_cg_display() -> void:
	_cancel_auto_skip()
	_is_cg_active = false
	if _idle_tween and _idle_tween.is_running():
		_idle_tween.kill()
	if _min_timer:
		_min_timer.stop()
		_min_timer.queue_free()
		_min_timer = null

	BackgroundManager.perform_fade_out(TRANSITION_DURATION)
	if not BackgroundManager.fade_out_finished.is_connected(_on_cg_faded_out):
		BackgroundManager.fade_out_finished.connect(_on_cg_faded_out, CONNECT_ONE_SHOT)


func _on_cg_faded_out() -> void:
	if _cg_display:
		_cg_display.hide()
		if _animation_player and _animation_player.is_playing():
			_animation_player.stop()
	BackgroundManager.perform_fade_in(TRANSITION_DURATION)
	if not BackgroundManager.fade_in_finished.is_connected(_on_scene_faded_in):
		BackgroundManager.fade_in_finished.connect(_on_scene_faded_in, CONNECT_ONE_SHOT)


func _on_scene_faded_in() -> void:
	UIManager.restore_hud_buttons_after_cg()
	print("[CGManager] CG转场演出全部结束。")
	cg_finished.emit()


# ================= 动画生成（占位） =================
func _generate_and_play_animation(script_data: Array) -> void:
	# 根据传入的脚本数据生成并播放动画，目前未实现具体内容
	pass


# ================= 随机运镜 =================
func _start_random_motion() -> void:
	if _idle_tween and _idle_tween.is_running():
		_idle_tween.kill()
	_idle_tween = create_tween()
	_idle_tween.set_loops()

	var target_scale = Vector2(1.0 + randf_range(-0.05, 0.08), 1.0 + randf_range(-0.05, 0.08))
	var target_offset = Vector2(randf_range(-20, 20), randf_range(-15, 15))
	var duration = randf_range(4.0, 7.0)

	_idle_tween.tween_property(_cg_display, "scale", target_scale, duration).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_cg_display, "position", target_offset, duration).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_cg_display, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_cg_display, "position", Vector2.ZERO, duration).set_ease(Tween.EASE_IN_OUT)


# ================= 输入监听 =================
func _listen_for_player_input() -> void:
	set_process_input(true)
	print("[CGManager] 等待玩家点击以结束 CG...")


func _input(event: InputEvent) -> void:
	if not _is_cg_active:
		return
	if _min_time_reached and (event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed)):
		print("[CGManager] 玩家点击，结束 CG。")
		_cancel_auto_skip()
		set_process_input(false)
		_end_cg_display()


# ================= 定时器与自动跳过 =================
func _on_animation_finished(_anim_name: String) -> void:
	_animation_finished = true


func _on_min_time_reached() -> void:
	_min_time_reached = true


func _check_cg_complete() -> void:
	# 已弃用，不再自动结束，完全由玩家点击或自动模式控制
	pass


func _start_auto_skip_if_needed() -> void:
	_cancel_auto_skip()
	
	if GameManager.is_auto_mode or GameManager.is_skip_mode:
		auto_skip_timer = Timer.new()
		add_child(auto_skip_timer)
		auto_skip_timer.one_shot = true
		if GameManager.is_skip_mode:
			auto_skip_timer.wait_time = 1.0
		else:
			auto_skip_timer.wait_time = MIN_CG_DURATION
		auto_skip_timer.timeout.connect(_auto_skip_cg)
		auto_skip_timer.start()


func _auto_skip_cg() -> void:
	if _is_cg_active:
		print("[CGManager] 自动模式：跳过CG")
		_end_cg_display()


func _cancel_auto_skip() -> void:
	if auto_skip_timer:
		auto_skip_timer.stop()
		auto_skip_timer.queue_free()
		auto_skip_timer = null
