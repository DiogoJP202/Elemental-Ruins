class_name LabTerrainFactory
extends RefCounted
## Monta o terreno volumétrico do laboratório P0.
##
## O mundo-base é um SDF determinístico: plano y = GROUND_HEIGHT unido (smooth
## union) a uma esfera parcialmente enterrada, que forma a colina do túnel.
## O gerador é um VoxelGeneratorGraph nativo construído em código: a variante
## GDExtension do Voxel Tools tem limitações com geradores em script
## (godot_voxel#442), e o grafo roda em C++ nas threads do motor voxel.
## Os nomes de portas usados aqui foram conferidos no binário instalado
## (docs/evidence/voxel_api_probe.txt).

const GROUND_HEIGHT := 0.0
const HILL_CENTER := Vector3(0.0, -12.0, -10.0)
const HILL_RADIUS := 24.0
const HILL_BLEND := 4.0
## Topo da colina = HILL_CENTER.y + HILL_RADIUS.
const HILL_TOP_Y := HILL_CENTER.y + HILL_RADIUS

## Limites dos dados voxel (coordenadas locais do terreno = mundo, pois o nó
## fica na origem sem escala). Edições fora disso são recusadas.
const VOXEL_BOUNDS := AABB(Vector3(-256, -64, -256), Vector3(512, 192, 512))

const LOD_COUNT := 4
const LOD_DISTANCE := 48.0
const VIEW_DISTANCE := 256
const MESH_BLOCK_SIZE := 16
const COLLISION_LOD_COUNT := 2

const TERRAIN_SHADER := preload("res://materials/terrain_lab.gdshader")


static func create_generator() -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	var fn: VoxelGraphFunction = gen.get_main_function()

	var in_x := fn.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var in_y := fn.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 80))
	var in_z := fn.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 160))

	# SdfSphere não tem centro: desloca as coordenadas (p - centro) com Add.
	var off_x := _add_offset(fn, in_x, -HILL_CENTER.x, Vector2(160, 0))
	var off_y := _add_offset(fn, in_y, -HILL_CENTER.y, Vector2(160, 80))
	var off_z := _add_offset(fn, in_z, -HILL_CENTER.z, Vector2(160, 160))

	var sphere := fn.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(320, 80))
	fn.add_connection(off_x, 0, sphere, fn.get_node_input_index(sphere, "x"))
	fn.add_connection(off_y, 0, sphere, fn.get_node_input_index(sphere, "y"))
	fn.add_connection(off_z, 0, sphere, fn.get_node_input_index(sphere, "z"))
	fn.set_node_default_input_by_name(sphere, "radius", HILL_RADIUS)

	var plane := fn.create_node(VoxelGraphFunction.NODE_SDF_PLANE, Vector2(320, 240))
	fn.add_connection(in_y, 0, plane, fn.get_node_input_index(plane, "y"))
	fn.set_node_default_input_by_name(plane, "height", GROUND_HEIGHT)

	var union := fn.create_node(VoxelGraphFunction.NODE_SDF_SMOOTH_UNION, Vector2(480, 160))
	fn.add_connection(plane, 0, union, fn.get_node_input_index(union, "a"))
	fn.add_connection(sphere, 0, union, fn.get_node_input_index(union, "b"))
	fn.set_node_param_by_name(union, "smoothness", HILL_BLEND)

	var out := fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(640, 160))
	fn.add_connection(union, 0, out, fn.get_node_input_index(out, "sdf"))

	var result: Dictionary = gen.compile()
	if not result.get("success", false):
		push_error("[LabTerrainFactory] falha ao compilar o grafo: %s" % result)
	return gen


static func create_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	return mat


## Cria um VoxelLodTerrain novo, sem dados editados. Usado na carga e no reset.
static func create_terrain() -> VoxelLodTerrain:
	var terrain := VoxelLodTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.generator = create_generator()
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.material = create_material()
	terrain.voxel_bounds = VOXEL_BOUNDS
	terrain.lod_count = LOD_COUNT
	terrain.lod_distance = LOD_DISTANCE
	terrain.view_distance = VIEW_DISTANCE
	terrain.mesh_block_size = MESH_BLOCK_SIZE
	terrain.generate_collisions = true
	terrain.collision_layer = Layers.TERRAIN
	terrain.collision_mask = 0
	terrain.collision_lod_count = COLLISION_LOD_COUNT
	terrain.collision_update_delay = 0
	return terrain


static func _add_offset(fn: VoxelGraphFunction, src: int, offset: float, pos: Vector2) -> int:
	var add := fn.create_node(VoxelGraphFunction.NODE_ADD, pos)
	fn.add_connection(src, 0, add, fn.get_node_input_index(add, "a"))
	fn.set_node_default_input_by_name(add, "b", offset)
	return add
