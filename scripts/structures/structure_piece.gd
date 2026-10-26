class_name StructurePiece
extends RigidBody3D
## Peça modular de estrutura (P2): caixa convexa (BoxShape3D) que começa congelada
## (freeze estático, custo ~zero na física). O StructureService a solta (freeze = false)
## quando ela perde apoio; solta, nunca volta a sustentar outra peça.

var piece_index := -1
var kind := ""
## Material elemental da peça (BodyMaterialLibrary): pedra ou madeira.
var material_id: StringName = &"stone"
var size := Vector3.ONE
## Transform de montagem (para conferir que o reset devolve a torre idêntica).
var home := Transform3D()
## Índices das peças imediatamente abaixo (que a sustentam) e das vizinhas laterais.
var below := PackedInt32Array()
var lateral := PackedInt32Array()
## Pé apoiado direto no terreno.
var is_foot := false
var anchor_valid := true
var released := false


## Caixa da peça na posição de montagem (eixos do mundo; as peças não giram montadas).
func home_box() -> AABB:
	return AABB(home.origin - size * 0.5, size)


## Pontos de âncora sob a face de baixo (centro + 4 cantos recuados), 1 m dentro do chão.
## Não 0,5 m: TerrainService.sample_sdf arredonda para o voxel mais próximo, e y = −0,45
## cai no voxel y = 0, a própria superfície (SDF 0), que não conta como sólido.
func anchor_points() -> PackedVector3Array:
	var box := home_box()
	var y := box.position.y - 1.0
	var inset := 0.15
	var x0 := box.position.x + inset
	var x1 := box.end.x - inset
	var z0 := box.position.z + inset
	var z1 := box.end.z - inset
	return PackedVector3Array([Vector3(box.get_center().x, y, box.get_center().z),
		Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1)])
