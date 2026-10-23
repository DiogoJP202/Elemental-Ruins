class_name TerrainMaterialLibrary
extends RefCounted
## Os três materiais simplificados do P1, indexados pelo valor do canal INDICES.
## Valores são escolhas de laboratório (docs/decisions.md, D15), não dados medidos.
## Cores da paleta do GDD v0.2.

const SOIL := &"soil"
const SAND := &"sand"
const STONE := &"stone"

const INDEX_SOIL := 0
const INDEX_SAND := 1
const INDEX_STONE := 2

static var _materials: Array[TerrainMaterial] = []


static func all() -> Array[TerrainMaterial]:
	if _materials.is_empty():
		_materials = [
			TerrainMaterial.create(SOIL, INDEX_SOIL, "Solo", 1.0, 1500.0, true, Color("#B87968")),
			TerrainMaterial.create(SAND, INDEX_SAND, "Areia", 0.5, 1600.0, true, Color("#DCC7A7")),
			TerrainMaterial.create(STONE, INDEX_STONE, "Pedra", 3.0, 2600.0, true, Color("#65786A")),
		]
	return _materials


## null para índice desconhecido.
static func get_by_index(index: int) -> TerrainMaterial:
	var list := all()
	return list[index] if index >= 0 and index < list.size() else null


static func get_by_id(id: StringName) -> TerrainMaterial:
	for m in all():
		if m.id == id:
			return m
	return null


## Cores de superfície em espaço linear, na ordem dos índices (uniform do shader).
static func linear_surface_colors() -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in all():
		var c := m.surface_color.srgb_to_linear()
		out.append(Vector3(c.r, c.g, c.b))
	return out
