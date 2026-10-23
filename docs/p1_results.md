# Resultados do P1 — ferramentas, materiais e persistência

**Data:** 23/10/2026 · **Execução:** Claude Code (sessão automatizada nesta máquina).
Mesma máquina do P0 (Windows 11 Pro 10.0.26200, i5-1135G7 4C/8T, 15,7 GB, Intel Iris Xe, Vulkan 1.4.323) e o mesmo
binário: `godot.windows.editor.x86_64.exe` **4.7.2.stable.custom_build.ed1daf0bf** com **Voxel Tools 1.7 como módulo**
(D13). Todos os números vêm de execuções reais; logs e JSON em `docs/evidence/p1/`, capturas em
`docs/evidence/p1/screens/`. Nada aqui é estimativa, salvo quando marcado.

**Rodada de referência:** `tools/run_p1_tests.ps1 -Window -Export` no commit `c489be7`, 11:12–11:18, começando com
`.godot/` apagado. **14 de 14 passos com exit 0.** Os JSON e logs em `docs/evidence/p1/` são dessa rodada.

## 1. Gate do P1 (`PROJETO_ROADMAP.md`)

| Status | Critério do roadmap | Prova |
|---|---|---|
| PASSOU | **100 alterações observadas** | T15: 100 escavações pela fila a 20/s, as 100 vistas no collider por raycast, nos 4 modos. Também T5b (100 diretas, regressão P0) e T8–T13 (traços, tubos, suavização, rampa) |
| PASSOU | **10 resets observados** | T16: 10 ciclos editar pela fila → reset com stream SQLite: 14 probes físicas = baseline, nós 32 → 32, 1 arquivo de sessão por ciclo, memória estável. Também T7b (regressão P0) |
| PASSOU | **Persistência recupera estados idênticos sem duplicar geometria** | T14 (mesmo processo): salvar → reset (volta ao baseline) → carregar 2×: **0 diferenças** em 14 probes físicas, 108 amostras de SDF e 108 de material, nós 32 em todas as etapas, topo da coluna 6,50 → 6,50. T14x (processos separados): o processo novo carrega o slot e reproduz o estado salvo com 0 diferenças. Nos 4 modos (editor/`.exe`, headless/janela) |
| PASSOU | **Limitações documentadas** | §8 |

**Gate P1: PASSOU**, com as limitações da §8. O B1 do P0 (crash raro no encerramento do `--import`, risco aceito em
D14) continua existindo; nesta rodada a importação limpa passou na 1ª tentativa.

## 2. Escopo pedido para o P1

| Status | Item | Onde / prova |
|---|---|---|
| Implementado e testado | `TerrainBrushQueue`: traço contínuo por intervalo temporal e espacial, AABB limitada | `scripts/world/terrain_brush_queue.gd`; T8, T8b, T9 |
| Implementado e testado | Brushes REMOVE / ADD / PATH / SMOOTH | `TerrainService.dig_sphere`, `add_sphere`, `dig_path`/`add_path`, `smooth_area`; T8–T13 |
| Implementado e testado | Materiais `soil`/`stone`/`sand` com `hardness`, `density`, `bendable`, `surface_color`, sem confundir textura com física | Índice no canal `INDICES` (D15); T11, spike S1–S5 |
| Implementado e testado | Evento `TerrainChanged {aabb, revision}` | Sinal `TerrainService.terrain_changed`; T12 |
| Implementado e testado | Persistência com `VoxelStreamSQLite`, salvar e recarregar sem duplicar | D18; T14, T14x, spike S6/S7 |
| Implementado e testado | Overlay: FPS/tempo de quadro, edições pendentes, último brush, corpos ativos, resultados de reset | `scripts/ui/debug_hud.gd`; T17, captura 16 |
| Implementado e testado | Benchmarks de 100 escavações e 10 resets com latência medida | T15, T16 (§5) |
| Implementado e testado | API nova conferida no binário | `tools/probe_voxel_api.gd` (dump) + `tools/spike_p1_api.gd` (8 checagens empíricas) |
| Implementado e testado | Selftest P0 12/12 preservado e estendido | `--p0-selftest` 12/12; `--p1-selftest` 23/23 |
| Implementado, **não testado por pessoa** | Controles G/H/N (segurar), J, K, M, F5, F9 | Só por input simulado (T8b usa `Input.action_press`). Roteiro manual no README |

