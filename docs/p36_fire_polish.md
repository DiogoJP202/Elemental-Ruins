# P3.6 M2 — Fogo: antecipação, varredura, impacto único e propagação visível

Implementado em 26/10/2026. Resource: `scripts/abilities/fire_tuning.gd` + `data/abilities/fire_tuning.tres`, editável no inspetor
(grupos Emissão e transporte, Impacto, Reações térmicas compartilhadas, Apresentação). Controles preservados: 3 seleciona Fogo;
LMB é toque. Nenhuma habilidade nova.

## Fases
| Fase | Padrão | O que acontece | Observável |
|---|---|---|---|
| Clique | 0 | Origem (mão) e direção (mira) capturadas; projétil entra na lista em `anticipation`, ocupando slot do limite | `fire_anticipation` |
| Antecipação | 80 ms | Nenhuma consulta, nenhum calor. Brasas fracas reunindo-se na mão (telegraph) | bola cresce 0,2→0,75 |
| Emissão | tick em que a idade ≥ 80 ms | O resto do tick já voa (sem perder tempo de física) | `fire_launch` |
| Voo | 35 m/s, até 30 m | Uma varredura de segmento por tick (`cast_segment` robusto); turbulência transversal 0,5 m/s a 6 Hz com velocidade total preservada; último segmento recortado no alcance | trilha chama→brasa→fumaça |
| Impacto | 1º contato | HEAT 450 com respingo de 2 m, origem no lado livre (normal × 0,02), alvo = corpo atingido; uma única vez | `fire_impact`, clarão, vapor se secou umidade |
| Dissipação | alcance esgotado | Sem calor, sem evento térmico | `fire_dissipate`, baforada de fumaça |
| Recuperação | 140 ms | Cliques recusados (`rejected`), contados; contrato < 300 ms | HUD "recuperando" |

- **Mira:** capturada no clique (o comando). Girar a câmera durante a antecipação não muda a trajetória (T49). Escolha para
  PvP: o telegraph mostra a direção comprometida e os tempos são determinísticos a partir do clique.
- **Cancelamento:** trocar de elemento remove antecipações (`cancelled`), sem lançamento, calor ou FX posterior. Projéteis já
  lançados seguem (compromisso após a emissão). Reset/save/load limpam antecipações, voos e recuperação no próprio sinal de
  início do comando (T57).
- **Limite:** `max_projectiles` editável (1–8), com teto absoluto de 8 do pool visual. Antecipações contam no limite.
- **Contadores separados:** `fired` (cliques aceitos), `launched`, `exploded` (= `impacts`, impactos com calor),
  `dissipated`, `cancelled`, `rejected`, `queries`, `ray_fallback_hits`, `stale_dropped`.

## Obstrução
- Respingo de calor: `MaterialResponseSystem.apply` só aquece corpos da esfera com linha de visada a partir da origem do
  impacto, consultando TERRAIN|PROPS com `hit_from_inside`/`hit_back_faces`, excluindo o RID do alvo.
- Propagação: cada fonte em chamas só aquece vizinhos com linha de visada centro→centro, excluindo os RIDs da fonte e do
  alvo. Contadores `spread_queries` e `spread_blocked`.
- Raio do fogo: `cast_segment(..., robust = true)` usa as testemunhas de ±1 mm do `PhysicsRayHelper` (D44) somente quando o
  raio original falha. A Água continua com o raio único validado no M1.

## Apresentação (só lê estado)
Núcleo + casca aditiva de chamas periféricas (turbulência visual só na casca), trilha com rampa chama→brasa→fumaça, clarão de
impacto com a mesma rampa, vapor quando o impacto secou umidade real do alvo, baforada de fumaça na dissipação, chamas
contínuas por corpo em chamas (teto 24 emissores), escurecimento progressivo pela integridade e carbonização. Cada projétil
ocupa um slot estável do pool (por id), para a trilha não saltar entre trajetórias quando outro projétil termina. Pools fixos:
8 núcleos/cascas/trilhas, 4 clarões, 4 vapores, 4 baforadas.

## Verificação
Comando: `powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage m2 -TestIds T31,T32,T33,T34,T35,T36,T37,T46,T47,T48,T49,T50,T51,T57 -Window`.
Contrato `p36` atualizado para incluir T49, T50, T51 e T57 (`tools/lib_selftest_contract.ps1`).
- Editor headless: 15/15 PASS, zero erros/avisos (`docs/evidence/p36/m2/editor_headless.json`).
- Editor janela: 15/15 PASS, zero erros/avisos, capturas em `docs/evidence/p36/m2/screens/` (`editor_window.json`).
- **T49**: slot ocupado desde o clique; nenhum evento térmico antes do voo; lançamento a 0,0833 s (5 ticks; tuning 0,08 s ± 1 tick);
  direção do lançamento × direção do clique = 1,0 mesmo com a câmera virada para outro alvo; 1 impacto e 1 evento térmico
  (alvo 470 °C, isca 20 °C). Cancelar 2 ticks após o clique remove o projétil no próprio comando, sem lançamento, calor ou
  FX posterior. Voo sobrevive à troca de elemento e impacta. Recuperação 0,15 s (9 ticks; tuning 0,14 s). Limite 3 → 3 vivos e
  2 recusas; pedido de 20 → teto 8, VFX com 8 slots e nenhum faltando; cancelar libera os 8. Variante (0,2 s, 20 m/s, calor
  120): antecipação 0,200 s, erro do tempo de voo 0,0058 s (< 1 tick), ΔT exato de 120 °C, sem ignição.
