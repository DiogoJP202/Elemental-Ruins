class_name IceBody
extends RigidBody3D
## Corpo da sessão: a temperatura pertence ao MaterialResponseSystem.
## Fusão/limite removem a física primeiro; ElementalFx conserva só uma cópia visual curta.
const GROUP := &"persistent_ice"
const WALL_SUPPORT_TOLERANCE := 0.12
const WALL_FLOOR_NORMAL_Y := 0.85
enum ShapeKind { SPHERE, WALL }
var shape_kind: ShapeKind = ShapeKind.SPHERE
var wall_size := Vector3.ZERO
var wall_anchored := false
var ice_radius := 0.33
var volume_liters := 150.0
var melt_duration_s := 0.45
var material_id: StringName = BodyMaterialLibrary.ICE
var _materials: MaterialResponseSystem
var _notify := Callable()
var _retiring := false
var _terrain: TerrainService


func setup(tuning: WaterOrbTuning, radius: float, liters: float,
		materials: MaterialResponseSystem, notify: Callable, p_wall_size: Vector3 = Vector3.ZERO) -> void:
	wall_size = p_wall_size
	shape_kind = ShapeKind.WALL if wall_size != Vector3.ZERO else ShapeKind.SPHERE
	ice_radius = radius
	volume_liters = liters
	melt_duration_s = maxf(tuning.ice_melt_duration_s, 0.05)
	_materials = materials
	_notify = notify
	name = "PersistentIce"
	mass = maxf(liters * 0.001 * tuning.ice_density, 0.1)
	collision_layer = Layers.PROPS
	collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
	continuous_cd = true
	var surface := PhysicsMaterial.new()
	surface.friction = 0.6
	surface.bounce = 0.0
	physics_material_override = surface
	var shape := CollisionShape3D.new()
	shape.name = "IceCollision"
	if shape_kind == ShapeKind.WALL:
		var box := BoxShape3D.new()
		box.size = wall_size
		shape.shape = box
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true # Restrição estrutural explícita; não é repouso natural.
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Crystal"
	mesh.mesh = wall_mesh(wall_size) if shape_kind == ShapeKind.WALL else crystal_mesh(radius)
	var visual := StandardMaterial3D.new()
	visual.albedo_color = tuning.ice_color
	visual.albedo_color.a = 1.0
	visual.vertex_color_use_as_albedo = true
	visual.roughness = 0.24
	visual.metallic = 0.12
	visual.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = visual
	add_child(mesh)
	var material: BodyMaterial = BodyMaterialLibrary.get_by_id(BodyMaterialLibrary.ICE).duplicate(true)
	material.density = tuning.ice_density
	material.initial_temperature = minf(tuning.ice_initial_temperature, tuning.ice_melt_temperature - 1.0)
	material.melt_temperature = tuning.ice_melt_temperature
	set_meta("body_material", material)
	# Sem volume_m3: o seletor de rochas P4B não pode capturar gelo.
	add_to_group(DebrisBudget.GROUP)
	add_to_group(GROUP)
	_materials.melted.connect(_on_melted)
	_materials.state_of(self)


func anchor_wall(terrain: TerrainService) -> void:
	if shape_kind != ShapeKind.WALL:
		return
	_terrain = terrain
	wall_anchored = true
	check_wall_support()


## TerrainContactWaker chama isto nos mesmos pulsos que acordam os destroços.
func check_wall_support() -> bool:
	if not wall_anchored:
		return false
	if _retiring or not is_instance_valid(_terrain) or not _terrain.is_ready():
		return true
	if wall_supported(_terrain, global_transform, wall_size):
		return true
	wall_anchored = false
	freeze = false
	sleeping = false
	return false


