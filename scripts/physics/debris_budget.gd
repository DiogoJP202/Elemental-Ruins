class_name DebrisBudget
extends Node
## Teto de corpos físicos ativos e culling de destroços (P2).
##
## Corpos de destroço = nós do grupo "debris" (peças de estrutura soltas, rochas extraídas,
## caixas de teste). A cada check_interval_s:
##   - acima de freeze_distance do jogador: o corpo é ESTACIONADO (freeze estático) para não
##     cair se o collider daquele trecho sair do alcance de colisão do terreno; volta a ser
##     dinâmico quando o jogador chega a menos de unpark_distance;
##   - com mais de max_active corpos dinâmicos: estaciona os mais antigos que já estão
##     PARADOS (velocidade < settle_speed). Corpo em movimento nunca é congelado no ar.
## Malhas de destroço ganham visibility_range_end (culling por distância na renderização).
## Fica parado enquanto o terreno é recriado (reset/salvar/carregar).

const GROUP := "debris"
const PARKED_META := "debris_parked"
const SEEN_META := "debris_seen_ms"

@export var terrain_service_path: NodePath = ^"../TerrainService"
@export var player_path: NodePath = ^"../../Player"
@export var max_active := 64
@export var freeze_distance := 80.0
@export var unpark_distance := 64.0
@export var settle_speed := 0.05
@export var visibility_range := 120.0
@export var check_interval_s := 0.25

var terrain_service: TerrainService
var player: Node3D
var _accum := 0.0
var _stats := {"checks": 0, "parked_budget": 0, "parked_distance": 0, "unparked_distance": 0,
	"max_active_seen": 0, "over_budget_moving": 0, "max_park_speed": 0.0}


func _ready() -> void:
	terrain_service = get_node(terrain_service_path) as TerrainService
	player = get_node(player_path) as Node3D


## Volta um corpo estacionado a ser dinâmico (usado também pelo TerrainContactWaker).
static func unpark(body: RigidBody3D) -> void:
	body.remove_meta(PARKED_META)
	body.freeze = false
	body.sleeping = false


func get_stats() -> Dictionary:
	var d := _stats.duplicate()
	var counts := _counts()
	d["tracked"] = counts.tracked
	d["active"] = counts.active
	d["parked"] = counts.parked
	return d


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < check_interval_s or terrain_service.is_resetting():
		return
	_accum = 0.0
	_stats.checks += 1
	var now := Time.get_ticks_msec()
	var p := player.global_position
	var active: Array[RigidBody3D] = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var body := n as RigidBody3D
		if body == null or not body.is_inside_tree():
			continue
		if not body.has_meta(SEEN_META):
			body.set_meta(SEEN_META, now)
			for ch in body.get_children():
				if ch is GeometryInstance3D:
					(ch as GeometryInstance3D).visibility_range_end = visibility_range
		var dist := body.global_position.distance_to(p)
		if body.get_meta(PARKED_META, "") == "distance" and dist < unpark_distance:
			unpark(body)
			_stats.unparked_distance += 1
		if body.freeze:
			continue
		if dist > freeze_distance:
			_park(body, "distance")
			_stats.parked_distance += 1
			continue
		active.append(body)
	if active.size() > max_active:
		var settled := active.filter(func(b: RigidBody3D): return b.linear_velocity.length() < settle_speed)
		settled.sort_custom(func(a: RigidBody3D, b: RigidBody3D): return a.get_meta(SEEN_META) < b.get_meta(SEEN_META))
		var excess := active.size() - max_active
		for b: RigidBody3D in settled.slice(0, excess):
			_stats.max_park_speed = maxf(_stats.max_park_speed, b.linear_velocity.length())
			_park(b, "budget")
			_stats.parked_budget += 1
		var left := active.size() - mini(excess, settled.size())
		if left > max_active:
			_stats.over_budget_moving += 1
		_stats.max_active_seen = maxi(_stats.max_active_seen, left)
	else:
		_stats.max_active_seen = maxi(_stats.max_active_seen, active.size())


func _park(body: RigidBody3D, reason: String) -> void:
	body.set_meta(PARKED_META, reason)
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true


func _counts() -> Dictionary:
	var tracked := 0
	var active := 0
	var parked := 0
	for n in get_tree().get_nodes_in_group(GROUP):
		var body := n as RigidBody3D
		if body == null:
			continue
		tracked += 1
		if body.has_meta(PARKED_META):
			parked += 1
		elif not body.freeze:
			active += 1
	return {"tracked": tracked, "active": active, "parked": parked}
