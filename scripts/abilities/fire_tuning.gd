class_name FireTuning
extends Resource
## Fogo: transporte e calor de jogo. Habilidade e sistema material usam o mesmo
## .tres padrão; variantes atribuídas em runtime são referências independentes.

@export_group("Emissão e transporte")
@export_range(0.0, 0.5, 0.01) var anticipation_s := 0.08
@export_range(0.0, 1.0, 0.01) var cooldown_s := 0.14
@export_range(1.0, 300.0, 0.1) var speed := 35.0
@export_range(0.1, 60.0, 0.1) var max_range := 30.0
@export_range(1, 8, 1) var max_projectiles := 8
## Componente transversal oscilante (m/s), com velocidade total preservada.
@export_range(0.0, 5.0, 0.01) var turbulence_mps := 0.5
@export_range(0.0, 20.0, 0.1) var turbulence_hz := 6.0

@export_group("Impacto")
@export_range(0.0, 2000.0, 1.0) var heat := 450.0
@export_range(0.0, 5.0, 0.1) var splash_radius := 2.0

@export_group("Reações térmicas compartilhadas")
@export_range(0.05, 1.0, 0.01) var thermal_tick_s := 0.2
@export_range(0.0, 6.0, 0.1) var spread_radius := 2.2
@export_range(0.0, 1000.0, 1.0) var spread_heat_per_s := 200.0
@export_range(0.0, 2.0, 0.01) var fire_growth_per_s := 0.25
@export_range(1, 48, 1) var max_burning := 48
@export_range(1.0, 2000.0, 1.0) var dry_heat := 400.0

@export_group("Apresentação (sem física)")
@export_range(0.05, 0.5, 0.01) var projectile_radius := 0.25
@export_range(1, 24, 1) var trail_amount := 16
@export_range(0.05, 0.5, 0.01) var trail_lifetime_s := 0.22
@export_range(0.02, 0.3, 0.01) var trail_size := 0.12
@export_range(1, 24, 1) var max_flame_emitters := 24
@export_range(1, 48, 1) var flame_amount := 24
@export_range(0.2, 1.5, 0.05) var flame_lifetime_s := 0.7
@export_range(0.1, 1.0, 0.01) var flame_size := 0.45
@export var flame_color := Color("#FF8A2A")
@export var ember_color := Color("#CF5E25")
@export var smoke_color := Color("#47484C")
