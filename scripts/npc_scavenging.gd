extends NavigationRegion3D

# Reservations distribute the NPCs without preventing the player from taking an item.
var reservations: Dictionary = {}

func _ready() -> void:
    name = "ScavengingRoutes"
    add_to_group("scavenging")
    NavigationServer3D.map_set_cell_size(get_navigation_map(), 0.35)
    NavigationServer3D.map_set_cell_height(get_navigation_map(), 0.15)
    NavigationServer3D.map_set_merge_rasterizer_cell_scale(get_navigation_map(), 0.1)
    navigation_mesh = preload("res://navigation/scavenging.tres")

func available(item: Node3D) -> bool:
    return is_instance_valid(item) and item.held_by == null and not item.deposited and item.pickup_cooldown <= 0.0

func release_target(actor: Node3D) -> void:
    for id in reservations.keys():
        if reservations[id].get_ref() == actor or reservations[id].get_ref() == null:
            reservations.erase(id)

func choose_scrap(actor: Node3D) -> Node3D:
    release_target(actor)
    var candidates: Array[Dictionary] = []
    var preferred_distance: float = [0.0, 110.0, 220.0][actor.wander_seed % 3]
    var preferred_angle := float(actor.wander_seed) * 2.399963
    for item in get_tree().get_nodes_in_group("scraps"):
        if not available(item) or actor.avoided_scraps.has(item.get_instance_id()):
            continue
        var id := item.get_instance_id()
        if reservations.has(id) and reservations[id].get_ref() != null:
            continue
        var offset: Vector3 = item.global_position - actor.global_position
        offset.y = 0
        var angle_cost := absf(angle_difference(preferred_angle, atan2(offset.z, offset.x))) * 15.0
        candidates.append({"item": item, "score": absf(offset.length() - preferred_distance) + angle_cost})
    candidates.sort_custom(func(a, b): return a.score < b.score)
    for candidate in candidates:
        var path := route(actor.global_position, candidate.item.global_position)
        if path.is_empty():
            continue
        reservations[candidate.item.get_instance_id()] = weakref(actor)
        return candidate.item
    return null

func route(from: Vector3, destination: Vector3) -> PackedVector3Array:
    var map := get_navigation_map()
    if NavigationServer3D.map_get_iteration_id(map) == 0:
        return PackedVector3Array()
    var path := NavigationServer3D.map_get_path(map, from, destination, true)
    if path.is_empty() or Vector2(path[-1].x - destination.x, path[-1].z - destination.z).length() > 2.0:
        return PackedVector3Array()
    return path
