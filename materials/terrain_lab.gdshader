shader_type spatial;
// Material de laboratório: cor do MATERIAL do voxel (soil/sand/stone, índice do canal INDICES
// que o mesher Transvoxel entrega em CUSTOM1), escurecida em paredes e tetos para ler a forma,
// e grade de 1 m e 4 m em espaço do mundo para ler escala e movimento.
// As cores vêm de TerrainMaterialLibrary (u_material_colors); a física nunca lê este shader.
// Não é a direção de arte final (toon/retro ficam para P4).

// --- Início: trecho oficial do Voxel Tools 1.7 (doc/source/smooth_terrain.md,
// "Smooth stitches in vertex shader"), necessário para costurar LODs do Transvoxel.
// This uniform is assigned internally by the voxel engine.
// Layout: 00000000 00000000 0000000 00xxyyzz
uniform int u_transition_mask;

float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;

	int cell_border_mask = (idata >> 0) & 63; // Which sides the cell is touching
	int vertex_border_mask = (idata >> 8) & 63; // Which sides the vertex is touching
	// If the vertex is near a side where there is a low-resolution neighbor,
	// move it to secondary position
	int m = transition_mask & cell_border_mask;
	float t = float(m != 0);
	// If the vertex lies on one or more sides, and at least one side has no low-resolution neighbor,
	// don't move the vertex.
	t *= float((vertex_border_mask & ~transition_mask) == 0);

	return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);

	// Move vertices to smooth transitions
	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 secondary_position = fdata.xyz;
	vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);

	// If the mesh combines transitions and the vertex belongs to a transition,
	// when that transition isn't active we change the position of the vertices so
	// all triangles will be degenerate and won't be visible.
	int itransition = (idata >> 16) & 0xff; // Is the vertex on a transition mesh?
	float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
	pos *= transition_cull;

	return pos;
}
// --- Fim do trecho oficial.

// Cores de superfície por índice de material, já em espaço linear (preenchidas em código).
uniform vec3 u_material_colors[3];
uniform float wall_shade = 0.82;
uniform float ceiling_shade = 0.62;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
// Modo de textura Single/S4 do Transvoxel: CUSTOM1.x = 4 índices (1 byte cada),
// CUSTOM1.y = 4 pesos (1 byte cada), conforme doc do Voxel Tools 1.7 (smooth_terrain).
varying flat vec4 v_indices;
varying vec4 v_weights;

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(float(i & 0xffu), float((i >> 8u) & 0xffu), float((i >> 16u) & 0xffu), float((i >> 24u) & 0xffu));
}

vec3 material_color(float index) {
	int i = clamp(int(index + 0.5), 0, 2);
	return u_material_colors[i];
}

float grid_line(vec2 p) {
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-4));
	return 1.0 - min(min(g.x, g.y), 1.0);
}

float triplanar_grid(vec3 p, vec3 n, float cell) {
	vec3 b = abs(n);
	b /= max(b.x + b.y + b.z, 1e-4);
	vec3 q = p / cell;
	return grid_line(q.zy) * b.x + grid_line(q.xz) * b.y + grid_line(q.xy) * b.z;
}

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_indices = decode_8bit_vec4(CUSTOM1.x);
	v_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec4 w = v_weights / max(v_weights.x + v_weights.y + v_weights.z + v_weights.w, 1e-4);
	vec3 col = material_color(v_indices.x) * w.x + material_color(v_indices.y) * w.y
		+ material_color(v_indices.z) * w.z + material_color(v_indices.w) * w.w;
	col *= mix(1.0, wall_shade, 1.0 - smoothstep(0.55, 0.8, n.y));
	col *= mix(1.0, ceiling_shade / wall_shade, smoothstep(-0.35, -0.65, n.y));
	float g1 = triplanar_grid(v_world_pos, n, 1.0);
	float g4 = triplanar_grid(v_world_pos, n, 4.0);
	col *= 1.0 - 0.10 * g1 - 0.22 * g4;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
