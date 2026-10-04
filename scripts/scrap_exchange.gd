extends Node3D

signal scrap_received(character: Node3D, progress: int)
signal gun_rewarded(character: Node3D, gun: RigidBody3D)
var platform: MeshInstance3D
var active := false
var deposits: Dictionary = {}
var guns_created := 0
var floor_offset := 0.0
var deposit_area: Area3D
var status: Label
var player: Node3D
var crosshair: Label
var intro: Label
var controls: Label
var scrap_counter: Label
var outcome: Label

func _ready() -> void:
    add_to_group("scrap_exchange")
    var bounds := platform.global_transform * platform.get_aabb()
    floor_offset = bounds.end.y - platform.global_position.y
    global_position = platform.global_position + Vector3.UP * floor_offset
    deposit_area = Area3D.new()
    deposit_area.name = "ScrapDepositArea"
    deposit_area.collision_layer = 0
    deposit_area.collision_mask = 4
    add_child(deposit_area)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(bounds.size.x, 1.2, bounds.size.z)
    collision.shape = shape
    collision.position.y = 0.55
    deposit_area.add_child(collision)
    for character in get_tree().get_nodes_in_group("characters"):
        if character.player_controlled:
            player = character
            break
    var hud := CanvasLayer.new()
    hud.name = "PlatformStatus"
    add_child(hud)
    var layout := Control.new()
    layout.name = "HUD"
    hud.add_child(layout)
    layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
    intro = _hud_label(layout, "SpawnInstructions", 32)
    intro.text = "Throw 3 Scraps on the Platform to Get Weapons"
    intro.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    intro.offset_left = 24
    intro.offset_right = -24
    intro.offset_top = 32
    intro.offset_bottom = 130
    intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    get_tree().create_timer(8.0).timeout.connect(intro.hide)
    controls = _hud_label(layout, "Controls", 18)
    controls.text = "Shift= Run\nQ= Throw\nLeft Click= Shoot"
    controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    controls.offset_left = 24
    controls.offset_right = 260
    controls.offset_top = -110
    controls.offset_bottom = -24
    scrap_counter = _hud_label(layout, "ScrapCounter", 24)
    scrap_counter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
    scrap_counter.offset_left = -240
    scrap_counter.offset_right = -24
    scrap_counter.offset_top = -24
    scrap_counter.offset_bottom = 24
    scrap_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    outcome = _hud_label(layout, "Outcome", 42)
    outcome.anchor_right = 1.0
    outcome.anchor_top = 0.5
    outcome.anchor_bottom = 0.5
    outcome.offset_left = 24
    outcome.offset_right = -24
    outcome.offset_top = -64
    outcome.offset_bottom = 64
    outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status = _hud_label(layout, "PlayerStatus", 18)
    status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    status.offset_left = -480
    status.offset_right = -24
    status.offset_top = -85
    status.offset_bottom = -24
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    crosshair = _hud_label(layout, "Crosshair", 24)
    crosshair.text = "+"
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    crosshair.position -= Vector2(6, 12)
    _update_status()

func _physics_process(_delta: float) -> void:
    global_position = platform.global_position + Vector3.UP * floor_offset
    if active:
        for item in deposit_area.get_overlapping_bodies():
            if item.has_method("consume_for_platform") and item.linear_velocity.y <= 0.5:
                accept_scrap(item)
    _update_status()

func accept_scrap(item: RigidBody3D) -> bool:
    if not active or not deposit_area.overlaps_body(item):
        return false
    var contributor: Node3D = item.consume_for_platform()
    if not is_instance_valid(contributor):
        return false
    var id := contributor.get_instance_id()
    var progress: int = deposits.get(id, 0) + 1
    deposits[id] = progress % 3
    scrap_received.emit(contributor, deposits[id])
    _update_status()
    if progress >= 3:
        _eject_gun.call_deferred(contributor)
    return true

func _eject_gun(contributor: Node3D) -> void:
    var gun: RigidBody3D = preload("res://gun.tscn").instantiate()
    get_parent().add_child(gun)
    guns_created += 1
    gun.global_position = global_position + Vector3.UP * 1.4
    var landing := get_dropoff_point(contributor)
    if is_instance_valid(contributor):
        landing = contributor.global_position
    var horizontal := landing - global_position
    horizontal.y = 0
    if horizontal.length() > 24:
        horizontal = horizontal.normalized() * 24
    if horizontal.length() < 3:
        horizontal = Vector3.RIGHT * 5
    landing = global_position + horizontal
    var query := PhysicsRayQueryParameters3D.create(landing + Vector3.UP * 10, landing - Vector3.UP * 15, 1)
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    landing.y = hit.position.y + 0.7 if not hit.is_empty() else global_position.y + 0.7
    var flight_time := 1.15
    # Compensate for gravity so the platform throws the gun back toward its contributor.
    gun.linear_damp = 0.0
    gun.linear_velocity = (landing - gun.global_position) / flight_time + Vector3.UP * (4.9 * flight_time)
    gun.angular_velocity = Vector3(0.5, 2, 0.3)
    gun.recovery_position = landing + Vector3.UP
    if is_instance_valid(contributor):
        contributor.pending_gun = gun
    gun_rewarded.emit(contributor, gun)

func get_dropoff_point(character: Node3D) -> Vector3:
    var lane := float(character.wander_seed % 7 - 3) * 1.5 if is_instance_valid(character) else 0.0
    return global_position + Vector3(19, 0, lane)

func get_throw_target(character: Node3D) -> Vector3:
    var point := get_dropoff_point(character)
    point.x = global_position.x + 7
    return point

func _update_status() -> void:
    if not is_instance_valid(player):
        return
    var living := 0
    for actor in get_tree().get_nodes_in_group("characters"):
        if not actor.dead:
            living += 1
    var ended: bool = player.dead or living == 1
    crosshair.visible = not ended and player.equipped_gun != null
    scrap_counter.text = "Scraps: %d/3" % int(deposits.get(player.get_instance_id(), 0))
    outcome.visible = ended
    if ended:
        intro.hide()
        outcome.text = "You Died" if player.dead else "You Were The Last One Standing"
    status.text = "Health: %d/3  |  Remaining: %d" % [player.health, living]
    if player.equipped_gun != null:
        status.text = "Ammo: %d/20\n" % player.equipped_gun.ammo + status.text
    elif is_instance_valid(player.pending_gun) and player.pending_gun.equipped_by == null:
        status.text = "Walk over your gun to equip it\n" + status.text

func _hud_label(parent: Control, label_name: String, font_size: int) -> Label:
    var label := Label.new()
    label.name = label_name
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_shadow_color", Color.BLACK)
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    return label
