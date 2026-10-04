extends RigidBody3D

@export var grip_offset := Vector3.ZERO
var equipped_by: Node3D
var pickup_delay := 0.8
var recovery_position := Vector3.ZERO
const CAPACITY := 20
const SHOT_INTERVAL := 0.18
const SHOT_RANGE := 150.0
var ammo := CAPACITY
var shot_cooldown := 0.0
var flash_time := 0.0
var muzzle: Node3D
var muzzle_flash: MeshInstance3D
var muzzle_light: OmniLight3D
var world_parent: Node
signal fired(rounds_left: int)
@onready var pickup_area: Area3D = $PickupArea

func _ready() -> void:
    add_to_group("guns")
    world_parent = get_parent()
    pickup_area.body_entered.connect(_try_pickup)
    _create_muzzle()

func _create_muzzle() -> void:
    var visual: MeshInstance3D = $Model
    var vertices: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var front := visual.mesh.get_aabb().end.z
    var center := Vector3.ZERO
    var count := 0
    for vertex in vertices:
        if vertex.z > front - 0.02:
            center += vertex
            count += 1
    muzzle = Node3D.new()
    muzzle.name = "Muzzle"
    add_child(muzzle)
    muzzle.position = visual.transform * (center / maxf(count, 1.0))
    muzzle_flash = MeshInstance3D.new()
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.075
    flash_mesh.height = 0.15
    flash_mesh.radial_segments = 8
    flash_mesh.rings = 3
    muzzle_flash.mesh = flash_mesh
    muzzle_flash.scale = Vector3(1, 1, 3)
    muzzle_flash.position.z = 0.1
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.75, 0.18)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.45, 0.05)
    material.emission_energy_multiplier = 3.0
    muzzle_flash.material_override = material
    muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle.add_child(muzzle_flash)
    muzzle_flash.hide()
    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.65, 0.25)
    muzzle_light.light_energy = 2.0
    muzzle_light.omni_range = 3.0
    muzzle.add_child(muzzle_light)
    muzzle_light.hide()

func fire_at(aim_point: Vector3) -> bool:
    if not is_instance_valid(equipped_by) or equipped_by.dead or equipped_by.throwing or ammo <= 0 or shot_cooldown > 0:
        return false
    var shooter := equipped_by
    ammo -= 1
    shot_cooldown = SHOT_INTERVAL
    flash_time = 0.055
    muzzle_flash.show()
    muzzle_light.show()
    var origin := muzzle.global_position
    var endpoint := origin + (aim_point - origin).normalized() * minf(origin.distance_to(aim_point) + 0.1, SHOT_RANGE)
    # Check from the shooter's body first so a protruding barrel cannot shoot through cover.
    var obstruction := PhysicsRayQueryParameters3D.create(shooter.global_position + Vector3.UP * 1.35, origin, 1)
    var space := get_world_3d().direct_space_state
    var hit := space.intersect_ray(obstruction)
    if hit.is_empty():
        var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 3, [shooter.get_rid()])
        hit = space.intersect_ray(query)
    if not hit.is_empty():
        endpoint = hit.position
        if hit.collider.has_method("take_bullet"):
            hit.collider.take_bullet(shooter)
    _show_tracer(origin, endpoint)
    fired.emit(ammo)
    return true

func _show_tracer(start: Vector3, end: Vector3) -> void:
    var tracer := MeshInstance3D.new()
    var mesh := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.85, 0.45)
    mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
    mesh.surface_add_vertex(start)
    mesh.surface_add_vertex(end)
    mesh.surface_end()
    tracer.mesh = mesh
    world_parent.add_child(tracer)
    tracer.global_transform = Transform3D.IDENTITY
    get_tree().create_timer(0.045).timeout.connect(tracer.queue_free)

func drop(drop_position: Vector3, inherited_velocity: Vector3 = Vector3.ZERO) -> void:
    equipped_by = null
    pickup_delay = 0.8
    _drop_deferred.call_deferred(drop_position, inherited_velocity)

func launch(drop_position: Vector3, direction: Vector3, inherited_velocity: Vector3) -> void:
    equipped_by = null
    pickup_delay = 1.2
    _drop_deferred.call_deferred(drop_position, inherited_velocity, direction * 10.0 + Vector3.UP * 3.0)

func _drop_deferred(drop_position: Vector3, inherited_velocity: Vector3, launch_velocity: Vector3 = Vector3.UP * 1.5) -> void:
    reparent(world_parent, true)
    global_position = drop_position
    recovery_position = drop_position
    freeze = false
    sleeping = false
    collision_layer = 8
    collision_mask = 13
    linear_damp = 0.3
    linear_velocity = inherited_velocity * 0.3 + launch_velocity
    angular_velocity = Vector3(1.0, 0.5, 0.7)
    pickup_area.monitoring = true

func _try_pickup(body: Node3D) -> void:
    if equipped_by == null and pickup_delay <= 0 and (sleeping or linear_velocity.length() < 2.5) and body.has_method("try_equip_gun"):
        body.try_equip_gun(self)

func claim(character: Node3D) -> bool:
    if equipped_by != null or pickup_delay > 0 or ammo <= 0 or character.dead:
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
    shot_cooldown = maxf(0.0, shot_cooldown - delta)
    flash_time = maxf(0.0, flash_time - delta)
    muzzle_flash.visible = flash_time > 0
    muzzle_light.visible = flash_time > 0
    if equipped_by != null:
        return
    pickup_delay = maxf(0.0, pickup_delay - delta)
    if pickup_area.monitoring:
        for body in pickup_area.get_overlapping_bodies():
            _try_pickup(body)
            if equipped_by != null:
                break
    if global_position.y < -115:
        global_position = recovery_position
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
