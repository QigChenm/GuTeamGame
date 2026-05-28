# splash_screen.gd
extends Control

@onready var logo_container: HBoxContainer = $LogoContainer
@onready var title_label: TextureRect = $TitleLabel

func _ready() -> void:
	title_label.modulate.a = 0.0
	logo_container.modulate.a = 0.0

	var tween1 = create_tween()
	tween1.tween_property(logo_container, "modulate:a", 1.0, 1.0)
	tween1.tween_interval(1.0)
	tween1.tween_callback(_show_title)

func _show_title() -> void:
	$TitleAppearSound.play()
	var tween2 = create_tween()
	tween2.tween_property(logo_container, "modulate:a", 0.0, 1.0)
	tween2.tween_property(title_label, "modulate:a", 1.0, 1.0)
	tween2.tween_interval(1.0)
	tween2.tween_callback(_finish_splash)

func _finish_splash() -> void:
	# 标题淡出
	var tween3 = create_tween()
	tween3.tween_property(title_label, "modulate:a", 0.0, 0.8)
	tween3.tween_callback(_start_white_flash)

func _start_white_flash() -> void:
	var white_rect = ColorRect.new()
	white_rect.color = Color.WHITE
	white_rect.modulate.a = 0.0
	white_rect.size = get_viewport().get_visible_rect().size
	var canvas_layer = CanvasLayer.new()
	canvas_layer.add_child(white_rect)
	add_child(canvas_layer)
	
	var flash_tween = create_tween()
	flash_tween.tween_property(white_rect, "modulate:a", 1.0, 1.2)
	flash_tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
