class_name AbilityController
extends Node
## Poderes elementais (P3): 1–4 escolhem Terra / Água / Fogo / Ar e o LMB usa o poder do
## elemento (segurar ou tocar, conforme o poder). Terra também usa RMB para um pilar.
## Modo Criativo: recurso infinito e sem recarga. Reset/salvar/carregar cancelam poderes;
## salvar preserva a física viva. Não aceita comandos com o input do jogador desligado.

signal element_changed(element: StringName)
signal ability_used(ability_id: StringName, phase: String)

const ELEMENT_NAMES := {&"earth": "TERRA", &"water": "ÁGUA", &"fire": "FOGO", &"air": "AR"}

## Só age com o mouse capturado: o clique que recaptura o mouse não lança poder.
## Os testes desligam isto (o selftest deixa o mouse livre de propósito).
var require_captured_mouse := true

var terrain_service: TerrainService
## Edições de terreno feitas por poderes passam pela fila (D17): cratera da Terra (P3.5).
var brush_queue: TerrainBrushQueue
var materials: MaterialResponseSystem
var structures: StructureService
var player: PlayerController
var props_root: Node3D
var dust: DustFx

var abilities: Array[Ability] = []
var current := 0
var holding := false
var session_id := 1
var _next_event_id := 1


func setup(p_terrain: TerrainService, p_materials: MaterialResponseSystem, p_structures: StructureService,
		p_player: PlayerController, p_props: Node3D, p_dust: DustFx, p_queue: TerrainBrushQueue = null) -> void:
	terrain_service = p_terrain
	brush_queue = p_queue
	materials = p_materials
	structures = p_structures
	player = p_player
	props_root = p_props
	dust = p_dust
	abilities = [EarthLiftThrow.new(), WaterJet.new(), FireBurst.new(), AirGust.new()]
	for a in abilities:
		a.setup(self)
	require_captured_mouse = DisplayServer.get_name() != "headless"
	terrain_service.world_reset_started.connect(cancel_all)
	terrain_service.world_save_started.connect(func(_s): cancel_all())
	terrain_service.world_load_started.connect(func(_s): cancel_all())


func current_ability() -> Ability:
	return abilities[current] if current < abilities.size() else null


func get_ability(ability_id: StringName) -> Ability:
	for a in abilities:
		if a.id == ability_id:
			return a
	return null


func select(index: int) -> bool:
	if index < 0 or index >= abilities.size() or index == current:
		return false
	if holding:
		use_released()
	current_ability().cancel()
	current = index
	element_changed.emit(current_ability().element)
	return true


## LMB pressionado (também chamado pelos testes).
func use_pressed() -> bool:
	if not _can_act():
		return false
	var a := current_ability()
	if a is EarthLiftThrow and (a.pillar_aiming or a.fissure_aiming or a.phase in ["pillar_pending", "fissure_pending"]):
		return false
	if a is WaterJet and a.orb.phase != "":
		return false
	holding = a.input_mode == "hold"
	a.on_press()
	ability_used.emit(a.id, "press")
	return true


func use_released() -> void:
	var a := current_ability()
	if a == null:
		return
	if holding:
		holding = false
		a.on_release()
		ability_used.emit(a.id, "release")


func cancel_all() -> void:
	session_id += 1
	holding = false
	for a in abilities:
		a.cancel()
		a.clear()


func next_event_context() -> Dictionary:
	var context := {"event_id": _next_event_id, "session_id": session_id,
		"world_generation": terrain_service.get_world_generation(), "tick": Engine.get_physics_frames()}
	_next_event_id += 1
	return context


## A roda é consumida antes de qualquer _unhandled_input do pincel, independentemente
## da ordem dos nós. Teclas [ ] continuam chegando ao TerrainEditController.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or not (can_manipulate_earth() or can_manipulate_water()):
		return
	var step := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1.0
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1.0
	else:
		return
	if can_manipulate_water():
		var water := current_ability() as WaterJet
		water.orb.adjust_hold_distance(step * event.factor * water.orb.tuning.distance_step)
	else:
		var earth := current_ability() as EarthLiftThrow
		earth.adjust_hold_distance(step * event.factor * earth.tuning.hold_distance_step)
	get_viewport().set_input_as_handled()


