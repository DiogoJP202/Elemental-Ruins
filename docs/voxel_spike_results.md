# Resultados do spike voxel — P0

**Data:** 22/10/2026 · **Responsável pela execução:** Claude Code (sessão automatizada nesta máquina).
Todos os números abaixo vêm de execuções reais nesta máquina. Os logs e JSON estão em `docs/evidence/` e as capturas em
`docs/evidence/screens/`. Nada aqui é estimativa, a menos que esteja marcado como tal.

## 1. Ambiente

| Item | Valor (medido) |
|---|---|
| SO | Windows 11 Pro 10.0.26200 (build 26200), 64 bits |
| CPU | 11th Gen Intel Core i5-1135G7 @ 2.40 GHz, 4 núcleos / 8 threads |
| RAM | 15,7 GB |
| GPU | Intel Iris Xe Graphics, driver 32.0.101.7085; Vulkan 1.4.323 (Forward+) |
| Tela | 1920×1200 (janela do jogo 1600×900) |
| Git | 2.55.0.windows.3 |

## 2. Binários e dependências

| Item | Detalhe |
|---|---|
| Godot editor | `C:\Users\dsoares\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_win64(.exe/_console.exe)`; `--version` = `4.7.2.stable.official.ed1daf0bf`; hash completo `ed1daf0bf001b61586d9930840f2f1394092c079`; Authenticode **Valid** (Prehensile Tales B.V.); sha256 do `.exe` `AB1824F8…B22424` |
| Build mono na mesma pasta | `4.7.2.stable.mono.official.ed1daf0bf`, **não usada** |
| Voxel Tools | **GDExtension 1.7**, release `v1.7x` "Voxel Tools GDExtension 1.7 for Godot 4.5+"; `GodotVoxelExtension.zip`, 54 457 774 bytes, sha256 `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8` (igual ao publicado no GitHub) |
| `voxel.gdextension` | `entry_symbol = "voxel_library_init"`, `compatibility_minimum = "4.4.1"` |
| DLL editor/debug | `libvoxel.windows.editor.x86_64.dll`, sha256 `e7191869…fe07ad` |
| DLL release | `libvoxel.windows.template_release.x86_64.dll`, sha256 `cff4fdef…115bf0` |
| Templates de export | `Godot_v4.7.2-stable_export_templates.tpz`, 1 281 349 702 bytes, sha256 `f298490b…248011` (igual ao publicado); instalados em `%APPDATA%\Godot\export_templates\4.7.2.stable\` (`version.txt` = `4.7.2.stable`) |
| Física | `physics/3d/physics_engine = "Jolt Physics"` (Jolt integrado; nenhum addon legado) |
| Variante | **GDExtension** na Godot oficial. A build custom (plano B) não foi necessária |

A API foi conferida duas vezes: na documentação oficial (readthedocs, latest/1.7) e no **binário instalado**
(`tools/probe_voxel_api.gd` → `docs/evidence/voxel_api_probe.txt`, 382 linhas). Métodos usados e confirmados:
`VoxelNode.get_voxel_tool`, `VoxelTool.{mode, channel, do_sphere, do_path, is_area_editable, get_voxel_f, raycast}`,
`VoxelLodTerrain.{is_area_meshed, voxel_bounds, generate_collisions, collision_layer, collision_lod_count,
collision_update_delay, lod_count, lod_distance, view_distance, mesh_block_size, debug_get_mesh_block_info,
voxel_to_mesh_block_position, get_statistics}`, `VoxelGeneratorGraph.{get_main_function, compile}`,
`VoxelGraphFunction.{create_node, add_connection, get_node_input_index, set_node_default_input_by_name,
set_node_param_by_name}`. Enums reais: `MODE_ADD=0`, `MODE_REMOVE=1`, `CHANNEL_SDF=1`.

## 3. Comandos executados (todos com saída salva)

`$G = C:\Users\dsoares\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_win64_console.exe`

| # | Comando | Log | Resultado |
|---|---|---|---|
| 1 | `$G --headless --path . --import` | `01_import.log` | exit 0 (com `.godot/` já existente; ver bug B1) |
| 2 | `$G --headless --path . --script res://tools/check_env.gd` | `02_check_env.log` | exit 0; 11/11 classes Voxel OK; extensão carregada; Jolt; Forward+ |
| 3 | `$G --headless --path . --script res://tools/probe_voxel_api.gd` | `03_probe_run.log`, `voxel_api_probe.txt` | exit 0 |
| 4 | `$G --headless --path . res://scenes/main.tscn -- --p0-selftest` | `05_selftest_headless.log`, `p0_selftest_headless.json` | **12/12 PASS**, 0 erros/avisos do motor, 36,9 s |
| 5 | `$G --path . res://scenes/main.tscn -- --p0-selftest --p0-screenshots` (janela) | `06_selftest_window.log`, `p0_selftest_window.json`, `screens/*.png` | **12/12 PASS**, 0 erros/avisos, 49,6 s |
| 6 | `$G --headless --path . --export-release "Windows Desktop" build/elemental_ruins.exe` | `07_export_release.log` | exit 0; `.exe` (= template oficial, sha256 `d34d36f3…4b0562`), `.pck` 190 KB (`docs/` fora da importação via `.gdignore`; antes eram ~3 MB porque as capturas de evidência entravam no pacote), DLL release copiada |
| 7 | `build/elemental_ruins.exe --headless -- --p0-selftest --report=…` | `08_export_selftest_headless.log`, `p0_selftest_export_headless.json` | **12/12 PASS**, 0 erros/avisos, 36,0 s |
| 8 | `build/elemental_ruins.exe -- --p0-selftest --report=…` (janela) | `09_export_selftest_window.log`, `p0_selftest_export_window.json` | **12/12 PASS**, 0 erros/avisos, 40,3 s |
| 9 | `$G --headless --editor --path . res://scenes/main.tscn --quit-after 900` | `10_editor_open_main.log` | exit 0; o editor abre a cena principal sem erros |
| 10 | Sessão interativa no `.exe` (seção 6) | `11_…antes_da_correcao.log`, `12_…depois_da_correcao.log` | ver seção 6 |