## 3. Comandos executados (rodada de referência)

`tools/run_p1_tests.ps1 -Window -Export`; logs em `docs/evidence/p1/`.

| # | Passo | Log / relatório | Resultado |
|---|---|---|---|
| 1 | `--import` (cache vazio) | `01_import.log` | exit 0, 1ª tentativa |
| 2 | `check_env.gd` | `02_check_env.log` | exit 0; `Voxel Tools: módulo embutido`, `GDExtensions carregadas: []` |
| 3 | `probe_voxel_api.gd` | `03_probe_run.log`, `../voxel_api_probe.txt` | exit 0 |
| 4 | `spike_p1_api.gd` | `04_spike_api.log`, `00_spike_api.txt` | exit 0, 8/8 OK |
| 5 | selftest P0 sozinho (editor, headless) | `05_p0_regressao_headless.log`, `p0_regressao_headless.json` | **12/12**, 0 erros/avisos do motor |
| 6 | selftest P1 (editor, headless) | `06_…`, `p1_selftest_headless.json` | **23/23**, 0/0 |
| 7–8 | persistência entre processos (editor) | `07_persist_write.log`, `08_persist_read.log` | 2/2 e 2/2, 0/0 |
| 9 | selftest P1 (editor, janela, capturas) | `09_…`, `p1_selftest_window.json`, `screens/` | **23/23**, 0/0 |
| 10 | export release | `10_export_release.log` | exit 0 |
| 11 | selftest P1 no `.exe` (headless) | `11_…`, `p1_selftest_export_headless.json` | **23/23**, 0/0 |
| 12–13 | persistência entre processos no `.exe` | `12_…`, `13_…` | 2/2 e 2/2, 0/0 |
| 14 | selftest P1 no `.exe` (janela) | `14_…`, `p1_selftest_export_window.json` | **23/23**, 0/0 |

Os 23 testes do P1 = 12 do P0 + T8, T8b, T9, T10, T11, T12, T13, T14, T15, T16, T17. Cada fase de persistência
conta T1 + a fase (2 testes).

## 4. Testes do P1 (resultado igual nos 4 modos, salvo onde indicado)

| ID | O que prova | Observado (editor headless) |
|---|---|---|
| T8 | traço contínuo simulado (120 amostras de mira em 2 s, 10 m/s) | 13 carimbos (limite 16), 12 viraram tubo por salto, máx. 1 op/quadro; vala contínua no collider em 41 pontos |
| T8b | G segurado 1 s por `Input.action_press` → controlador → fila | 7 carimbos aplicados; chão sob a mira 0,02 → −1,69 |
| T9 | PATH de 26 m dividido; rajada de 20 carimbos num quadro | 3 trechos, maior AABB 14,1 m (limite 14 + folgas internas de 0,05 m); rajada fundida em **1** operação (19 fundidos); vala contínua nos dois casos |
| T10 | SMOOTH | inclinação máxima do perfil 1,93 → 0,40; topo 3,02 → 0,81 m; a 3 m do centro 0,02 → 0,07 m (base alargou) |
| T11 | materiais | layout do gerador = dados em 7 pontos; ADD de areia lido como areia, 3 m fora continua solo; massa = volume × 1600 (22 619 kg); mesmo traço: **areia 18, solo 10, pedra 4 carimbos**; `bendable=false` → `material_not_bendable` (política isolada) |
| T12 | `TerrainChanged` | 8 eventos para 8 edições aplicadas, 0 para 2 recusas, revisões consecutivas, AABB do evento contém o brush, dados já mudados no evento, **collider ainda velho no evento em 8/8** |
| T13 | rampa (PATH aditivo de areia) a pé | jogador sobe até y = 2,88 (topo medido 2,91; esperado 3,1), material no meio = areia |
| T14 | persistência no mesmo processo | ver §1; inclui **save abortado** (prazo zerado): não cria slot e não libera o terreno; o save seguinte, imediato, **esperou** as gravações em voo do abortado e o slot saiu completo |
| T14x | persistência entre processos | write: salva e grava `p1_persist_expected.json`; read (processo novo): 0 diferenças, e o mundo novo diferia do salvo em 5 probes antes de carregar |
| T15 | 100 alterações pela fila | §5 |
| T16 | 10 resets com stream | §5 |
| T17 | overlay | as 12 seções esperadas presentes; reset mostrado com duração e "ok" |

