# Resultados do P3 — quatro elementos iniciais

**Data:** 26/10/2026 · **Execução:** Claude Code (sessão automatizada nesta máquina).
Mesma máquina e mesmo binário do P0–P2: Windows 11 Pro 10.0.26200, i5-1135G7, 15,7 GB, Intel Iris Xe (Vulkan 1.4.323),
`godot.windows.editor.x86_64.exe` **4.7.2.stable.custom_build.ed1daf0bf** com **Voxel Tools 1.7 como módulo**.
Todos os números vêm de execuções reais; logs e JSON em `docs/evidence/p3/`, capturas em `docs/evidence/p3/screens/`
(só as 8 dos testes do P3; as 24 das cenas P0–P2 que a rodada em janela também gera não foram versionadas).

**Rodada de referência:** `tools/run_p3_tests.ps1 -Window -Export`, 11:33–11:52, começando com `.godot/` apagado, com a
árvore idêntica à do commit `21bcbad` (commitado logo depois, sem mudar scripts). **14 de 14 passos com exit 0.**
Antes dela houve 3 rodadas que reprovaram e foram corrigidas (§7): T36 no editor headless (rajada fora de alcance),
T28 em janela (mouse preso) e T26 no `.exe` em janela (peça escorregou depois do salvar).

**Pendente desde o P0:** o roteiro manual por uma pessoa (agora P0–P3) no editor custom. Continua NÃO TESTADO.

## 1. Gate do P3 (`PROJETO_ROADMAP.md` e pesquisa §8)

| Status | Critério | Prova |
|---|---|---|
| PASSOU | **Cada elemento gera um efeito físico real verificável** | Terra: rocha real extraída, suspensa só por forças, arremessada a 21,7 m/s; desloca uma caixa 2,7–3,6 m (T29) e solta um bloco de pilar por impacto, e o grafo derruba o de cima (T30). Água: empurra uma caixa 5,1–5,6 m em 1,5 s, molha a 65%, não atravessa terreno (T31) e apaga fogo em 1,4 s (T33). Fogo: acende madeira, a vizinha pega fogo em 4,6–4,7 s, carboniza; madeira molhada resiste à 1ª bola; rocha só aquece (T32); queimar os 2 pilares de madeira da frente derruba as placas de cima em 12,7–12,8 s (T35). Ar: caixa a 9,27 m/s, rocha de 4,2 t a 0,22 m/s, nada atrás de terreno, fogo fraco apaga e o forte aviva (T34). Nos 4 modos |
| PASSOU | **… com o mínimo de VFX** | `ElementalFx` só lê o estado já decidido: chamas por corpo, vapor, carvão, jato, bolas, clarão, rajada. Chamas e carvão aparecem nas capturas do T32, T35 e T37; os FX de ação (jato, bola, rajada) foram conferidos só por contadores (§2) |
| PASSOU | **Habilidades integradas por interface comum** | `AbilityController` → `Ability` (`on_press/on_hold/on_release/physics_tick/cancel/clear`) → `ElementalEvent` → `MaterialResponseSystem` (D28). T28: as teclas 1–4 escolhem os 4 poderes pelo evento de input real, o LMB chega ao poder, o clique sem mouse preso é ignorado e nada age durante o reset |
| PASSOU | **No máximo 4 poderes** | 4, um por elemento (Terra segurar, Água segurar, Fogo toque, Ar toque) |
| PASSOU | **Sequência transversal de ~20 s modificando cenário e props, e reset correto** | T36: 6 passos em **16,6 s** (Terra quebra pilar → Fogo acende pilar de madeira e caixa → Água apaga a caixa → Ar sopra outra caixa → anda até a torre e apaga o pilar → Ar sopra os destroços); depois do reset: 36 peças no lugar e congeladas, 0 estados, 0 em chamas, 0 chamas, 0 destroços, poderes parados, **nós 173 = baseline**. Nos 4 modos |
| PASSOU (critério da D27, D33) | Sem destruir o FPS no pior caso do P3 | T37 em janela (colapso total + 12 caixas em chamas + os 4 poderes): intervalo entre quadros **p95 18,1 / p99 19,1 / máx. 30,7 ms** (editor) e **18,1 / 20,2 / 29,9 ms** (`.exe`) (critério p95 ≤ 20, p99 ≤ 33, máx. ≤ 50) |

