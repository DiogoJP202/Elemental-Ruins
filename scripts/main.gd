extends Node3D
## Raiz da cena: liga serviços, jogador, controle de edição e HUD, e coordena o
## reset do mundo (terreno + jogador + props de teste).
##
## Argumentos de usuário (depois de `--` na linha de comando):
##   --p0-selftest        executa o roteiro automatizado de aceite do P0 (12 testes)
##   --p0-screenshots     (com o anterior) salva capturas PNG em docs/evidence/screens
##   --p1-selftest        P0 + testes do P1 (capturas com --p1-screenshots em docs/evidence/p1/screens)
##   --p1-persist=write|read  fases do teste de persistência entre processos (ver p1_selftest.gd)
##   --p2-selftest        P0 + P1 + testes do P2 (capturas com --p2-screenshots em docs/evidence/p2/screens)
##   --p3-selftest        P0 + P1 + P2 + testes do P3 (capturas com --p3-screenshots em docs/evidence/p3/screens)
##   --p35-selftest       P0–P3 + testes do P3.5, Terra polida (capturas com --p35-screenshots em docs/evidence/p35/screens)
##   --report=<caminho>   caminho do relatório JSON do selftest

const SELFTEST_SCRIPT := "res://scripts/dev/p0_selftest.gd"
const P1_SELFTEST_SCRIPT := "res://scripts/dev/p1_selftest.gd"
const P2_SELFTEST_SCRIPT := "res://scripts/dev/p2_selftest.gd"
const P3_SELFTEST_SCRIPT := "res://scripts/dev/p3_selftest.gd"
const P35_SELFTEST_SCRIPT := "res://scripts/dev/p35_selftest.gd"
## Slot único do laboratório (F5 salva, F9 carrega).
const SAVE_SLOT := "slot1"

@onready var terrain_service: TerrainService = $World/TerrainService
@onready var brush_queue: TerrainBrushQueue = $World/TerrainBrushQueue
@onready var spawn_point: Marker3D = $World/SpawnPoint
@onready var props_root: Node3D = $World/Props
@onready var structures: StructureService = $World/StructureService
@onready var contact_waker: TerrainContactWaker = $World/ContactWaker
@onready var debris: DebrisBudget = $World/DebrisBudget
@onready var dust: DustFx = $World/DustFx
@onready var materials: MaterialResponseSystem = $World/MaterialResponseSystem
@onready var player: PlayerController = $Player
@onready var edit_controller: TerrainEditController = $TerrainEditController
@onready var abilities: AbilityController = $AbilityController
@onready var fx: ElementalFx = $ElementalFx
@onready var earth_fx: EarthFx = $EarthFx
@onready var hud: DebugHud = $HUD

var reset_count := 0
## Última espera por collider depois de salvar: {bodies, frames, ms, timeout}.
var last_thaw := {}


func _ready() -> void:
	print("[Main] Godot %s | física 3D: %s | renderer: %s" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		RenderingServer.get_current_rendering_method()])
	edit_controller.setup(terrain_service, brush_queue, player, props_root)
	abilities.setup(terrain_service, materials, structures, player, props_root, dust, brush_queue)
	fx.setup(abilities, materials)
	earth_fx.setup(abilities, player.camera_rig, edit_controller)
	hud.setup(terrain_service, brush_queue, player, edit_controller, structures, debris, abilities, materials)
	edit_controller.reset_requested.connect(request_world_reset)
	edit_controller.save_requested.connect(func(): request_world_save(SAVE_SLOT))
	edit_controller.load_requested.connect(func(): request_world_load(SAVE_SLOT))

	player.set_frozen(true)
	player.teleport_to(spawn_point.global_position)
	player.camera_rig.set_view(0.0, deg_to_rad(-12.0))

	var args := OS.get_cmdline_user_args()
	var p1 := args.has("--p1-selftest")
	for a in args:
		p1 = p1 or a.begins_with("--p1-persist=")
	var script := ""
	if args.has("--p35-selftest"):
		script = P35_SELFTEST_SCRIPT
	elif args.has("--p3-selftest"):
		script = P3_SELFTEST_SCRIPT
	elif args.has("--p2-selftest"):
		script = P2_SELFTEST_SCRIPT
	elif p1:
		script = P1_SELFTEST_SCRIPT
	elif args.has("--p0-selftest"):
		script = SELFTEST_SCRIPT
	if script != "":
		var test: Node = load(script).new()
		test.name = "SelfTest"
		add_child(test)

	if terrain_service.is_ready():
		_on_terrain_ready()
	else:
		terrain_service.terrain_ready.connect(_on_terrain_ready, CONNECT_ONE_SHOT)


func _on_terrain_ready() -> void:
	player.set_frozen(false)


## Reset real do mundo: descarta todas as edições do terreno (recria o nó a
## partir do gerador), remove props de teste, remonta as estruturas intactas e
## devolve o jogador ao spawn.
func request_world_reset() -> bool:
	if terrain_service.is_resetting():
		return false
	player.set_frozen(true)
	player.teleport_to(spawn_point.global_position)
	for prop in props_root.get_children():
		prop.queue_free()
	# Antes do terreno: peças soltas cairiam pelo chão enquanto ele é recriado.
	structures.build()
	var ok: bool = await terrain_service.reset_world()
	reset_count += 1
	player.teleport_to(spawn_point.global_position)
	player.set_frozen(false)
	return ok


