class_name DebugProps
extends RefCounted
## Caixas RigidBody3D de teste, para verificar se formas novas do terreno
## sustentam objetos físicos. Não são props de gameplay.

const CRATE_SIZE := 1.0
const CRATE_MASS := 20.0


static func spawn_crate(parent: Node3D, world_position: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "TestCrate"
	body.mass = CRATE_MASS
	body.collision_layer = Layers.PROPS
	body.collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
	body.continuous_cd = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * CRATE_SIZE
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * CRATE_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#D4A546")
	box_mesh.material = mat
	mesh.mesh = box_mesh
	body.add_child(mesh)

	parent.add_child(body)
	body.global_position = world_position
	return body
