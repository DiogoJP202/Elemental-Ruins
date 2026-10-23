class_name SupportGraph
extends RefCounted
## Grafo de apoio entre peças de uma estrutura (P2). Só dados: sem física nem voxels.
##
## Ligações saem do contato entre as caixas de montagem: VERTICAL quando o topo de uma
## toca o fundo da outra com sobreposição em XZ; LATERAL quando as duas ocupam a mesma
## faixa de altura e se tocam por uma face.
## Regra de apoio (ponto fixo mínimo, crescendo a partir dos pés):
##   pé com âncora válida, OU ≥ 1 peça de baixo apoiada, OU ≥ 2 vizinhas laterais apoiadas
##   (placa sustentada como viga). Peça solta nunca apoia.

const CONTACT_EPS := 0.06
const MIN_OVERLAP := 0.05


static func link(pieces: Array[StructurePiece]) -> void:
	for p in pieces:
		p.below = PackedInt32Array()
		p.lateral = PackedInt32Array()
	for a in pieces:
		var ba := a.home_box()
		for b in pieces:
			if a == b:
				continue
			var bb := b.home_box()
			# a sustenta b: topo de a encosta no fundo de b, com área em comum em XZ.
			if absf(ba.end.y - bb.position.y) < CONTACT_EPS and _overlap(ba.position.x, ba.end.x, bb.position.x, bb.end.x) > MIN_OVERLAP \
					and _overlap(ba.position.z, ba.end.z, bb.position.z, bb.end.z) > MIN_OVERLAP:
				b.below.append(a.piece_index)
			# Laterais: mesma faixa de altura (> metade da menor) e faces encostadas.
			var y_overlap := _overlap(ba.position.y, ba.end.y, bb.position.y, bb.end.y)
			if y_overlap < 0.5 * minf(ba.size.y, bb.size.y) or a.piece_index > b.piece_index:
				continue
			var touch_x := (absf(ba.end.x - bb.position.x) < CONTACT_EPS or absf(bb.end.x - ba.position.x) < CONTACT_EPS) \
				and _overlap(ba.position.z, ba.end.z, bb.position.z, bb.end.z) > MIN_OVERLAP
			var touch_z := (absf(ba.end.z - bb.position.z) < CONTACT_EPS or absf(bb.end.z - ba.position.z) < CONTACT_EPS) \
				and _overlap(ba.position.x, ba.end.x, bb.position.x, bb.end.x) > MIN_OVERLAP
			if touch_x or touch_z:
				a.lateral.append(b.piece_index)
				b.lateral.append(a.piece_index)


## Para cada peça (pelo índice), 1 se está apoiada.
static func supported(pieces: Array[StructurePiece]) -> PackedByteArray:
	var sup := PackedByteArray()
	sup.resize(pieces.size())
	sup.fill(0)
	var changed := true
	while changed:
		changed = false
		for p in pieces:
			if sup[p.piece_index] == 1 or p.released:
				continue
			var ok := p.is_foot and p.anchor_valid
			if not ok:
				for i in p.below:
					if sup[i] == 1:
						ok = true
						break
			if not ok:
				var n := 0
				for i in p.lateral:
					n += sup[i]
				ok = n >= 2
			if ok:
				sup[p.piece_index] = 1
				changed = true
	return sup


static func _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return minf(a1, b1) - maxf(a0, b0)
