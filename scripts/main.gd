extends Node3D
## Raiz da cena: liga serviços, jogador, controle de edição e HUD, e coordena o
## reset do mundo (terreno + jogador + props de teste).
##
## Argumentos de usuário (depois de `--` na linha de comando):
##   --p0-selftest        executa o roteiro automatizado de aceite do P0 (12 testes)
##   --p0-screenshots     (com o anterior) salva capturas PNG em docs/evidence/screens
##   --p1-selftest        P0 + testes do P1 (capturas com --p1-screenshots em docs/evidence/p1/screens)
##   --p1-persist=write|read  fases do teste de persistência entre processos (ver p1_selftest.gd)
##   --report=<caminho>   caminho do relatório JSON do selftest

const SELFTEST_SCRIPT := "res://scripts/dev/p0_selftest.gd"
const P1_SELFTEST_SCRIPT := "res://scripts/dev/p1_selftest.gd"

@onready var terrain_service: TerrainService = $World/TerrainService
@onready var brush_queue: TerrainBrushQueue = $World/TerrainBrushQueue
@onready var spawn_point: Marker3D = $World/SpawnPoint
@onready var props_root: Node3D = $World/Props
@onready var player: PlayerController = $Player
@onready var edit_controller: TerrainEditController = $TerrainEditController
@onready var hud: DebugHud = $HUD

var reset_count := 0


func _ready() -> void:
	print("[Main] Godot %s | física 3D: %s | renderer: %s" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		RenderingServer.get_current_rendering_method()])
	edit_controller.setup(terrain_service, brush_queue, player, props_root)
	hud.setup(terrain_service, player, edit_controller)
	edit_controller.reset_requested.connect(request_world_reset)

	player.set_frozen(true)
	player.teleport_to(spawn_point.global_position)
	player.camera_rig.set_view(0.0, deg_to_rad(-12.0))

	var args := OS.get_cmdline_user_args()
	var p1 := args.has("--p1-selftest")
	for a in args:
		p1 = p1 or a.begins_with("--p1-persist=")
	if p1 or args.has("--p0-selftest"):
		var test: Node = load(P1_SELFTEST_SCRIPT if p1 else SELFTEST_SCRIPT).new()
		test.name = "P1SelfTest" if p1 else "P0SelfTest"
		add_child(test)

	if terrain_service.is_ready():
		_on_terrain_ready()
	else:
		terrain_service.terrain_ready.connect(_on_terrain_ready, CONNECT_ONE_SHOT)


func _on_terrain_ready() -> void:
	player.set_frozen(false)


## Reset real do mundo: descarta todas as edições do terreno (recria o nó a
## partir do gerador), remove props de teste e devolve o jogador ao spawn.
func request_world_reset() -> bool:
	if terrain_service.is_resetting():
		return false
	player.set_frozen(true)
	player.teleport_to(spawn_point.global_position)
	for prop in props_root.get_children():
		prop.queue_free()
	var ok: bool = await terrain_service.reset_world()
	reset_count += 1
	player.teleport_to(spawn_point.global_position)
	player.set_frozen(false)
	return ok
