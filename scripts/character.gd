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
var equipped_gun: RigidBody3D
var pending_gun: RigidBody3D
var gun_socket: Node3D
var carry_socket: Node3D
var carry_animation: AnimationPlayer
var throwing := false
var throw_elapsed := 0.0
var throw_released := false
var throw_direction := Vector3.FORWARD
var pickup_grace := 0.0
var scrap_target: Node3D
var avoided_scraps: Dictionary = {}
var search_delay := 0.0
var delivery_wait := 0.0
var route_points := PackedVector3Array()
var route_index := 0
var route_destination := Vector3.INF
var route_refresh := 0.0
var progress_position := Vector3.ZERO
var progress_time := 0.0
var health := 3
var dead := false
var fire_requested := false
var gun_pickup_grace := 0.0
var combat: Node
signal died(character: Node3D, killer: Node3D)
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
    for clip in ["Walk", "run", "Walk With Gun", "Run with Gun"]:
        animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
    _apply_colors()
    _animate(false, false)
    carry_socket = Node3D.new()
    carry_socket.name = "CarrySocket"
    add_child(carry_socket)
    gun_socket = Node3D.new()
    gun_socket.name = "GunSocket"
    add_child(gun_socket)
    carry_animation = AnimationPlayer.new()
    carry_animation.name = "CarryPose"
    add_child(carry_animation)
    carry_animation.root_node = NodePath("../CharacterModel")
    carry_animation.process_priority = 1
    carry_animation.add_animation_library("", preload("res://GameJAM/Character/carry_throw_animations.tres"))
    carry_animation.active = false
    skeleton.skeleton_updated.connect(_update_hand_socket)
    if not player_controlled:
        combat = preload("res://scripts/npc_combat.gd").new()
        combat.actor = self
        add_child(combat)
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
        elif not dead and equipped_gun != null:
            fire_requested = true
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("throw_item") and not event.is_echo():
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
    running = true
    change_timer = rng.randf_range(6.0, 10.0)
    # The east rim meets the terrain; the other sides rise above the floor.
    exit_target = center + Vector3(20, 0, float(wander_seed % 7 - 3) * 1.7)
    _pick_target()

func _pick_target() -> void:
    if leaving_elevator:
        target = exit_target
    elif not released:
        target = home + Vector3(rng.randf_range(-8.5, 8.5), 0, rng.randf_range(-8.5, 8.5))
    elif is_instance_valid(pending_gun) and pending_gun.equipped_by == null:
        target = pending_gun.global_position
    elif carried_scrap != null:
        var exchange := get_tree().get_first_node_in_group("scrap_exchange")
        if exchange != null and exchange.active:
            target = exchange.get_dropoff_point(self)
    elif not player_controlled and equipped_gun == null:
        var scavenging := get_tree().get_first_node_in_group("scavenging")
        if scavenging == null or delivery_wait > 0:
            target = global_position
            return
        if not is_instance_valid(scrap_target) or not scavenging.available(scrap_target):
            scrap_target = null
            if search_delay <= 0:
                scrap_target = scavenging.choose_scrap(self)
                search_delay = 1.0
        target = scrap_target.global_position if is_instance_valid(scrap_target) else global_position
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
    if dead:
        return
    gun_pickup_grace = maxf(0.0, gun_pickup_grace - delta)
    if player_controlled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and equipped_gun != null:
        if fire_requested or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            _shoot_from_camera()
    fire_requested = false
    pickup_grace = maxf(0.0, pickup_grace - delta)
    search_delay = maxf(0.0, search_delay - delta)
    delivery_wait = maxf(0.0, delivery_wait - delta)
    route_refresh -= delta
    for id in avoided_scraps.keys():
        avoided_scraps[id] -= delta
        if avoided_scraps[id] <= 0:
            avoided_scraps.erase(id)
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
        var fighting: bool = combat.update(delta)
        if not fighting and released and not leaving_elevator and (equipped_gun == null or equipped_gun.ammo <= 0):
            _pick_target()
        change_timer -= delta
        if change_timer <= 0:
            if released and equipped_gun == null:
                # Objective runs dominate; short walking intervals retain both supplied clips.
                running = not running
                change_timer = rng.randf_range(7.0, 12.0) if running else rng.randf_range(0.5, 1.0)
            else:
                running = not running
                change_timer = rng.randf_range(3.0, 7.0)
            if not fighting:
                _pick_target()
        direction = target - global_position
        direction.y = 0
        if direction.length() < 0.7:
            var exchange := get_tree().get_first_node_in_group("scrap_exchange")
            if carried_scrap != null and released and not leaving_elevator and exchange != null and exchange.active:
                begin_throw((exchange.get_throw_target(self) - global_position).normalized())
            if leaving_elevator:
                leaving_elevator = false
                home = global_position
            if not fighting:
                _pick_target()
            direction = target - global_position
            direction.y = 0
        if released and not leaving_elevator and direction.length() > 0.7:
            direction = _route_direction(direction)
        direction = direction.normalized()
        var separation := Vector3.ZERO
        for other in get_tree().get_nodes_in_group("characters"):
            if other == self or other.dead:
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
    if not player_controlled and not released:
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
        if released and not leaving_elevator and not throwing:
            progress_time += delta
            if global_position.distance_to(progress_position) > 1.5:
                progress_position = global_position
                progress_time = 0.0
            elif progress_time > 8.0:
                if is_instance_valid(scrap_target):
                    avoided_scraps[scrap_target.get_instance_id()] = 30.0
                    scrap_target = null
                    var scavenging := get_tree().get_first_node_in_group("scavenging")
                    if scavenging != null:
                        scavenging.release_target(self)
                route_refresh = 0.0
                progress_time = 0.0
                _pick_target()

