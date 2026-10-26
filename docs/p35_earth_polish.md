# P3.5 — Terra polida: fases, peso e legibilidade

**Data:** 26/10/2026 · **Execução:** Claude Code (sessão automatizada nesta máquina).
Mesma máquina e mesmo binário do P0–P3: Windows 11 Pro 10.0.26200, i5-1135G7, Intel Iris Xe (Vulkan 1.4.323),
`godot.windows.editor.x86_64.exe` **4.7.2.stable.custom_build.ed1daf0bf** com **Voxel Tools 1.7 como módulo**.
Todos os números vêm de execuções reais; logs e JSON em `docs/evidence/p35/`, capturas em `docs/evidence/p35/screens/`
(só T29, T30, T43 e as 7 fases da Terra do T45).

**Rodada de referência:** `tools/run_p35_tests.ps1 -Window -Export`, 14:41–15:02, commit `797c46c`, começando com
`.godot/` apagado. **14 de 14 passos com exit 0**; selftest **51/51 nos 4 modos** (editor e `.exe`, headless e janela),
0 erros do motor. Antes dela, uma rodada em que as janelas foram fechadas pelo usuário (§8) e várias rodadas parciais
durante o desenvolvimento.

**Pendente:** o teste por uma pessoa com teclado e mouse (P0–P3.5). A sensação de jogo da Terra é exatamente o que
estes testes **não** medem: eles provam tempos, física e FX, não se é gostoso. NÃO TESTADO.

## 1. Pedido e resultado

| Pedido | Status | Prova |
|---|---|---|
| Manter a base física real | Atendido e testado | A rocha é o corpo do `separate_floating_chunks` (massa do material, 4–8 t); só forças e impulsos (T29: desvio de teleporte 0,003 m). Dano cinético na torre (T30) e cratera real no chão (T43) |
| Reestruturar em fases | Atendido e testado | antecipação → desprendimento → levantamento → hold → lançamento → impacto (T39: ordem e quadros 5/7/10 em todos os modos) |
| Pequeno delay satisfatório, configurável | Atendido e testado | 100 / 110 / 160 ms → **pronta em 361–375 ms** (P3: ~900 ms); tudo em `data/abilities/earth_tuning.tres` (T44 prova que os valores são usados) |
| O chão reage antes da rocha surgir | Atendido e testado | antecipação com chão **intacto** (SDF sólido a cada quadro, T39): rachadura, anel, poeira e pedrinhas; a rocha só existe a partir do desprendimento |
| Rocha parece desprendida | Atendido e testado | cavidade real, rocha congelada no buraco durante o desprendimento (T39), cópia visual da malha tremendo e subindo 0,35 m, estouro de pedrinhas na cor do material |
| Movimento que transmite massa | Atendido e testado (sensação NÃO TESTADA) | subida que desacelera no fim (smoothstep), giro leve, hold com atraso: num giro de câmera de 90°, 6,2 m de atraso aos 100 ms e 1,21 s para assentar, **sem sobressinal** (T42); balanço de 4 cm; jogador a 0,8× |
| Melhorar arremesso e impacto | Atendido e testado | windup de 60 ms, 24 m/s com topspin, rastro; impacto com poeira, pedrinhas, rachadura e tremor; cratera real ≥ 12 m/s (T43: 23,5 m/s → 1 cratera; 8,6 m/s → nenhuma) |
| Viável e legível em PvP | Atendido no desenho (sem PvP real para testar) | telegraph visível a todos por ~210 ms antes de existir rocha; windup de 60 ms; tempos determinísticos e independentes da massa; sem hitstop/`time_scale`; FX locais separados dos visíveis a todos (§3) |
| Responsividade | Atendido e testado | toque curto arranca e lança em 434–437 ms, na direção da mira daquele instante (T40: 1,5° de erro); alvo inválido responde no mesmo quadro (T41) |

## 2. Arquitetura

```
EarthTuning (.tres)  →  EarthLiftThrow (lógica + física, máquina de fases)  →  Ability.fx_event(kind, data)
                                 ↓ TerrainService (extract_rock, cavity_confirmed)     ↓
                                 ↓ TerrainBrushQueue (cratera)                    EarthFx · câmera (add_trauma) · HUD (ReadyRing)
```
- `scripts/abilities/earth_lift_throw.gd`: as fases rodam em `physics_tick` (seguem mesmo depois de soltar o LMB);
  `on_press` valida o alvo e `on_release` guarda o lançamento ou começa o windup.
