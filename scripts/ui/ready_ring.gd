class_name ReadyRing
extends Control
## Anel em volta da retícula (P3.5): progresso da Terra do clique até a rocha pronta, cheio e
## claro quando pronta, e um X vermelho curto quando o alvo é inválido. Só lê estado.

const RADIUS := 22.0
const WIDTH := 3.0
const CHARGE := Color(0.95, 0.68, 0.32, 0.9)
const READY := Color(0.95, 0.95, 0.85, 0.95)
const INVALID := Color(0.95, 0.25, 0.2, 0.95)
const INVALID_S := 0.45

var abilities: AbilityController
var earth: EarthLiftThrow
var _invalid_t := -1.0


func setup(p_abilities: AbilityController) -> void:
	abilities = p_abilities
	earth = abilities.get_ability(&"earth_lift_throw") as EarthLiftThrow
	if earth != null:
		earth.fx_event.connect(func(kind, _data):
			if kind == &"invalid":
				_invalid_t = 0.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _invalid_t >= 0.0:
		_invalid_t += delta
		if _invalid_t > INVALID_S:
			_invalid_t = -1.0
	queue_redraw()


func _draw() -> void:
	if earth == null or abilities.current_ability() != earth:
		return
	# Centro da tela pelo viewport (com o tamanho do controle em 0 o anel saía no canto; T45).
	var c := get_viewport_rect().size * 0.5
	if _invalid_t >= 0.0:
		var a := 1.0 - _invalid_t / INVALID_S
		var col := Color(INVALID.r, INVALID.g, INVALID.b, INVALID.a * a)
		var d := RADIUS * 0.55
		draw_line(c + Vector2(-d, -d), c + Vector2(d, d), col, WIDTH)
		draw_line(c + Vector2(-d, d), c + Vector2(d, -d), col, WIDTH)
		return
	match earth.phase:
		"anticipation", "detach", "rise":
			draw_arc(c, RADIUS, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(0, 0, 0, 0.35), WIDTH + 2.0)
			draw_arc(c, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * earth.ready_progress(), 48, CHARGE, WIDTH)
		"hold", "windup":
			draw_arc(c, RADIUS, 0.0, TAU, 48, READY, WIDTH)