func can_manipulate_earth() -> bool:
	if not holding or not _can_act() or (require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		return false
	var earth := current_ability() as EarthLiftThrow
	return earth != null and earth.can_manipulate()


func can_manipulate_water() -> bool:
	var water := current_ability() as WaterJet
	return water != null and water.orb.phase == "hold" and _can_act() \
		and (not require_captured_mouse or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func begin_water_orb() -> bool:
	var water := current_ability() as WaterJet
	if water == null or holding or water.active or not _can_act() \
			or (require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		return false
	var formed := water.orb.begin()
	if not formed:
		water.last_result = water.orb.last_result
	return formed


func release_water_orb() -> void:
	var water := current_ability() as WaterJet
	if water == null:
		return
	if can_manipulate_water():
		water.orb.release()
	else:
		water.orb.cancel()


func freeze_water_orb() -> bool:
	var water := current_ability() as WaterJet
	return can_manipulate_water() and water.orb.freeze_orb()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.input_enabled:
		return
	var water := current_ability() as WaterJet
	if water != null and event.is_action_pressed(&"water_freeze"):
		if freeze_water_orb():
			get_viewport().set_input_as_handled()
		return
	if water != null and event.is_action_pressed(&"toggle_mouse_capture"):
		water.orb.cancel()
	if water != null and event.is_action(&"water_orb"):
		if event.is_action_pressed(&"water_orb"):
			begin_water_orb()
		elif event.is_action_released(&"water_orb"):
			release_water_orb()
		get_viewport().set_input_as_handled()
		return
	for i in ElementalKeys.ACTIONS.size():
		if event.is_action_pressed(ElementalKeys.ACTIONS[i]):
			select(i)
			return
	if event.is_action(&"earth_pillar") or event.is_action(&"earth_fissure"):
		var earth := current_ability() as EarthLiftThrow
		if earth == null or holding:
			return
		if not _can_act() or (require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
			earth.cancel()
			return
		if event.is_action(&"earth_fissure"):
			if event.is_action_pressed(&"earth_fissure"):
				earth.begin_fissure()
			elif event.is_action_released(&"earth_fissure"):
				earth.finish_fissure()
		elif event.is_action_pressed(&"earth_pillar"):
			earth.begin_pillar()
		elif event.is_action_released(&"earth_pillar"):
			earth.finish_pillar()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ability_use"):
		if require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		use_pressed()
	elif event.is_action_released(&"ability_use"):
		use_released()


func _physics_process(delta: float) -> void:
	if abilities.is_empty():
		return
	var earth := current_ability() as EarthLiftThrow
	var water := current_ability() as WaterJet
	if water != null and water.orb.phase != "" and (not _can_act() \
			or (require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)):
		water.orb.cancel()
	if earth != null and (earth.pillar_aiming or earth.fissure_aiming or earth.phase in ["pillar_pending", "fissure_pending"]) \
			and (not _can_act() or (require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)):
		earth.cancel()
	if holding and (not _can_act() or not player.input_enabled):
		cancel_all()
	elif holding:
		current_ability().on_hold(delta)
	var speed := 1.0
	for a in abilities:
		a.physics_tick(delta)
		speed = minf(speed, a.move_speed_scale())
	if player != null:
		player.speed_scale = speed


func _can_act() -> bool:
	return terrain_service != null and terrain_service.is_ready() and player != null and player.input_enabled


# --- Mira (centro da tela) ---------------------------------------------------------------

func aim_ray() -> Array:
	return player.camera_rig.get_aim_ray()


func aim_direction() -> Vector3:
	return (aim_ray()[1] as Vector3).normalized()


## Ponto de terreno sob a mira até `max_distance` ({} se nada).
func aim_terrain(max_distance: float) -> Dictionary:
	var r := aim_ray()
	return terrain_service.raycast_terrain(r[0], r[0] + r[1] * max_distance)


## Primeiro terreno ou corpo (PROPS) sob a mira.
func aim_any(max_distance: float, exclude: Array[RID] = []) -> Dictionary:
	var r := aim_ray()
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * max_distance, Layers.TERRAIN | Layers.PROPS, exclude)
	var space := player.get_world_3d().direct_space_state
	return PhysicsRayHelper.intersect(space, q)


## Ponto que a mira atinge (terreno ou corpo), ou o fim do raio se não atinge nada.
func aim_point(max_distance: float) -> Vector3:
	var hit := aim_any(max_distance)
	if not hit.is_empty():
		return hit.position
	var r := aim_ray()
	return r[0] + (r[1] as Vector3).normalized() * max_distance


## De onde saem jato, bola de fogo e rajada: à frente do peito, na direção horizontal da mira
## (fora da cápsula do jogador, raio 0,35 m).
func hand_position() -> Vector3:
	var fwd := aim_direction()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return player.global_position + Vector3.UP * 1.3 + fwd * 0.6


## Primeiro terreno ou corpo (PROPS) no segmento `from` → `to` ({} se nada).
## `robust` usa as testemunhas de ±1 mm do PhysicsRayHelper só quando o raio falha.
func cast_segment(from: Vector3, to: Vector3, robust := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN | Layers.PROPS)
	q.hit_from_inside = true
	var space := player.get_world_3d().direct_space_state
	return PhysicsRayHelper.intersect(space, q) if robust else space.intersect_ray(q)


## Corpo físico sob a mira (para o HUD mostrar o estado do material).
func aimed_body(max_distance := 40.0) -> Node3D:
	var hit := aim_any(max_distance)
	return hit.get("collider") as RigidBody3D if not hit.is_empty() else null


func element_label() -> String:
	var a := current_ability()
	if a == null:
		return "—"
	return "%d %s — %s [%s LMB]" % [current + 1, ELEMENT_NAMES.get(a.element, a.element), a.display_name,
		"segure" if a.input_mode == "hold" else "toque"]