Os passos 1–7 são reproduzíveis com `tools/run_p0_tests.ps1 -Window -Export` (todos com exit 0 na rodada final, às 18:08–18:10).

## 4. Selftest automatizado (cena real, física real)

O roteiro (`scripts/dev/p0_selftest.gd`) roda dentro de `scenes/main.tscn`, com o mesmo `TerrainService`, o mesmo
`PlayerController` (`CharacterBody3D.move_and_slide`) e o Jolt. "Colisão" é sempre verificada por **raycast físico**
ou por **movimento do corpo**, nunca só pelos dados. Um `Logger` (API da Godot 4.7) conta todos os erros e avisos do motor.

| ID | O que prova | Resultado (headless, editor) |
|---|---|---|
| T1 | terreno pronto (`is_area_meshed` + raycast), jogador cai do spawn e para no chão | PASS, y = 0,020 estável |
| T0 | dados SDF coerentes: dentro da colina −7, acima +8; topo físico da colina y = 12,02 (esperado 12) | PASS |
| T1b | jogador teleportado acima do topo da colina fica sobre ela | PASS, y = 12,02 estável |
| T2 | `dig_sphere` r=3 no plano: os dados mudam no mesmo frame (SDF +1,04 onde era sólido) e o collider desce para y = −3,05; o jogador cai na cratera e fica no fundo (y = −3,04, `on_floor`) | PASS |
| T3a | `dig_path` em 2 trechos de 26 m (r=1,8, y=1,5) atravessando a colina: raio no eixo sem obstáculo; topo da colina **intacto** (12,02 antes e depois); **teto interno** y = 3,35; **piso interno** y = −0,35 | PASS |
| T3b | jogador anda por input simulado de z=19 até z=−37 (boca a boca) em 11,3 s; dentro do túnel y ∈ [−0,334; −0,328] (não subiu na colina); **360/360** amostras com teto sólido acima da cabeça | PASS |
| T4 | 3× `add_sphere` r=2 empilhadas: topo físico y = 6,50; caixa `RigidBody3D` solta de y=10 repousa em y = 7,0 com vel. 0; jogador fica no topo (y = 6,23, `on_floor`) | PASS |
| T5 | 20 ciclos escavar+adicionar no **mesmo ponto** (40 edições), aguardando a colisão a cada passo; nº de nós estável (34→34) | PASS |
| T5b | 100 escavações em sequência (grade 10×10, r=1,5) | PASS, 0 recusas, 0 timeouts |
| T6 | edição fora dos `voxel_bounds` → `outside_bounds`; dentro dos bounds mas fora do LOD0 carregado → `area_not_loaded`; raio 50 → `radius_out_of_range`; adicionar sobre o jogador → `overlaps_player`; todas < 20 ms, sem travar | PASS |
| T7 | reset: as 14 probes físicas (12 verticais + 2 horizontais no eixo do túnel) voltam **idênticas** ao baseline (tol. 5 cm); geração +1; caixas removidas; nº de nós = baseline (31) | PASS |
| T7b | 10 ciclos escavar → confirmar cratera na colisão → reset → probes = baseline | PASS, 10/10 |