**Gate P3: PASSOU** nesta cena de laboratório, com as limitações da §8.

## 2. Escopo do P3

| Status | Item | Onde / prova |
|---|---|---|
| Implementado e testado | Seleção 1–4 e LMB por input map, bloqueio no reset | `AbilityController`; T28 |
| Implementado e testado | Terra: erguer (mola-amortecedor) e arremessar rocha real | `EarthLiftThrow`; T29, T30, T36 |
| Implementado e testado | Dano cinético em peça presa da torre | `MaterialResponseSystem` (KINETIC) + `StructureService.break_piece`; T38 g, T30 |
| Implementado e testado | Água: jato com força, molhar, resfriar, apagar | `WaterJet`; T31, T33, T36 |
| Implementado e testado | Fogo: bola com calor, ignição, queima, propagação, carvão | `FireBurst` + tick do `MaterialResponseSystem`; T32, T35, T38 |
| Implementado e testado | Ar: cone com impulso pela massa, oclusão por terreno, apaga/aviva fogo | `AirGust`; T34, T36 |
| Implementado e testado | Estados de material (madeira/pedra/solo/areia) | `BodyMaterial`, `MaterialState`; T38 (a–g) |
| Implementado e testado | Torre mista: madeira queimada sai do grafo e derruba o que dependia dela | `TowerFactory`, `StructureService.consume_piece`; T35 |
| Implementado e testado | Reset limpa estados, fogo, FX e poderes | T35 (reset), T36 |
| Implementado e testado | Chamas e carvão visíveis | Contadores no T32, T35 e T37; capturas 28, 30 e 32 |
| Implementado, só contador | Vapor, jato, bolas de fogo, clarão e rajada | Contadores (`steam`, `blasts`, `gusts`) no T33 e T37; as capturas são tiradas depois da ação |
| Implementado e testado | HUD: elemento, resultado do poder, estado do corpo mirado | Capturas 25–32 (linha "Poder:"); legenda com 1–4/LMB |
| Não implementado | 16 habilidades, Q/E, RMB, carga, câmera lenta, custos de matéria, lama/gelo/vapor persistente, calor no terreno, áudio, arte | Fora do escopo do P3 (plano) |

## 3. Comandos executados (rodada de referência)

| # | Passo | Log / relatório | Resultado |
|---|---|---|---|
| 1 | `--import` (cache vazio) | `01_import.log` | exit 0, 1ª tentativa |
| 2–3 | `check_env`, dump da API | `02_…`, `03_…` | exit 0 |
| 4 | spike de física do P3 | `04_spike_p3_physics.log`, `00_spike_p3.txt` | exit 0, H1–H3 OK |
| 5 | selftest P0 sozinho | `05_…`, `p0_regressao_headless.json` | **12/12**, 0 erros/avisos |
| 6 | selftest P3 (editor, headless) | `06_…`, `p3_selftest_headless.json` | **44/44**, 0/0, 244 s |
| 7–8 | persistência entre processos (editor) | `07_…`, `08_…` | 2/2 e 2/2 |
| 9 | selftest P3 (editor, janela, capturas) | `09_…`, `p3_selftest_window.json`, `screens/` | **44/44**, 0/0, 291 s |
| 10 | export release | `10_…` | exit 0 |
| 11 | selftest P3 no `.exe` (headless) | `11_…`, `p3_selftest_export_headless.json` | **44/44**, 0/0 |
| 12–13 | persistência entre processos no `.exe` | `12_…`, `13_…` | 2/2 e 2/2 |
| 14 | selftest P3 no `.exe` (janela) | `14_…`, `p3_selftest_export_window.json` | **44/44**, 0/0 |

44 testes = 12 do P0 + 11 do P1 + 10 do P2 + 11 do P3 (T28–T38).

## 4. Testes do P3 (editor headless; os 4 modos deram o mesmo resultado, com as variações indicadas)

