# ELEMENTAL // RUINS — protótipo técnico (P0 + P1 + P2 + P3 + P3.5 + P3.6)

Laboratório de **terreno volumétrico escavável** em Godot 4.7.2 + Voxel Tools 1.7 (SDF + Transvoxel).

**Status: gate P0 PASSOU em 23/10/2026, com ressalva aceita** (crash raro da Godot no fim do `--import`; ver `P0_CHECKLIST.md`).
**P1 (ferramentas, materiais e persistência):** resultado e gate em [`docs/p1_results.md`](docs/p1_results.md).
**P2 (sustentação, destroços e extração):** resultado e gate em [`docs/p2_results.md`](docs/p2_results.md).
**P3 (quatro elementos iniciais):** resultado e gate em [`docs/p3_results.md`](docs/p3_results.md).
**P3.5 (Terra polida: fases, peso, telegraph):** resultado e parâmetros em [`docs/p35_earth_polish.md`](docs/p35_earth_polish.md).

P0: personagem em terceira pessoa, colina voxel com colisão, escavar e adicionar matéria pela mira, túnel real sob
teto sólido e reset de verdade do mundo. P1: fila de brushes contínuos (REMOVE/ADD/PATH/SMOOTH), materiais
solo/areia/pedra com propriedades físicas gravadas nos voxels, evento `TerrainChanged`, salvar/carregar com
`VoxelStreamSQLite`, overlay de observabilidade e benchmarks. P2: torre modular de 36 peças que perde apoio quando
se escava sob ela e cai em etapas, corpos que acordam quando o chão some, teto de corpos ativos, poeira decorativa e
extração de rocha real do terreno. P3: um poder por elemento pela mesma interface (`AbilityController` → `Ability` →
`ElementalEvent` → `MaterialResponseSystem`): Terra ergue e arremessa uma rocha real (dano cinético na torre), Água
empurra, molha e apaga, Fogo acende madeira que queima, carboniza e espalha (o 2º andar da torre é de madeira e cai
quando queima), Ar empurra pela massa e apaga fogo fraco; FX mínimos. Não há arte final, menus, áudio nem simulação
de fluidos.

> Comece por [`INICIO_AQUI.md`](INICIO_AQUI.md) e [`CLAUDE.md`](CLAUDE.md) (requisitos). Resultados e provas estão em
> [`docs/voxel_spike_results.md`](docs/voxel_spike_results.md) (P0), [`docs/p1_results.md`](docs/p1_results.md) (P1), [`docs/p2_results.md`](docs/p2_results.md) (P2) e [`docs/p3_results.md`](docs/p3_results.md) (P3),
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

## Controles (provisórios, conforme CLAUDE.md)

| Tecla | Ação |
|---|---|
| **1 / 2 / 3 / 4** | escolher o elemento: Terra / Água / Fogo / Ar (P3; o HUD mostra o poder atual) |
| **LMB** | usar o poder do elemento. Terra (segurar; P3.5): mire o chão a 2,5–7 m. O chão racha (~0,1 s), a rocha se solta (~0,1 s) e sobe (~0,16 s), pronta em ~0,37 s (o anel da retícula enche); soltar arremessa no ponto mirado. Um toque curto arranca e lança assim que fica pronta; impacto forte no chão abre cratera. Água (segurar): jato até 14 m que empurra, molha e apaga. Fogo (toque; P3.6): a bola se forma na mão por ~0,08 s com a mira do clique, voa a 35 m/s e aquece no primeiro contato; no fim dos 30 m só se dissipa; nova rajada após ~0,14 s; madeira acende e o fogo não atravessa paredes. Ar (toque; P3.6): uma frente de pressão sai da mão a 30 m/s em cone de 10 m e decide cada corpo uma vez; empurra pela massa, é bloqueada por terreno e corpos (exposição parcial reduz o empurrão), apaga fogo fraco e aviva o forte; nova rajada após ~0,15 s |
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
| **R** | extrair uma rocha logo abaixo da mira (raio do pincel limitado a 1–2 m): o núcleo vira um corpo físico real, com a massa do material, e pousa ao lado do buraco |
| **T** | impulso de teste (lançamento a 45°) no corpo físico mirado: rocha, caixa ou peça já caída da torre |
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