- **T50**: parede de 1 mm: 6/6 disparos param na face (normal +Z), 1 evento térmico cada após 3 ticks, 0 testemunhas de 1 mm
  usadas; caixa exposta aquece (468,75 °C), caixa atrás fica em 20 °C e a visada do lado livre confirma. Corpos adjacentes: alvo
  470 °C, caixa encostada atrás 20 °C no instante do impacto. Alcance: face a 30,143 m (além de 30 m e a menos de um passo),
  projétil percorre exatamente 30,000 m (último segmento recortado; sem recorte chegaria a ~30,45 m), 53/53 consultas, 0
  impactos, 0 eventos térmicos, caixa a 20 °C e nenhum FX depois da dissipação. Caixa com face a ~29,4 m ainda recebe impacto.
- **T51**: fonte acesa; vizinho aberto acende em 6,68 s; vizinho atrás da parede de 1 mm fica em 20,0 °C o tempo todo (44
  bloqueios de 156 consultas); vizinho molhado seca antes de aquecer e acende só em 9,07 s com umidade 0; dano/combustível =
  0,0800 (= material); fonte carboniza e o VFX escurece; caixa só aquecida resfria 13 °C em 1 s (taxa 15/s, tolerância de um
  tick térmico). Terreno: morro real bloqueia a visada e a caixa atrás fica em 20 °C; variante com raio 4 m aquece um vizinho
  a 3,2 m até 72,9 °C (impossível com 2,2 m), provando que o FireTuning é usado pelo MaterialResponseSystem.
- **T57**: reset durante antecipação, save durante voo e load com voo + antecipação: no sinal de início do comando já não há
  projéteis, a sessão mudou, recuperação zerada; nenhum lançamento, impacto, dissipação, evento térmico ou FX depois. A caixa
  preservada pelo save fica em 20 °C.
- Regressões: T32 (rocha só aquece, madeira molhada resiste à 1ª rajada, acende, espalha, carboniza), T33 (apaga em 1,73 s),
  T35 (torre cai em 12,75 s, reset remonta), T36, T37, e Água T31/T46/T47/T48 e Ar T34 sem alteração de critérios.
- Capturas revisadas: voo (núcleo + casca), impacto na isca, impacto na parede fina com a caixa de trás intacta, propagação
  bloqueada e carbonização. A bola em antecipação fica atrás do capsule na câmera do próprio jogador; o retorno local é o HUD
  ("preparando rajada"). Para quem observa de outro ângulo, a antecipação aparece na mão; isso não foi avaliado por pessoas.

## Desempenho
Mesma máquina e configuração do baseline: i5-1135G7, Iris Xe, Godot custom 4.7.2 + Voxel Tools 1.7, Jolt, Forward+, 1600×900.
Método T37 agregado (colapso total + 12 caixas em chamas + os 4 poderes), intervalo entre quadros por `process_frame`; não é
custo GPU isolado. Headless não comprova renderização.

| T37 editor janela | p95 ms | p99 ms | máximo ms |
|---|---|---|---|
| Histórico P3.5 | 19,2 | 21,8 | 36,4 |
| HEAD corrigido (8c4beaf) | 19,67 | 21,23 | 30,13 |
| M1 | 18,92 | 19,91 | 38,37 |
| M2, 1ª rodada completa | 18,41 | 20,49 | 34,43 |
| M2, rodada final | 18,64 | 20,06 | 30,29 |

Limites 20/33/50 ms passaram nas duas rodadas do M2. Variação entre rodadas não comprova ganho causal.

Custos de CPU por sistema na janela do T37 (rodada final em janela; instrumentação nova, médias por tick ativo):
| Sistema | Média | Observações |
|---|---|---|
| Avanço dos projéteis (inclui consultas, calor no impacto e callbacks de FX) | 48,6 µs/tick ativo | 99 ticks ativos, 79 consultas, 0 testemunhas de 1 mm |
| Tick térmico (a cada 0,2 s) | 1,99 ms/tick | 35 ticks; pico de 13 corpos em chamas |
| Propagação dentro do tick térmico | 1,89 ms/tick | 2152 consultas de vizinho, 187 bloqueadas |
| VFX de fogo/ar por quadro | 32 µs | máximo acumulado 1,3 ms |

- O máximo acumulado do avanço do fogo (desde o início do processo, não só no T37) foi 8,4 ms na rodada final e 109,5 ms na
  rodada anterior em janela; em headless, 4,5–5,0 ms. O valor inclui os callbacks do impacto (ignição → criação do emissor de
  chamas). O pico de 109,5 ms não se repetiu e a causa não foi isolada; ele não caiu na janela do T37.
- O monitor TIME_PHYSICS_PROCESS tem p95 = máximo também no M1: ele é amostrado em ritmo menor que o tick e repete valores;
  por isso os custos acima vêm da instrumentação por sistema.
- O tick térmico com visibilidade custa ~2 ms a cada 0,2 s com ~13 corpos em chamas. Cabe no gate agregado, mas é o maior
  custo do M2 e deve ser acompanhado no M4 (espalhar a propagação entre ticks, se necessário).

## Mudanças semânticas e limites
- T37: antes, `exploded` contava também o fim de alcance (que aquecia remotamente). Agora o benchmark exige 5 disparos
  aceitos, ≥ 4 lançamentos e ≥ 4 conclusões (impactos + dissipações); limites de FPS inalterados. T50 cobre separadamente
  impacto com calor e dissipação sem calor.
- A visibilidade é um raio centro→centro: uma caixa encostada ao lado do alvo, cujo centro fica atrás da face atingida, não
  recebe respingo. É conservador; exposição parcial por amostragem fica para o Ar (M3), conforme o M0.
- Raycasts: as amostras sem falha (parede de 1 mm, corpos adjacentes, alcance) não provam correção universal.
- Avaliação humana de controles, legibilidade e game feel: **NÃO TESTADO**. Capturas são evidência técnica.