## Painel vertical: ambos os lados da base precisam de chão próximo e pouco inclinado.
static func wall_supported(terrain: TerrainService, at: Transform3D, size: Vector3) -> bool:
	if not is_instance_valid(terrain) or not terrain.is_ready():
		return false
	var half := size * 0.5
	for x: float in [-maxf(half.x - 0.02, 0.0), 0.0, maxf(half.x - 0.02, 0.0)]:
		for z: float in [-maxf(half.z - 0.005, 0.0), maxf(half.z - 0.005, 0.0)]:
			var foot := at * Vector3(x, -half.y, z)
			var hit := terrain.raycast_terrain(foot + Vector3.UP * WALL_SUPPORT_TOLERANCE,
				foot + Vector3.DOWN * WALL_SUPPORT_TOLERANCE)
			if hit.is_empty() or hit.normal.y < WALL_FLOOR_NORMAL_Y:
				return false
			# sample_sdf arredonda para 1 m: mesma profundidade conservadora das âncoras de estruturas.
			# Também invalida suporte removido antes de chegar o novo collider assíncrono.
			var sdf := terrain.sample_sdf(foot + Vector3.DOWN * 0.6)
			if is_nan(sdf) or sdf >= 0.0:
				return false
	return true


func can_retire() -> bool:
	return not _retiring and not is_queued_for_deletion() and not has_meta(DebrisBudget.EARTH_HELD_META)


func _on_melted(body: Node3D) -> void:
	if body == self:
		retire("melt")


func retire(reason: String) -> void:
	if _retiring:
		return
	_retiring = true
	wall_anchored = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group(DebrisBudget.GROUP)
	remove_from_group(GROUP)
	if _notify.is_valid():
		_notify.call(self, reason)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_materials):
		if _materials.melted.is_connected(_on_melted):
			_materials.melted.disconnect(_on_melted)
		_materials.forget_body(self)


## Mesma malha do P4F, compartilhada com ElementalFx; inscrita na esfera de colisão.
static func crystal_mesh(size: float) -> ArrayMesh:
	var points := PackedVector3Array([Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0.9, 0, 0), Vector3(0, 0, 0.9), Vector3(-0.9, 0, 0), Vector3(0, 0, -0.9)])
	var faces: Array[Vector3i] = [Vector3i(0, 2, 3), Vector3i(0, 3, 4), Vector3i(0, 4, 5), Vector3i(0, 5, 2),
		Vector3i(1, 3, 2), Vector3i(1, 4, 3), Vector3i(1, 5, 4), Vector3i(1, 2, 5)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in faces.size():
		var face: Vector3i = faces[i]
		var a: Vector3 = points[face.x]
		var b: Vector3 = points[face.y]
		var c: Vector3 = points[face.z]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(a + b + c) < 0.0:
			normal = -normal
		var shade := 1.0 - float(i % 3) * 0.09
		for point: Vector3 in [a, b, c]:
			vertices.append(point * size)
			normals.append(normal)
			colors.append(Color(shade, shade, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Painel com borda chanfrada e faces trianguladas; toda a malha fica dentro da caixa nominal.
static func wall_mesh(size: Vector3) -> ArrayMesh:
	var half := size * 0.5
	var cut := minf(size.x, size.y) * 0.055
	var outline := PackedVector2Array([Vector2(-half.x + cut, -half.y), Vector2(half.x - cut, -half.y),
		Vector2(half.x, -half.y + cut), Vector2(half.x, half.y - cut * 1.3),
		Vector2(half.x - cut * 1.3, half.y), Vector2(-half.x + cut * 0.8, half.y),
		Vector2(-half.x, half.y - cut * 0.8), Vector2(-half.x, -half.y + cut)])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for side: float in [-1.0, 1.0]:
		for i in outline.size():
			var a := outline[i]
			var b := outline[(i + 1) % outline.size()]
			var inside_a := Vector3(a.x * 0.94, a.y * 0.94, half.z * side)
			var inside_b := Vector3(b.x * 0.94, b.y * 0.94, half.z * side)
			var edge_a := Vector3(a.x, a.y, 0.0)
			var edge_b := Vector3(b.x, b.y, 0.0)
			var center := Vector3(size.x * 0.025, size.y * 0.035, half.z * side)
			var shade := 0.86 + float(i % 3) * 0.06
			for triangle: Array in [[center, inside_a, inside_b], [inside_a, edge_a, edge_b], [inside_a, edge_b, inside_b]]:
				var normal: Vector3 = ((triangle[1] as Vector3) - triangle[0]).cross((triangle[2] as Vector3) - triangle[0]).normalized()
				if normal.z * side < 0.0: normal = -normal
				for point: Vector3 in triangle:
					vertices.append(point)
					normals.append(normal)
					colors.append(Color(shade, minf(shade + 0.04, 1.0), 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