### Roteiro manual do P2 (≈ 4 min)
1. A torre fica a ~24 m do spawn, à direita (x = 19, z = 14). Ande até ela.
2. Escave (**G**) embaixo de um pilar do térreo: só aquele pilar cai; a laje continua.
3. Escave sob o pilar vizinho do mesmo lado: metade da torre cai em etapas, com poeira; as peças param sobre o terreno.
4. Mire no chão e aperte **R**: uma rocha sai do buraco e pousa ao lado. Mire nela e aperte **T**: ela é lançada.
5. Solte uma caixa (**B**), espere ela parar e escave embaixo: ela cai na cratera (não fica flutuando).
6. **F5**, **Z** (torre de pé de novo) e **F9**: a torre cai de novo, porque o terreno salvo não tem o apoio.

### Roteiro manual do P3 (≈ 5 min)
O LMB só age com o mouse preso (o clique que prende o mouse não lança poder). O HUD mostra o elemento, o resultado do
último uso e o estado do corpo mirado (`MADEIRA • 470 °C • EM CHAMAS 40%`).
1. Ande até ~16 m da frente da torre. **1** (Terra), mire o chão a uns 5 m e **segure LMB**: a rocha sobe e fica à
   frente. Mire o pé do pilar de pedra da frente e **solte**: o pilar perde blocos e o de cima cai.
2. **3** (Fogo), mire o bloco de baixo de um pilar de **madeira** (2º andar, marrom) e clique: ele acende. Acenda
   também o outro pilar de madeira da frente e espere ~15 s: os blocos queimam até sumir e as placas de cima caem.
3. Solte duas caixas (**B**) lado a lado com ~0,5 m de vão e acenda uma: em alguns segundos a vizinha pega fogo e
   ambas escurecem (carbonizadas).
4. **2** (Água), segure LMB numa caixa em chamas: ela apaga com vapor e é empurrada. Molhe uma caixa e tente acendê-la
   (**3**): a 1ª bola só a seca.
5. **4** (Ar), clique perto de caixas e de destroços: as caixas voam, os blocos de pedra mal se mexem; uma caixa atrás
   de um morro (**H**) não é atingida. Fogo fraco apaga; fogo forte cresce.
6. **Z**: torre de pé, sem fogo nem estados, poderes parados.

### Roteiro manual do P3.5 — Terra (≈ 3 min)
Parâmetros em `data/abilities/earth_tuning.tres` (abra no inspetor da Godot; ver `docs/p35_earth_polish.md`).
1. **1** (Terra) e mire o chão a ~4–5 m: o anel verde no chão mostra de onde a rocha sai (vermelho = inválido).
2. **Segure LMB**: anel âmbar + rachadura e poeira (antecipação); o chão abre e pedrinhas saltam (desprendimento); a
   rocha sobe e para à frente (levantamento). O anel em volta da retícula enche e fica branco quando pronta.
3. Ainda segurando, gire a câmera rápido: a rocha acompanha com atraso e balança de leve (peso). Ande: você fica mais lento.
4. Mire o chão a ~12 m e **solte**: a rocha recua, sai com giro, deixa rastro e abre uma cratera onde bate.
5. **Toque curto** no LMB mirando o chão: a rocha é arrancada e lançada sozinha assim que fica pronta.
6. Mire o céu, o chão a 1 m ou a 10 m e clique: X vermelho na retícula, nada acontece.
7. Mude `anticipation_s`, `rise_s` ou `throw_speed` no `.tres`, rode de novo e compare a sensação.

### Roteiro manual do P3.6 — Água, Fogo e Ar (≈ 6 min)
Parâmetros em `data/abilities/water_tuning.tres`, `fire_tuning.tres` e `air_tuning.tres` (inspetor da Godot); detalhes em
`docs/p36_elemental_polish.md`. Use **B** para criar caixas de teste e **H** para levantar um morro de terreno.
1. **2** (Água), segure LMB numa caixa a ~6 m: o jato avança (não nasce inteiro) e a pressão sobe em ~0,1 s. Gire 90° segurando:
   a água já lançada segue a direção antiga e a nova chega depois. Solte: para na hora.
2. Com uma caixa atrás de um morro ou de outra caixa, molhe a da frente: a de trás não molha através do obstáculo.
3. **3** (Fogo), clique numa caixa e gire a câmera logo em seguida: a bola se forma na mão (~0,08 s) e segue a mira do clique.
   Clique várias vezes: no máximo 8 bolas e uma nova a cada ~0,14 s. Troque de elemento logo após clicar: a bola não sai.