## 5. Medições

Latência = do retorno da chamada (ou do enfileiramento) até o primeiro quadro de física em que o raycast enxerga a
geometria nova. Granularidade de 1 tick (16,7 ms). Não é benchmark de GPU.

| Medida | Editor headless | Editor janela | `.exe` headless | `.exe` janela |
|---|---|---|---|---|
| T15 espera na fila (méd / p95 / máx, ms) | 0,64 / 0,97 / 3,09 | 0,45 / 0,68 / 1,04 | 0,49 / 0,83 / 1,37 | 0,39 / 0,61 / 0,70 |
| T15 aplicar → collider (méd / p95 / máx, ms) | 15,6 / 20,4 / 23,3 | 31,5 / 33,4 / 34,5 | 16,0 / 20,4 / 20,5 | 31,4 / 33,6 / 34,3 |
| T15 enfileirar → collider (méd / p95 / máx, ms) | 16,3 / 20,7 / 23,8 | 32,0 / 33,8 / 34,9 | 16,5 / 20,7 / 20,8 | 31,8 / 33,9 / 34,6 |
| T15 chamada nativa (méd / p95 / máx, ms) | 0,12 / 0,28 / 1,57 | 0,09 / 0,27 / 0,69 | 0,10 / 0,26 / 0,87 | 0,07 / 0,18 / 0,43 |
| T15 intervalo entre quadros durante as 100 edições (p50 / p95 / p99 / máx, ms) | sem render: não representa | **16,6 / 18,0 / 18,8 / 19,5** | sem render | **16,6 / 17,9 / 18,4 / 18,5** |
| FPS no roteiro inteiro (méd / p95; amostra a cada 0,5 s) | — | 57,8 / 60 | — | 59,1 / 60 |
| T16 reset com stream, 10 ciclos (mín / méd / máx, ms) | 285 / 350 / 436 | 366 / 411 / 449 | 246 / 277 / 324 | 366 / 426 / 449 |
| T7b reset (regressão, mín / méd / máx, ms) | 255 / 288 / 379 | 366 / 455 / 500 | 246 / 291 / 385 | 367 / 410 / 450 |
| T14 salvar / carregar (ms) | 257 / 258 | 430 / 432 | 247 / 243 | 379 / 450 |
| Tamanho do slot (cenário do T14) | 147 456 B | 147 456 B | 147 456 B | 147 456 B |
| T5b collider, 100 diretas (regressão, méd / p95, ms) | 16,3 / 20,5 | 30,6 / 34,1 | 16,4 / 20,6 | 30,8 / 33,6 |
| Terreno inicial pronto (ms) | 348 | 893 | 288 | 609 |

**Memória** (`Performance.MEMORY_STATIC` e `VoxelEngine.get_stats().memory_pools`):

| Medida | Editor headless | Editor janela |
|---|---|---|
| T15, antes → depois das 100 edições | estática 95,17 → 95,84 MB; voxel usado 0 → 0,29 MB (46 blocos) | 118,97 → 119,38 MB; voxel usado 0 → 0,29 MB |
| T16, antes → depois dos 10 resets | estática 93,42 → 93,45 MB; voxel total 11,76 → 11,76 MB | 115,88 → 115,94 MB; voxel total 13,40 → 13,40 MB |