- `scripts/abilities/earth_tuning.gd` + `data/abilities/earth_tuning.tres`: todos os parâmetros (§4).
- `Ability.fx_event`: o poder anuncia o que já fez; FX, câmera e HUD só ouvem (gancho também para áudio).
- `scripts/elements/earth_fx.gd`: todo o visual da Terra; não muda física (D35, D40).
- `TerrainService`: `can_extract_rock` (validar no clique), `extract_rock(..., hold_kinematic)` (para o `Timer` do
  Voxel Tools), `cavity_confirmed` (raio no buraco) e centro do núcleo alinhado ao voxel (D39).
- Câmera: tremor por trauma que não mexe na mira; HUD: `ReadyRing` em volta da retícula.

## 3. Fases: físico × só VFX

| Fase | Padrão | Físico (real) | Visível a todos (VFX) | Só local |
|---|---|---|---|---|
| clique | — | valida: 2,5–7 m, chão, material, área carregada, sem prender o jogador | — | preview verde/vermelho do ponto; X vermelho se inválido |
| antecipação | 100 ms | nada muda (terreno intacto) | rachadura (decal procedural) crescendo, anel âmbar, poeira rasteira, pedrinhas saltando | tremor leve; anel da retícula começa a encher |
| desprendimento | 110 ms | `extract_rock`: cavidade real; rocha **congelada** até o fim da fase e o raio confirmar a cavidade | cópia da malha treme e sobe 0,35 m; estouro de poeira e pedrinhas na cor do material | tremor médio |
| levantamento | 160 ms | descongela, gravidade 0, trajetória planejada seguida por forças (PD + alimentação direta, teto 600 m/s²), giro leve | poeira saindo do buraco, pedrinhas caindo da rocha | — |
| hold | até soltar | mola "pesada" atrás do ponto à frente do jogador, balanço, amortecimento angular; jogador 0,8× | a rocha, balançando | anel cheio e branco |
| lançamento | windup 60 ms | recuo de 0,3 m, impulso a 24 m/s com compensação de arco, topspin | puff de poeira, rastro acima de 8 m/s | tranco de câmera |
| impacto | 1º contato | corpo: KINETIC dividido entre os tocados; chão ≥ 12 m/s: **cratera real** (fila de brushes); carência no 1º 1,2 m de voo | poeira, pedrinhas, rachadura | tremor ∝ força e proximidade |

Pedrinhas e poeira são partículas (sem corpos físicos); as pedrinhas colidem com o chão por um
`GPUParticlesCollisionHeightField3D` que segue a câmera. Custo medido no spike E4 (§7).

## 4. Parâmetros ajustáveis (`data/abilities/earth_tuning.tres`, classe `EarthTuning`)

Abra o `.tres` no inspetor da Godot; os grupos seguem as fases. Tempos em segundos, distâncias em metros.

