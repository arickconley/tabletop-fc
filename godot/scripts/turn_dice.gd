class_name TurnDice
extends Control

signal roll_requested

const Die = preload("res://scripts/die.gd")
var shade: ColorRect
var title: Label
var caption: Label
var first: Button
var second: Button
var busy = false
var docking = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	shade = ColorRect.new()
	shade.color = Color(0.025, 0.05, 0.1, 0.38)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	first = Die.new()
	second = Die.new()
	for die in [first, second]:
		die.pressed.connect(func(): roll_requested.emit())
		add_child(die)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("e4edf9"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	resized.connect(_layout)
	hide()

func _layout() -> void:
	if docking:
		return
	var side = clampf(minf(size.x * (0.36 if second.visible else 0.48), size.y * 0.35), 100, 180)
	var center = size * Vector2(0.5, 0.48)
	first.size = Vector2.ONE * side
	second.size = first.size
	first.position = center - first.size * 0.5
	if second.visible:
		first.position.x -= side * 0.57
		second.position = center - second.size * 0.5 + Vector2(side * 0.57, 0)
	title.size = Vector2(size.x - 24, 40)
	title.position = Vector2(12, center.y - side * 0.5 - 44)
	caption.size = Vector2(minf(520, size.x - 32), 0)
	caption.position = Vector2((size.x - caption.size.x) * 0.5, center.y + side * 0.5 + 12)

func present(state: Dictionary) -> void:
	if busy:
		return
	var kickoff = state.phase in ["ready", "halftime"]
	title.text = "HALFTIME KICKOFF" if state.phase == "halftime" else ("KICKOFF" if kickoff else "%s’S TURN" % state.team.to_upper())
	title.modulate = Color("d8ff3e") if kickoff else (Color("6fc9ff") if state.team == "blue" else Color("ff8090"))
	caption.text = "Tap the dice · set the kickoff distance" if state.phase == "halftime" else ("Tap the dice · highest roll kicks off" if kickoff else "Tap the die to find your moves")
	first.tint = Color("6fc9ff") if kickoff or state.team == "blue" else Color("ff8090")
	second.tint = Color("ff8090")
	first.face = 5
	second.face = 3
	first.scale = Vector2.ONE
	first.show()
	second.visible = kickoff
	first.disabled = false
	second.disabled = false
	first.tooltip_text = "Roll kickoff dice" if kickoff else "Roll for %s" % state.team
	second.tooltip_text = "Roll kickoff dice"
	title.modulate.a = 1
	caption.modulate.a = 1
	shade.modulate.a = 1
	show()
	_layout.call_deferred()
	first.grab_focus.call_deferred()

func reveal(values: Array, moves: int, result_text: String, badge: Control) -> void:
	busy = true
	first.disabled = true
	second.disabled = true
	caption.text = "Rolling…"
	if values.size() > 1:
		second.roll_to(values[1])
	await first.roll_to(values[0])
	caption.text = result_text
	await get_tree().create_timer(0.65).timeout
	if moves == 0:
		caption.text = "A tie! Tap either die to roll again"
		first.disabled = false
		second.disabled = false
		busy = false
		first.grab_focus()
		return
	docking = true
	second.hide()
	first.face = moves
	first.tint = badge.tint
	var start = first.position
	var flight = create_tween().set_parallel(true)
	flight.tween_property(title, "modulate:a", 0.0, 0.2)
	flight.tween_property(caption, "modulate:a", 0.0, 0.2)
	flight.tween_property(shade, "modulate:a", 0.0, 0.4)
	flight.tween_method(func(progress: float):
		first.position = start.lerp(badge.global_position, progress)
		first.scale = Vector2.ONE.lerp(badge.size / first.size, progress)
	, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await flight.finished
	docking = false
	busy = false
	hide()
