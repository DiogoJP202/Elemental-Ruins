class_name WaterOrbTuning
extends Resource
## Reserva abstrata do Criativo; litros nominais definem a silhueta, não um fluido conservativo.
@export_group("Reserva e controle")
@export_range(10.0, 600.0, 5.0) var nominal_liters := 150.0
@export_range(1.0, 4.0, 0.1) var min_distance := 2.0
@export_range(4.0, 12.0, 0.1) var max_distance := 7.0
@export_range(1.0, 8.0, 0.1) var initial_distance := 3.0
@export_range(0.4, 5.0, 0.1) var initial_height := 1.6
@export_range(0.4, 2.0, 0.1) var min_height := 0.6
@export_range(2.0, 8.0, 0.1) var max_height := 4.0
@export_range(0.1, 5.0, 0.1) var height_speed := 2.0
@export_range(0.1, 1.0, 0.1) var distance_step := 0.5
@export_range(2.0, 12.0, 0.1) var follow_omega := 7.0
@export_range(1.0, 15.0, 0.1) var max_control_speed := 8.0
@export_range(5.0, 120.0, 1.0) var max_control_accel := 55.0
@export_group("Lançamento e contato")
@export_range(5.0, 60.0, 0.5) var launch_speed := 22.0
@export_range(0.0, 10.0, 0.1) var inherited_speed_limit := 5.0
@export_range(5.0, 60.0, 1.0) var max_range := 24.0
@export_range(0.0, 6000.0, 10.0) var impulse_ns := 1800.0
@export_range(0.0, 20.0, 0.1) var max_target_delta_v := 8.0
@export_range(0.0, 2.0, 0.05) var wetness := 0.9
@export_range(0.0, 4.0, 0.1) var splash_radius := 1.8
@export_group("Gelo")
@export_range(0.0, 0.5, 0.01) var freeze_transition_s := 0.18
@export_range(5.0, 60.0, 0.5) var ice_launch_speed := 26.0
@export_range(0.0, 40.0, 0.1) var ice_gravity := 9.8
@export_range(0.0, 6000.0, 10.0) var ice_impulse_ns := 3000.0
@export_range(0.0, 20.0, 0.1) var ice_max_target_delta_v := 12.0
@export var ice_color := Color("#C4E5F5")
@export_group("Gelo persistente")
@export_range(100.0, 2000.0, 1.0) var ice_density := 917.0
@export_range(1, 16, 1) var ice_max_bodies := 8
@export_range(-100.0, -1.0, 1.0) var ice_initial_temperature := -20.0
@export_range(0.0, 100.0, 1.0) var ice_melt_temperature := 0.0
@export_range(0.05, 1.0, 0.05) var ice_melt_duration_s := 0.45
@export_group("Apresentação (sem física)")
@export var color := Color("#80DDEDCC")
@export_range(0.0, 0.1, 0.005) var wobble := 0.045
@export_range(0, 12, 1) var trail_amount := 8
@export_range(0.05, 0.4, 0.01) var trail_lifetime_s := 0.18
@export var visual_enabled := true
