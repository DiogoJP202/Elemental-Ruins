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
##
## P1: o grafo também escreve o MATERIAL de cada voxel no canal INDICES (modo Single,
## 8 bits; ver TerrainMaterialLibrary). Layout: pedra abaixo de STONE_BELOW_Y e no
## núcleo da colina (mais de HILL_SOIL_DEPTH para dentro), areia a leste de SAND_MIN_X,
## solo no resto. Comportamento do Select conferido no spike: t < limiar → a.

const GROUND_HEIGHT := 0.0
const HILL_CENTER := Vector3(0.0, -12.0, -10.0)
const HILL_RADIUS := 24.0
const HILL_BLEND := 4.0
## Topo da colina = HILL_CENTER.y + HILL_RADIUS.
const HILL_TOP_Y := HILL_CENTER.y + HILL_RADIUS

const STONE_BELOW_Y := -6.0
const HILL_SOIL_DEPTH := 3.0
const SAND_MIN_X := 24.0

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

	# Material: três Select encadeados (t < limiar → a, senão b).
	gen.texture_mode = VoxelGeneratorGraph.TEXTURE_MODE_SINGLE
	var soil_or_sand := _select(fn, TerrainMaterialLibrary.INDEX_SOIL, TerrainMaterialLibrary.INDEX_SAND,
		in_x, -1, SAND_MIN_X, Vector2(320, 400))
	var hill_core := _select(fn, TerrainMaterialLibrary.INDEX_STONE, -1, sphere, soil_or_sand, -HILL_SOIL_DEPTH,
		Vector2(480, 400))
	var bedrock := _select(fn, TerrainMaterialLibrary.INDEX_STONE, -1, in_y, hill_core, STONE_BELOW_Y,
		Vector2(640, 400))
	var out_mat := fn.create_node(VoxelGraphFunction.NODE_OUTPUT_SINGLE_TEXTURE, Vector2(800, 400))
	fn.add_connection(bedrock, 0, out_mat, fn.get_node_input_index(out_mat, "index"))

	var result: Dictionary = gen.compile()
	if not result.get("success", false):
		push_error("[LabTerrainFactory] falha ao compilar o grafo: %s" % result)
	return gen


## Índice de material que o gerador escreve em `p` (mesma regra do grafo). Só para testes:
## o jogo lê o material dos DADOS voxel (TerrainService.get_material_at), que mudam com edições.
static func generator_material_index(p: Vector3) -> int:
	if p.y < STONE_BELOW_Y:
		return TerrainMaterialLibrary.INDEX_STONE
	if p.distance_to(HILL_CENTER) - HILL_RADIUS < -HILL_SOIL_DEPTH:
		return TerrainMaterialLibrary.INDEX_STONE
	return TerrainMaterialLibrary.INDEX_SAND if p.x >= SAND_MIN_X else TerrainMaterialLibrary.INDEX_SOIL


static func create_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("u_material_colors", TerrainMaterialLibrary.linear_surface_colors())
	return mat


## Cria um VoxelLodTerrain novo, sem dados editados. Usado na carga e no reset.
## `stream` nulo = edições só em memória (comportamento do P0).
static func create_terrain(stream: VoxelStream = null) -> VoxelLodTerrain:
	var terrain := VoxelLodTerrain.new()
	terrain.name = "VoxelTerrain"
	var fmt := VoxelFormat.new()
	fmt.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
	terrain.format = fmt
	terrain.generator = create_generator()
	var mesher := VoxelMesherTransvoxel.new()
	mesher.texturing_mode = VoxelMesherTransvoxel.TEXTURES_SINGLE_S4
	terrain.mesher = mesher
	if stream != null:
		terrain.stream = stream
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


## Select com `a` constante; `b` vem do nó `b_node` ou, se for -1, da constante `b_value`.
static func _select(fn: VoxelGraphFunction, a_value: int, b_value: int, t_node: int, b_node: int,
		threshold: float, pos: Vector2) -> int:
	var sel := fn.create_node(VoxelGraphFunction.NODE_SELECT, pos)
	fn.set_node_default_input_by_name(sel, "a", float(a_value))
	if b_node >= 0:
		fn.add_connection(b_node, 0, sel, fn.get_node_input_index(sel, "b"))
	else:
		fn.set_node_default_input_by_name(sel, "b", float(b_value))
	fn.add_connection(t_node, 0, sel, fn.get_node_input_index(sel, "t"))
	fn.set_node_param_by_name(sel, "threshold", threshold)
	return sel


static func _add_offset(fn: VoxelGraphFunction, src: int, offset: float, pos: Vector2) -> int:
	var add := fn.create_node(VoxelGraphFunction.NODE_ADD, pos)
	fn.add_connection(src, 0, add, fn.get_node_input_index(add, "a"))
	fn.set_node_default_input_by_name(add, "b", offset)
	return add
