extends Node
## Registra as ações de input do protótipo (P0/P1) em um único lugar.
##
## Usa physical_keycode (posição física da tecla), então WASD/G/H/J/K/N/M/Z/B ficam
## no mesmo lugar em teclados US e ABNT2. Idempotente: não duplica eventos se a
## ação já existir (por exemplo, se alguém a definir depois no editor).
## Atalhos são provisórios (CLAUDE.md) e não são o sistema de 4 elementos (sem 1–4).

const KEY_ACTIONS := {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"terrain_dig": [KEY_G],
	&"terrain_add": [KEY_H],
	&"terrain_tunnel": [KEY_J],
	&"terrain_ramp": [KEY_K],
	&"terrain_smooth": [KEY_N],
	&"brush_cycle_material": [KEY_M],
	&"terrain_extract": [KEY_R],
	&"debug_push": [KEY_T],
	&"world_reset": [KEY_Z],
	&"world_save": [KEY_F5],
	&"world_load": [KEY_F9],
	&"brush_radius_up": [KEY_BRACKETRIGHT, KEY_KP_ADD],
	&"brush_radius_down": [KEY_BRACKETLEFT, KEY_KP_SUBTRACT],
	&"debug_spawn_crate": [KEY_B],
	&"toggle_mouse_capture": [KEY_ESCAPE],
}

const MOUSE_BUTTON_ACTIONS := {
	&"brush_radius_up": [MOUSE_BUTTON_WHEEL_UP],
	&"brush_radius_down": [MOUSE_BUTTON_WHEEL_DOWN],
}


func _enter_tree() -> void:
	for action: StringName in KEY_ACTIONS:
		_ensure_action(action)
		for keycode: Key in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			_add_event_once(action, ev)
	for action: StringName in MOUSE_BUTTON_ACTIONS:
		_ensure_action(action)
		for button: MouseButton in MOUSE_BUTTON_ACTIONS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			_add_event_once(action, ev)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _add_event_once(action: StringName, ev: InputEvent) -> void:
	for existing in InputMap.action_get_events(action):
		if existing.is_match(ev, true):
			return
	InputMap.action_add_event(action, ev)
