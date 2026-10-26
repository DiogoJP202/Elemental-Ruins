class_name MaterialState
extends RefCounted
## Estado elemental de um corpo (GDD §5.2): temperatura, umidade, fogo e integridade.
## Só o MaterialResponseSystem escreve aqui; VFX e HUD apenas leem.

const AMBIENT := 20.0

var material: BodyMaterial
var temperature := AMBIENT
## 0 = seco, 1 = encharcado.
var wetness := 0.0
var burning := false
## 0–1: quanto o fogo está forte (cresce sozinho, cai com água, sobe com vento moderado).
var intensity := 0.0
var fuel := 0.0
## 1 = intacto, 0 = consumido.
var integrity := 1.0
var charred := false
var consumed := false


static func create(p_material: BodyMaterial) -> MaterialState:
	var s := MaterialState.new()
	s.material = p_material
	s.fuel = p_material.fuel_seconds
	return s


func describe() -> String:
	var parts := PackedStringArray(["%s" % material.display_name.to_upper(), "%.0f °C" % temperature])
	if wetness > 0.01:
		parts.append("molhada %d%%" % roundi(wetness * 100.0))
	if burning:
		parts.append("EM CHAMAS %d%%" % roundi(intensity * 100.0))
	if charred:
		parts.append("carbonizada")
	if integrity < 0.999:
		parts.append("integridade %d%%" % roundi(integrity * 100.0))
	return " • ".join(parts)