## Salva as edições do terreno no slot. O terreno é recriado do disco durante o save:
## jogador, caixas e peças soltas ficam congelados (sem chão por alguns quadros) e voltam
## no mesmo lugar. Caixas, rochas e destroços NÃO são salvos (só o terreno).
func request_world_save(slot: String) -> bool:
	if terrain_service.is_resetting():
		return false
	player.set_frozen(true)
	var frozen := _freeze_props()
	structures.suspend()
	var bodies: Array[Node3D] = []
	for b in frozen:
		bodies.append(b)
	for p in structures.get_suspended():
		bodies.append(p)
	# Antes de recriar o terreno: quais raios curtos sob cada corpo tocam o chão que o apoia.
	var support := {}
	for b in bodies:
		support[b] = _support_hits(b)
	var ok: bool = await terrain_service.save_world(slot)
	# save_world só espera o terreno em volta do ponto de prontidão; em outros trechos o
	# collider pode chegar alguns quadros depois, e um corpo descongelado antes cairia.
	await _wait_terrain_under(bodies, support, 3.0)
	structures.resume()
	for body in frozen:
		if is_instance_valid(body):
			body.freeze = false
	player.set_frozen(false)
	return ok


## Troca o mundo pelo slot salvo: jogador volta ao spawn (o terreno salvo pode ter
## matéria onde ele está agora), as caixas de teste são removidas e as estruturas são
## remontadas intactas; depois as âncoras são reavaliadas contra o terreno carregado
## (se o apoio foi escavado no save, a estrutura cai de novo).
func request_world_load(slot: String) -> bool:
	if terrain_service.is_resetting():
		return false
	if not terrain_service.has_saved_world(slot):
		return await terrain_service.load_world(slot)
	player.set_frozen(true)
	player.teleport_to(spawn_point.global_position)
	for prop in props_root.get_children():
		prop.queue_free()
	structures.build()
	var ok: bool = await terrain_service.load_world(slot)
	structures.check_all()
	player.teleport_to(spawn_point.global_position)
	player.set_frozen(false)
	return ok


## Espera haver collider de terreno sob cada corpo (raio vertical pela origem) E de volta em
## cada raio de apoio que tocava o chão antes do save (`support`), ou o prazo. Só o raio
## pela origem não bastava: uma peça na borda de um buraco via o fundo do buraco já
## carregado, era descongelada antes do collider da borda e escorregava 0,5 m (T26 no .exe).
func _wait_terrain_under(bodies: Array[Node3D], support: Dictionary, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + int(timeout_s * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline:
		var missing := 0
		for b in bodies:
			if not is_instance_valid(b):
				continue
			var p := b.global_position
			if terrain_service.raycast_terrain(p + Vector3.UP * 2.0, p + Vector3.DOWN * 30.0).is_empty():
				missing += 1
				continue
			var before: Array = support.get(b, [])
			var now := _support_hits(b)
			for i in mini(before.size(), now.size()):
				if before[i] and not now[i]:
					missing += 1
					break
		if missing == 0:
			last_thaw = {"bodies": bodies.size(), "frames": frames, "ms": Time.get_ticks_msec() - t0, "timeout": false}
			return true
		frames += 1
		await get_tree().physics_frame
	last_thaw = {"bodies": bodies.size(), "frames": frames, "ms": Time.get_ticks_msec() - t0, "timeout": true}
	push_warning("[Main] collider do terreno não apareceu sob todos os corpos em %.1f s" % timeout_s)
	return false


## Raios curtos (de 0,3 m acima a 0,6 m abaixo do fundo da malha) no centro e em 4 cantos
## recuados da base do corpo: quais tocam terreno.
func _support_hits(b: Node3D) -> Array[bool]:
	var hits: Array[bool] = []
	var box := AABB(b.global_position, Vector3.ZERO)
	for ch in b.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			box = mi.global_transform * mi.mesh.get_aabb()
			break
	var c := box.get_center()
	var hx := box.size.x * 0.3
	var hz := box.size.z * 0.3
	var y := box.position.y
	for off in [Vector2.ZERO, Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var top := Vector3(c.x + off.x, y + 0.3, c.z + off.y)
		hits.append(not terrain_service.raycast_terrain(top, top + Vector3.DOWN * 0.9).is_empty())
	return hits


## Congela as caixas/rochas que estão soltas e devolve quais foram (as que já estavam
## congeladas, por exemplo pelo orçamento de corpos, continuam assim depois).
func _freeze_props() -> Array[RigidBody3D]:
	var frozen: Array[RigidBody3D] = []
	for prop in props_root.get_children():
		var body := prop as RigidBody3D
		if body != null and not body.freeze:
			body.freeze = true
			frozen.append(body)
	return frozen