| ID | Observado |
|---|---|
| T38 | eventos aplicados direto: madeira seca não acende com 200 (220 °C) e acende com +150; pedra com 1000 só aquece (353 °C); madeira a 60% de umidade fica a 100 °C na 1ª rajada de 320 e acende na 2ª; água a 40% apaga; vento 0,8 apaga fogo de 0,2 e aviva 0,6 → 0,84; queima até o fim remove a caixa; impacto Δv 3 m/s não solta a coroa e 7 m/s solta |
| T28 | 1–4 → poderes 0–3 (terra/água/fogo/ar); LMB roteado (press/release); clique sem mouse preso ignorado; `use_pressed` durante o reset recusado |
| T29 | rocha de solo de **5,44 t**; suspensa a < 1 m do alvo em 895–902 ms, erro final 0,1 mm; maior passo por quadro 0,151 m (só forças); lançamento 21,7 m/s; 1º contato com a caixa (impulso estimado 1751 N·s); caixa deslocada 2,7–3,6 m |
| T30 | rocha arremessada no pé do pilar de pedra da frente: impulso estimado 106 799 N·s; 1 bloco solto por impacto (o do meio, P07) e o de cima (P08) pelo grafo; o pé fica |
| T31 | caixa de 20 kg a 6 m: 1,5 s de jato (90 quadros nela) → deslocada 5,1–5,6 m, molhada 65%; caixa atrás de um morro de terreno: 0 m, 0% (os 60 quadros de jato pararam no morro) |
| T32 | rocha de solo (4161 kg) atingida: 245 °C, não acende. Caixa molhada a 60%: 233–237 °C depois da 1ª bola (não acende), 677–684 °C e acesa depois da 2ª. Caixa seca acende; a vizinha (vão de 0,5 m) pega fogo em 4,6–4,7 s; a 1ª fica carbonizada (integridade 50%, combustível 12 → 5,7) |
| T33 | caixa com fogo a 100%: o jato apaga em **1,35–1,40 s**, causa "água", 1 disparo de vapor |
| T34 | caixa a ~5 m: 9,27 m/s, voa 7,2–7,3 m; rocha de 4161 kg na mesma faixa: 0,22 m/s (**43× menos**); caixa atrás de um morro: 0 m/s (1 corpo bloqueado por terreno); fogo de 0,2 apaga e o de 0,6 vai a 0,88–0,93 |
| T35 | 2 bolas nos blocos de baixo dos 2 pilares de madeira da frente → as 2 placas de cima caem em **12,7–12,8 s**; 2 blocos consumidos, 9 peças soltas, pilares e placas de trás intactos; 4 chamas e 4 carbonizações no FX; reset: 36 peças, sem estados |
| T36 | §1; o último destroço ficou a 5,7 m do jogador quando a rajada saiu (o roteiro anda até ele se estiver a > 7 m) |
| T37 | §5; pico de 12–13 corpos em chamas e 36 peças dinâmicas; poderes usados: 5 bolas de fogo, 120 quadros de jato em corpos, 4 rajadas, 1 arremesso |

## 5. Medições

| Medida | Editor headless | Editor janela | `.exe` headless | `.exe` janela |
|---|---|---|---|---|
| T37 intervalo entre quadros, 4 poderes + colapso + 12 fogos (p50 / p95 / p99 / máx., ms) | sem render | **16,7 / 18,1 / 19,1 / 30,7** | sem render | **16,7 / 18,1 / 20,2 / 29,9** |
| T37 TIME_PHYSICS_PROCESS (méd. / máx., ms) | 5,3 / 13,7 | 4,2 / 14,4 | 3,2 / 11,0 | 4,2 / 13,9 |
| T27 colapso total, torre mista (p50 / p95 / p99 / máx., ms) | sem render | 16,7 / 17,6 / 18,3 / 18,5 | sem render | 16,7 / 17,6 / 18,5 / 21,7 |
| T35 bolas → placas de cima caídas (s) | 12,7 | 12,8 | 12,8 | 12,7 |
| T33 jato → fogo apagado (s) | 1,40 | 1,35 | 1,40 | 1,40 |
| T36 duração da sequência (s) | 16,6 | 16,6 | 16,6 | 16,6 |
| T26 maior deslocamento depois do salvar (m; critério ≤ 0,1) | 0,004 | **0,072** | 0,020 | 0,025 |
| FPS no roteiro inteiro (méd. / p95) | — | 58,8 / 61 | — | 59,7 / 60 |
| P1 T15 (100 edições) intervalo entre quadros p95 / máx. (ms) | — | 18,1 / 19,4 | — | 18,5 / 22,1 |