| Grupo | Parâmetro | Padrão | O que muda |
|---|---|---|---|
| Alvo | `min_range` / `max_range` | 2,5 / 7,0 | distância horizontal do jogador ao ponto de arranque; fora disso o clique é inválido |
| Alvo | `rock_radius` | 1,2 | raio do núcleo extraído (1–2 m; 1,2 m de solo ≈ 4–8 t pela malha do Voxel Tools) |
| Alvo | `min_floor_normal_y` | 0,6 | só arranca de chão (não de parede/teto) |
| Antecipação | `anticipation_s` | 0,10 | tempo de telegraph com o chão intacto (rachadura, anel, poeira) |
| Desprendimento | `detach_s` | 0,11 | tempo com a rocha congelada no buraco aberto |
| Desprendimento | `detach_visual_rise` / `detach_shake` | 0,35 / 0,06 | quanto a CÓPIA visual da malha sobe e treme (só visual) |
| Desprendimento | `cavity_confirm_timeout_s` | 0,25 | espera extra máxima pelo collider da cavidade (medido: 0 quadros extras) |
| Levantamento | `rise_s` | 0,16 | duração da subida planejada |
| Levantamento | `hold_height` | 2,0 | altura do centro da rocha sobre o chão (no fim da subida e no hold) |
| Levantamento | `rise_track_omega` / `rise_max_accel` | 30 / 600 | rigidez do seguidor de trajetória e teto de aceleração (m/s²) |
| Levantamento | `rise_spin` | 0,8 | giro inicial (rad/s) ao sair do chão |
| Hold | `hold_omega` / `hold_feedforward` / `hold_max_accel` | 4,5 / 0,6 / 40 | "peso": rigidez da mola, quanto ela antecipa o movimento do alvo e teto de aceleração |
| Hold | `hold_settle_s` | 0,15 | transição do ponto sobre o buraco ao ponto relativo ao jogador |
| Hold | `hold_bob_amplitude` / `hold_bob_hz` | 0,05 / 0,7 | balanço vertical |
| Hold | `hold_angular_damp` | 3,0 | estabiliza o giro enquanto segura |
| Hold | `hold_move_speed_scale` | 0,8 | velocidade do jogador enquanto ergue, segura ou lança |
| Lançamento | `windup_s` / `windup_pullback` | 0,06 / 0,3 | recuo antes do lançamento (0 = lança no quadro em que soltar) |
| Lançamento | `throw_speed` / `throw_spin` | 24 / 2,0 | velocidade de saída (m/s) e topspin (rad/s) |
| Lançamento | `aim_range` | 60 | alcance do raio de mira do lançamento |
| Lançamento | `buffer_release` | true | soltar antes de pronta guarda o lançamento (false = cancela e solta a rocha) |
| Lançamento | `recovery_s` | 0,2 | intervalo antes de aceitar outro clique |
| Impacto | `impact_monitor_s` | 4,0 | por quanto tempo o voo é monitorado |
| Impacto | `ground_grace_m` | 1,2 | contatos com o terreno no primeiro trecho do voo não contam (borda do próprio buraco) |
| Impacto | `crater_enabled` / `crater_min_speed` / `crater_radius` | true / 12 / 0,7 | cratera real no impacto com o chão |
| Impacto | `impact_fx_min_speed` | 5 | abaixo disso, tocar o chão não dispara FX |
| Massa | `mass_time_scale` | 0 | 0 = tempos independentes da massa (PvP); 1 = desprendimento/levantamento escalam por (massa / 5 t)^0,25 |

Tremor de câmera (`ThirdPersonCamera`, grupo "Tremor (P3.5)"): `shake_scale` 1 (0 desliga), `shake_max_offset`
0,22 m, `shake_max_roll_deg` 1,2°, `shake_decay_per_s` 1,8, `shake_frequency` 22. Intensidades por evento ficam em
`EarthFx._on_fx` (antecipação 0,12, desprendimento 0,3, lançamento 0,15, impacto 0,15–0,8 pela força), escaladas pela
proximidade da câmera (zero a 30 m).

## 5. Testes do P3.5 (`scripts/dev/p35_selftest.gd`; os 4 modos deram o mesmo resultado, com as variações indicadas)

| ID | Prova | Observado |
|---|---|---|
| T39 | fases na ordem e nos tempos; chão intacto na antecipação; rocha congelada e cavidade aberta no desprendimento; dinâmica no levantamento; pronta ≤ 400 ms; cada FX na fase certa | quadros 5 / 7 / 10 (a antecipação conta o próprio quadro do clique), **pronta em 361–369 ms**, 0 quadros extras esperando a cavidade; rachadura e anel na antecipação, tremor da malha no desprendimento, pedrinhas da rocha no levantamento, rastro e impacto depois do lançamento |
| T40 | toque curto = lançamento guardado; recuperação | soltou na antecipação; lançou em 434–437 ms na direção da mira mudada depois de soltar (1,5° de diferença); clique na recuperação ignorado; livre depois de 200 ms |
| T41 | alvo inválido | céu ("sem chão na mira"), 9 m ("longe demais"), 1,5 m ("perto demais"), sobre o jogador (`overlaps_player`): 0 extrações, 0 edições, fase vazia |
| T42 | peso no hold | giro de 90°: 6,2 m de atraso aos 100 ms, 0,3 m em 1,21 s, sobressinal 0; balanço de 0,041 m; jogador a 0,8× segurando e 1,0× depois |
| T43 | cratera no impacto | rápido: 23,5 m/s no chão → 1 cratera pela fila, SDF +0,69 no ponto (vazio); lento (8 m/s): 8,6 m/s no chão → 0 crateras |
| T44 | o tuning é usado | antecipação de 140 ms → 8 quadros (esperado 9 ± 1); velocidade no hold 0,5 |
| T45 | capturas durante cada fase | 7 capturas no editor em janela (no `.exe` o runner não pede capturas); todas as fases vistas nos 4 modos |
| T29 (P3, ajustado) | rocha real, só forças, acerta a caixa | rocha de 6,97 t, pronta em 366–375 ms, desvio de teleporte 0,003 m, maior passo 0,58 m/quadro, 24 m/s, caixa deslocada 3,2–4,2 m |
| T30 / T36 / T37 (P3) | seguem passando com a Terra nova | T30: 1 bloco por impacto + o de cima pelo grafo; T36: 15,97–16,06 s, nós 199 = baseline; T37 abaixo |

