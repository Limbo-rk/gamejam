extends CanvasLayer

signal started
var start_button: Button
var volume_slider: HSlider
var volume_label: Label
var player: Node3D

func _ready() -> void:
    name = "StartMenu"
    layer = 100
    process_mode = Node.PROCESS_MODE_ALWAYS
    for actor in get_tree().get_nodes_in_group("characters"):
        if actor.player_controlled:
            player = actor
            player.capture_requested = false
            player.set_process_input(false)
            break
    var background := ColorRect.new()
    background.color = Color(0.025, 0.035, 0.05, 0.8)
    add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var center := CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 420
    column.add_theme_constant_override("separation", 24)
    center.add_child(column)
    start_button = Button.new()
    start_button.text = "Start"
    start_button.custom_minimum_size.y = 76
    start_button.add_theme_font_size_override("font_size", 40)
    column.add_child(start_button)
    volume_label = Label.new()
    volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    volume_label.add_theme_font_size_override("font_size", 26)
    column.add_child(volume_label)
    volume_slider = HSlider.new()
    volume_slider.custom_minimum_size.y = 36
    volume_slider.min_value = 0
    volume_slider.max_value = 100
    volume_slider.step = 1
    volume_slider.value = 0 if AudioServer.is_bus_mute(0) else db_to_linear(AudioServer.get_bus_volume_db(0)) * 100
    column.add_child(volume_slider)
    volume_slider.value_changed.connect(_set_volume)
    _set_volume(volume_slider.value)
    start_button.pressed.connect(_start)
    start_button.grab_focus()
    get_tree().paused = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_volume(value: float) -> void:
    volume_label.text = "Volume: %d%%" % roundi(value)
    AudioServer.set_bus_mute(0, value <= 0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value / 100.0, 0.0001)))

func _start() -> void:
    start_button.disabled = true
    player.capture_requested = true
    player.fire_requested = false
    player.set_process_input(true)
    get_tree().paused = false
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    hide()
    started.emit()
    queue_free()
