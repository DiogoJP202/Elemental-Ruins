shader_type spatial;
// Material de laboratório do P0: cor por orientação da normal (piso / parede / teto)
// e grade de 1 m e 4 m em espaço do mundo para ler escala e movimento.
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

uniform vec3 color_floor : source_color = vec3(0.863, 0.780, 0.655);   // areia #DCC7A7
uniform vec3 color_wall : source_color = vec3(0.722, 0.475, 0.408);    // terracota #B87968
uniform vec3 color_ceiling : source_color = vec3(0.396, 0.471, 0.416); // verde mineral #65786A

varying vec3 v_world_pos;
varying vec3 v_world_normal;

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
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 col = color_wall;
	col = mix(col, color_floor, smoothstep(0.55, 0.8, n.y));
	col = mix(col, color_ceiling, smoothstep(-0.35, -0.65, n.y));
	float g1 = triplanar_grid(v_world_pos, n, 1.0);
	float g4 = triplanar_grid(v_world_pos, n, 4.0);
	col *= 1.0 - 0.10 * g1 - 0.22 * g4;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
