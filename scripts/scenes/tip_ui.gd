# tip_ui.gd
extends CanvasLayer

signal confirmed
signal canceled
signal closed

@onready var message_label: RichTextLabel = $TipRect/Message
@onready var confirm_btn: TextureButton = $TipRect/ConfirmBtn
@onready var cancel_btn: TextureButton = $TipRect/CancelBtn
@onready var close_btn: TextureButton = $TipRect/CloseBtn
@onready var confirm_txt: Label = $TipRect/ConfirmBtn/Label
@onready var cancel_txt: Label = $TipRect/CancelBtn/Label

func _ready():
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	close_btn.visible = false
	confirm_btn.pressed.connect(func(): confirmed.emit())
	cancel_btn.pressed.connect(func(): canceled.emit())
	close_btn.pressed.connect(func(): closed.emit())


func show_tip(text: String, confirm_text: String = "确认", cancel_text: String = "取消", show_close: bool = false):
	message_label.text = text
	confirm_txt.text = confirm_text
	cancel_txt.text = cancel_text
	close_btn.visible = show_close

	_disconnect_all()
	visible = true

func _disconnect_all():
	if confirm_btn.pressed.is_connected(_emit_confirmed):
		confirm_btn.pressed.disconnect(_emit_confirmed)
	if cancel_btn.pressed.is_connected(_emit_canceled):
		cancel_btn.pressed.disconnect(_emit_canceled)
	if close_btn.pressed.is_connected(_emit_closed):
		close_btn.pressed.disconnect(_emit_closed)

func _emit_confirmed():
	confirmed.emit()

func _emit_canceled():
	canceled.emit()

func _emit_closed():
	closed.emit()

func hide_tip():
	visible = false
	_disconnect_all()
