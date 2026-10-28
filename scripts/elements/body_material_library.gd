class_name BodyMaterialLibrary
extends RefCounted
## Materiais de corpos do P3. Rochas extraídas usam o id do material do terreno de onde
## saíram (soil/sand/stone); caixas de teste são de madeira; peças da torre declaram o seu.

const WOOD := &"wood"
const STONE := &"stone"
const SOIL := &"soil"
const SAND := &"sand"
const ICE := &"ice"

static var _all: Array[BodyMaterial] = []


static func all() -> Array[BodyMaterial]:
	if _all.is_empty():
		var ice := BodyMaterial.create(ICE, "Gelo", 917.0, false, 0.0, 0.0, 30.0, 2.0, 0.03, 0.0, 6.0, Color("#C4E5F5"))
		ice.initial_temperature = -20.0
		ice.melt_temperature = 0.0
		_all = [
			#                    id     nome      kg/m³  infl.  ign.°C combust. resist. resfr. secagem dano/s Δv quebra
			BodyMaterial.create(WOOD, "Madeira", 600.0, true, 300.0, 12.0, 1.0, 15.0, 0.04, 0.08, 4.0, Color("#8B5A2B")),
			BodyMaterial.create(STONE, "Pedra", 2600.0, false, 0.0, 0.0, 3.0, 6.0, 0.02, 0.0, 6.0, Color("#9A8F84")),
			BodyMaterial.create(SOIL, "Solo", 1500.0, false, 0.0, 0.0, 2.0, 8.0, 0.02, 0.0, 3.0, Color("#B87968")),
			BodyMaterial.create(SAND, "Areia", 1600.0, false, 0.0, 0.0, 2.0, 8.0, 0.03, 0.0, 2.0, Color("#DCC7A7")),
			ice,
		]
	return _all


static func get_by_id(id: StringName) -> BodyMaterial:
	for m in all():
		if m.id == id:
			return m
	return null


## Material de um corpo: `body_material` (id ou Resource por instância) > `material_id` (peça de estrutura ou meta de
## rocha extraída). null = corpo sem reação elemental.
static func of_body(body: Node) -> BodyMaterial:
	if body == null:
		return null
	if body.has_meta("body_material"):
		var material = body.get_meta("body_material")
		return material as BodyMaterial if material is BodyMaterial else get_by_id(material)
	var id = body.get("material_id")
	if id == null and body.has_meta("material_id"):
		id = body.get_meta("material_id")
	return get_by_id(id) if id != null and id != &"" else null