4. Mire o céu: a bola some numa baforada de fumaça no fim dos 30 m, sem aquecer nada.
5. Acenda uma caixa encostada em outra e uma terceira separada por um morro: a encostada pega fogo, a de trás do morro não.
   Atire numa caixa molhada: sai vapor, ela seca e só a 2ª bola acende.
6. **4** (Ar), toque perto de um grupo de caixas: o anel avança e as caixas reagem na ordem da distância; uma caixa escondida
   atrás de outra ou de um morro fica (total ou parcialmente) protegida; a rocha extraída (**R**) mal se mexe.
7. Ar em fogo fraco apaga; em fogo forte aviva e a caixa voa queimando. A água apaga com vapor.
8. Com bolas de fogo ou frentes de ar em andamento, aperte **Z**, **F5** ou **F9**: nada continua depois.
9. Avalie (como jogador e como observador de outro ângulo, pensando em PvP): legibilidade das antecipações e frentes, peso,
   clareza de limites e recuperação. **NÃO TESTADO** por pessoas até aqui.

## Testes automatizados

### P3.6 — Água, Fogo e Ar polidos (inclui as regressões do P0 ao P3.5)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage final -Window -Export
```

Grava em `docs/evidence/p36/final/`: import, selftest P3.6 (P0–P3.5 + T46–T58) no editor e no export, headless e em janela,
com contrato explícito de IDs, zero erros/avisos e capturas em janela. `-Stage m1|m2|m3` grava as evidências de cada marco;
`-TestIds T49,T50` limita a IDs do contrato (T1 sempre incluso). Direto: `... -- --p36-selftest --evidence-stage=final`
(opções `--only=`, `--p36-screenshots`).

### P3.5 — Terra polida (inclui as regressões do P0 ao P3)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p35_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p35/`: import, `check_env`, dump da API, spike da Terra (`tools/spike_p35_earth.gd`:
Timer do Voxel Tools, cavidade, levantamento e separação sub-voxel; custo de GPU só em janela), selftest P0 sozinho,
selftest P3.5 (P0–P3 + T39–T45) e a persistência entre processos; `-Window` inclui as capturas de cada fase da Terra
(T45). Direto: `... -- --p35-selftest` (opções `--only=T39,T43`, `--p35-screenshots`, `--report=`).

### P3 (inclui as regressões do P0, P1 e P2)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p3_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p3/`: import, `check_env`, dump da API, spike de física do P3 (`tools/spike_p3_physics.gd`,
`00_spike_p3.txt`), selftest P0 sozinho, selftest P3 (P0 + P1 + P2 + T28–T38) e a persistência entre processos;
`-Window` roda o selftest P3 em janela com capturas (os critérios de FPS do T27 e do T37 só valem aí) e `-Export`
repete tudo no `.exe`. Direto: `... -- --p3-selftest` (opções `--only=T31,T35`, `--p3-screenshots`, `--report=`).

### P2 (inclui as regressões do P0 e do P1)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p2_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p2/`: import, `check_env`, dump da API, spike da API P2 (`tools/spike_p2_api.gd`), selftest P0
sozinho, selftest P2 (P0 + P1 + T18–T27) e a persistência entre processos; `-Window` roda o selftest P2 em janela com
capturas (o critério de FPS do T27 só vale aí) e `-Export` repete tudo no `.exe`. Direto: `... -- --p2-selftest`.