Em headless o intervalo entre quadros não tem render nem vsync; só a janela vale para o critério (D27). O máximo de
~30 ms do T37 em janela fica dentro do teto de 50 ms, mas é ~1,7× o do T27.

Contadores acumulados do roteiro no fim do T37 (editor headless): 29 ignições (0 recusadas pelo teto), 7 apagados,
3 queimados até o fim, 3 quebras por impacto; FX: 29 chamas criadas (0 recusadas pelo teto de 24), 18 carbonizações,
14 clarões, 8 rajadas, 5 vapores. Não medi o custo de GPU das partículas separadamente.

Leitura honesta: a cena tem 1 torre, até 13 corpos em chamas e 36 peças dinâmicas. O critério de FPS foi cumprido
**nesta** cena, com vsync, nesta máquina; não garante várias torres ou dezenas de fogueiras.

## 6. Spike P3 (`tools/spike_p3_physics.gd`, `docs/evidence/p3/00_spike_p3.txt`)

| ID | Resultado |
|---|---|
| H1 | rocha de 14,7 t na mola-amortecedor (ω = 6, teto de 40 m/s²): chega a < 0,3 m em 849 ms, erro 2 mm depois de 2 s, sobressinal 0,29 m, segue um alvo em movimento com erro máximo de 0,22 m, maior passo por quadro 0,145 m |
| H2 | arremesso por impulso + `contact_monitor` contra peça congelada: 1º contato em 600 ms, impulso estimado pela velocidade antes/depois (309 329 N·s); a peça congelada fica no lugar |
| H3 | consulta em cone com 150 corpos (esfera + ângulo + raio no terreno): 0,81 ms |

## 7. Bugs e achados durante o P3

- **Rocha atrasada ao seguir o alvo (corrigido no spike, H1).** Com amortecimento só pela velocidade absoluta, a rocha
  seguia o jogador 1,42 m atrás (≈ 2v/ω). Com o amortecimento relativo à velocidade do alvo, 0,22 m.
- **Rocha caía antes do arremesso (corrigido no spike, H2).** Solta da mola sem impulso imediato, só registrava contato
  com o terreno. A rocha agora fica na mola até o quadro do lançamento, com a gravidade religada nesse quadro.
- **Origem do corpo longe do centro (corrigido).** O corpo do `separate_floating_chunks` tem a origem no canto da caixa
  do pedaço, ~3 m do centro da malha: segurar e mirar pela origem errava o alvo (T29). Tudo usa o centro da malha
  (`MaterialResponseSystem.body_center`).
- **Rocha raspando o chão e quicando por cima da caixa (corrigido).** Mirando o pé de uma caixa, o centro de uma rocha de
  ~2 m passava rente ao chão (T29). O ponto mirado sobe para meia altura acima do chão sob ele.
- **Impulso inteiro no corpo errado (corrigido).** A rocha tocou o bloco de cima de raspão no mesmo passo em que bateu no
  pé, e o 1º corpo relatado levava tudo (T30). O impulso é dividido entre os corpos tocados no mesmo passo.
- **1096 erros "previously freed instance" (corrigido).** O reset liberava a rocha em voo e o `physics_tick` atribuía o
  corpo liberado a uma variável tipada antes de checar. Checa `is_instance_valid` antes.
- **Mira dos testes passando ao lado da caixa (corrigido no teste).** Depois de um giro grande, o braço de mola da câmera
  muda de posição no quadro de física seguinte; o raio calculado no quadro do giro passava ao lado (T32: 3 de 4 bolas
  no chão). Os testes esperam 4 quadros para a mira assentar. Um jogador re-mira continuamente; não é bug do poder.
- **Falso positivo no T34 (corrigido no teste).** Sem `place_dir`, a rocha extraída fica **dentro** da cavidade, 2 m
  abaixo do chão; a rajada não a alcançava, e a velocidade medida era a da rocha assentando, o que bastou para passar.
  O teste agora põe a rocha ao lado do buraco e exige que ela esteja na lista de corpos da rajada.
- **Jogador caindo no buraco da rocha (contornado no teste).** No T36, andar na diagonal até a torre passava pela boca
  da cavidade de onde a rocha saiu. O roteiro contorna o buraco. No jogo, o buraco é real e o jogador pode cair nele.
