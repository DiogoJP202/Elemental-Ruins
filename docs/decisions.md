# Decisões e trade-offs — P0

Registro das escolhas técnicas da primeira sessão (22/10/2026). Formato: decisão → motivo → consequência.

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