### Medições (edição → collider observado pelo raycast físico)
A latência é medida do retorno da chamada de edição até o primeiro quadro de física em que o raycast enxerga a
geometria nova. A granularidade é de 1 tick (16,7 ms). Não é benchmark de GPU.

| Medida | Headless (editor) | Janela (editor) | Headless (.exe) | Janela (.exe) |
|---|---|---|---|---|
| Terreno inicial pronto | 338 ms | 1079 ms | 297 ms | 786 ms |
| Latência collider, 100 escavações (mín/méd/p95/máx) | 11,4 / 16,4 / 20,5 / 27,3 ms | 26,9 / 33,0 / 36,4 / 38,6 ms | 13,2 / 16,4 / 20,5 / 20,6 ms | 27,8 / 33,1 / 36,6 / 38,0 ms |
| Tempo da chamada `dig_sphere` (méd/p95/máx) | 0,14 / 0,23 / 0,41 ms | 0,11 / 0,17 / 0,29 ms | 0,13 / 0,23 / 0,35 ms | 0,11 / 0,15 / 0,28 ms |
| Latência collider, 40 edições T5 (méd/p95/máx) | 16,3 / 20,4 / 20,5 ms | 31,2 / 35,2 / 36,7 ms | 16,2 / 20,5 / 20,5 ms | 33,1 / 36,1 / 37,7 ms |
| Reset (10 ciclos, mín/méd/máx) | 348 / 424 / 480 ms | 466 / 518 / 622 ms | 305 / 342 / 384 ms | 445 / 461 / 484 ms |
| FPS durante o roteiro (amostras a cada 0,5 s; méd / p95) | — | 55,8 / 62 | — | 58,1 / 61 |

Observações sobre FPS: o **mínimo de 1 FPS** é a primeira amostra, tirada antes de o contador da Godot estabilizar
na inicialização. O roteiro inclui resets e teleportes, então isso **não** é medida de jogo contínuo. Memória não foi medida.
Em execuções anteriores do mesmo dia, o tempo de "terreno pronto" na primeira execução em janela chegou a 5,3 s
(compilação de shaders sem cache); nas seguintes, 0,4–1,1 s.

### Capturas (rodada em janela, `docs/evidence/screens/`)
`01_spawn_vista_colina` · `02_cratera` · `03_jogador_na_cratera` · `04_boca_do_tunel` · `05_dentro_do_tunel`
(paredes, teto e piso, com a saída visível) · `06_saida_olhando_para_tras` (luz da boca oposta através da
colina) · `07_coluna_com_caixa` · `08_pos_reset_colina` · `09_pos_reset_tunel_fechado`. Revisei visualmente as
imagens das rodadas anteriores e da final; o conteúdo bate com o que os testes medem.

## 5. Bugs encontrados, diagnóstico e estado

### B1 — Segfault intermitente na **primeira** importação com cache vazio (aberto, mitigado)
- **Reprodução:** cópia limpa do projeto sem `.godot/` → `$G --headless --path <cópia> --import` → exit 139
  (Segmentation fault) ao final, depois de concluir a importação. Foi a primeira coisa que aconteceu nesta sessão.
- **Frequência medida (cópias descartáveis no scratchpad):**

  | Condição | Crashes |
  |---|---|
  | cache vazio (clone limpo), com e sem cena principal | **10 de 17** (log da última série: `14_b1_reproducao.log`) |
  | cache vazio, mas com `.godot/extension_list.cfg` pré-criado apontando para `voxel.gdextension` (9 manuais + 2 via `run_p0_tests.ps1`) | **0 de 11** |
  | cache vazio, projeto **sem** `addons/zylann.voxel` | 0 de 2 |
  | segunda importação (cache já existe) | 0 em todas as tentativas; o projeto roda (selftest PASS) |

