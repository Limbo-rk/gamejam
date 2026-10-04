extends RigidBody3D

signal picked_up(character: Node3D)
signal thrown(character: Node3D)
@export_enum("barrel", "spring", "panel", "gear") var scrap_kind: String = "barrel"
var held_by: Node3D
var last_thrower: Node3D
var deposited := false
var world_parent: Node
var pickup_cooldown := 0.0
var home_position := Vector3.ZERO
@onready var pickup_area: Area3D = $PickupArea

func _ready() -> void:
    world_parent = get_parent()
    home_position = global_position
    pickup_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
    if held_by == null and pickup_cooldown <= 0 and body.has_method("try_pickup_scrap"):
        body.try_pickup_scrap(self)

func claim(character: Node3D) -> bool:
    if held_by != null or pickup_cooldown > 0 or deposited:
        return false
    # Reserve immediately so overlapping characters cannot claim the same item.
    held_by = character
    last_thrower = null
    pickup_area.set_deferred("monitoring", false)
    set_deferred("collision_layer", 0)
    set_deferred("collision_mask", 0)
    _attach.call_deferred()
    picked_up.emit(character)
    return true

func _attach() -> void:
    if not is_instance_valid(held_by):
        return
    freeze = true
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    reparent(held_by.carry_socket, false)
    transform = Transform3D.IDENTITY
    # The narrow spring is held sideways across the two hands.
    if scrap_kind == "spring":
        rotation.z = PI * 0.5

func launch(direction: Vector3, inherited_velocity: Vector3) -> void:
    var previous_holder = held_by
    last_thrower = previous_holder
    reparent(world_parent, true)
    held_by = null
    pickup_cooldown = 1.2
    freeze = false
    sleeping = false
    collision_layer = 4
    collision_mask = 5
    linear_velocity = direction * 10.0 + Vector3.UP * 3.0 + inherited_velocity * 0.3
    angular_velocity = Vector3(2.2, 1.1, 0.4)
    thrown.emit(previous_holder)

func consume_for_platform() -> Node3D:
    if deposited or held_by != null or not is_instance_valid(last_thrower):
        return null
    deposited = true
    pickup_area.set_deferred("monitoring", false)
    set_deferred("collision_layer", 0)
    set_deferred("collision_mask", 0)
    queue_free()
    return last_thrower

func _physics_process(delta: float) -> void:
    if held_by != null or deposited:
        return
    if pickup_cooldown > 0:
        pickup_cooldown = maxf(0.0, pickup_cooldown - delta)
        if pickup_cooldown == 0:
            pickup_area.set_deferred("monitoring", true)
    # Recover a scrap thrown beyond the edge of the map; preserve the item count.
    if global_position.y < -115:
        freeze = true
        global_position = home_position
        rotation = Vector3.ZERO
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
