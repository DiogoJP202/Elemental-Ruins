class_name WaterTuning
extends Resource
## Fluxo de jogo limitado, não SPH. Unidades: m, s, N e umidade/s.
@export_group("Transporte")
@export_range(1.0, 40.0, 0.1) var max_range := 14.0
@export_range(5.0, 100.0, 0.1) var stream_speed := 30.0
@export_range(0.016667, 0.1, 0.001) var emission_interval_s := 1.0 / 30.0
@export_range(1, 64, 1) var max_packets := 32
@export_range(0.01, 1.0, 0.01) var pressure_rise_s := 0.12
@export_group("Pressão e materiais")
@export_range(0.0, 3000.0, 1.0) var force := 300.0
@export_range(0.0, 2.0, 0.01) var wet_per_s := 0.5
@export_range(0.0, 3.0, 0.05) var splash_radius := 1.2
## Variação limitada da pressão; não desvia o raio da mira.
@export_range(0.0, 0.25, 0.01) var pressure_turbulence := 0.04
@export_group("Apresentação (sem física)")
@export var stream_color := Color("#67AFC3")
@export_range(0.02, 0.2, 0.005) var stream_radius := 0.095
@export_range(4, 24, 1) var visual_segments := 24
@export_range(0.0, 0.1, 0.005) var visual_turbulence := 0.025
@export_range(0.0, 0.3, 0.01) var tail_s := 0.12
