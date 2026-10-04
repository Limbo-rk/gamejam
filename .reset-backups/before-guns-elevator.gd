extends Node3D

@export_range(0.0, 60.0, 0.1) var start_delay: float = 5.0
@onready var elevator_animation: AnimationPlayer = $ElevatorAnimation
var platform_body: AnimatableBody3D
var cage_body: AnimatableBody3D
var platform_mesh: MeshInstance3D
var cage_mesh: MeshInstance3D

func _ready() -> void:
	# Hold the authored starting pose during the delay, then play once.
	elevator_animation.play("ElevatorRise")
	elevator_animation.seek(0.0, true)
	elevator_animation.pause()
	platform_mesh = get_node("scrap jam/Cube_005")
	cage_mesh = get_node("scrap jam/Cube_004")
	_static_body(get_node("scrap jam/Map"), "GroundCollision")
	_static_body(get_node("ElevatorSideWalls/Cube_003"), "ShaftCollision")
	platform_body = _moving_body(platform_mesh, "PlatformCollision")
	cage_body = _moving_body(cage_mesh, "CageCollision")
	var floor_bounds := platform_mesh.global_transform * platform_mesh.get_aabb()
	# Include the small perimeter seam in the platform's collision surface.
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(27.8, 0.12, 27.8)
	var collider: CollisionShape3D = platform_body.get_child(0)
	collider.shape = floor_shape
	collider.position.y = floor_bounds.end.y - platform_body.global_position.y - 0.06
	for actor in get_tree().get_nodes_in_group("characters"):
		actor.global_position.y = floor_bounds.end.y + 0.04
		actor.start_on_elevator(Vector3(platform_mesh.global_position.x, floor_bounds.end.y, platform_mesh.global_position.z))
	await get_tree().create_timer(start_delay, false).timeout
	elevator_animation.play("ElevatorRise")
	await elevator_animation.animation_finished
	var final_bounds := platform_mesh.global_transform * platform_mesh.get_aabb()
	for actor in get_tree().get_nodes_in_group("characters"):
		actor.release_from_elevator(Vector3(platform_mesh.global_position.x, final_bounds.end.y, platform_mesh.global_position.z))

func _physics_process(_delta: float) -> void:
	if platform_body:
		platform_body.global_position = platform_mesh.global_position
		cage_body.global_position = cage_mesh.global_position

func _shape(mesh: MeshInstance3D, origin: Vector3) -> ConcavePolygonShape3D:
	var vertices := mesh.mesh.get_faces()
	for i in vertices.size():
		vertices[i] = mesh.global_transform * vertices[i] - origin
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	shape.backface_collision = true
	return shape

func _static_body(mesh: MeshInstance3D, body_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = _shape(mesh, Vector3.ZERO)
	body.add_child(collider)

func _moving_body(mesh: MeshInstance3D, body_name: String) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = body_name
	body.sync_to_physics = false
	add_child(body)
	body.global_position = mesh.global_position
	var collider := CollisionShape3D.new()
	collider.shape = _shape(mesh, body.global_position)
	body.add_child(collider)
	return body
