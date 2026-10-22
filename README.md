# ELEMENTAL // RUINS — protótipo técnico P0

Laboratório de **terreno volumétrico escavável** em Godot 4.7.2 + Voxel Tools 1.7 (SDF + Transvoxel).
Escopo deste marco: **somente P0**. Personagem em terceira pessoa, colina voxel com colisão, escavar e
adicionar matéria pela mira, túnel real sob teto sólido e reset de verdade do mundo. Não há poderes,
arte final, menus ou água.

> Comece por [`INICIO_AQUI.md`](INICIO_AQUI.md) e [`CLAUDE.md`](CLAUDE.md) (requisitos). Resultados e provas estão em
> [`docs/voxel_spike_results.md`](docs/voxel_spike_results.md), decisões em [`docs/decisions.md`](docs/decisions.md)
> e o gate em [`P0_CHECKLIST.md`](P0_CHECKLIST.md).

## Versões usadas (verificadas nesta máquina)

| Item | Versão / origem |
|---|---|
| Godot | **4.7.2.stable.official.ed1daf0bf** (build padrão, não a mono/.NET), assinatura Authenticode válida |
| Voxel Tools | **GDExtension 1.7** (release `v1.7x`, `GodotVoxelExtension.zip`, sha256 `600737572a5e…a1d2d8`), em `addons/zylann.voxel/` |
| Física 3D | Jolt Physics integrado (`physics/3d/physics_engine="Jolt Physics"`) |
| Renderer | Forward+ (Vulkan 1.4.323 na Intel Iris Xe testada) |
| Templates de export | oficiais 4.7.2 (`Godot_v4.7.2-stable_export_templates.tpz`, sha256 `f298490b…248011`) |

## Requisitos

1. Windows 10/11 x64.
2. Godot **4.7.2 padrão**: <https://github.com/godotengine/godot/releases/tag/4.7.2-stable> (`Godot_v4.7.2-stable_win64.exe.zip`).
   Nesta máquina ela está em `C:\Users\dsoares\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_win64.exe`.
3. O Voxel Tools **já vem no repositório** (`addons/zylann.voxel/`, só os binários Windows x86_64). Para outras
   plataformas, reextraia o `GodotVoxelExtension.zip` da release `v1.7x` na raiz do projeto.

## Abrir e rodar no editor

1. Abra a Godot 4.7.2 (o executável **sem** "mono").
2. No Gerenciador de Projetos, clique em **Importar**, escolha `project.godot` desta pasta e depois **Importar e editar**.
3. **Primeira abertura num clone limpo (sem a pasta `.godot/`):** a primeira importação com o Voxel Tools GDExtension
   fecha a Godot com segfault de forma **intermitente** (10 de 17 tentativas; bug B1 em `docs/voxel_spike_results.md`).
   Se acontecer, abra o projeto de novo: com o cache criado, não reproduziu. Para evitar, rode antes
   `powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1`, que pré-registra a extensão em
   `.godot/extension_list.cfg` (0 de 11 crashes assim) e importa o projeto.
4. Pressione **F5** (cena principal `res://scenes/main.tscn`).
   O terreno é **criado em código** ao rodar (`LabTerrainFactory`), por isso a colina não aparece na viewport do editor.

## Controles (provisórios do P0, conforme CLAUDE.md)

| Tecla | Ação |
|---|---|
| WASD | andar, relativo à câmera |
| Shift | correr |
| Espaço | pular |
| Mouse | orbitar a câmera (Esc solta/prende o mouse; clique recaptura) |
| **G** | escavar uma esfera no ponto mirado (segure para repetir a cada 0,15 s) |
| **H** | adicionar matéria no ponto mirado (recusa se for prender o personagem) |
| **J** | abrir túnel de 10 m na direção horizontal da câmera, na altura da mira |
| **Z** | **reset do mundo**: recria o terreno do gerador, apaga todas as edições, devolve o jogador ao spawn e remove as caixas |
| Roda do mouse ou `[` `]` | raio do pincel (0,5–6 m; padrão 2 m) |
| B | soltar uma caixa `RigidBody3D` de teste no ponto mirado (máx. 10) |

O marcador esférico na mira fica **verde** quando a área é editável e **vermelho** quando não é. O HUD mostra
FPS, estado do terreno (geração/revisão), posição, se o jogador está no chão, o resultado da última edição e os resets.

