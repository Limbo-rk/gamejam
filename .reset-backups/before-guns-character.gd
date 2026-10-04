extends CharacterBody3D

@export var player_controlled: bool = false
@export var robe_color: Color = Color("398552")
@export var hat_color: Color = Color.WHITE
@export var skin_color: Color = Color("c18b65")
@export var wander_seed: int = 1
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var mouse_sensitivity: float = 0.0025
var released := false
var leaving_elevator := false
var exit_target := Vector3.ZERO
var capture_requested := true
@export var step_height: float = 0.4
var target := Vector3.ZERO
var home := Vector3.ZERO
var running := false
var change_timer := 0.0
var stuck_time := 0.0
var rng := RandomNumberGenerator.new()
var carried_scrap: RigidBody3D
var carry_socket: Node3D
var carry_animation: AnimationPlayer
var throwing := false
var throw_elapsed := 0.0
var throw_released := false
var throw_direction := Vector3.FORWARD
var pickup_grace := 0.0
@export_range(0.0, 1.0) var throw_release_fraction: float = 0.68
@export_range(0.0, 0.5, 0.01) var carry_height_offset: float = 0.20
@onready var skeleton: Skeleton3D = $CharacterModel/Armature/Skeleton3D
@onready var model: Node3D = $CharacterModel
@onready var animation: AnimationPlayer = $CharacterModel/AnimationPlayer
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot")

func _ready() -> void:
    rng.seed = wander_seed
    home = global_position
    running = bool(wander_seed % 2)
    change_timer = rng.randf_range(3.0, 6.0)
    _pick_target()
    for clip in ["Walk", "run"]:
        animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
    _apply_colors()
    _animate(false, false)
    carry_socket = Node3D.new()
    carry_socket.name = "CarrySocket"
    add_child(carry_socket)
    carry_animation = AnimationPlayer.new()
    carry_animation.name = "CarryPose"
    add_child(carry_animation)
    carry_animation.root_node = NodePath("../CharacterModel")
    carry_animation.process_priority = 1
    carry_animation.add_animation_library("", preload("res://GameJAM/Character/carry_throw_animations.tres"))
    carry_animation.active = false
    skeleton.skeleton_updated.connect(_update_hand_socket)
    if player_controlled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        var arm: SpringArm3D = $CameraPivot/SpringArm3D
        arm.add_excluded_object(get_rid())
        var clearance := SphereShape3D.new()
        clearance.radius = 0.2
        arm.shape = clearance

func _apply_colors() -> void:
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        mesh.extra_cull_margin = 2.0
        if mesh.name == "Torso":
            var robe := ShaderMaterial.new()
            robe.shader = preload("res://shaders/character_robe.gdshader")
            robe.set_shader_parameter("robe_texture", preload("res://GameJAM/Character/CharacterRig_Baked UVS.png"))
            robe.set_shader_parameter("robe_color", robe_color)
            mesh.material_override = robe
        else:
            var material := StandardMaterial3D.new()
            material.roughness = 1.0
            material.cull_mode = BaseMaterial3D.CULL_DISABLED
            if mesh.name == "Hat":
                material.albedo_texture = preload("res://GameJAM/Main Character Hat.png")
                material.albedo_color = hat_color
            elif mesh.name == "Face":
                material.albedo_color = skin_color
            else:
                material.albedo_color = Color("493326")
            mesh.material_override = material

func _input(event: InputEvent) -> void:
    if not player_controlled:
        return
    if event.is_action_pressed("ui_cancel"):
        capture_requested = false
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            capture_requested = true
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        elif carried_scrap != null and not throwing:
            begin_throw()
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mouse_delta: Vector2 = event.screen_relative
        if mouse_delta.is_zero_approx():
            mouse_delta = event.relative
        camera_pivot.rotate_y(-mouse_delta.x * mouse_sensitivity)
        var arm: SpringArm3D = $CameraPivot/SpringArm3D
        arm.rotation.x = clampf(arm.rotation.x - mouse_delta.y * mouse_sensitivity, deg_to_rad(-60), deg_to_rad(20))
        get_viewport().set_input_as_handled()

func start_on_elevator(center: Vector3) -> void:
    home = center
    _pick_target()

func release_from_elevator(center: Vector3) -> void:
    home = center
    released = true
    leaving_elevator = true
    # The east rim meets the terrain; the other sides rise above the floor.
    exit_target = center + Vector3(20, 0, float(wander_seed % 7 - 3) * 1.7)
    _pick_target()

func _pick_target() -> void:
    if leaving_elevator:
        target = exit_target
    elif not released:
        target = home + Vector3(rng.randf_range(-8.5, 8.5), 0, rng.randf_range(-8.5, 8.5))
    else:
        var space := get_world_3d().direct_space_state
        for attempt in 16:
            var point := home + Vector3(rng.randf_range(-10, 26), 0, rng.randf_range(-24, 24))
            if point.x < 26:
                continue
            var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 60, point - Vector3.UP * 60, 1)
            var hit := space.intersect_ray(query)
            if not hit.is_empty() and hit.collider.name == "GroundCollision" and hit.normal.y > 0.75:
                target = hit.position
                return
        target = home

