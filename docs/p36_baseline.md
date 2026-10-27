# Baseline do P3.5 (antes do P3.6)

> **CLASSIFICAÇÃO: HISTÓRICO.** Arquivo recuperado sem commit na retomada em `08b6c6e`, preservado e versionado na Etapa A. As medições abaixo continuam sendo as da rodada original, sem substituição. A Etapa B será registrada separadamente em `docs/evidence/p36/baseline/` e `docs/p36_baseline_corrected.md`.

Ponto de partida medido para o P3.6. Fonte: a rodada de referência do P3.5
(`tools/run_p35_tests.ps1 -Window -Export`, 26/10/2026 14:41–15:02, commit `797c46c`, `.godot/` apagado; relatórios em
`docs/evidence/p35/`). Mesma máquina de todas as fases: Windows 11 Pro, i5-1135G7, Intel Iris Xe (Vulkan 1.4.323),
Godot 4.7.2 custom + Voxel Tools 1.7 (módulo), Jolt.

Entre essa rodada e o início do P3.6 só mudaram: a validação de relatório dos runners, o fechamento do traço contínuo
(`TerrainBrushQueue.end_stroke`) e a repetição deslocada de 1 mm em raios de terreno que erram. Nenhuma das três toca no
caminho de render nem nos poderes; o T8 e o P1 foram reconferidos depois delas (`docs/evidence/p36/t8/`).

**Critério de FPS vigente (D27, D33):** em janela, intervalo entre quadros p95 ≤ 20 ms, p99 ≤ 33 ms, máx. ≤ 50 ms, no pior
caso medido (T27 colapso total e T37 colapso + 4 poderes + 12 fogos). Em headless os números não valem para o critério
(sem render nem vsync). **Atenção:** o T37 no editor em janela estava com p95 = 19,2 ms, a 0,8 ms do limite.

Não medido no baseline: custo de GPU separado por efeito (só o agregado do spike P3.5 E4), áudio (não existe) e o jogo
nas mãos de uma pessoa.

## Os 51 testes (status nos 4 modos)