func _route_direction(fallback: Vector3) -> Vector3:
    var scavenging := get_tree().get_first_node_in_group("scavenging")
    if scavenging == null:
        return fallback
    if route_refresh <= 0 or route_destination.distance_to(target) > 1.0:
        route_points = scavenging.route(global_position, target)
        route_destination = target
        route_index = 0
        route_refresh = 2.0
    while route_index < route_points.size():
        var direction := route_points[route_index] - global_position
        direction.y = 0
        if direction.length() > 0.55:
            return direction
        route_index += 1
    return fallback

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
    var walk_clip := "Walk With Gun" if equipped_gun != null else "Walk"
    var run_clip := "Run with Gun" if equipped_gun != null else "run"
    if moving:
        var clip := run_clip if sprinting else walk_clip
        if animation.current_animation != clip or not animation.is_playing():
            animation.play(clip, 0.18)
    elif animation.is_playing() or animation.current_animation != walk_clip:
        # Use a still frame of the supplied walk clip; no idle clip was supplied.
        animation.play(walk_clip)
        animation.seek(0.33, true)
        animation.pause()

func try_pickup_scrap(scrap: RigidBody3D) -> bool:
    if dead:
        return false
    if not player_controlled:
        if delivery_wait > 0 or (is_instance_valid(pending_gun) and pending_gun.equipped_by == null):
            return false
        if is_instance_valid(scrap_target) and scrap_target != scrap:
            return false
    if equipped_gun != null or carried_scrap != null or throwing or pickup_grace > 0 or not scrap.claim(self):
        return false
    carried_scrap = scrap
    scrap_target = null
    var scavenging := get_tree().get_first_node_in_group("scavenging")
    if scavenging != null:
        scavenging.release_target(self)
    carry_animation.active = true
    carry_animation.play("Hands up")
    carry_animation.advance(0.0)
    _update_hand_socket()
    return true

