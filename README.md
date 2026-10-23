# ELEMENTAL // RUINS — protótipo técnico (P0 + P1)

Laboratório de **terreno volumétrico escavável** em Godot 4.7.2 + Voxel Tools 1.7 (SDF + Transvoxel).

**Status: gate P0 PASSOU em 23/10/2026, com ressalva aceita** (crash raro da Godot no fim do `--import`; ver `P0_CHECKLIST.md`).
**P1 (ferramentas, materiais e persistência):** resultado e gate em [`docs/p1_results.md`](docs/p1_results.md).

P0: personagem em terceira pessoa, colina voxel com colisão, escavar e adicionar matéria pela mira, túnel real sob
teto sólido e reset de verdade do mundo. P1: fila de brushes contínuos (REMOVE/ADD/PATH/SMOOTH), materiais
solo/areia/pedra com propriedades físicas gravadas nos voxels, evento `TerrainChanged`, salvar/carregar com
`VoxelStreamSQLite`, overlay de observabilidade e benchmarks. Não há poderes, arte final, menus ou água.

> Comece por [`INICIO_AQUI.md`](INICIO_AQUI.md) e [`CLAUDE.md`](CLAUDE.md) (requisitos). Resultados e provas estão em
> [`docs/voxel_spike_results.md`](docs/voxel_spike_results.md) (P0) e [`docs/p1_results.md`](docs/p1_results.md) (P1),
> decisões em [`docs/decisions.md`](docs/decisions.md) e o gate do P0 em [`P0_CHECKLIST.md`](P0_CHECKLIST.md).

## Versões usadas (verificadas nesta máquina)

| Item | Versão / origem |
|---|---|
| Editor Godot | **Godot 4.7.2.stable.custom_build.ed1daf0bf + Voxel Tools 1.7 como módulo** (release `v1.7` do Voxel Tools, `godot.windows.editor.x86_64.exe.zip`, sha256 `e2292adb…6f1956b`). Mesmo commit da Godot oficial 4.7.2; binário **não assinado** |
| Template de export | `godot.windows.template_release.x86_64.exe.zip` da mesma release (sha256 `86fe371e…2f0775`); só **release** no Windows |
| Física 3D | Jolt Physics integrado (`physics/3d/physics_engine="Jolt Physics"`) |
| Renderer | Forward+ (Vulkan 1.4.323 na Intel Iris Xe testada) |

> **Por que não a Godot oficial + GDExtension?** Funcionava, mas a primeira importação de um clone limpo derrubava a
> Godot em 10 de 17 tentativas, e qualquer import com outra Godot aberta no projeto também caía. Com o módulo, o
> resultado foi 1 em 50 e 0 em 3, respectivamente, com os mesmos testes 12/12. Detalhes em `docs/decisions.md` (D13).
> **A Godot oficial não abre este projeto corretamente:** ela não tem as classes Voxel. **Não reextraia a GDExtension
> (`addons/zylann.voxel/`) neste projeto:** módulo e GDExtension juntos registram as mesmas classes e conflitam.

## Requisitos e instalação