- **Conclusão provável:** o crash ocorre quando a GDExtension é descoberta e carregada **no meio** da primeira
  varredura, e não quando é carregada na inicialização. É compatível com a limitação "falha no primeiro carregamento,
  reinicie o editor" listada em godot_voxel#442. Não depurei a pilha nativa (não há símbolos na build oficial).
- **Mitigação:** `tools/run_p0_tests.ps1` pré-cria `.godot/extension_list.cfg` antes de importar. No editor com
  interface, se a primeira abertura fechar, basta reabrir. Não afeta o jogo rodando nem o export.
- **Não testado:** se o mesmo crash ocorre na primeira abertura do **editor com interface** (só reproduzi com `--import`).

### B2 — Película sólida após adicionar e remover a mesma esfera (corrigido)
- **Sintoma:** T5 falhava a partir do 2º ciclo. Após `add_sphere` e depois `dig_sphere` no mesmo centro e raio,
  o raycast físico continuava batendo em y = 2,02 por mais de 5 s.
- **Diagnóstico (com dados):** não era collider desatualizado. `debug_get_mesh_block_info` mostrava o bloco
  LOD0 `MESH_UP_TO_DATE`, e o mesmo ocorria com GodotPhysics3D (logo, não é Jolt). Amostrando o SDF da coluna:
  y=1 → 0,99; **y=2 → 0,00**; y=3 → 0,99. A remoção `max(atual, −esfera)` dava exatamente 0 na fronteira
  coincidente, e o Transvoxel transformava esse zero numa película de espessura zero, com colisão real.
- **Correção:** `TerrainService.remove_radius_padding = 0.05` (raio de remoção +5 cm). Depois disso a coluna fica
  y=2 → 0,05 (ar) e T5 passa (20/20 ciclos).

### B3 — Toque rápido em G/H podia se perder (corrigido)
- **Sintoma (teste interativo):** um toque instantâneo em G não gerou edição (HUD com revisão 0), enquanto segurar G por 0,3 s funcionou.
- **Causa:** a edição só era disparada se `Input.is_action_pressed` fosse verdadeiro no quadro de física; tecla
  descendo e subindo no mesmo quadro passava despercebida.
- **Correção:** a primeira edição sai do evento em `_unhandled_input`; a repetição segurando continua no
  `_physics_process`. Confirmado: depois de reexportar, o mesmo toque rápido gerou `dig_sphere OK rev=1`.

### Outros erros corrigidos durante o desenvolvimento
- 4 erros de parser de inferência de tipo (`:=` com valores de `Dictionary`) no selftest, pegos pelo
  `--check-only` e corrigidos antes da primeira rodada válida.
- Nomes de captura duplicados e sobreposição de texto no HUD, corrigidos.
- O script de testes no Windows PowerShell 5.1 gerava logs em UTF-16 e não aguardava o `.exe` (subsistema
  GUI). Passou a usar `System.Diagnostics.Process`.

## 6. Teste interativo (teclado e mouse sintéticos)

Executado por Claude via computer use no `build/elemental_ruins.exe` em janela, lendo o HUD após cada ação.
É input real do Windows (SendInput), não input simulado no código. **Não substitui** a avaliação de sensação por
uma pessoa.

| Ação | Observado no HUD/tela | Status |
|---|---|---|
| W por 2 s | z 28,0 → 17,9 (~5 m/s = `walk_speed`), na direção da câmera | OK |
| Espaço | após 0,25 s: y = 1,9, "no chão: não"; após 1,75 s: y = 0, no chão | OK |
| Shift+W por 1 s | ~9 m percorridos (= `sprint_speed`) | OK |
| S / A / D por 1 s | ~5 m cada; A/D perpendiculares à frente | OK |
| Mouse | yaw e pitch mudam com o movimento | OK qualitativo; sensibilidade **não avaliada** (o mouse sintético chega como coordenada absoluta em modo capturado e o ganho fica imprevisível) |
| G segurado 0,3 s | 2 escavações (repetição de 0,15 s), cratera visível | OK |
| G toque rápido | antes: nada (bug B3); depois da correção: `dig_sphere OK rev=1` | OK após a correção |
| H | 1ª adição OK; 2ª **recusada** `overlaps_player` (proteção funcionando) | OK |
| J | `dig_path OK pontos=6 comp=10.0m` (vala na direção da câmera) | OK |
| Z | "Mundo restaurado do gerador (geração 2) em 453 ms", jogador no spawn, edições sumiram | OK |
| Túnel aberto **interativamente** na encosta e atravessado a pé | não feito: não consegui orientar a câmera com precisão pelo mouse sintético | **NÃO TESTADO** (coberto pelo T3b automatizado) |