- **Rajada fora de alcance no T36 (1ª rodada da bateria; corrigido no teste).** O destroço caiu a ~10,4 m do jogador,
  além dos 10 m do Ar, e a rajada não o pegou; nas rodadas isoladas ele tinha caído mais perto. O roteiro anda até o
  destroço mais próximo quando ele está a > 7 m.
- **Clique "sem mouse preso" agiu em janela (2ª rodada; corrigido no teste).** O T28 supunha o mouse livre, mas em janela
  ele estava preso naquele momento (qualquer clique na janela o prende, `third_person_camera`). Não identifiquei o que o
  prendeu; nas rodadas seguintes estava livre. O teste agora solta o mouse e registra o estado anterior.
- **Peça escorregou 0,51 m depois do salvar (3ª rodada, T26 no `.exe` em janela; reforçado, causa não provada).** Ver
  D34: a espera por collider passou a exigir de volta o apoio que cada corpo tinha antes do save. Não reproduzi em 5
  rodadas isoladas nem na rodada de referência (espera de 0 quadros em todas).
- **Constantes de propagação e secagem recalibradas** antes do 1º teste do Fogo (D31): pela conta, com os valores do M1
  a madeira molhada acenderia na 1ª rajada e a caixa vizinha não pegaria fogo antes de a primeira queimar até o fim.
- **Título do HUD ainda dizia "laboratório P2"** (visto nas capturas da 3ª rodada); corrigido antes da rodada de referência.

## 8. Limitações e riscos

- **Modelos de jogo, não simulação:** o jato é um raio (sem fluido, poça, lama ou vapor persistente); o fogo é estado
  por corpo (não queima o terreno, não aquece voxels); a rajada é um impulso instantâneo (sem vento contínuo).
- **Jato com força absoluta e central** (300 N, sem torque no ponto atingido); a mesma força em qualquer distância até 14 m.
- **Bola de fogo** é um ponto com raio por quadro, não um corpo físico: não é empurrada nem desviada.
- **Ar:** só o terreno bloqueia a visada; corpos não fazem sombra uns aos outros.
- **Dano cinético** só no 1º contato com corpos e só em peças **presas** da torre (sem fratura; peças soltas não quebram).
- **Uma peça só não derruba a laje:** a placa se sustenta como viga com 2 laterais apoiadas (D21); é preciso queimar ou
  quebrar os 2 pilares de um lado.
- **Estados de material não são salvos** (D31); o reset e o carregar zeram tudo.
- **Tetos:** 48 corpos em chamas (os excedentes não acendem, contados), 24 chamas visíveis, 8 bolas em voo.
- **Mira pelo centro da tela:** a câmera fica atrás do jogador; o jato e a bola saem da mão em direção ao ponto mirado,
  então um obstáculo entre a mão e o alvo (fora da linha da câmera) pode parar o poder.
- **Sequência transversal automatizada de 16,6 s**, não 20 (seis passos completos; o "~20 s" da pesquisa é de uma pessoa
  jogando).
- **T26 perto do limite em janela:** na rodada de referência a peça que mais andou depois do salvar se moveu 0,072 m
  (critério 0,1 m), e numa rodada anterior uma peça andou 0,51 m (D34). É o teste mais instável da bateria.
- B1 (crash raro no fim do `--import`) continua aceito; nas 4 rodadas do P3 o import passou na 1ª tentativa.

## 9. Não testado

- **Teste manual por pessoa** (P0, P1, P2 e P3) no editor custom, com teclado e mouse reais: roteiros no README. Em
  particular, a sensação de segurar/mirar/arremessar, o alcance dos poderes e a leitura do HUD.
- Abrir o projeto no editor com interface depois do P3 (só editor headless e o jogo rodando).
- FX de ação vistos em movimento (jato, bola, clarão, rajada): só contadores; custo de GPU das partículas em separado.
- Várias torres e dezenas de fogueiras ao mesmo tempo.
- Poderes durante salvar/carregar reais (o T28 cobre o reset; salvar e carregar usam o mesmo cancelamento, sem teste próprio).

## 10. Próximo passo recomendado

Rodar os roteiros manuais do README (P0 a P3) no editor custom, com teclado e mouse reais, antes de iniciar o P4.
