class_name TerrainMaterial
extends Resource
## Definição física simplificada de um material de terreno (P1).
##
## `index` é o valor gravado no canal INDICES de cada voxel e é a ÚNICA ligação entre
## o dado voxel e esta definição. Regras de jogo leem hardness/density/bendable daqui;
## o shader só recebe surface_color. Nada é deduzido de textura, cor ou peso de pintura.

@export var id: StringName
## Valor no canal INDICES (0–255; formato de 8 bits).
@export var index := 0
@export var display_name := ""
## Resistência relativa à escavação (soil = 1). Escala o intervalo da escavação contínua.
@export var hardness := 1.0
## kg/m³. Usado na massa ESTIMADA de cada brush (volume nominal × densidade).
@export var density := 1500.0
## Se a dobra de terra pode moldá-lo. false = a fila de brushes recusa a edição.
@export var bendable := true
## Cor de superfície no material de laboratório.
@export var surface_color := Color.WHITE


static func create(p_id: StringName, p_index: int, p_name: String, p_hardness: float,
		p_density: float, p_bendable: bool, p_color: Color) -> TerrainMaterial:
	var m := TerrainMaterial.new()
	m.id = p_id
	m.index = p_index
	m.display_name = p_name
	m.hardness = p_hardness
	m.density = p_density
	m.bendable = p_bendable
	m.surface_color = p_color
	return m


func _to_string() -> String:
	return "%s(dureza %.1f, %d kg/m³%s)" % [id, hardness, density, "" if bendable else ", não dobrável"]
