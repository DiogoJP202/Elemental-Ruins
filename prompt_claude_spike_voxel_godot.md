# PROMPT DE IMPLEMENTAÇÃO PARA CLAUDE CODE — P0/P1, TERRENO VOLUMÉTRICO

Você é engenheiro sênior de jogos em **Godot 4.7.2 + GDScript**, com experiência em C++/GDExtension quando necessário. Trabalhará no projeto **ELEMENTAL // RUINS**, um sandbox 3D em terceira pessoa com dobra de elementos e **deformação volumétrica de terreno obrigatória** (crateras, túneis, escavação contínua, adição de matéria, pilares e rampas). A estética futura mistura clareza cel-shaded e visual low-poly retrô de modo original.

## Contexto e ordem de leitura
Leia antes de qualquer alteração:
1. `pesquisa_tecnica_elemental_ruins_godot_2026.md` — decisões e riscos técnicos atualizados.
2. `elemental_ruins_gdd_v02.md` — GDD integral atualizado; qualquer texto anterior contraditório foi substituído.
3. `avatar_atlas_poderes_sandbox.md` e `.json` — referência de técnicas, não conjunto de classes prontas.
4. `elemental_abilities_mvp.json` — planejamento, NÃO lista de tarefas imediatas.

## Restrição fundamental
**NÃO** substitua mundo escavável por `HeightMap`, decalque de cratera, malha que abaixa só a superfície, buracos de textura ou uma torre de cubos simples que fingem ser solo. O jogador deve conseguir cavar **um túnel atravessável por baixo da superfície**, com teto sólido e colisão atualizada, e alterar novamente a mesma região.

## Etapa P0 — investigação executável, bloqueante

1. Examine o diretório. Se já existe projeto Godot, preserve/registre estado antes de alterar. Use **Godot 4.7.2 estável** e Jolt **integrado** à engine (não instalar extensão Godot Jolt legada).
2. Verifique dependência. Prioridade: **Voxel Tools GDExtension 1.7** compatível com Godot 4.5+ e testar em **Godot 4.7.2**. Consulte releases: `https://github.com/Zylann/godot_voxel/releases` e instalação `https://voxel-tools.readthedocs.io/en/latest/getting_the_module/`. Se não funcionar, use build oficial custom da release `Godot 4.7.2.stable.custom_build + Voxel Tools 1.7`, verificando templates para export Windows. **Não invente APIs ou suponha que o plugin instalou**.
3. Configure cena técnica com `VoxelLodTerrain`, `VoxelMesherTransvoxel`, gerador SDF, `VoxelViewer` e colisão; `CharacterBody3D` com câmera orbitável por `SpringArm3D`, WASD/mouse/pulo. Não investir em modelo/arte antes da viabilidade.
4. Implemente `TerrainService` isolado de Voxel Tools: `dig_sphere(world_point, radius)`, `add_sphere(world_point, radius)`, `dig_path(points, radii)`, `smooth_area(...)`, `can_edit_area(...)`. Use APIs reais `get_voxel_tool()`, canal `VoxelBuffer.CHANNEL_SDF`, modo `VoxelTool.MODE_REMOVE/MODE_ADD`, `do_sphere`, `do_path`, `is_area_editable`. Converter mundo -> local. Verificar região carregada (LOD0) antes de editar. Registrar o resultado das chamadas.
5. Crie um minigame de engenharia sem poderes: tecla G = escavar, H = acrescentar terreno, J = túnel por pontos, Z = Reset. Mostre raio/mira e um indicador de sucesso/falha da edição. Restrinja a execução a áreas válidas e evite escavar um enorme volume por frame.
6. Verifique que *malha e colisões* refletem escavação e adição. Cavar no solo, entrar no buraco, abrir túnel horizontal sob colina, andar no teto de túnel e em rampa adicionada. Evite editar sob o jogador sem corrigir penetração.
7. Teste export Windows (se disponível) e import/parsing headless. Diga exatamente qual binário/versionamento/plugin foi usado, quais logs de execução existem e o que não pôde verificar.

