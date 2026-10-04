extends Node

var actor: CharacterBody3D
var opponent: CharacterBody3D
var decision_time := 0.0
var fire_time := 0.8

func update(delta: float) -> bool:
    decision_time -= delta
    fire_time -= delta
    if actor.dead or not actor.released or actor.leaving_elevator or actor.carried_scrap != null:
        return false
    if actor.equipped_gun == null or actor.equipped_gun.ammo <= 0:
        if decision_time <= 0:
            decision_time = 0.5
            var closest := INF
            for gun in get_tree().get_nodes_in_group("guns"):
                if gun.equipped_by != null or gun.ammo <= 0:
                    continue
                var distance: float = actor.global_position.distance_squared_to(gun.global_position)
                if distance < closest:
                    closest = distance
                    actor.pending_gun = gun
        return false
    if decision_time <= 0 or not is_instance_valid(opponent) or opponent.dead:
        decision_time = 0.6
        opponent = null
        var closest := INF
        for other in get_tree().get_nodes_in_group("characters"):
            if other == actor or other.dead:
                continue
            var distance: float = actor.global_position.distance_squared_to(other.global_position)
            if distance < closest:
                closest = distance
                opponent = other
    if not is_instance_valid(opponent):
        actor.target = actor.global_position
        return true
    var aim_point := opponent.global_position + Vector3.UP * 1.1
    var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.35, aim_point, 3, [actor.get_rid()])
    var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
    var visible: bool = not hit.is_empty() and hit.collider == opponent
    var distance := actor.global_position.distance_to(opponent.global_position)
    actor.target = actor.global_position if visible and distance < 18.0 else opponent.global_position
    actor.running = distance > 18.0
    if visible and distance < 55.0:
        var facing := aim_point - actor.global_position
        actor.model.rotation.y = atan2(facing.x, facing.z)
        actor._update_hand_socket()
        if fire_time <= 0:
            # The NPCs use the same bullets and cover checks, with imperfect aim.
            var spread := minf(0.9, distance * 0.025)
            aim_point += Vector3(actor.rng.randf_range(-spread, spread), actor.rng.randf_range(-spread, spread), actor.rng.randf_range(-spread, spread))
            actor.equipped_gun.fire_at(aim_point)
            fire_time = actor.rng.randf_range(0.55, 0.95)
    return true
