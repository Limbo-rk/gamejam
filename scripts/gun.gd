extends RigidBody3D

@export var grip_offset := Vector3.ZERO
var equipped_by: Node3D
var pickup_delay := 0.8
var recovery_position := Vector3.ZERO
@onready var pickup_area: Area3D = $PickupArea

func _ready() -> void:
    add_to_group("guns")
    pickup_area.body_entered.connect(_try_pickup)

func _try_pickup(body: Node3D) -> void:
    if equipped_by == null and pickup_delay <= 0 and (sleeping or linear_velocity.length() < 2.5) and body.has_method("try_equip_gun"):
        body.try_equip_gun(self)

func claim(character: Node3D) -> bool:
    if equipped_by != null or pickup_delay > 0:
        return false
    equipped_by = character
    pickup_area.set_deferred("monitoring", false)
    set_deferred("collision_layer", 0)
    set_deferred("collision_mask", 0)
    _attach.call_deferred()
    return true

func _attach() -> void:
    if not is_instance_valid(equipped_by):
        return
    freeze = true
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    reparent(equipped_by.gun_socket, false)
    transform = Transform3D(Basis.IDENTITY, -grip_offset)

func _physics_process(delta: float) -> void:
    if equipped_by != null:
        return
    pickup_delay = maxf(0.0, pickup_delay - delta)
    for body in pickup_area.get_overlapping_bodies():
        _try_pickup(body)
        if equipped_by != null:
            break
    if global_position.y < -115:
        global_position = recovery_position
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