func try_equip_gun(gun: RigidBody3D) -> bool:
    if dead or gun_pickup_grace > 0 or carried_scrap != null or throwing:
        return false
    if equipped_gun != null and equipped_gun.ammo >= gun.ammo:
        return false
    if not gun.claim(self):
        return false
    if equipped_gun != null:
        equipped_gun.drop(global_position + Vector3.UP, velocity)
    equipped_gun = gun
    gun_pickup_grace = 0.8
    scrap_target = null
    var scavenging := get_tree().get_first_node_in_group("scavenging")
    if scavenging != null:
        scavenging.release_target(self)
    pending_gun = null
    carry_animation.stop()
    carry_animation.active = false
    _animate(false, false)
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
    if is_instance_valid(gun_socket):
        var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Bone.008.R"))
        var orientation := Basis(Vector3.LEFT, Vector3.BACK, Vector3.UP)
        gun_socket.global_transform = Transform3D((wrist.basis * orientation).orthonormalized(), wrist.origin + wrist.basis.y.normalized() * 0.08)

func begin_throw(aim_direction: Vector3 = Vector3.ZERO) -> void:
    if dead or (carried_scrap == null and equipped_gun == null) or throwing:
        return
    throwing = true
    throw_elapsed = 0.0
    throw_released = false
    carry_animation.stop()
    carry_animation.active = false
    throw_direction = -$CameraPivot/SpringArm3D/Camera3D.global_basis.z if player_controlled else model.global_basis.z
    if not aim_direction.is_zero_approx():
        throw_direction = aim_direction
    throw_direction.y = clampf(throw_direction.y, -0.15, 0.65)
    throw_direction = throw_direction.normalized()
    model.rotation.y = atan2(throw_direction.x, throw_direction.z)
    animation.play("Throw", 0.04)

func _release_scrap() -> void:
    throw_released = true
    if carried_scrap == null and equipped_gun != null:
        _update_hand_socket()
        var gun := equipped_gun
        equipped_gun = null
        pending_gun = null
        # The thrown gun has its own anti-recatch delay. Other ground guns
        # should be collectable as soon as the throw animation finishes.
        gun_pickup_grace = 0.0
        gun.launch(gun.global_position, throw_direction, velocity)
        return
    if carried_scrap == null:
        return
    _update_hand_socket()
    var scrap := carried_scrap
    carried_scrap = null
    pickup_grace = 0.8
    delivery_wait = 2.5
    scrap.launch(throw_direction, velocity)

func _shoot_from_camera() -> void:
    if dead or throwing or equipped_gun == null:
        return
    var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
    var direction := -camera.global_basis.z
    var endpoint := camera.global_position + direction * 150.0
    var query := PhysicsRayQueryParameters3D.create(camera.global_position, endpoint, 3, [get_rid()])
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        endpoint = hit.position
    model.rotation.y = atan2(direction.x, direction.z)
    _update_hand_socket()
    equipped_gun.fire_at(endpoint)

func take_bullet(shooter: Node3D) -> void:
    if dead or shooter == self:
        return
    health = maxi(0, health - 1)
    if health > 0:
        return
    dead = true
    fire_requested = false
    throwing = false
    animation.pause()
    carry_animation.stop()
    carry_animation.active = false
    model.hide()
    set_deferred("collision_layer", 0)
    set_deferred("collision_mask", 0)
    set_physics_process(false)
    var scavenging := get_tree().get_first_node_in_group("scavenging")
    if scavenging != null:
        scavenging.release_target(self)
    scrap_target = null
    if equipped_gun != null:
        equipped_gun.drop(global_position + Vector3.UP, velocity)
        equipped_gun = null
    if carried_scrap != null:
        _drop_scrap_on_death.call_deferred()
    if player_controlled:
        capture_requested = false
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    died.emit(self, shooter)

func _drop_scrap_on_death() -> void:
    if carried_scrap == null:
        return
    var scrap := carried_scrap
    carried_scrap = null
    scrap.launch(Vector3.ZERO, Vector3.ZERO)
    scrap.last_thrower = null

func _notification(what: int) -> void:
    if not player_controlled:
        return
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN and capture_requested:
        Input.set_mouse_mode.call_deferred(Input.MOUSE_MODE_CAPTURED)
