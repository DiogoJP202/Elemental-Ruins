class_name BodyMaterial
extends Resource
## Material de um CORPO físico (caixa, rocha, peça de estrutura) para as reações elementais
## do P3. Separado do TerrainMaterial (voxels), mas com os mesmos ids para rochas extraídas.
## Valores são escolhas de laboratório (docs/decisions.md), não dados medidos.

@export var id: StringName
@export var display_name := ""
## kg/m³ (informativo; a massa do corpo já vem calculada).
@export var density := 1000.0
@export var flammable := false
## °C em que o material acende (só se flammable e quase seco).
@export var ignition_temperature := 300.0
## Segundos de queima a intensidade 1.
@export var fuel_seconds := 0.0
## Divide o calor recebido: pedra esquenta mais devagar que madeira.
@export var heat_resistance := 1.0
## °C por segundo de volta à temperatura ambiente.
@export var cooling_per_second := 10.0
## Umidade (0–1) perdida por segundo ao ar.
@export var drying_per_second := 0.03
## Integridade (0–1) perdida por segundo de queima a intensidade 1.
@export var burn_damage_per_second := 0.0
## Variação de velocidade equivalente (impulso / massa, m/s) que solta uma peça presa.
@export var break_delta_v := 6.0
@export var color := Color.WHITE


static func create(p_id: StringName, p_name: String, p_density: float, p_flammable: bool, p_ignition: float,
		p_fuel: float, p_heat_res: float, p_cooling: float, p_drying: float, p_burn_damage: float,
		p_break_dv: float, p_color: Color) -> BodyMaterial:
	var m := BodyMaterial.new()
	m.id = p_id
	m.display_name = p_name
	m.density = p_density
	m.flammable = p_flammable
	m.ignition_temperature = p_ignition
	m.fuel_seconds = p_fuel
	m.heat_resistance = p_heat_res
	m.cooling_per_second = p_cooling
	m.drying_per_second = p_drying
	m.burn_damage_per_second = p_burn_damage
	m.break_delta_v = p_break_dv
	m.color = p_color
	return m
