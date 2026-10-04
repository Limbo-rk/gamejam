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
var target := Vector3.ZERO
var home := Vector3.ZERO
var running := false
var change_timer := 0.0
var stuck_time := 0.0
var rng := RandomNumberGenerator.new()
@onready var model: Node3D = $CharacterModel
@onready var animation: AnimationPlayer = $CharacterModel/AnimationPlayer
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot")

func _ready() -> void:
    rng.seed = wander_seed
    home = global_position
    for clip in ["Walk", "run"]:
        animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
    _apply_colors()
    _animate(false, false)
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

func _unhandled_input(event: InputEvent) -> void:
    if not player_controlled:
        return
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
        var arm: SpringArm3D = $CameraPivot/SpringArm3D
        arm.rotation.x = clampf(arm.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-60), deg_to_rad(20))

func release_from_elevator(center: Vector3) -> void:
    home = center
    released = true
    running = bool(wander_seed % 2)
    change_timer = rng.randf_range(3.0, 6.0)
    _pick_target()

func _pick_target() -> void:
    target = home + Vector3(rng.randf_range(-8.5, 8.5), 0, rng.randf_range(-8.5, 8.5))

func _physics_process(delta: float) -> void:
    var direction := Vector3.ZERO
    if player_controlled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        direction = camera_pivot.global_basis * Vector3(axes.x, 0, axes.y)
        running = Input.is_action_pressed("sprint")
    elif not player_controlled and released:
        change_timer -= delta
        if change_timer <= 0:
            running = not running
            change_timer = rng.randf_range(3.0, 7.0)
            _pick_target()
        direction = target - global_position
        direction.y = 0
        if direction.length() < 0.7:
            _pick_target()
        direction = direction.normalized()
    direction.y = 0
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
    move_and_slide()
    var moved := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
    var walking := direction.length_squared() > 0.01 and moved > delta * 0.1
    _animate(walking, running)
    if not player_controlled and released:
        stuck_time = stuck_time + delta if not walking else 0.0
        if stuck_time > 0.8:
            _pick_target()
            stuck_time = 0.0

func _animate(moving: bool, sprinting: bool) -> void:
    if moving:
        var clip := "run" if sprinting else "Walk"
        if animation.current_animation != clip or not animation.is_playing():
            animation.play(clip, 0.18)
    elif animation.is_playing() or animation.current_animation.is_empty():
        # Use a still frame of the supplied walk clip; no idle clip was supplied.
        animation.play("Walk")
        animation.seek(0.33, true)
        animation.pause()

func _notification(what: int) -> void:
    if player_controlled and what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