### Roteiro manual sugerido (≈ 3 min)
1. Ande até a colina (W) e erga a câmera até a mira cair na encosta, a cerca de 1,5 m do chão.
2. Raio 2 m (padrão). Aperte **J**, ande para dentro do túnel e aperte J de novo lá dentro para continuar até sair do outro lado. Confira que há teto sobre a cabeça e que você não atravessa o chão.
3. Fora da colina, segure **G** sobre o chão para abrir uma cratera e pule dentro dela.
4. Mire no chão a uns 4–5 m e segure **H** para formar uma coluna; suba nela (pulo) ou solte uma caixa com **B**.
5. Repita G/H no mesmo ponto várias vezes.
6. Aperte **Z**: cratera, túnel e coluna devem sumir, e o jogador volta ao spawn.

## Testes automatizados

Roteiro de aceite completo (T0–T7b), dentro da cena real, com o mesmo `TerrainService`, a mesma física e o mesmo
`CharacterBody3D` do jogo:

```bash
"C:/Users/dsoares/Tools/Godot/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scenes/main.tscn -- --p0-selftest
```

Saída `[P0TEST] ...` no console, relatório JSON em `docs/evidence/p0_selftest_<modo>.json` e código de saída 0 quando tudo passa.
Opções depois de `--`: `--p0-screenshots` (só em janela; salva PNGs em `docs/evidence/screens/`), `--only=T2,T5`,
`--report=<caminho>`.

Bateria completa (importação, ambiente, dump da API, selftest headless, janela com capturas, export e selftest no `.exe`):

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Window -Export
```

Ferramentas avulsas:
- `--headless --path . --script res://tools/check_env.gd`: versão, classes Voxel carregadas, física, renderer.
- `--headless --path . --script res://tools/probe_voxel_api.gd`: dump da API **real** do binário instalado → `docs/evidence/voxel_api_probe.txt`.

## Export Windows

```bash
"C:/Users/dsoares/Tools/Godot/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build/elemental_ruins.exe
```

Gera `build/elemental_ruins.exe`, `.pck` e `libvoxel.windows.template_release.x86_64.dll` (os três precisam ficar juntos).
O selftest também roda no executável: `build/elemental_ruins.exe --headless -- --p0-selftest --report=<caminho.json>`.

## Estrutura

```
project.godot, export_presets.cfg
addons/zylann.voxel/              Voxel Tools GDExtension 1.7 (binários Windows versionados)
scenes/main.tscn                  Main → World (voxel_lab) + Player + TerrainEditController + HUD
scenes/world/voxel_lab.tscn       ambiente, sol, TerrainService, TerrainRoot, SpawnPoint, Props
scenes/player/player.tscn         CharacterBody3D + VoxelViewer + CameraRig (SpringArm3D + Camera3D)
scenes/ui/debug_hud.tscn          HUD de engenharia (montado em código)
scripts/world/terrain_service.gd  ÚNICO ponto que conhece o Voxel Tools (API em coordenadas do mundo)
scripts/world/lab_terrain_factory.gd  VoxelLodTerrain + Transvoxel + VoxelGeneratorGraph (plano + colina)
scripts/gameplay/terrain_edit_controller.gd  atalhos G/H/J/Z/B, mira e marcador
scripts/player/*.gd               locomoção e câmera
scripts/dev/p0_selftest.gd        roteiro automatizado de aceite
materials/terrain_lab.gdshader    cor por normal + grade 1 m/4 m + costura LOD oficial do Transvoxel
tools/                            check_env, probe_voxel_api, run_p0_tests.ps1
docs/                             decisões, resultados e evidências (logs, JSON, PNG)
```

API pública do `TerrainService` (mundo): `dig_sphere(p, r)`, `add_sphere(p, r)`, `dig_path(points, radii)`,
`can_edit_area(aabb)`, `raycast_terrain(from, to)`, `sample_sdf(p)`, `reset_world()` (assíncrono), `is_ready()`.
Sinais: `terrain_ready`, `terrain_changed(aabb, revision)`, `edit_rejected(op, reason, aabb)`,
`world_reset_started`, `world_reset_finished(generation, ms)`.
