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
    status = Label.new()
    hud.add_child(status)
    status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    status.offset_top = -52
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status.add_theme_color_override("font_shadow_color", Color.BLACK)
    status.add_theme_constant_override("shadow_offset_x", 2)
    status.add_theme_constant_override("shadow_offset_y", 2)
    _update_status()

func _physics_process(_delta: float) -> void:
    global_position = platform.global_position + Vector3.UP * floor_offset
    if not active:
        return
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
    if player.equipped_gun != null:
        status.text = "Gun equipped"
    elif is_instance_valid(player.pending_gun) and player.pending_gun.equipped_by == null:
        status.text = "Gun ready — walk over it to equip"
    else:
        status.text = "Platform: %d/3 scraps — throw scraps onto the platform" % int(deposits.get(player.get_instance_id(), 0))
