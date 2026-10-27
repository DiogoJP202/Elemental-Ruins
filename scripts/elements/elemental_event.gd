class_name ElementalEvent
extends RefCounted
## Evento de jogo elemental (GDD §5.2): o que um poder FEZ ao mundo, sem partículas.
## O MaterialResponseSystem atualiza os MaterialState com ele ANTES de qualquer VFX.
##
## Unidades por tipo (valores de jogo, não grandezas físicas canônicas):
##   KINETIC  magnitude = impulso transferido (N·s); direction = sentido do golpe
##   HEAT     magnitude = unidades de calor no centro (°C antes da resistência térmica do material)
##   WET      magnitude = umidade somada no centro (0–1), que também resfria e apaga
##   AIRFLOW  magnitude = intensidade do vento no centro (0–1); o empurrão físico é aplicado pelo poder

enum Kind { KINETIC, HEAT, WET, AIRFLOW }

const KIND_NAMES := ["kinetic", "heat", "wet", "airflow"]

var kind: Kind = Kind.HEAT
var origin := Vector3.ZERO
var direction := Vector3.ZERO
var magnitude := 0.0
## 0 = só o alvo (`target`); > 0 = esfera com queda linear até a borda.
var radius := 0.0
var duration := 0.0
var source_ability: StringName = &""
var tags := PackedStringArray()
## Alvo único (contato direto); nulo = área.
var target: Node3D
var tick := 0
var event_id := 0
var session_id := 0
var world_generation := 0


static func make(p_kind: Kind, p_origin: Vector3, p_magnitude: float, p_radius: float,
		p_source: StringName, p_direction := Vector3.ZERO) -> ElementalEvent:
	var e := ElementalEvent.new()
	e.kind = p_kind
	e.origin = p_origin
	e.magnitude = p_magnitude
	e.radius = p_radius
	e.source_ability = p_source
	e.direction = p_direction
	e.tick = Engine.get_physics_frames()
	return e


func kind_name() -> String:
	return KIND_NAMES[kind]


func _to_string() -> String:
	return "%s %.1f r=%.1f de %s" % [kind_name(), magnitude, radius, source_ability]