**Gate P0 obrigatório:** cena abre, há piso voxel com colisões, remoção/adicionamento muda geometria e colisão, túnel subterrâneo atravessável, sem erros fatais. Se falhar, diagnosticar e CORRIGIR antes de prosseguir; não entregar falsa implementação.

## Etapa P1 — escavação contínua, materiais e reset
Somente após gate P0:
- `TerrainBrushQueue` agrega comandos de escavação contínua por intervalo espacial/temporal e limita AABBs editadas. Não fazer loop GDScript de todos voxels em cada frame.
- Material do terreno simplificado: `soil`, `stone`, `sand`, com propriedades `hardness`, `density`, `bendable`, `surface_color`. Não confundir tinta/texture weight com propriedade física.
- `TerrainChanged {aabb, revision}` informa reconstrução de suporte e efeitos visuais; *a confirmação de evento não garante collider atualizado no mesmo frame*.
- `WorldReset`: estado original do gerador e ausência de edições, não apenas recolocar o personagem no spawn. Escolha reset por sessão/stream limpo e teste 10 ciclos. Salvar via `VoxelStreamSQLite` pode ser P1.5, mas documente interface e teste se implementado.
- Overlay debug com FPS/tempo de quadro, edições pendentes, tamanho do último brush, corpos ativos e resultados de reset.
- Benchmarks: 100 escavações e 10 resets. Documentar latência de remesh/collider, memória e limites no PC de teste; NÃO declarar 60 FPS garantidos sem captura.

## Etapa P2 — preparar integração sem inventar desabamento
- Um objeto de teste (`RigidBody3D`) cai/repousa sobre solo escavável; testar atualização de contato após alterar o terreno.
- Torre modular com 2–4 apoios e peças convexas pré-fraturadas; a escavação sob suportes invalida suas âncoras de acordo com `SupportResolver` e permite que desabe.
- Testar `VoxelToolLodTerrain.separate_floating_chunks(AABB, parent_node)` **somente** em regiões pequenas e se a API específica existir nessa versão; medir custo. Se não for viável, usar extração controlada de volumes locais para alguns `RigidBody3D` como fallback e explicar a diferença.
- Limitar o número de fragmentos físicos e usar partículas/MultiMesh para cascalho cosmético.

## Não objetivos agora
- Não implementar SPH, todos os 214 poderes, multiplayer, mundo infinito, cavernas com enchente realista, shaders PS1 completos, árvores de habilidades ou combate.
- NÃO criar outra engine/browser/app web. NÃO alterar o objetivo para deformação de *heightmap*.
- Não instalar addons aleatórios; se uma dependência falhar, registrar alternativas e reportar.

## Condições de qualidade
- API usada deve ser verificada contra documentos reais de Voxel Tools 1.7/Godot 4.7.2.
- Não alterar física de `RigidBody3D` por `position` a cada frame; usar forças/impulsos apropriados.
- Testar colisão, input, export, reset e vida útil dos nós após reabrir cena.
- Separar *implementado e testado*, *implementado e não testado*, *não implementado*; nunca declarar sucesso por apenas gerar arquivos.
- Commits/marcos pequenos: P0 integração -> P0 deformação -> P1 brushes -> P1 reset -> P2 suporte.

## Entrega esperada
1. Diretório com projeto Godot executável e cenas testáveis.
2. `README.md` com versão exata de engine/addon, instalação, entrada na cena e controles reais.
3. `docs/voxel_spike_results.md` com provas de testes executados, logs e medições observadas (sem inventar números).
4. Código modular de terreno com API própria e testes manuais reproduzíveis.
5. Lista de bloqueios reais + próxima recomendação após P0/P1.

**Regra final:** o novo coração do sandbox é o terreno volumétrico. P0/P1 têm precedência absoluta sobre poderes e arte.