| # | ID | Teste | Editor headless | Editor janela | .exe headless | .exe janela |
|---|---|---|---|---|---|---|
| 1 | T1 | Terreno pronto; jogador para no chão voxel e não atravessa | PASS | PASS | PASS | PASS |
| 2 | T0 | Dados SDF volumétricos coerentes com o gerador (colina sólida, ar acima) | PASS | PASS | PASS | PASS |
| 3 | T1b | Jogador fica sobre o topo da colina voxel sem atravessar | PASS | PASS | PASS | PASS |
| 4 | T2 | Escavar remove matéria E colisão; jogador cai na cratera | PASS | PASS | PASS | PASS |
| 5 | T3a | Túnel escavado: eixo livre, teto e piso sólidos (raycasts físicos) | PASS | PASS | PASS | PASS |
| 6 | T3b | Jogador atravessa o túnel de boca a boca com teto sólido acima | PASS | PASS | PASS | PASS |
| 7 | T4 | Adicionar matéria forma coluna sólida (caixa e jogador apoiados) | PASS | PASS | PASS | PASS |
| 8 | T5 | 20 ciclos escavar+adicionar no mesmo ponto (40 edições) | PASS | PASS | PASS | PASS |
| 9 | T5b | 100 escavações em sequência (latência edição→collider) | PASS | PASS | PASS | PASS |
| 10 | T6 | Edições inválidas/fora da área falham rápido e com motivo | PASS | PASS | PASS | PASS |
| 11 | T7 | Reset restaura geometria E colisão originais (cratera, túnel e coluna somem) | PASS | PASS | PASS | PASS |
| 12 | T7b | 10 ciclos escavar→reset retornam ao baseline | PASS | PASS | PASS | PASS |
| 13 | T8 | Traço contínuo (120 amostras em 2 s) vira vala contínua com carimbos limitados | PASS | PASS | PASS | PASS |
| 14 | T8b | G segurado 1 s (Input → controlador → fila) abre cratera no collider | PASS | PASS | PASS | PASS |
| 15 | T9 | PATH de 26 m dividido por AABB; rajada de 20 carimbos fundida; orçamento por quadro | PASS | PASS | PASS | PASS |
| 16 | T10 | SMOOTH arredonda saliência: topo desce e a maior inclinação cai (collider e dados) | PASS | PASS | PASS | PASS |
| 17 | T11 | Materiais: layout do gerador, ADD de areia lido nos dados, dureza no ritmo, massa por densidade | PASS | PASS | PASS | PASS |
| 18 | T12 | TerrainChanged {aabb, revision}: 1 evento por edição aplicada, nenhum por recusa | PASS | PASS | PASS | PASS |
| 19 | T13 | Rampa (PATH aditivo de areia): jogador sobe a pé até o topo | PASS | PASS | PASS | PASS |
| 20 | T14 | Persistência: salvar → reset (baseline) → carregar 2× devolve estado idêntico, sem duplicar | PASS | PASS | PASS | PASS |
| 21 | T15 | Benchmark: 100 alterações pela fila (20/s), latência até o collider e tempo de quadro | PASS | PASS | PASS | PASS |
| 22 | T16 | 10 ciclos editar (fila) → reset com stream: baseline, nós, arquivos e memória | PASS | PASS | PASS | PASS |
| 23 | T17 | Overlay mostra FPS/quadro, fila, último brush, motor voxel, memória, corpos e reset/save/load | PASS | PASS | PASS | PASS |
| 24 | T18 | Caixa dormindo sobre o solo cai quando o chão embaixo é escavado (contato atualizado) | PASS | PASS | PASS | PASS |
| 25 | T19 | Torre modular intacta: 36 peças congeladas paradas 5 s; grafo de apoio como montado | PASS | PASS | PASS | PASS |
| 26 | T20 | Escavar sob 1 pilar solta só esse pilar (laje fica: 2 placas vizinhas a sustentam) | PASS | PASS | PASS | PASS |
| 27 | T21 | Escavar sob os outros 3 pilares: colapso total em etapas, peças sobre o terreno | PASS | PASS | PASS | PASS |
| 28 | T22 | Orçamento: 150 caixas + 36 peças → corpos ativos ≤ teto; só corpos parados são estacionados | PASS | PASS | PASS | PASS |
| 29 | T23 | Extração: núcleo do terreno vira corpo convexo (separate_floating_chunks) com massa = volume × densidade | PASS | PASS | PASS | PASS |
| 30 | T24 | Impulso de teste (T) arremessa a rocha para fora da cavidade e ela repousa no terreno | PASS | PASS | PASS | PASS |
| 31 | T25 | 10 ciclos meia torre caída → reset: torre idêntica (36 peças no lugar, congeladas), sem destroços, nós = baseline | PASS | PASS | PASS | PASS |
| 32 | T26 | Salvar/carregar: peças soltas sobrevivem ao save; slot com apoio escavado derruba a torre de novo; slot sem escavação não | PASS | PASS | PASS | PASS |
| 33 | T27 | Benchmark do colapso total (4 pés no mesmo quadro): quadro e física por 6 s; critério de FPS em janela | PASS | PASS | PASS | PASS |
| 34 | T38 | Estados de material: ignição, pedra só aquece, molhada resiste, água e vento apagam, queima consome, impacto solta | PASS | PASS | PASS | PASS |
| 35 | T28 | 1–4 escolhem o elemento; LMB chega ao poder; clique de recaptura não age; nada age no reset | PASS | PASS | PASS | PASS |
| 36 | T29 | Terra: rocha real extraída, suspensa só por forças e arremessada; acerta a caixa e a desloca | PASS | PASS | PASS | PASS |
| 37 | T30 | Terra × torre: rocha arremessada solta bloco(s) de pilar por impacto e o grafo derruba o bloco de cima | PASS | PASS | PASS | PASS |
| 38 | T31 | Água: jato empurra a caixa por força contínua e a molha; caixa atrás de terreno não é atingida | PASS | PASS | PASS | PASS |
| 39 | T32 | Fogo: rajada acende madeira, queima, carboniza e espalha; molhada resiste à 1ª; rocha só aquece | PASS | PASS | PASS | PASS |
| 40 | T33 | Água × Fogo: o jato apaga a caixa em chamas em ≤ 3 s (causa: água) e solta vapor | PASS | PASS | PASS | PASS |
| 41 | T34 | Ar: rajada lança a caixa, mal mexe a rocha, não passa terreno; apaga fogo fraco e aviva o forte | PASS | PASS | PASS | PASS |
| 42 | T35 | Fogo × torre: queimar os 2 pilares de madeira da frente derruba as placas de cima pelo grafo; reset remonta | PASS | PASS | PASS | PASS |
| 43 | T36 | Sequência transversal (Terra → Fogo → Água → Ar diante da torre, ~20 s) e reset devolve tudo ao início | PASS | PASS | PASS | PASS |
| 44 | T37 | Benchmark: colapso total + 12 caixas em chamas + os 4 poderes; critério de FPS em janela | PASS | PASS | PASS | PASS |
| 45 | T39 | Terra em fases: antecipação (chão intacto) → desprendimento (rocha congelada, cavidade aberta) → levantamento → pronta em ≤ 400 ms | PASS | PASS | PASS | PASS |
| 46 | T40 | Toque curto: soltar na antecipação guarda o arremesso, que sai ao ficar pronta na direção da mira do instante; recuperação bloqueia novo clique | PASS | PASS | PASS | PASS |
| 47 | T41 | Alvo inválido (céu, longe, perto, sobre o jogador): nenhuma extração, nenhuma edição, evento 'invalid' com motivo | PASS | PASS | PASS | PASS |
| 48 | T42 | Peso no hold: giro de 90° faz a rocha atrasar e assentar sem oscilar; balanço vertical; jogador mais lento só enquanto carrega | PASS | PASS | PASS | PASS |
| 49 | T43 | Impacto no chão a ≥ 12 m/s abre cratera real pela fila (uma por arremesso); arremesso lento não abre | PASS | PASS | PASS | PASS |
| 50 | T44 | Tuning em uso: antecipação de 140 ms e velocidade 0,5 no hold mudam o que é medido | PASS | PASS | PASS | PASS |
| 51 | T45 | Capturas da Terra durante cada fase (janela); em headless só confere que as fases aconteceram | PASS | PASS | PASS | PASS |