## 6. Medições

| Medida | Editor headless | Editor janela | `.exe` headless | `.exe` janela |
|---|---|---|---|---|
| Clique → rocha pronta (T39, ms) | 369 | 366 | 361 | 367 |
| Toque curto → lançamento (T40, ms) | 436 | 435 | 437 | 434 |
| Giro de 90° → rocha a 0,3 m (T42, ms) | 1216 | 1216 | 1207 | 1212 |
| T37 intervalo entre quadros, 4 poderes + colapso (p50 / p95 / p99 / máx., ms) | sem render | 16,6 / **19,2** / 21,8 / 36,4 | sem render | 16,7 / 17,9 / 19,2 / 31,0 |
| T37 TIME_PHYSICS_PROCESS (méd. / máx., ms) | 8,2 / 23,2 | 6,4 / 21,7 | 8,9 / 27,0 | 4,6 / 16,0 |
| T27 colapso total (p50 / p95 / p99 / máx., ms) | sem render | 16,6 / 17,8 / 18,4 / 19,6 | sem render | 16,7 / 17,6 / 18,1 / 18,9 |
| FPS no roteiro inteiro (méd. / p95) | — | 58,6 / 60 | — | 59,8 / 60 |
| T26 maior deslocamento depois do salvar (m; critério 0,1) | 0,059 | 0,022 | 0,037 | 0,030 |

O T37 em janela do editor ficou com p95 de 19,2 ms, perto do critério de 20 ms (D27); na referência do P3 era 18,1. Em
headless não há render nem vsync.

## 7. Spike P3.5 (`tools/spike_p35_earth.gd`; `00_spike_p35.txt` headless, `00_spike_p35_window.txt` janela)

| ID | Resultado |
|---|---|
| E1 | o `Timer` do Voxel Tools tem 0,200 s, `one_shot`, ligado a `set_freeze_enabled`; parado, o corpo fica congelado (≥ 1 s). Descongelar no 1º quadro não dá empurrão (subida 0 m/s; a rocha só cai ~1,1 m na folga) |
| E2 | o collider da cavidade aparece em 1–2 quadros (15–26 ms), visto por um raio no centro do buraco. A consulta de forma não serve (o collider é uma casca) |
| E3 | levantamento planejado de ~2,6 m: em 160–200 ms, erro em T ≤ 0,12 m, sobressinal 0, sem contato com a cavidade (núcleo ≤ 1,2 m). Informativo: em 120 ms houve 4 contatos com a cavidade numa rodada em janela |
| E4 | em janela, sem vsync: 8 decals + 6 emissores de pedrinhas + heightfield custam Δp95 0,63–0,98 ms; o shader do terreno recebe decal (`spike_decal.png`) |
| E5 | separação do núcleo em 36 posições sub-voxel: 32/36 antes do alinhamento ao voxel, **36/36 depois** (D39) |

## 8. Achados e correções

- **O Voxel Tools descongelava a rocha sozinho em 0,2 s** (E1). Paramos o `Timer` e o desprendimento decide (D36).
- **Consulta de forma não detecta rocha dentro do sólido** (o collider é casca): confirmação por raio no buraco (D36).
- **Núcleo preso ao terreno em 4/36 posições sub-voxel** (achado no T45: cavidade aberta, 0 corpos). Centro do
  núcleo alinhado ao voxel (D39); vale também para a extração R do P2 (T23/T24 seguem passando).
