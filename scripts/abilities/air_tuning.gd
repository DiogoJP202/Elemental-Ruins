class_name AirTuning
extends Resource
## Ar: frente de pressão de jogo (casca esférica recortada por um cone), não CFD.
## Unidades: m, s, kg e N·s. A apresentação não altera física.

@export_group("Frente")
@export_range(1.0, 120.0, 0.5) var front_speed := 30.0
@export_range(1.0, 30.0, 0.1) var max_range := 10.0
@export_range(5.0, 90.0, 1.0) var half_angle_deg := 35.0
## Corpos mais perto que isso contam mesmo fora do ângulo (colados no jogador).
@export_range(0.0, 5.0, 0.1) var near_radius := 1.5
@export_range(1, 4, 1) var max_waves := 4
@export_range(0.0, 1.0, 0.01) var cooldown_s := 0.15

@export_group("Impulso e materiais")
@export_range(0.0, 5000.0, 10.0) var impulse_cap := 1500.0
@export_range(0.0, 40.0, 0.1) var max_delta_v := 12.0
## Componente para cima somado à direção: a caixa sai do chão em vez de só deslizar.
@export_range(0.0, 1.0, 0.01) var lift := 0.35
## Força = 1 − (distância / alcance)^expoente.
@export_range(0.5, 4.0, 0.1) var falloff_exponent := 2.0
## 1 = só o centro; 5 = centro e quatro pontos da silhueta perpendicular à frente.
@export_enum("Centro:1", "Silhueta:5") var exposure_samples: int = 5
## Fração da menor meia-extensão do corpo usada nos pontos laterais da silhueta.
@export_range(0.1, 1.0, 0.05) var silhouette_fraction := 0.7

@export_group("Apresentação (sem física)")
@export var front_color := Color("#DDE6EA")
@export_range(0.0, 1.0, 0.01) var front_alpha := 0.35
@export_range(0.0, 0.5, 0.01) var visual_turbulence := 0.12
@export_range(0.5, 5.0, 0.1) var dust_spacing_m := 2.0
@export var dust_color := Color("#B9A58C")
