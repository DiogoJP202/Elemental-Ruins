# ELEMENTAL // RUINS — protótipo técnico P0

Laboratório de **terreno volumétrico escavável** em Godot 4.7.2 + Voxel Tools 1.7 (SDF + Transvoxel).

**Status: gate P0 PASSOU em 23/10/2026, com ressalva aceita** (crash raro da Godot no fim do `--import`; ver `P0_CHECKLIST.md`).

Escopo deste marco: **somente P0**. Personagem em terceira pessoa, colina voxel com colisão, escavar e
adicionar matéria pela mira, túnel real sob teto sólido e reset de verdade do mundo. Não há poderes,
arte final, menus ou água.

> Comece por [`INICIO_AQUI.md`](INICIO_AQUI.md) e [`CLAUDE.md`](CLAUDE.md) (requisitos). Resultados e provas estão em
> [`docs/voxel_spike_results.md`](docs/voxel_spike_results.md), decisões em [`docs/decisions.md`](docs/decisions.md)
> e o gate em [`P0_CHECKLIST.md`](P0_CHECKLIST.md).

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
docs/                             decisões, resultados e evidências (logs, JSON, PNG); ignorada pela Godot (.gdignore)
```

API pública do `TerrainService` (mundo): `dig_sphere(p, r)`, `add_sphere(p, r)`, `dig_path(points, radii)`,
`can_edit_area(aabb)`, `raycast_terrain(from, to)`, `sample_sdf(p)`, `reset_world()` (assíncrono), `is_ready()`.
Sinais: `terrain_ready`, `terrain_changed(aabb, revision)`, `edit_rejected(op, reason, aabb)`,
`world_reset_started`, `world_reset_finished(generation, ms)`.
