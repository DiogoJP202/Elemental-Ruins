class_name IceBody
extends RigidBody3D
## Corpo da sessão: a temperatura pertence ao MaterialResponseSystem.
## Fusão/limite removem a física primeiro; ElementalFx conserva só uma cópia visual curta.
const GROUP := &"persistent_ice"
var ice_radius := 0.33
var volume_liters := 150.0
var melt_duration_s := 0.45
var material_id: StringName = BodyMaterialLibrary.ICE
var _materials: MaterialResponseSystem
var _notify := Callable()
var _retiring := false


func setup(tuning: WaterOrbTuning, radius: float, liters: float,
		materials: MaterialResponseSystem, notify: Callable) -> void:
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
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Crystal"
	mesh.mesh = crystal_mesh(radius)
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


func can_retire() -> bool:
	return not _retiring and not is_queued_for_deletion() and not has_meta(DebrisBudget.EARTH_HELD_META)


func _on_melted(body: Node3D) -> void:
	if body == self:
		retire("melt")


func retire(reason: String) -> void:
	if _retiring:
		return
	_retiring = true
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