1. Windows 10/11 x64.
2. Baixe da release **v1.7** do Voxel Tools (<https://github.com/Zylann/godot_voxel/releases/tag/v1.7>):
   - `godot.windows.editor.x86_64.exe.zip` (editor)
   - `godot.windows.template_release.x86_64.exe.zip` (template de export)
3. Confira os SHA-256 acima e extraia os dois `.exe` numa pasta fora do projeto. Nesta máquina:
   `C:\Users\dsoares\Tools\Godot\4.7.2-voxel1.7\`.
4. Se usar outra pasta, ajuste `custom_template/release` em `export_presets.cfg` (caminho absoluto) e passe
   `-Godot <caminho do editor>` ao script de testes (ou defina `$env:GODOT`).
5. Como o binário não é assinado, o Windows SmartScreen pode avisar na primeira execução.

## Abrir e rodar no editor

1. Abra `godot.windows.editor.x86_64.exe` (o editor **custom**, não o `Godot_v4.7.2-stable_win64.exe` oficial).
2. No Gerenciador de Projetos, clique em **Importar**, escolha `project.godot` desta pasta e depois **Importar e editar**.
   O projeto já aparecia na lista do editor oficial; os dois editores compartilham essa lista, então confira
   qual executável está aberto.
3. Pressione **F5** (cena principal `res://scenes/main.tscn`).
   O terreno é **criado em código** ao rodar (`LabTerrainFactory`), por isso a colina não aparece na viewport do editor.

## Controles (provisórios, conforme CLAUDE.md; sem seleção 1–4)

| Tecla | Ação |
|---|---|
| WASD | andar, relativo à câmera |
| Shift | correr |
| Espaço | pular |
| Mouse | orbitar a câmera (Esc solta/prende o mouse; clique recaptura) |
| **G** (segurar) | escavar em traço contínuo: carimbos a cada 0,15 s × dureza do material (areia 2× mais rápido, pedra 3× mais lento), vala contínua ao varrer a mira |
| **H** (segurar) | adicionar matéria do material atual em traço contínuo (recusa se for prender o personagem) |
| **N** (segurar) | suavizar (SMOOTH) quinas e degraus no ponto mirado (raio até 4 m) |
| **J** | abrir túnel de 10 m na direção horizontal da câmera, na altura da mira |
| **K** | erguer rampa de 8 m que sobe 3 m na direção da câmera, com o material atual |
| **M** | trocar o material do H/K: solo → areia → pedra |
| **F5** | salvar as edições do terreno no slot `slot1` (o terreno é recarregado do disco; ~0,5 s congelado) |
| **F9** | carregar o slot `slot1` (jogador volta ao spawn; caixas somem) |
| **Z** | **reset do mundo**: recria o terreno do gerador, apaga todas as edições, devolve o jogador ao spawn e remove as caixas (o slot salvo fica intacto) |
| Roda do mouse ou `[` `]` | raio do pincel (0,5–6 m; padrão 2 m) |
| B | soltar uma caixa `RigidBody3D` de teste no ponto mirado (máx. 10) |

> F5 dentro do **jogo** salva; F5 no **editor** continua sendo "rodar o projeto". As caixas de teste não são salvas
> (persistência de objetos é P2). Os arquivos ficam em `%APPDATA%\Godot\app_userdata\ELEMENTAL -- RUINS\`
> (`world/` = sessões temporárias, `saves/` = slots).

O marcador esférico na mira fica **verde** quando a área é editável e **vermelho** quando não é. O overlay mostra
FPS e tempo de quadro (média e pico do último segundo), estado do terreno e da sessão, a fila de brushes (pendentes,
aplicadas, recusadas, fundidas, divididas), o último brush (AABB, material, massa estimada, tempo), o material sob a
mira com dureza/densidade, tarefas e memória do motor voxel, corpos físicos ativos e os resultados de reset/salvar/carregar.

### Roteiro manual sugerido (≈ 3 min)
1. Ande até a colina (W) e erga a câmera até a mira cair na encosta, a cerca de 1,5 m do chão.
2. Raio 2 m (padrão). Aperte **J**, ande para dentro do túnel e aperte J de novo lá dentro para continuar até sair do outro lado. Confira que há teto sobre a cabeça e que você não atravessa o chão.
3. Fora da colina, segure **G** sobre o chão para abrir uma cratera e pule dentro dela.
4. Mire no chão a uns 4–5 m e segure **H** para formar uma coluna; suba nela (pulo) ou solte uma caixa com **B**.
5. Repita G/H no mesmo ponto várias vezes.
6. Aperte **Z**: cratera, túnel e coluna devem sumir, e o jogador volta ao spawn.

### Roteiro manual do P1 (≈ 4 min)
1. Segure **G** e varra a mira pelo chão: deve sair uma vala contínua. Faça o mesmo na faixa de areia (leste, clara)
   e no fundo de uma cratera funda (pedra, verde, abaixo de y = −6): a areia cava mais rápido e a pedra mais devagar.
   O overlay mostra o material sob a mira.
2. Aperte **M** até "areia" e segure **H**: a matéria nova aparece na cor da areia. Aperte **K** para uma rampa e suba nela.
3. Segure **N** numa quina (borda de cratera ou coluna): ela arredonda.
4. Aperte **F5** (salvar), depois **Z** (reset: tudo some) e **F9** (carregar): as edições voltam iguais.
5. Feche o jogo, abra de novo e aperte **F9**: as edições do último F5 voltam.

## Testes automatizados

### P1 (inclui a regressão do P0)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p1_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p1/`: import (com repetição se a Godot cair no encerramento, B1), `check_env`, dump da API,
spike da API P1 (`tools/spike_p1_api.gd`), selftest P0 sozinho (12 testes), selftest P1 (P0 + T8–T17) e a
persistência entre processos (`--p1-persist=write` num processo, `--p1-persist=read` noutro). `-Window` roda o
selftest P1 em janela com capturas em `docs/evidence/p1/screens/` (só aí FPS e tempo de quadro valem algo);
`-Export` exporta e repete selftest P1 e persistência no `.exe`. Feche o editor deste projeto antes de rodar.

Direto, num terminal bash:

```bash
"C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe" --headless --path . res://scenes/main.tscn -- --p1-selftest
```

Opções depois de `--`: `--p1-screenshots` (janela), `--only=T8,T14` (T1 e baseline sempre rodam),
`--report=<caminho>`, `--p1-persist=write|read`. Relatório JSON em `docs/evidence/p1/p1_selftest_<modo>.json`.

### P0

O jeito recomendado é o script, que espera cada processo terminar e grava os logs em UTF-8 em `docs/evidence/`:

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Window -Export
```

Ele importa o projeto (com uma nova tentativa automática se a Godot cair no encerramento do `--import`, bug B1),
roda `check_env`, o dump da API, o selftest headless e em janela, exporta e roda o selftest no `.exe`.
Sem `-Window`/`-Export`, roda só os passos headless. Feche o editor deste projeto antes de rodar.

O selftest (T0–T7b) roda dentro da cena real, com o mesmo `TerrainService`, a mesma física e o mesmo
`CharacterBody3D` do jogo. Para chamá-lo direto (num terminal bash; o editor custom é um executável de
subsistema GUI e no `cmd`/PowerShell a saída não aparece sem redirecionamento):

```bash
"C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe" --headless --path . res://scenes/main.tscn -- --p0-selftest
```

Saída `[P0TEST] ...`, relatório JSON em `docs/evidence/p0_selftest_<modo>.json` e código de saída 0 quando tudo passa.
Opções depois de `--`: `--p0-screenshots` (só em janela; salva PNGs em `docs/evidence/screens/`), `--only=T2,T5`,
`--report=<caminho>`.

Ferramentas avulsas (mesmo executável, `--headless --path . --script ...`):
- `res://tools/check_env.gd`: versão, variante do Voxel Tools (módulo/GDExtension), classes, física, renderer.
- `res://tools/probe_voxel_api.gd`: dump da API **real** do binário → `docs/evidence/voxel_api_probe.txt`.

## Export Windows

```bash
"C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe" --headless --path . --export-release "Windows Desktop" build/elemental_ruins.exe
```

Gera `build/elemental_ruins.exe` (template custom, 88,5 MB, com o Voxel Tools embutido) e `build/elemental_ruins.pck`.
O template oficial **não** serve, porque não contém o Voxel Tools. **Export debug** não está disponível: a release só
traz template de release para Windows, e o debug exigiria compilar o template.
O selftest também roda no executável: `build/elemental_ruins.exe --headless -- --p0-selftest --report=<caminho.json>`.

## Estrutura

```
project.godot, export_presets.cfg (template custom com caminho absoluto desta máquina)
scenes/main.tscn                  Main → World (voxel_lab) + Player + TerrainEditController + HUD
scenes/world/voxel_lab.tscn       ambiente, sol, TerrainService, TerrainBrushQueue, TerrainRoot, SpawnPoint, Props
scenes/player/player.tscn         CharacterBody3D + VoxelViewer + CameraRig (SpringArm3D + Camera3D)
scenes/ui/debug_hud.tscn          overlay de engenharia (montado em código)
scripts/world/terrain_service.gd  ÚNICO ponto que conhece o Voxel Tools (API em coordenadas do mundo; stream SQLite)
scripts/world/terrain_brush_queue.gd  fila de brushes: traços contínuos, orçamento por quadro, divisão e fusão
scripts/world/terrain_brush_request.gd  pedido REMOVE/ADD/PATH/SMOOTH
scripts/world/terrain_material*.gd  TerrainMaterial (dureza, densidade, dobrável, cor) e a biblioteca soil/sand/stone
scripts/world/terrain_save_files.gd  caminhos e arquivos de sessão/slot (sem Voxel Tools)
scripts/world/lab_terrain_factory.gd  VoxelLodTerrain + Transvoxel + VoxelGeneratorGraph (plano + colina + materiais)
scripts/gameplay/terrain_edit_controller.gd  atalhos, mira e marcador → TerrainBrushQueue
scripts/player/*.gd               locomoção e câmera
scripts/dev/p0_selftest.gd        roteiro automatizado de aceite do P0
scripts/dev/p1_selftest.gd        P0 + testes do P1 (herda o anterior)
materials/terrain_lab.gdshader    cor do material (CUSTOM1) + grade 1 m/4 m + costura LOD oficial do Transvoxel
tools/                            check_env, probe_voxel_api, spike_p1_api, run_p0_tests.ps1, run_p1_tests.ps1
docs/                             decisões, resultados e evidências (logs, JSON, PNG); ignorada pela Godot (.gdignore)
```

API pública do `TerrainService` (mundo): `dig_sphere(p, r)`, `add_sphere(p, r, material)`, `dig_path(points, radii)`,
`add_path(points, radii, material)`, `smooth_area(p, r)`, `get_material_at(p)`, `can_edit_area(aabb)`,
`raycast_terrain(from, to)`, `sample_sdf(p)`, `reset_world()`, `save_world(slot)`, `load_world(slot)` (os três
assíncronos), `has_saved_world(slot)`, `is_ready()`. Sinais: `terrain_ready`, `terrain_changed(aabb, revision)`
(o evento TerrainChanged: os dados já mudaram, o collider ainda não), `edit_rejected(op, reason, aabb)`,
`world_reset_started/finished`, `world_save_started/world_saved`, `world_load_started/world_loaded`.
Gameplay edita pela `TerrainBrushQueue` (`enqueue`, `begin_stroke/update_stroke/end_stroke`, sinal `brush_applied`).