## 7. O que ainda depende de validação manual (pessoa, Windows)
1. Sensação de câmera e mouse (sensibilidade, limites de pitch, SpringArm aproximando nas paredes do túnel).
2. Abrir **J** na encosta da colina com a mira, entrar e sair do túnel pelo controle manual (roteiro no README).
3. Abrir o projeto no **editor com interface gráfica** e conferir o painel Output sem erros. No modo headless do editor, a cena abriu sem erros.
4. Primeira abertura num clone limpo (B1): confirmar o contorno.

## 8. Riscos e limites conhecidos
- GDExtension do Voxel Tools é "pouco testada" segundo o próprio release; B1 é um sintoma. A build custom continua como plano B.
- Sem persistência (VoxelStreamSQLite): edições vivem em memória até o reset ou o fim da execução. Previsto para P1.
- Edições só no LOD0 carregado (raio ~48 m do viewer). Fora disso o serviço recusa com `area_not_loaded`, de propósito.
- Material de laboratório não é a arte final. Bordas dos `voxel_bounds` aparecem como linhas no horizonte.
- Latência de collider medida só neste laboratório pequeno e com raios ≤ 3 m. Edições grandes não foram medidas.

## 9. Gate geral P0
**Os critérios funcionais PASSARAM:** terreno volumétrico, colisão, cratera, túnel sob teto sólido atravessado,
coluna, edição repetida, reset real, export e controles com input sintético.
**Há uma falha conhecida e mitigada:** a primeira importação de um clone limpo fecha a Godot em ~metade das vezes
(B1). Por isso o critério "sem erros fatais de importação" está como FALHOU no `P0_CHECKLIST.md`, apesar de
o parser estar limpo e a mitigação ter funcionado 11/11.
**Ainda depende de pessoa:** a sensação de mouse e câmera e o túnel aberto à mão com J.

## 10. Atualização (22/10/2026, ~18:30) — validação manual e bug B4

**Validação manual pelo usuário:** seguiu o roteiro do README no editor (túnel com J na encosta e travessia a pé,
cratera, coluna, reset, câmera e mouse) e relatou que tudo funcionou bem. Isso cobre os itens da §7.1 e §7.2.

### B4 — Import em crash quando outra Godot está aberta no mesmo projeto (mitigado)
- **Ocorrência real:** o usuário rodou `run_p0_tests.ps1` com o editor aberto. O passo `import` saiu com
  `-1073741819` (0xC0000005); o Visualizador de Eventos registrou a falha às 18:27:07. O log (preservado em
  `run_usuario_2026-10-22_1827/01_import.log`) mostra `Failed to open …/bin/~libvoxel.windows.editor.x86_64.dll`
  → `Can't open GDExtension dynamic library`. Os demais passos dessa execução saíram com 0.
- **Causa:** o editor da Godot carrega uma cópia `~libvoxel…dll`. Com outra instância segurando essa cópia, a nova
  não consegue recriá-la, a extensão não carrega e o processo cai no encerramento.
- **Reprodução controlada:** editor headless em segundo plano + `--import` → mesmos erros e segfault (1 de 2;
  `15_b4_import_concorrente_reproducao.log`). Sozinho: exit 0, sem erros.
- **Mitigação:** `run_p0_tests.ps1` testa se a cópia está travada e aborta com exit 2 e mensagem clara, sem tocar
  nas evidências (testado). Script salvo em UTF-8 com BOM (acentos corretos no Windows PowerShell 5.1).
  `addons/zylann.voxel/bin/~*` ignorado no Git.
- **Nota:** o editor regravou `project.godot` e removeu duas chaves iguais ao padrão (`physics_ticks_per_second=60`,
  `rendering_method="forward_plus"`). Inofensivo; mantido.