No `.exe` (template **release**), `MEMORY_STATIC` devolve **0**: o contador só existe em build debug. Os números do
`VoxelEngine` aparecem nos dois (voxel total 9,68 MB headless e 13,39 MB janela, iguais antes e depois dos 10 resets).

**Stream com e sem key cache** (T7b headless, mesma bateria P0): sem stream (fim do P0) ~217–248 ms de média;
com stream SQLite sem `key_cache_enabled` **581 ms**; com key cache **~260–290 ms**. Ver D18.

Leitura honesta: em janela, o intervalo entre quadros ficou em ~16,6 ms (p99 ≤ 18,8 ms) durante 100 escavações a
20/s **nesta cena de laboratório**, com vsync. Isso não garante 60 FPS em cenas maiores, com mais corpos ou com raios
maiores (o maior raio cronometrado aqui é 3 m; o T15 usa 1,5 m).

## 6. Spike da API (`tools/spike_p1_api.gd`, `docs/evidence/p1/00_spike_api.txt`)

Terrenos próprios, sem a cena do jogo, para provar o comportamento antes de escrever gameplay:

| ID | Resultado |
|---|---|
| S1 | grafo com `OutputSingleTexture` compila; terreno com índices de 8 bits fica pronto |
| S2 | o gerador escreve `INDICES`; `Select` devolve `a` quando `t < limiar` (ordem confirmada) |
| S3 | `MODE_SET` + `CHANNEL_INDICES` + `value` + `do_sphere` pinta só a esfera; o SDF não muda (a variação de 0,0081 aparece igual num ponto de controle fora da esfera: é a quantização de 16 bits ao materializar o bloco) |
| S4 / S4b | `do_path` em `MODE_ADD` cria matéria; em `MODE_SET` pinta `INDICES` ao longo do tubo |
| S5 | `smooth_sphere` muda o SDF e não o material |
| S6 | SQLite: editar → `save_modified_blocks` → tracker completo (8 tarefas, 12 ms) → liberar → fechar → copiar → reabrir a cópia: SDF e índices idênticos em 126 amostras |
| S7 | arquivo novo devolve o estado do gerador |
| I1 | liberar o terreno **sem** `save_modified_blocks` **não** grava as edições |
| I2 / I3 | apagar o arquivo com o stream aberto falha (Windows); depois de fechar (`database_path = ""`), funciona |

## 7. Bugs e achados durante o P1

- **B5 — corrida no T3a do P0 (corrigido no teste).** Na 1ª bateria completa do P1, o T3a falhou 2 vezes
  (regressão P0 headless e `.exe` em janela) com `teto_interno_y = null`, enquanto o T3b, logo depois, atravessou o
  túnel com teto em todas as amostras. Causa: o predicado "eixo do túnel livre" podia ser satisfeito com blocos de
  collider ainda **velhos**: blocos de malha recebem o collider novo em quadros diferentes, e um raio que entra num bloco
  sólido antigo pela fronteira entre blocos não encontra face frontal (o Transvoxel não gera face na fronteira e
  `hit_back_faces = false`). O piso interno (bloco de baixo, já novo) aparecia e o teto (bloco de cima, ainda velho) não.
  Antes do P1 isso não tinha aparecido em nenhuma rodada; a hipótese (não verificada) é que o stream SQLite mudou o
  ritmo de atualização dos blocos.
  **Correção:** o T3a espera eixo livre **e** teto e piso internos visíveis ao mesmo tempo. Depois: 8/8 repetições
  isoladas e as duas baterias completas seguintes sem falha. O jogador nunca está dentro do túnel nesse intervalo, mas
  a lição vale para P2: **colliders de blocos vizinhos não mudam no mesmo quadro**.
- **B6 — perda de edições se o save estourasse o prazo (corrigido).** A 1ª versão de `save_world` liberava o terreno
  mesmo se `save_modified_blocks` não terminasse. Agora o save aborta sem liberar. Achado na revisão do código, depois
  testado no T14 com prazo zerado.