### P1 (inclui a regressão do P0)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p1_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p1/`: import (com repetição se a Godot cair no encerramento, B1), `check_env`, dump da API,
spike da API P1 (`tools/spike_p1_api.gd`), selftest P0 sozinho (12 testes), selftest P1 (P0 + T8–T17) e a
persistência entre processos (`--p1-persist=write` num processo, `--p1-persist=read` noutro). `-Window` roda o
selftest P1 em janela com capturas em `docs/evidence/p1/screens/` (só aí FPS e tempo de quadro valem algo);
`-Export` exporta e repete selftest P1 e persistência no `.exe`. Feche o editor deste projeto antes de rodar.
Cada passo tem limite de tempo (`-StepTimeoutSec`, padrão 600 s; 0 desliga): se estourar (por exemplo, um script
que não compila deixa a cena rodando sem o selftest), o processo é encerrado, o log ganha uma linha `TIMEOUT` e o passo
sai com exit 124. O `run_p0_tests.ps1` aceita o mesmo parâmetro.

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
scenes/main.tscn                  Main → World (voxel_lab) + Player + TerrainEditController + AbilityController + ElementalFx + EarthFx + HUD
scenes/world/voxel_lab.tscn       ambiente, sol, TerrainService, TerrainBrushQueue, TerrainRoot, SpawnPoint, Props, Structures, StructureService, ContactWaker, DebrisBudget, DustFx, MaterialResponseSystem
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
scripts/dev/p2_selftest.gd        P0 + P1 + testes do P2 (herda o anterior)
scripts/dev/p3_selftest.gd        P0 + P1 + P2 + testes do P3 (herda o anterior)
scripts/dev/p35_selftest.gd       P0–P3 + testes do P3.5 (fases da Terra; herda o anterior)
scripts/abilities/*.gd            AbilityController (1–4 + LMB), base Ability, os 4 poderes e EarthTuning (parâmetros da Terra)
data/abilities/earth_tuning.tres  valores da Terra polida (tempos, forças, alcance, cratera)
scripts/elements/*.gd             ElementalEvent, BodyMaterial(+biblioteca), MaterialState, MaterialResponseSystem, ElementalFx, EarthFx, CrackTexture
scripts/ui/ready_ring.gd          anel de prontidão da Terra em volta da retícula
scripts/structures/*.gd           peça, fábrica da torre, grafo de apoio e StructureService (âncoras, soltura em etapas)
scripts/physics/*.gd              TerrainContactWaker, DebrisBudget (teto de corpos, culling) e DustFx
materials/terrain_lab.gdshader    cor do material (CUSTOM1) + grade 1 m/4 m + costura LOD oficial do Transvoxel
tools/                            check_env, probe_voxel_api, spike_p1_api, spike_p2_api, spike_p3_physics, spike_p35_earth, run_p0/p1/p2/p3/p35_tests.ps1
docs/                             decisões, resultados e evidências (logs, JSON, PNG); ignorada pela Godot (.gdignore)
```

API pública do `TerrainService` (mundo): `dig_sphere(p, r)`, `add_sphere(p, r, material)`, `dig_path(points, radii)`,
`add_path(points, radii, material)`, `smooth_area(p, r)`, `get_material_at(p)`, `can_edit_area(aabb)`,
`raycast_terrain(from, to)`, `sample_sdf(p)`, `reset_world()`, `save_world(slot)`, `load_world(slot)` (os três
assíncronos), `has_saved_world(slot)`, `is_ready()`. Sinais: `terrain_ready`, `terrain_changed(aabb, revision)`
(o evento TerrainChanged: os dados já mudaram, o collider ainda não), `edit_rejected(op, reason, aabb)`,
`world_reset_started/finished`, `world_save_started/world_saved`, `world_load_started/world_loaded`.
Gameplay edita pela `TerrainBrushQueue` (`enqueue`, `begin_stroke/update_stroke/end_stroke`, sinal `brush_applied`).
P2: `TerrainService.extract_rock(p, normal, raio, pai, direção)`; `StructureService.build/check_all/suspend/resume`, sinal `piece_released`.
P3: `AbilityController.select(i)/use_pressed()/use_released()`, sinais `element_changed` e `ability_used`;
`MaterialResponseSystem.apply(ElementalEvent)`, `state_of(corpo)`, sinais `ignited`, `extinguished`, `burned_out`,
`kinetic_break`; `StructureService.break_piece(peça, impulso, motivo)` e `consume_piece(peça, motivo)`.
P3.5: `Ability.fx_event(kind, data)` (ganchos de FX/áudio); `EarthLiftThrow.phase`, `is_ready()`, `ready_progress()`,
`validate_target()`; `TerrainService.can_extract_rock(p, normal, raio)`, `cavity_confirmed(p)` e
`extract_rock(..., hold_kinematic)`; `ThirdPersonCamera.add_trauma(x)`.

## P3.6 — polimento incremental
M0–M4 concluídos (relatório final em docs/p36_elemental_polish.md); baseline corrigido em docs/p36_baseline_corrected.md, arquitetura em docs/p36_m0.md, Água em docs/p36_water_polish.md, Fogo em docs/p36_fire_polish.md e Ar em docs/p36_air_polish.md (parâmetros em data/abilities/*_tuning.tres; testes por marco: `tools/run_p36_tests.ps1 -Stage m2|m3 -Window`). Capturas e automação não são playtest humano.

