# Decisões e trade-offs — P0–P3.6

Registro das escolhas técnicas. D1–D14: P0 (22–23/10/2026). D15–D20: P1. D21+: P2 (23/10/2026). Formato: decisão → motivo → consequência.

## D1. Voxel Tools GDExtension 1.7 na Godot oficial (não a build custom) — **SUBSTITUÍDA por D13 em 23/10/2026**
- **Motivo:** CLAUDE.md manda testar primeiro a GDExtension. Ela carregou na Godot 4.7.2 oficial
  (`compatibility_minimum = "4.4.1"`) com todas as classes necessárias, e o selftest passou 12/12.
- **Consequência:** export com os templates **oficiais** (sem template custom). Plano B (build custom
  `v1.7` 4.7.2 + módulo) **não foi necessário nem testado**.
- **Risco conhecido:** a primeira importação com cache vazio fecha a Godot com segfault, de forma intermitente
  (10/17; ver `voxel_spike_results.md`, B1). Mitigação: pré-registrar a extensão em `.godot/extension_list.cfg`
  (0/11 crashes), feito por `tools/run_p0_tests.ps1`; no editor, reabrir. Se isso piorar, o plano B é testar a
  build custom `v1.7`.

## D2. Gerador nativo `VoxelGeneratorGraph` montado em código
- **Motivo:** a GDExtension tem limitações conhecidas com métodos virtuais de script (godot_voxel#442), o que
  ameaça o `VoxelGeneratorScript`. O grafo roda em C++ nas threads do motor voxel, sem loop por voxel em GDScript.
- **Como:** `LabTerrainFactory.create_generator()` cria `InputX/Y/Z → Add(−centro) → SdfSphere(r=24)` e
  `SdfPlane(y=0)`, unidos por `SdfSmoothUnion(smoothness=4)`. Os nomes de portas e parâmetros foram conferidos no binário
  (`tools/probe_voxel_api.gd`; `SdfSphere` não tem centro, daí os nós `Add`).
- **Consequência:** o mundo-base é um SDF determinístico (não é heightmap; os dados são voxels 3D e o túnel é
  matéria removida de verdade).

## D3. Terreno criado em código, cenas só com tipos nativos (exceto `VoxelViewer`)
- **Motivo:** o reset precisa recriar o nó; uma factory única garante configuração idêntica na carga e no reset.
  Evita também `.tscn` escritos à mão com sub-recursos do Voxel Tools.
- **Consequência:** a colina não aparece na viewport do editor, só ao rodar. O `VoxelViewer` fica em
  `player.tscn` (pertence ao jogador).

## D4. Reset = liberar o `VoxelLodTerrain` e criar outro do mesmo gerador
- **Motivo:** a API não documenta `restart_stream`/`reset` para `VoxelLodTerrain` (conferido na doc e no dump).
  Sem stream, todas as edições vivem nos dados do nó; liberá-lo descarta dados, malhas e colliders juntos.
- **Consequência:** reset real em ~0,2 s (headless) a ~0,3–0,5 s (janela), medido. O jogador é congelado e
  teleportado para o spawn; caixas de teste são removidas. Não há persistência ainda (VoxelStreamSQLite fica para P1).

## D5. Folga de 0,05 m no raio de **remoção**
- **Motivo (diagnóstico real):** remover exatamente a esfera que acabou de ser adicionada deixava voxels com
  SDF == 0 na fronteira coincidente (`max(atual, −esfera) = 0`). O Transvoxel trata isso como superfície e
  gerava uma película sólida de espessura zero, com colisão. Detectado pelo teste T5.
- **Consequência:** escavações ficam 5 cm maiores que o raio nominal (≈ 3 passos de quantização de 16 bits).
  T5 (20 ciclos no mesmo ponto) passou a ser PASS. Exposto como `TerrainService.remove_radius_padding`.

## D6. Validação antes de editar
- Ordem: entrada finita → raio 0,5–6 m → `voxel_bounds` (AABB de 512×192×512 em torno da origem) →
  `VoxelTool.is_area_editable` (LOD0 carregado) → sobreposição com a cápsula do jogador (só para ADD) →
  orçamento de 4 edições por quadro de física. Falhas retornam `TerrainEditResult` com motivo, sem tocar nos dados.
- A taxa de repetição de G/H (0,15 s) fica no controlador de input, não no serviço, para que testes e futuros
  sistemas possam emitir edições controladas sem esperar cooldown de input.

## D7. Mira por raycast **físico**
- **Motivo:** o jogador colide com o collider, não com os dados. Usar a física para mirar mostra a verdade do
  que é sólido agora; o atraso de collider (medido em ~10–35 ms) é imperceptível na mira.

## D8. Input: ações registradas em código (`InputActions`, autoload) com `physical_keycode`
- **Motivo:** uma fonte única e explícita, que funciona igual em teclados US e ABNT2 e não depende de serializar
  `InputEvent` à mão no `project.godot`.
- **Correção após teste interativo:** a primeira edição de G/H passou a sair do **evento** de tecla. Um toque
  rapidíssimo (tecla desce e sobe no mesmo quadro) se perdia quando só se consultava `Input.is_action_pressed`.
  A repetição segurando continua no `_physics_process`. Atalhos funcionam com Shift pressionado.

## D9. Versionamento
- `.gitattributes` com LF para os arquivos Godot.
- ~~Do Voxel Tools versionamos `.gdextension`, LICENSE, ícones e só os binários Windows x86_64.~~ Desde D13 o
  repositório **não tem binários do Voxel Tools**: ele vem embutido no editor e no template custom, que ficam fora
  do projeto (são baixados da release `v1.7`; ver README).
- `export_presets.cfg` **passou a ser versionado** (o `.gitignore` original o ignorava): ele não contém segredos
  (a Godot 4 guarda credenciais em `.godot/export_credentials.cfg`) e é necessário para reproduzir o export.
- `build/` é ignorado; logs de evidência em `docs/evidence/*.log` são versionados (exceção ao `*.log`).
- `docs/.gdignore`: a Godot não importa a pasta de documentação. As capturas PNG de evidência não viram
  texturas nem entram no `.pck` (3 MB → 190 KB). O selftest continua gravando nela via `FileAccess`.

## D10. Material de laboratório simples
- Shader próprio com cor por orientação da normal (piso areia / parede terracota / teto verde mineral) e grade
  de 1 m e 4 m em espaço do mundo, para ler escala e movimento, mais o trecho **oficial** de costura de LOD do
  Transvoxel (doc do Voxel Tools v1.7). Não é a direção de arte (toon/retro ficam para P4).

## D11. Parâmetros do terreno
- `mesh_block_size=16` (rebuild menor por edição), `lod_count=4`, `lod_distance=48`, `view_distance=256`,
  `collision_lod_count=2`, `collision_update_delay=0`, sem `full_load_mode`. São escolhas para o laboratório
  compacto; não foram otimizadas por benchmark.

## D12. Plano B (módulo) avaliado — decisão pendente do usuário
- **Dados (seção 11 do `voxel_spike_results.md`):** o módulo elimina o B4 e reduz o crash de importação limpa de
  10/17 para 1/34, com resultados funcionais idênticos (12/12 em todos os modos).
- **Custo:** editor não assinado, template custom só release no Windows, caminho absoluto no preset de export e
  troca de editor e template a cada atualização.
- **Estado:** decidido pelo usuário em 23/10/2026: trocar para o módulo (D13).

## D13. Voxel Tools 1.7 como **módulo** (build custom Godot 4.7.2 + Voxel Tools 1.7)
- **Decisão:** o usuário aprovou em 23/10/2026, a partir do comparativo da seção 11 do `voxel_spike_results.md`.
  CLAUDE.md prevê essa build como alternativa quando a GDExtension se mostrar inviável; aqui o motivo foi
  robustez do `--import`, do qual a verificação automatizada depende.
- **O que mudou no repositório:** `addons/zylann.voxel/` removido; `export_presets.cfg` com
  `custom_template/release = C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.template_release.x86_64.exe`;
  `tools/run_p0_tests.ps1` usa o editor custom por padrão, valida o template antes de exportar e repete o import uma
  vez se a Godot cair no encerramento (B1 residual); a verificação de DLL travada (B4) saiu, porque não há mais DLL;
  `check_env.gd` informa a variante. **Nenhuma linha de gameplay mudou.** O dump da API difere só no tipo de um
  parâmetro de `separate_floating_chunks` (`Object` → `Node`), que não usamos.
- **Implicações (aceitas):**
  1. Editor e template **não assinados** (build de CI do projeto Voxel Tools); o SmartScreen pode avisar.
  2. A Godot oficial deixa de servir para este projeto (sem classes Voxel). Todo colaborador precisa do editor custom.
  3. Export só **release** no Windows. Não há template debug na release; o debug exigiria compilar o template.
  4. O caminho do template no preset é absoluto e específico desta máquina: quem usar outra pasta ajusta o preset.
  5. Atualizar o Voxel Tools significa trocar editor e template juntos, e a versão da Godot acompanha a release do Voxel Tools.
  6. Outras plataformas: a release `v1.7` tem editor e template para Linux e macOS; Android, iOS e Web exigiriam compilar.
- **Resultado medido após a troca, no projeto real:** 12/12 PASS em editor headless, editor em janela, `.exe` headless e
  `.exe` em janela, com 0 erros do motor; importação limpa 1/50 crashes no total (bug da Godot no encerramento do
  `--import`); import com outra instância aberta 0/3.
- **Reversão:** reextrair `GodotVoxelExtension.zip` (`v1.7x`) na raiz, limpar `custom_template/release` e usar a
  Godot oficial (o commit `de7514a` é o último com a GDExtension).

## D14. B1 residual aceito como risco conhecido — gate P0 fechado
- **Decisão do usuário (23/10/2026):** aceitar o crash residual da Godot no encerramento do `--import` em clone
  limpo (1/50 com o módulo) e fechar o gate do P0.
- **Mitigação mantida:** `tools/run_p0_tests.ps1` repete o import uma vez. No editor com interface, se a primeira
  abertura de um clone limpo fechar, basta reabrir.
- **Reavaliar quando:** sair Godot 4.7.3+ ou Voxel Tools 1.8 (testar de novo a importação limpa), ou se a taxa
  subir em CI.

---

# P1 — ferramentas, materiais e persistência (23/10/2026)

## D15. Material é dado voxel no canal INDICES, não textura
- **Decisão:** cada voxel guarda o índice do seu material no canal `INDICES` (`VoxelFormat` com índices de 8 bits,
  mesher `TEXTURES_SINGLE_S4`, grafo com `TEXTURE_MODE_SINGLE` e nó `OutputSingleTexture`). `TerrainMaterial`
  (`hardness`, `density`, `bendable`, `surface_color`) fica em `TerrainMaterialLibrary`, indexado por esse valor.
- **Motivo:** uma única fonte de verdade, que muda com as edições e persiste no SQLite junto com o SDF. Regras de
  jogo leem a **definição** pelo índice; o shader só recebe `surface_color` das definições. Nada lê física de cor ou
  de peso de pintura.
- **Verificação:** spike `tools/spike_p1_api.gd` S1–S4b (escrita do gerador, `MODE_SET` em `INDICES` com
  `do_sphere` e `do_path`, SDF intacto) e T11.
- **Valores (escolha de laboratório, não medidos):** solo 1,0 / 1500 kg/m³; areia 0,5 / 1600 kg/m³; pedra
  3,0 / 2600 kg/m³; todos dobráveis. Layout: pedra abaixo de y = −6 e no núcleo da colina (mais de 3 m para dentro),
  areia em x ≥ 24, solo no resto.
- **Consequências:** o ADD com material pinta o raio + 0,5 m (`material_paint_margin`) para a superfície nova ler o
  material por inteiro; matéria que já existia nessa faixa troca de material. A cor nas bordas é a mistura que o
  Transvoxel faz entre os 4 materiais mais presentes de cada célula.

## D16. Regras de jogo mínimas para as propriedades
- `hardness` multiplica o intervalo da escavação contínua (REMOVE): base 0,15 s → areia 0,075 s, solo 0,15 s, pedra
  0,45 s. O material vem dos dados logo abaixo da superfície mirada; se a amostra cai no ar (buraco recém-aberto,
  collider ainda velho), o traço mantém o último material sólido lido.
- `density` × volume nominal do brush = massa **estimada** em `TerrainEditResult.est_mass_kg` (rotulada assim no HUD).
  Não é volume real de matéria alterada.
- `bendable = false` faz a fila recusar com `material_not_bendable`. Nenhum dos 3 materiais é não dobrável, então a
  regra foi testada isolada (`TerrainBrushQueue.material_policy`), não no mundo.

## D17. `TerrainBrushQueue` como porta única das edições de gameplay
- **Traço:** um carimbo sai quando passou o intervalo (× dureza no REMOVE) **e** a mira andou pelo menos 0,35 × raio.
  O plano dizia "anda **ou** passa o intervalo"; com "ou", segurar G parado cavaria a cada quadro assim que o collider
  descesse, e a dureza não teria efeito. Se a mira andou mais que 1 × raio desde o último carimbo, o carimbo vira um
  tubo (PATH) do ponto anterior até a mira, para a vala não ter buracos. SMOOTH só exige o intervalo.
- **Orçamento:** até 2 operações e 3000 m³ de AABB somada por quadro de física; PATH cuja AABB passaria de 14 m é
  dividido em trechos de até 14 m − 2 × raio; carimbos acumulados do mesmo traço viram um único `do_path`.
  Esses limites não foram otimizados por benchmark; os medidos estão em `docs/p1_results.md`.
- A fila roda com `process_physics_priority = 100`: o carimbo pedido pelo controlador num quadro é aplicado no mesmo
  quadro. Reset, salvar e carregar esvaziam a fila.
- `TerrainService` continua aceitando chamadas diretas (os testes do P0 usam), com o seu orçamento de 4 edições por
  quadro; a fila respeita esse orçamento e tenta de novo no quadro seguinte.

## D18. Persistência: arquivo de sessão por instância + slot copiado
- **Decisão:** o terreno vivo sempre usa um `VoxelStreamSQLite` num arquivo de sessão `user://world/session_<pid>_<n>.sqlite`,
  novo a cada recriação. **Salvar (F5):** `save_modified_blocks()` → esperar o `VoxelSaveCompletionTracker` → liberar o
  nó → fechar o stream (`database_path = ""`) → copiar a sessão para `user://saves/<slot>.sqlite` → reabrir a mesma
  sessão. **Carregar (F9):** copiar o slot para uma sessão nova e recriar o nó. **Reset (Z):** sessão nova e vazia;
  o slot não é tocado.
- **Motivos (medidos no spike):** liberar o nó sem `save_modified_blocks` **não** grava as edições (I1), então a
  sessão descartada no reset não é contaminada; o Windows não deixa apagar o arquivo com o stream aberto (I2) e deixa
  depois de fechar (I3); o slot precisa ser uma cópia fechada para "carregar" significar "voltar ao último save",
  porque blocos descarregados por distância são gravados na sessão a qualquer momento.
- **Custo:** salvar recria o terreno a partir do disco (jogador e caixas congelados por ~0,3–0,7 s, medido).
  Copiar com o stream aberto evitaria isso, mas pode copiar um arquivo no meio de uma gravação assíncrona; não testado.
- `set_key_cache_enabled(true)` no stream: o reset médio com stream caiu de 581 ms para ~260 ms (headless, T7b).
- **Não persiste:** caixas de teste e qualquer objeto fora do terreno (o `WorldSave` de objetos é P2).
- `persistence_enabled = false` volta ao comportamento do P0 (sem stream).
- **Falhas do save (B6/B7, `p1_results.md` §7):** se `save_modified_blocks` não termina em `save_timeout_s` (15 s), o
  save é abortado **sem** liberar o terreno; o tracker abortado é guardado e o próximo save espera as gravações em voo
  dele antes de pedir as suas (senão veria "nada a gravar" e fecharia o stream com gravações pendentes).

## D19. Selftest P1 estende o do P0
- `scripts/dev/p1_selftest.gd` faz `extends "res://scripts/dev/p0_selftest.gd"`, roda os 12 testes P0 e depois
  T8–T17. Mudança no P0: `_run()` dividido em `_run_tests()` + `_finish()`, e prefixo do relatório, pasta de evidência,
  pasta de capturas e watchdog viraram métodos sobrescrevíveis. `--p0-selftest` continua igual (12 testes).
- Persistência entre processos: `--p1-persist=write` e `--p1-persist=read` em execuções separadas.
- `tools/run_p1_tests.ps1` é a bateria do P1; `Invoke-Native` e o retry do import (B1) foram para
  `tools/lib_godot_process.ps1`, usado pelos dois runners.
- Timeout por passo (`-StepTimeoutSec`, padrão 600 s): o watchdog do selftest só existe se os scripts compilarem; um
  erro de parse deixava a cena rodando e o runner esperando para sempre. Estourou → `taskkill /T /F`, linha `TIMEOUT`
  no log, exit 124, e o runner segue. Timeout no `--import` não é repetido (não é o B1). Conferido em `p1_results.md` §11.

## D20. Controles provisórios do P1
- G escavar, H adicionar e N suavizar (segurar = traço contínuo); J túnel de 10 m; K rampa de 8 m subindo 3 m com o
  material do H; M troca o material do H (solo → areia → pedra); F5/F9 salvar/carregar o slot `slot1`; Z reset.
- Sem seleção 1–4 (reservada para os elementos no P3, CLAUDE.md).

---

# P2 — sustentação, destroços e extração de rochas (23/10/2026)

## D21. Torre modular de 36 peças e regra de apoio
- **Decisão:** `TowerFactory` monta, em código, sempre a mesma torre em (19, 0, 14): 4 pilares de 3 blocos,
  laje em 4 placas (pré-fraturada), 4 pilares de 2 blocos, 2ª laje e 8 blocos de coroa. Peças = `RigidBody3D` com
  `BoxShape3D` (convexo), camada PROPS, massa = volume × 2600 kg/m³, **congeladas** (freeze estático) até perderem apoio.
  O plano previa (18, 0, −32); a 63 m do spawn, fora do LOD0, o resolvedor não leria o SDF sob os pés logo depois de
  uma carga. Em (19, 0, 14) fica a ~24 m do spawn, em chão plano de solo e longe das áreas dos testes P0/P1.
- **Regra (`SupportGraph`):** ligações pelo contato das caixas de montagem (vertical: topo encosta no fundo com área em
  comum; lateral: mesma faixa de altura e faces encostadas). Uma peça fica apoiada se é pé com âncora válida, ou tem
  ≥ 1 peça de baixo apoiada, ou ≥ 2 vizinhas laterais apoiadas (placa como viga). Ponto fixo mínimo a partir dos pés.
  Peça solta nunca volta a sustentar. Consequência medida: 1 pilar escavado → só ele cai (as duas placas vizinhas
  seguram a placa de cima); 2 pilares do mesmo lado → metade da torre (17 peças).
- **Fora do escopo:** fratura em tempo de execução, juntas, dano por impacto e re-ancoragem de peças caídas.

## D22. Âncoras pelos dados SDF, soltura depois do collider
- `TerrainChanged` perto dos pés marca a torre para checagem; no quadro seguinte, cada pé lê o SDF em 5 pontos (centro
  e 4 cantos) **1 m** abaixo da face de baixo; pé inválido com < 3 pontos sólidos. Com 0,5 m, `sample_sdf` arredondava
  para o voxel y = 0, a própria superfície (SDF 0), e todos os pés pareciam sem apoio (bug achado no T20).
- Pé invalidado só libera peças depois que o raycast de terreno sob ele mostra o buraco (o evento chega antes do
  collider; B5 do P1). Prazo de 1 s: passou, solta mesmo assim (os dados mandam) e conta `confirm_timeouts`; os testes
  exigem 0.
- Soltura por fila, de baixo para cima, até 6 peças por quadro de física.

## D23. Acordar corpos sobre terreno editado (`TerrainContactWaker`)
- **Motivo (spike P2, I3):** um `RigidBody3D` dormindo **não acorda** quando o collider do terreno embaixo dele some;
  fica flutuando. Acordado, cai.
- **Como:** cada `TerrainChanged` gera pulsos 1, 3, 8 e 20 quadros depois (o collider chega alguns quadros após o evento):
  consulta de forma (caixa = AABB da edição + 1 m) na camada PROPS; acorda os dormindo e solta os estacionados pelo
  `DebrisBudget`. Peças de estrutura ainda presas não são tocadas.

## D24. Orçamento de corpos e culling (`DebrisBudget`)
- Grupo `debris`: peças soltas, rochas extraídas e caixas de teste. A cada 0,25 s: corpo a mais de 80 m do jogador é
  estacionado (freeze estático; também evita cair se o collider daquele trecho sair do alcance de colisão do terreno)
  e volta a dinâmico a menos de 64 m; acima de 64 corpos dinâmicos, estaciona os mais antigos **já parados**
  (< 0,05 m/s). Corpo em movimento nunca é congelado no ar, então durante uma queda simultânea o número de corpos
  ativos pode passar do teto (medido no T22: pico de 150) até eles pararem.
- Malhas de destroço ganham `visibility_range_end = 120 m`. O orçamento pausa enquanto o terreno é recriado.
- Poeira: pool de 4 `GPUParticles3D` de disparo único, no máximo 2 disparos por quadro; sem corpo físico.

## D25. Extração de rocha por `separate_floating_chunks` (tecla R) e impulso de teste (tecla T)
- **Extração:** cavidade em volta de um núcleo de 1–2 m logo abaixo da mira, núcleo recriado com o material que
  estava ali e `VoxelToolLodTerrain.separate_floating_chunks` numa caixa de ~8 voxels (custo medido 0,5–1,9 ms até 30³).
  O Voxel Tools cria o corpo na **camada e máscara 1 (as do terreno)**, com massa 1 kg e malha sem material: o serviço
  muda para PROPS, massa = volume da malha × densidade e cor do material.
- **Posicionamento:** a boca da cavidade esférica é mais estreita que ela (r = 1,5: boca de ~1,9 m para uma rocha de
  ~1,3 m de meia-largura), e a rocha ficava presa no fundo (medido no T24). A rocha é posicionada **uma vez**, ainda
  cinemática (o Voxel Tools a mantém assim por < 0,5 s), sobre o chão ao lado do buraco, do lado oposto ao jogador.
  Não é teleporte por quadro.
- **Impulso de teste:** lançamento a 45° (direção horizontal da câmera + a mesma componente vertical), velocidade
  8 m/s, só em corpos soltos. R e T são ferramentas de laboratório; segurar, mirar e arremessar como habilidade de terra
  ficam para o P3.

## D26. Estruturas no reset, salvar e carregar
- **Reset:** a torre é remontada intacta **antes** de recriar o terreno (peças soltas cairiam pelo chão ausente).
- **Salvar:** caixas e peças soltas são congeladas durante a recarga do terreno e só descongeladas quando há collider
  de terreno sob cada uma: `save_world` espera o terreno apenas em volta do ponto de prontidão.
- **Carregar:** torre remontada intacta e `check_all()` depois que o terreno carrega: se o slot tem o apoio escavado, a
  torre cai de novo. O estado da estrutura é **derivado do terreno**; posições de destroços, rochas e caixas não são salvas.

## D27. Critério de FPS do gate e bateria do P2
- "Sem destruir o FPS" virou critério medido no T27 (os 4 pés escavados no mesmo quadro), **em janela nesta máquina**:
  intervalo entre quadros p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms durante 6 s. Em headless o teste só registra os números.
- `scripts/dev/p2_selftest.gd` estende o do P1 (P0 + P1 + T18–T27); `tools/run_p2_tests.ps1` roda P0 sozinho, o selftest
  P2 e a persistência entre processos pelo selftest P2 (grava em `docs/evidence/p2/`, sem tocar na evidência do P1).

## D28. Poderes do P3: interface comum e um poder por elemento
- `AbilityController` (nó em Main) lê 1–4 (elemento) e LMB (usar) pelo input map e chama a `Ability` atual:
  `on_press` / `on_hold(delta)` / `on_release` (modo "hold" ou "tap") e `physics_tick` em todos os poderes (o que segue
  em voo depois de soltar). `cancel()` interrompe o botão; `clear()` descarta o que está em voo (reset/salvar/carregar).
- Um poder age no mundo **só** por `TerrainService`, forças/impulsos em corpos e `ElementalEvent` no
  `MaterialResponseSystem`; o VFX (`ElementalFx`) só lê o que já foi decidido (pesquisa §3.5).
- Nada age com o terreno sendo recriado nem com o input do jogador desligado; o clique que recaptura o mouse não age.
- Terra = **erguer e arremessar rocha** (decisão do usuário em 26/10, roadmap), não o pilar do GDD. Modo Criativo:
  recurso infinito, sem recarga. Q/E, RMB, carga e câmera lenta ficam para o P4.

## D29. Terra: rocha segura por mola-amortecedor, impacto pelo 1º contato
- Rocha real extraída do terreno (D25), `gravity_scale 0` enquanto segura, força `k(alvo − centro) + c(v_alvo − v)` com
  k = mω², c = 2mω, ω = 6 rad/s e teto de 40 m/s² (spike H1: atraso de 1,42 m → 0,22 m ao usar a velocidade do alvo).
  O ponto controlado é o **centro da malha**: a origem do corpo do `separate_floating_chunks` fica no canto da caixa
  (~3 m do centro) e o arremesso errava o alvo (medido no T29).
- Sobe primeiro na vertical (a boca da cavidade é mais estreita que a rocha, D25). Soltar: 22 m/s na direção do ponto
  mirado com compensação de arco; o centro nunca mira abaixo de meia altura acima do chão (raspava e quicava, T29).
- Impulso = massa × velocidade perdida no 1º passo de física com contato em **corpos** (terreno não conta), dividido
  igualmente entre os corpos tocados no mesmo passo (atribuir tudo ao 1º relatado soltava a peça errada, T30). Peça
  presa solta quando impulso/massa ≥ Δv de quebra do material (pedra 6 m/s, madeira 4 m/s).

## D30. Água, Fogo e Ar: modelos de jogo, não simulação
- **Água (segurar):** raio por quadro da mão até 14 m; o 1º obstáculo para o jato. Força **absoluta** de 300 N no corpo
  atingido (caixa de 20 kg desliza ~5 m em 1,5 s; rocha de toneladas não se mexe) e WET 0,5/s com respingo de 1,2 m.
- **Fogo (toque):** bola simulada a 35 m/s, sem gravidade, raio por quadro, até 30 m (não é corpo físico, então anda
  por posição). HEAT 450 no corpo atingido + respingo de 2 m.
- **Ar (toque):** cone de 35° e 10 m, visada livre de **terreno** por raycast; impulso `min(massa × 12 m/s, 1500 N·s)
  × (1 − (d/10)²)` com componente para cima de 0,35: a mesma "pressão" dá Δv no teto à caixa e ~0,2 m/s a uma rocha de
  4 t. AIRFLOW com a mesma força: apaga fogo de intensidade < 0,35 sob vento > 0,5 e aviva o resto.
- Evento com `target` **e** `radius`: o alvo recebe a magnitude inteira e os outros corpos da esfera a queda linear pela
  distância ao centro da malha.

## D31. Estados de material e propagação
- Madeira 600 kg/m³ (ignição 300 °C, 12 s de combustível, resistência térmica 1); pedra/solo/areia não queimam
  (resistência 3/2/2). Secar umidade 1,0 custa 400 unidades de calor (`DRY_HEAT`): madeira molhada a 60% gasta a 1ª
  rajada secando (pela conta, com 100 a rajada de 450 acenderia mesmo molhada).
- Queima a cada 0,2 s: consome combustível e integridade, carboniza abaixo de 50% e aquece vizinhos num raio de 2,2 m
  a 200 °C/s × intensidade × queda (pela conta, com 1,8 m e 120 °C/s a caixa vizinha a 0,5 m de vão ganharia ~5 °C/s
  líquidos contra o resfriamento de 15 °C/s e não acenderia antes de a 1ª queimar até o fim).
  Teto de 48 corpos em chamas. Consumido → peça sai pelo `StructureService.consume_piece`
  (invisível, sem colisão, o grafo derruba o que dependia dela); caixa é liberada.
- Estados não são salvos (como destroços, D26); reset e carregar zeram tudo.

## D32. Torre mista e FX mínimos
- Os 8 blocos do 2º andar passam a ser de **madeira** (900 kg cada, antes 3,9 t de pedra). Queimar os 2 pilares da
  frente derruba as 2 placas de cima: a placa sem pilar ainda se sustenta como viga com 2 laterais apoiadas (D21), então
  um pilar só não basta.
- `ElementalFx`: chama por corpo em chamas (filha do corpo, teto 24), vapor ao apagar com água, carvão escurece o corpo,
  cilindro do jato, esferas das bolas de fogo, clarão e rajada. Sem arte: só sinaliza o estado.

## D33. Bateria do P3
- `scripts/dev/p3_selftest.gd` estende o do P2 (P0 + P1 + P2 + T28–T38); `tools/run_p3_tests.ps1` roda o spike de física
  do P3, P0 sozinho, o selftest P3 e a persistência entre processos pelo selftest P3 (`docs/evidence/p3/`).
- T37 aplica o critério de FPS do P2 (D27) ao pior caso do P3: colapso total + 12 caixas em chamas + os 4 poderes.
- A mira dos testes espera o braço de mola da câmera assentar (4 quadros): depois de um giro grande a câmera muda de
  posição no quadro seguinte e o raio passava ao lado da caixa (medido no T32).

## D34. Descongelar depois do salvar: esperar o apoio de cada corpo, não só "algum chão"
- Achado na 3ª rodada da bateria do P3 (`.exe` em janela): no T26 uma peça da coroa caída na borda de um buraco
  escorregou 0,51 m depois do salvar (parada durante o save; 0,005 m no controle sem save). A espera da D26 usava um
  único raio vertical pela origem do corpo, que numa peça sobre a borda podia ver o fundo do buraco já carregado.
- Agora, antes de recriar o terreno, cada corpo congelado registra quais de 5 raios curtos sob o fundo da malha (centro
  + 4 cantos recuados) tocam terreno; depois, só descongela quando esses mesmos raios tocam de novo (prazo de 3 s).
- **Não reproduzido:** em 5 rodadas isoladas do T26 (editor headless e janela, 3× no `.exe` em janela) a espera foi de
  0 quadros, e a peça que mais andou se moveu 0,003–0,05 m. A causa não está provada. Outra hipótese plausível são peças
  em equilíbrio precário que acordam todas juntas ao descongelar. A mudança não piora nada e fica.

## D35. P3.5: Terra em fases, parâmetros num recurso e ganchos de FX
- Fase aberta pelo usuário (26/10) só para game feel, peso, clareza e legibilidade em PvP da Terra, sem poderes novos.
- `EarthLiftThrow` virou máquina de fases: clique (valida o alvo) → antecipação → desprendimento → levantamento →
  hold → windup → recuperação; impacto separado por rocha em voo. Todos os tempos e forças ficam em `EarthTuning`
  (`data/abilities/earth_tuning.tres`), editável no inspetor.
- A base `Ability` ganhou o sinal `fx_event(kind, data)`: o poder anuncia o que JÁ fez, e `EarthFx`, câmera e HUD só
  leem (mesma regra do `ElementalFx`). O gancho também serve para áudio futuro.
- Decisões do usuário: alcance perto (2,5–7 m) com a rocha subindo no lugar; soltar antes de pronta guarda o
  lançamento; a rocha fica como destroço; impacto forte no chão abre cratera real.
- Sem hitstop e sem `time_scale`: em PvP isso é global. Os tempos são determinísticos a partir do clique.

## D36. Desprendimento: o Voxel Tools não decide quando a rocha solta
- O `separate_floating_chunks` cria o corpo com um `Timer` de 0,2 s ligado a `set_freeze_enabled` (spike P3.5 E1).
  `extract_rock(..., hold_kinematic = true)` para esse Timer: a rocha fica congelada no buraco até o fim do
  desprendimento.
- A confirmação de que o collider já tem a cavidade é um **raio no centro do buraco** que passa a ver o fundo
  (`TerrainService.cavity_confirmed`; 2 quadros, 23–26 ms). Uma consulta de forma não serve: o collider do terreno é
  uma casca, e uma rocha dentro do sólido não "sobrepõe" nada.
- O tremor e a subida de 0,35 m do desprendimento são de uma **cópia** da malha (a original fica escondida e parada).
  Mexer na malha original mudaria `body_center`, que a física usa.

## D37. Levantamento planejado e hold com peso
- Levantamento: trajetória vertical smoothstep até `hold_height` (2,0 m), seguida por PD (ω = 30) com aceleração de
  alimentação direta e teto de 600 m/s² (spike E3: sem sobressinal até 23 t em 160 ms). Giro leve por impulso angular.
- Hold: mola criticamente amortecida mais lenta que a do P3 (ω = 4,5, alimentação direta 0,6, teto 40 m/s²), balanço
  de ±5 cm a 0,7 Hz e amortecimento angular. Um giro de câmera de 90° leva ~1,2 s para a rocha assentar, sem
  sobressinal (T42). Jogador a 0,8× da velocidade enquanto ergue, segura ou lança.
- Tempos independentes da massa por padrão (justiça em PvP); `mass_time_scale` fica disponível.

## D38. Lançamento e impacto
- Windup de 60 ms (a rocha recua 0,3 m), impulso até 24 m/s com a compensação de arco e a mira consciente do chão do
  P3, e topspin. Recuperação de 200 ms antes de aceitar outro clique.
- Soltar o LMB antes de pronta guarda o lançamento, que sai ao entrar no hold com a mira daquele instante (toque curto
  = "arrancar e lançar" em ~440 ms).
- Contato com o terreno no primeiro 1,2 m de voo não conta como impacto: a rocha (malha de até ~3 m) raspava a
  borda do próprio buraco e a cratera saía ao lado do jogador (capturas do T45). Carência por distância, não por
  tempo: com 150 ms, um arremesso curto no chão à frente batia dentro da carência e o impacto se perdia (T39).
- Impacto no chão a ≥ 12 m/s abre cratera real de 0,7 m pela `TerrainBrushQueue` (D17), uma por arremesso. A cratera
  pode derrubar a torre se for sob um pé (consistente com o P2).

## D39. Centro do núcleo extraído alinhado ao meio do voxel
- Achado no selftest do P3.5 e medido no spike E5: com o centro em certas posições sub-voxel, a folga de 0,9 m (menor
  que um voxel) deixava uma ponte, o núcleo não se separava e ficava uma cavidade sem rocha (4 de 36 posições).
- `TerrainService._check_extract` alinha o centro do núcleo ao meio do voxel: 36/36 posições separam. A rocha muda até
  0,5 m por eixo. Vale para a Terra e para a extração de laboratório do P2 (R); T23/T24 seguem passando.

## D40. Telegraph e legibilidade
- **Visível a todos:** anel âmbar no chão e rachadura (decal procedural, sem assets) durante a antecipação e o
  desprendimento, antes de existir rocha (~210 ms de aviso). Depois vêm poeira e pedrinhas na cor do material, a
  rocha subindo e o windup.
- **Local (só o jogador):**
  - anel de prontidão em volta da retícula;
  - X vermelho em alvo inválido;
  - preview verde/vermelho do ponto de arranque;
  - tremor de câmera por trauma, que **não** mexe na mira (`get_aim_ray` usa o transform sem `h_offset`/`v_offset`)
    e é desligável (`shake_scale`).
- O marcador do pincel G/H fica escondido enquanto a Terra age (`marker_suppressed`): a esfera verde cobria a
  rachadura, o telegraph e a rocha.

## D41. Testes do P3.5 e dois achados de teste
- `scripts/dev/p35_selftest.gd` estende o do P3 (P0–P3 + T39–T45); `tools/run_p35_tests.ps1` roda o spike do P3.5
  e a bateria em `docs/evidence/p35/`.
- **Raio de 22 m do Jolt exatamente sobre uma aresta não acha nada.** Com x = −34,0 (inteiro) e direção x = −0,0, o
  raio de 22 m passa sobre a aresta compartilhada de dois triângulos e falhou em parte das rodadas, enquanto o mesmo
  raio com 200 m acertava. Os testes miram 0,17 m fora da grade. Um jogador quase nunca mira exatamente sobre uma
  aresta, então o jogo não muda.
- Depois de um teleporte de ~80 m, os dados ficam editáveis antes de o collider chegar: `_p3_lab` passou a esperar o
  collider sob e à frente do jogador.
- T29: o "só forças" virou detecção de teleporte (|Δx − v·dt| < 0,05 m, porque o Jolt integra x += v_nova·dt) no lugar
  do limite de passo de 0,5 m (o levantamento chega a 0,6 m/quadro). A caixa deslocada passou de > 2,0 para > 0,5 m:
  o choque às vezes é de raspão (medido 0,85–6,3 m), e o contato continua exigido.

## D42. P3.6: contrato de execução completo nos cinco runners
- `9788e7b` introduziu run_id, frescor e conclusão; a retomada completa isso com IDs explícitos por bateria, comparação dos resultados individuais, contadores tipados e coerentes, zero erros/avisos e diagnósticos de startup/shutdown no log. Nenhuma exceção ativa.
- Contratos em `tools/lib_selftest_contract.ps1`; testes negativos em `tools/test_selftest_contract.ps1`. Encerrar a janela com exit 0 continua sendo falha (exit 3). Evidências novas em `docs/evidence/p36/preparation/`, sem substituir as históricas.

## D43. Fechamento, interrupção e época das edições
- O T8 tinha causa geométrica real: `end_stroke` não cobria o resto até a última mira válida (corrigido em `08b6c6e`). A retomada também fecha restos menores que o espaçamento normal de carimbos.
- Perder o alvo encerra o segmento válido e quebra a continuidade. Segmentos separados não se fundem no backlog. Trocar ferramenta fecha explicitamente a anterior; reset/save/load cancelam sem segmento final e invalidam a época da fila. Pedido capturado antes da transição é rejeitado se reapresentado.
- Entrada mantida durante a transição fica bloqueada até soltar. A fila não aceita pedidos enquanto o serviço está indisponível.
- Teste direcionado T1/T8/T8b: 3/3, zero erros/avisos. Casos de perda da mira, cancelamento, troca e transições reais constam do relatório de preparação.

## D44. Raycast de arestas com testemunhas simétricas de 1 mm
- `08b6c6e` usava uma segunda consulta deslocada. Um único raio pode selecionar o colisor vizinho na silhueta. Agora `PhysicsRayHelper` compartilha o comportamento entre terreno e `aim_any`: primeiro o raio original; apenas se falhar, duas testemunhas transversais a ±1 mm.
- Fallback só aceito com mesmo RID, normais compatíveis (dot ≥ 0,95) e contatos a até 4 mm entre si. Máscara, exclusões e alcance preservados; ponto retornado é contato físico testemunha, até 1 mm fora do eixo.
- Amostra: 90/90 raios inclinados sobre coordenadas inteiras (6 recuperados pelo fallback), 100/100 através de parede de 1 mm e 100/100 seleções corretas em colisores adjacentes. Testes negativos rejeitam testemunhas de RIDs diferentes e contato unilateral; exclusão preservada.
- Não é prova universal. Em quinas de normais incompatíveis, fronteiras de RIDs ou detalhes menores que 1 mm, o fallback conserva a ausência de acerto. Custo máximo: duas consultas extras por raio que falha; comparar no baseline corrigido.

## D45. P3.6 M0: transporte e limites por elemento
Arquitetura, alternativas, medições, riscos, compatibilidade e critérios numéricos estão em docs/p36_m0.md. Água por pacotes evita transporte instantâneo ao girar; fogo mantém varredura com antecipação; ar usa frente/casca e exposição parcial. Nenhuma habilidade nova. GPU isolada e playtest humano não foram comprovados pelos spikes.

