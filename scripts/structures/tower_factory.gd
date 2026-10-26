class_name TowerFactory
extends RefCounted
## Monta a torre modular de laboratório do P2/P3 (36 peças), sempre igual:
##   térreo: 4 pilares de canto com 3 blocos 1 × 1,5 × 1 m (até y = 4,5)
##   laje 1: 4 placas 3 × 0,5 × 3 m (laje pré-fraturada), cada uma sobre um pilar
##   2º andar: 4 pilares de 2 blocos de MADEIRA (P3), um sobre cada placa (até y = 8)
##   laje 2: 4 placas iguais às da laje 1
##   coroa: 8 blocos 1 × 1 × 1 m na borda (os do meio de cada lado apoiam em 2 placas)
## Peças congeladas, camada PROPS, massa = volume × densidade do material (pedra ou madeira).
## A madeira do 2º andar queima (P3): queimar os 2 pilares de um lado derruba as placas de cima.

const FOOT_LIFT := 0.05  # folga sobre o chão (o collider do plano fica em y ≈ 0,02)
const PILLAR := Vector3(1.0, 1.5, 1.0)
const SLAB := Vector3(3.0, 0.5, 3.0)
const CROWN := Vector3(1.0, 1.0, 1.0)
const HALF_SPAN := 2.5  # centro dos pilares a ±2,5 m do centro da torre

const COLOR := Color("#9A8F84")
const WOOD_COLOR := Color("#8B5A2B")


static func build(parent: Node3D, origin: Vector3, name := "Tower") -> Array[StructurePiece]:
	var tower := Node3D.new()
	tower.name = name
	parent.add_child(tower)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = 0.9
	var density := TerrainMaterialLibrary.get_by_id(TerrainMaterialLibrary.STONE).density
	var wood_material := StandardMaterial3D.new()
	wood_material.albedo_color = WOOD_COLOR
	wood_material.roughness = 0.85
	var wood_density := BodyMaterialLibrary.get_by_id(BodyMaterialLibrary.WOOD).density
	var pieces: Array[StructurePiece] = []
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	var y := FOOT_LIFT
	# Térreo.
	for c: Vector2 in corners:
		for k in 3:
			_add(tower, pieces, "pilar0", Vector3(c.x * HALF_SPAN, y + PILLAR.y * (k + 0.5), c.y * HALF_SPAN), PILLAR, material, density, origin)
	y += PILLAR.y * 3
	_add_slab(tower, pieces, "laje1", y, corners, material, density, origin)
	y += SLAB.y
	for c: Vector2 in corners:
		for k in 2:
			_add(tower, pieces, "pilar1", Vector3(c.x * HALF_SPAN, y + PILLAR.y * (k + 0.5), c.y * HALF_SPAN), PILLAR, wood_material, wood_density, origin,
				BodyMaterialLibrary.WOOD)
	y += PILLAR.y * 2
	_add_slab(tower, pieces, "laje2", y, corners, material, density, origin)
	y += SLAB.y
	var crown := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
		Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for c: Vector2 in crown:
		_add(tower, pieces, "coroa", Vector3(c.x * HALF_SPAN, y + CROWN.y * 0.5, c.y * HALF_SPAN), CROWN, material, density, origin)
	SupportGraph.link(pieces)
	return pieces


static func _add_slab(tower: Node3D, pieces: Array[StructurePiece], kind: String, y: float, corners: Array,
		material: Material, density: float, origin: Vector3) -> void:
	for c: Vector2 in corners:
		_add(tower, pieces, kind, Vector3(c.x * SLAB.x * 0.5, y + SLAB.y * 0.5, c.y * SLAB.z * 0.5), SLAB, material, density, origin)


static func _add(tower: Node3D, pieces: Array[StructurePiece], kind: String, local_center: Vector3, size: Vector3,
		material: Material, density: float, origin: Vector3, material_id: StringName = BodyMaterialLibrary.STONE) -> void:
	var p := StructurePiece.new()
	p.piece_index = pieces.size()
	p.kind = kind
	p.material_id = material_id
	p.size = size
	p.name = "P%02d_%s" % [p.piece_index, kind]
	p.mass = size.x * size.y * size.z * density
	p.collision_layer = Layers.PROPS
	p.collision_mask = Layers.TERRAIN | Layers.PLAYER | Layers.PROPS
	p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	p.freeze = true
	p.continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	p.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mesh.mesh = bm
	p.add_child(mesh)
	p.home = Transform3D(Basis.IDENTITY, origin + local_center)
	p.is_foot = local_center.y - size.y * 0.5 < FOOT_LIFT + 0.01
	tower.add_child(p)
	p.global_transform = p.home
	pieces.append(p)