func _physics_process(delta: float) -> void:
    pickup_grace = maxf(0.0, pickup_grace - delta)
    if throwing:
        throw_elapsed += delta
        var duration := animation.get_animation("Throw").length
        if not throw_released and throw_elapsed >= duration * throw_release_fraction:
            _release_scrap()
        if throw_elapsed >= duration:
            throwing = false
    var direction := Vector3.ZERO
    if player_controlled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        direction = camera_pivot.global_basis * Vector3(axes.x, 0, axes.y)
        running = Input.is_action_pressed("sprint")
    elif not player_controlled:
        change_timer -= delta
        if change_timer <= 0:
            running = not running
            change_timer = rng.randf_range(3.0, 7.0)
            _pick_target()
        direction = target - global_position
        direction.y = 0
        if direction.length() < 0.7:
            if leaving_elevator:
                leaving_elevator = false
                home = global_position
            _pick_target()
            direction = target - global_position
            direction.y = 0
        direction = direction.normalized()
        var separation := Vector3.ZERO
        for other in get_tree().get_nodes_in_group("characters"):
            if other == self:
                continue
            var away: Vector3 = global_position - other.global_position
            away.y = 0
            var distance := away.length()
            if distance > 0.01 and distance < 1.15:
                separation += away.normalized() * (1.15 - distance) / 1.15
        direction = (direction + separation * 1.7).normalized()
    direction.y = 0
    if throwing:
        direction = Vector3.ZERO
    var speed := run_speed if running else walk_speed
    if not player_controlled:
        speed *= 0.55
    velocity.x = move_toward(velocity.x, direction.x * speed, 18 * delta)
    velocity.z = move_toward(velocity.z, direction.z * speed, 18 * delta)
    if is_on_floor():
        velocity.y = 0
    else:
        velocity.y -= 9.8 * delta
    if direction.length_squared() > 0.01:
        model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), minf(delta * 10, 1))
    var previous := global_position
    _step_up(direction, delta)
    move_and_slide()
    var moved := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    var walking := direction.length_squared() > 0.01 and moved > delta * 0.1
    _animate(walking, running)
    if not player_controlled:
        stuck_time = stuck_time + delta if not walking else 0.0
        if stuck_time > 0.8:
            _pick_target()
            stuck_time = 0.0

func _step_up(direction: Vector3, delta: float) -> void:
    if not is_on_floor() or direction.length_squared() < 0.01:
        return
    var motion := Vector3(velocity.x, 0, velocity.z) * delta
    var obstacle := KinematicCollision3D.new()
    if not test_move(global_transform, motion, obstacle) or obstacle.get_normal().y > 0.7:
        return
    var probe := global_position + direction.normalized() * 0.5
    var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * step_height, probe - Vector3.UP * 0.05, 1)
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty() or hit.normal.y < 0.7:
        return
    var rise: float = hit.position.y - global_position.y
    if rise <= 0.01 or rise > step_height:
        return
    var raised := global_transform
    raised.origin.y += rise + 0.025
    if not test_move(raised, motion):
        global_transform = raised
        velocity.y = 0

func _animate(moving: bool, sprinting: bool) -> void:
    if throwing:
        return
    if moving:
        var clip := "run" if sprinting else "Walk"
        if animation.current_animation != clip or not animation.is_playing():
            animation.play(clip, 0.18)
    elif animation.is_playing() or animation.current_animation.is_empty():
        # Use a still frame of the supplied walk clip; no idle clip was supplied.
        animation.play("Walk")
        animation.seek(0.33, true)
        animation.pause()

func try_pickup_scrap(scrap: RigidBody3D) -> bool:
    if carried_scrap != null or throwing or pickup_grace > 0 or not scrap.claim(self):
        return false
    carried_scrap = scrap
    carry_animation.active = true
    carry_animation.play("Hands up")
    carry_animation.advance(0.0)
    _update_hand_socket()
    return true

func _update_hand_socket() -> void:
    if not is_instance_valid(carry_socket):
        return
    var left := skeleton.get_bone_global_pose(skeleton.find_bone("Bone.008.L")).origin
    var right := skeleton.get_bone_global_pose(skeleton.find_bone("Bone.008.R")).origin
    var midpoint := skeleton.global_transform * ((left + right) * 0.5)
    # Lift thick pieces above the hands; keep flat scraps close to the palms.
    var lift := carry_height_offset
    if is_instance_valid(carried_scrap):
        var visual: MeshInstance3D = carried_scrap.get_node("Model")
        var bounds := (carried_scrap.transform * visual.transform) * visual.get_aabb()
        lift = minf(lift, maxf(0.08, bounds.size.y * 0.5))
    midpoint += Vector3.UP * lift
    carry_socket.global_transform = Transform3D(model.global_basis.orthonormalized(), midpoint)

func begin_throw() -> void:
    if carried_scrap == null or throwing:
        return
    throwing = true
    throw_elapsed = 0.0
    throw_released = false
    carry_animation.stop()
    carry_animation.active = false
    throw_direction = -$CameraPivot/SpringArm3D/Camera3D.global_basis.z if player_controlled else model.global_basis.z
    throw_direction.y = clampf(throw_direction.y, -0.15, 0.65)
    throw_direction = throw_direction.normalized()
    model.rotation.y = atan2(throw_direction.x, throw_direction.z)
    animation.play("Throw", 0.04)

func _release_scrap() -> void:
    throw_released = true
    if carried_scrap == null:
        return
    _update_hand_socket()
    var scrap := carried_scrap
    carried_scrap = null
    pickup_grace = 0.8
    scrap.launch(throw_direction, velocity)

func _notification(what: int) -> void:
    if not player_controlled:
        return
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN and capture_requested:
        Input.set_mouse_mode.call_deferred(Input.MOUSE_MODE_CAPTURED)