- **B7 — save logo após um save abortado podia sair incompleto (corrigido).** As gravações do save abortado continuam
  em segundo plano e os blocos deixam de contar como modificados; o save seguinte via "nada a gravar" e fecharia o stream
  com gravações em voo. Visto nos números do T14 (`blocks_tasks: 0`). Agora o próximo save espera o tracker anterior; na
  rodada de referência a espera foi exercitada nos 4 modos (`save_anterior_em_voo: esperado`).
- **Erro de parse travou um selftest.** `PackedStringArray.any()` não existe; com o `main.gd` sem compilar, a cena rodou
  sem script e o processo nunca saiu (o watchdog do selftest não chega a existir). Passei a conferir os scripts com
  `--check-only` e a rodar com `timeout`. **O runner ainda não tem timeout por passo** (§8).
- **Desempenho:** stream SQLite sem key cache dobrava o reset (581 ms). Resolvido com `set_key_cache_enabled(true)`.
- **Critérios de teste ajustados com dados:** T10 (3 suavizações achatavam a saliência inteira e a lateral também
  descia; passou a medir a inclinação do perfil) e T12 (posições x = 12,5… arredondavam para o voxel errado; passaram a
  ser inteiras). Nenhum dos dois era defeito do código do jogo.

## 8. Limitações e riscos conhecidos

- **Material do ADD:** a pintura cobre raio + 0,5 m; matéria que já existia nessa faixa troca de material. A cor nas
  bordas mistura até 4 materiais por célula (Transvoxel).
- **Dureza** só muda o ritmo do traço contínuo de REMOVE. Chamadas diretas ao `TerrainService` (J, K e testes) ignoram a
  dureza. Nenhum dos 3 materiais é não dobrável; a regra `bendable` só foi testada isolada.
- **Massa** é nominal (volume do brush × densidade), não o volume real de matéria alterada.
- **TerrainChanged chega antes do collider** (8/8 no T12). Quem precisa da colisão nova deve esperar o raycast.
  Colliders de blocos vizinhos atualizam em quadros diferentes (B5).
- **Salvar congela o mundo** ~0,25 s (headless) a ~0,45 s (janela), porque o terreno é recriado do disco.
- **Não persistem:** caixas de teste e qualquer objeto fora do terreno (o `WorldSave` de objetos é P2). Um único slot
  pelo teclado (`slot1`); a API aceita outros nomes.
- **Arquivos de sessão** de execuções anteriores só são apagados na próxima abertura do jogo.
- Persistência verificada com o jogador no spawn e probes a até ~50 m dele. Edições fora do LOD0 carregado continuam
  recusadas (`area_not_loaded`).
- `MEMORY_STATIC` não existe no template release (0 no `.exe`).
- **Runner sem timeout por passo:** se um script não compilar, o processo da Godot fica aberto e o runner espera para
  sempre.
- A captura `10_t8_vala_traco.png` não mostra a vala com clareza (ângulo de câmera); a vala está provada por raycast
  no T8. As demais capturas foram revisadas e batem com os testes.
- B1 (crash raro no fim do `--import`, D14) continua aceito.

## 9. Não testado

- **Teste manual por uma pessoa** dos controles do P1 (sensação do traço contínuo, F5/F9, M, K, N). Roteiro no README.
  Continua pendente também o roteiro manual do P0 no editor custom.
- Abrir o projeto no editor com interface depois das mudanças do P1 (só editor headless e jogo rodando foram testados).
- Copiar o arquivo de sessão com o stream aberto, que evitaria o congelamento do save.
- Raios grandes (6 m) e pincéis longos cronometrados; cenas com muitos corpos físicos.

## 10. Próximo passo recomendado

Rodar o roteiro manual do README (P0 e P1) no editor custom, com teclado e mouse reais, e registrar a sensação de
G/H/N contínuos e de F5/F9 antes de iniciar o P2.