## Resumo por modo

| Modo | Resultado | Duração (s) | Erros do motor | Avisos |
|---|---|---|---|---|
| Editor headless | PASS 51/51 | 272.8 | 0 | 0 |
| Editor janela | PASS 51/51 | 319.3 | 0 | 0 |
| .exe headless | PASS 51/51 | 276.9 | 0 | 0 |
| .exe janela | PASS 51/51 | 284.6 | 0 | 0 |


## Desempenho

| Métrica | Editor headless | Editor janela | .exe headless | .exe janela |
|---|---|---|---|---|
| T37 4 poderes + colapso: intervalo entre quadros p50 / p95 / p99 / máx. (ms) | 7,3 / 16,6 / 19,0 / 34,8 | 16,6 / 19,2 / 21,8 / 36,4 | 6,0 / 16,9 / 19,6 / 28,3 | 16,7 / 17,9 / 19,2 / 31,0 |
| T37 TIME_PHYSICS_PROCESS méd. / máx. (ms) | 8,2 / 23,2 | 6,4 / 21,7 | 8,9 / 27,0 | 4,6 / 16,0 |
| T27 colapso total: intervalo entre quadros p50 / p95 / p99 / máx. (ms) | 6,9 / 16,0 / 17,4 / 57,2 | 16,6 / 17,8 / 18,4 / 19,6 | 7,3 / 16,3 / 17,3 / 31,5 | 16,7 / 17,6 / 18,1 / 18,9 |
| T15 100 edições: intervalo entre quadros p50 / p95 / p99 / máx. (ms) | 6,9 / 8,7 / 9,6 / 11,2 | 16,6 / 18,4 / 18,8 / 19,3 | 7,6 / 16,5 / 17,7 / 18,9 | 16,6 / 18,1 / 18,5 / 19,1 |
| FPS no roteiro (méd. / p95) | — | 58,6 / 60 | — | 59,8 / 60 |
| T39 clique → rocha pronta (ms) | 369 | 366 | 361 | 367 |
