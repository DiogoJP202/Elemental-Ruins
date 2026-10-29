class_name EarthTuning
extends Resource
## Parâmetros da Terra (P3.5): tempos em segundos, distâncias em metros. Valores de jogo,
## editáveis no inspetor em data/abilities/earth_tuning.tres (docs/p35_earth_polish.md explica
## cada um). Os padrões de tempo são múltiplos próximos de quadros de 60 Hz: 6 + 7 + 10 quadros
## = ~383 ms do clique até a rocha pronta.

@export_group("Alvo")
## Distância horizontal do jogador ao arranque e ao alvo do hold.
@export var min_range := 2.5
## Também limita a captura P4B pela distância 3D do jogador ao centro da rocha.
@export var max_range := 7.0
## Raio do núcleo extraído (o TerrainService aceita 1–2 m; 1,2 m de solo ≈ 4–5 t).
@export var rock_radius := 1.2
## Componente vertical mínima da normal: só arranca de chão (não de parede ou teto).
@export var min_floor_normal_y := 0.6

@export_group("Pilar")
@export_range(3.0, 30.0, 0.5) var pillar_range := 18.0
## 2 m dá apoio estável para a caixa de 1 m sobre o topo arredondado na resolução atual.
@export_range(0.5, 2.0, 0.1) var pillar_radius := 2.0
## Altura do topo acima do chão mirado; o pilar fica no terreno até escavar/resetar.
@export_range(2.5, 6.0, 0.5) var pillar_height := 4.5

@export_group("Fissura")
## Todo o caminho precisa estar neste alcance 3D, sobre chão contínuo.
@export_range(3.0, 30.0, 0.5) var fissure_range := 18.0
@export_range(1.0, 10.0, 0.5) var fissure_length := 6.0
@export_range(0.5, 2.0, 0.1) var fissure_radius := 1.0
## Profundidade do centro do tubo; a remoção alcança mais um raio abaixo dele.
@export_range(0.0, 0.75, 0.05) var fissure_depth := 0.35
@export_range(0.1, 1.0, 0.1) var fissure_max_step_height := 1.0

@export_group("Espinhos")
@export_range(1, 3, 1) var spike_count := 3
@export_range(1.0, 3.0, 0.1) var spike_spacing := 1.8
@export_range(2.5, 4.0, 0.1) var spike_height := 3.0
@export_range(0.5, 1.2, 0.1) var spike_base_radius := 0.9
## 0,75 m evita perder a parte superior entre quatro vértices da grade SDF de 1 m.
## 0,5 m continua legal em PATH, mas pode ser subamostrado; 3 m nominais mediram 2,3–2,8 m físicos.
@export_range(0.5, 0.8, 0.05) var spike_tip_radius := 0.75
@export_range(6.0, 20.0, 0.5) var spike_range := 14.0
@export_range(0.10, 0.18, 0.01) var spike_interval_s := 0.14
@export_range(0.1, 1.0, 0.1) var spike_max_step_height := 0.75

@export_group("Antecipação")
@export var anticipation_s := 0.10

@export_group("Desprendimento")
@export var detach_s := 0.11
## Só visual: a malha sobe e treme enquanto o corpo segue congelado no buraco.
@export var detach_visual_rise := 0.35
@export var detach_shake := 0.06
## Espera extra máxima pelo collider da cavidade depois do fim da fase (medido: 2 quadros).
@export var cavity_confirm_timeout_s := 0.25

@export_group("Levantamento")
@export var rise_s := 0.16
## Altura do centro da rocha sobre o chão (no buraco e no hold, relativa aos pés do jogador).
## 2,0 m: com 1,8 m a rocha (malha de até ~3 m) raspava a borda do próprio buraco ao lançar.
@export var hold_height := 2.0
@export var rise_track_omega := 30.0
@export var rise_max_accel := 600.0
## Giro inicial ao sair do chão (rad/s, eixo horizontal sorteado).
@export var rise_spin := 0.8

@export_group("Hold")
## Altura do alvo relativa aos pés; o corpo continua sujeito à mola e às colisões.
@export var hold_min_height := 1.0
@export var hold_max_height := 6.0
@export var hold_height_speed := 2.0
## Metros por passo da roda; distância limitada por min_range/max_range.
@export var hold_distance_step := 0.5
## Mola mais lenta que a do P3 (ω = 6) e alimentação direta parcial: atrasa ao girar (peso).
@export var hold_omega := 4.5
@export var hold_feedforward := 0.6
@export var hold_max_accel := 40.0
## Transição do ponto sobre o buraco para o ponto relativo ao jogador.
@export var hold_settle_s := 0.15
@export var hold_bob_amplitude := 0.05
@export var hold_bob_hz := 0.7
@export var hold_angular_damp := 3.0
## Velocidade do jogador enquanto ergue/segura/lança (1 = normal).
@export var hold_move_speed_scale := 0.8

@export_group("Lançamento")
## 0 = lança no mesmo quadro em que soltar.
@export var windup_s := 0.06
@export var windup_pullback := 0.3
@export var throw_speed := 24.0
## Topspin no lançamento (rad/s).
@export var throw_spin := 2.0
@export var aim_range := 60.0
## Soltar o LMB antes de a rocha ficar pronta guarda o lançamento (false = cancela e solta).
@export var buffer_release := true
## Intervalo depois do lançamento antes de aceitar um novo clique.
@export var recovery_s := 0.2

@export_group("Impacto")
@export var impact_monitor_s := 4.0
## Contatos com o TERRENO no primeiro trecho do voo (m a partir do lançamento) não contam como
## impacto: a rocha raspava a borda do próprio buraco ao sair e a cratera abria ao lado do jogador
## (capturas do T45). Por distância, não por tempo: com 150 ms um arremesso curto no chão à frente
## batia dentro da carência e o impacto se perdia (T39).
@export var ground_grace_m := 1.2
## Impacto no TERRENO a partir desta velocidade abre cratera real (pela TerrainBrushQueue).
@export var crater_enabled := true
@export var crater_min_speed := 12.0
@export var crater_radius := 0.7
## Impacto no terreno a partir desta velocidade dispara FX (abaixo: rolar e quicar sem FX).
@export var impact_fx_min_speed := 5.0

@export_group("Massa")
## 0 = tempos independentes da massa (justo em PvP); 1 = desprendimento e levantamento
## escalam por (massa / 5 t)^0,25.
@export var mass_time_scale := 0.0


func time_scale_for(mass: float) -> float:
	return lerpf(1.0, pow(maxf(mass, 1.0) / 5000.0, 0.25), clampf(mass_time_scale, 0.0, 1.0))
