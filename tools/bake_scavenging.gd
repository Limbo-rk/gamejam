extends SceneTree

# Run with Godot --headless --path <project> --script res://tools/bake_scavenging.gd
# Rebuild after changing terrain, elevator walls, or rock placement.
func _initialize() -> void:
    bake.call_deferred()

func bake() -> void:
    var game := preload("res://node_3d.tscn").instantiate()
    # Baking needs only authored geometry, not the elevator's gameplay timers.
    game.set_script(null)
    root.add_child(game)
    var source := NavigationMeshSourceGeometryData3D.new()
    var terrain: MeshInstance3D = game.get_node("scrap jam/Map")
    source.add_mesh(terrain.mesh, terrain.global_transform)
    for rock in game.get_node("Rocks").get_children():
        var mesh: MeshInstance3D = rock.get_node("Model")
        source.add_mesh(mesh.mesh, mesh.global_transform)
    var walls: MeshInstance3D = game.get_node("ElevatorSideWalls/Cube_003")
    source.add_mesh(walls.mesh, walls.global_transform)
    var mesh := NavigationMesh.new()
    mesh.cell_size = 0.35
    mesh.cell_height = 0.15
    mesh.agent_radius = 0.7
    mesh.agent_height = 2.1
    mesh.agent_max_climb = 0.3
    mesh.agent_max_slope = 42.0
    NavigationServer3D.bake_from_source_geometry_data(mesh, source)
    _remove_overlapping_detail_triangles(mesh)
    var result := ResourceSaver.save(mesh, "res://navigation/scavenging.tres")
    print("Scavenging routes: %d polygons; save result %d" % [mesh.get_polygon_count(), result])
    game.free()
    await process_frame
    quit(0 if result == OK else 1)

func _remove_overlapping_detail_triangles(mesh: NavigationMesh) -> void:
    # The terrain bake can create a duplicate bridge triangle sharing two edges
    # with already connected faces. Remove these bridges, preserving their neighbors.
    var edges: Dictionary = {}
    var polygons: Array[PackedInt32Array] = []
    for i in mesh.get_polygon_count():
        var polygon := mesh.get_polygon(i)
        polygons.append(polygon)
        for j in polygon.size():
            var a := polygon[j]
            var b := polygon[(j + 1) % polygon.size()]
            var edge := Vector2i(mini(a, b), maxi(a, b))
            if not edges.has(edge):
                edges[edge] = []
            edges[edge].append(i)
    var overlaps: Dictionary = {}
    for faces in edges.values():
        if faces.size() > 2:
            for i in faces:
                overlaps[i] = int(overlaps.get(i, 0)) + 1
    mesh.clear_polygons()
    for i in polygons.size():
        if int(overlaps.get(i, 0)) < 2:
            mesh.add_polygon(polygons[i])