- **A rocha raspava a borda do próprio buraco ao sair**, e a cratera e o FX de impacto apareciam ao lado do jogador
  (capturas do T45). Carência no primeiro trecho do voo. A 1ª versão era por tempo (150 ms) e perdia o impacto de
  arremessos curtos no chão à frente (T39); ficou por distância (1,2 m). Altura do hold de 1,8 para 2,0 m (D38).
- **Legibilidade nas capturas:**
  - a esfera verde do pincel G/H cobria tudo: agora fica escondida enquanto a Terra age;
  - a poeira saía em quadrados duros: agora usa uma mancha radial suave;
  - as rachaduras quase não apareciam: linhas mais grossas e escuras e decal de 6 m;
  - o anel de prontidão era desenhado no canto da tela (controle com tamanho 0): agora é centrado pelo viewport.
- **3.500 erros "Trying to cast a freed object"** no `EarthFx` (rocha liberada pelo reset): checar antes de converter.
- **Testes:**
  - raio de 22 m do Jolt exatamente sobre uma aresta (x inteiro, direção x = −0,0) não acertava o chão em parte das
    rodadas: os testes miram 0,17 m fora da grade;
  - depois de um teleporte de ~80 m o collider chega depois dos dados: `_p3_lab` espera o collider;
  - T29 com detecção de teleporte e caixa > 0,5 m;
  - T43 B lançava de dentro da 1ª cavidade e passava sem lançar nada; agora exige o lançamento;
  - o registro de fases com teto de 32 entradas quebrava a indexação; o T44 passou a filtrar por quadro;
  - o T39 tirava a foto dos contadores de FX depois do clique; agora tira antes (D41).
- **Bateria:**
  - na 1ª tentativa o usuário fechou as janelas da Godot. Os passos em janela saíram com **exit 0** em 3,5 s e
    10,4 s sem rodar os testes: o runner não percebe uma janela fechada (§9);
  - na mesma tentativa, o T8 (P1, vala contínua) falhou 1 vez no `.exe` headless num único ponto (z = −10,0). O raio
    de verificação vertical em coordenadas inteiras é o mesmo cenário de aresta acima. Não repetiu na rodada de
    referência e não foi corrigido.

## 9. Limitações e riscos

- **Sensação de jogo não testada por pessoa.**
  - O levantamento é um "estalo" rápido (pico de ~35 m/s, até 0,58 m por quadro): em FPS baixo pode parecer salto.
  - O hold leva ~1,2 s para alcançar um giro de 90°. É pesado de propósito, mas pode parecer lento em PvP.
  - Ajuste: `rise_s`, `hold_omega` e `hold_max_accel`.
- **Rachaduras ainda sutis** à distância comum da câmera (~9 m), e só onde o decal alcança.
- **PvP só no desenho:** não há dano em jogadores, rede nem áudio. O telegraph, os tempos determinísticos e a ausência
  de efeitos globais estão prontos para isso, mas não foram exercitados com dois jogadores.
- **Cratera perto da torre** pode derrubá-la (consistente com o P2). A cratera é recusada perto do jogador.
- **Alcance 2,5–7 m** (decisão do usuário): a Terra não puxa rochas de longe como no P3.
- **Runner em janela:** se a janela for fechada, o passo sai com exit 0 sem testes. Vale para os runners P0–P3.5:
  conferir o `RESULTADO GERAL` no log. Correção sugerida: o runner exigir o relatório JSON do passo.
- **T8 do P1 intermitente:** falhou 1 vez, num passo do `.exe` headless, e passou em todas as outras rodadas do P3.5 (§8).
- B1 (crash raro no fim do `--import`) continua aceito; nas rodadas do P3.5 o import passou na 1ª tentativa.

## 10. Não testado

- A sensação por uma pessoa (roteiro manual do P3.5 no README), em especial: o delay de ~370 ms parece bom? O peso no
  hold atrapalha a mira? O telegraph é legível para quem está do outro lado?
- Terreno em declive, areia e pedra como origem da rocha (os testes usam chão plano de solo).
- Dois jogadores (PvP real), áudio e FPS baixo.

## 11. Próximo passo recomendado

Jogar o roteiro manual do P3.5 (README) e ajustar `data/abilities/earth_tuning.tres` pela sensação (`rise_s`,
`hold_omega`, `throw_speed`), antes de levar o mesmo tratamento à Água, ao Fogo e ao Ar.
