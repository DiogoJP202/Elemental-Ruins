# ELEMENTAL // RUINS — Pesquisa técnica e arquitetura proposta
**Data de referência:** 22 de outubro de 2026  
**Objetivo:** sandbox 3D de poderes elementais, em terceira pessoa, estética original inspirada na legibilidade ilustrada de *Sable* e no retro 3D de *Mouthwashing*.  
**Novo requisito obrigatório:** o jogador pode **escavar e deformar livremente o terreno em volume** — túneis, crateras, trincheiras, cavernas, pilares, saliências e terrenos elevados — além de destruir construções e manipular fragmentos.

> **Estado da pesquisa.** Este é um documento de engenharia fundamentado em documentação oficial e repositórios públicos, não um benchmark ou protótipo já executado. Compatibilidade e desempenho de plugins são **hipóteses que precisam de validação local**. Valores de orçamento e limites abaixo são *metas experimentais propostas*, não números medidos. A implementação anterior de GDD/prompt deve ser atualizada: *simular crateras apenas com decals* não atende mais ao requisito.

## 0. Decisões resumidas

| Subsistema | Escolha recomendada | Por que | Grau de confiança |
|---|---|---|---|
| Engine | **Godot 4.7.2 estável**, GDScript, desktop Windows | Versão estável confirmada em outubro/2026; produtividade para protótipo | Alta para versão; instalação local pendente |
| Física 3D | **Jolt integrado** à Godot | Padrão de novos projetos desde 4.6, não requer plugin externo | Alta |
| Terreno | **Voxel Tools 1.7**, `VoxelLodTerrain` + `VoxelMesherTransvoxel` + canal SDF | Volumes escaváveis, túneis, overhangs, LOD, colisões, brushes e salvamento | Alta para capacidade; média para integração específica |
| Distribuição voxel | Testar **GDExtension 1.7** na Godot oficial; plano B **build custom 4.7.2 + Voxel Tools 1.7** | Há releases específicos listados, mas GDExtension é menos testada | Média |
| Construções | Blocos modulares + peças pré-fraturadas em `RigidBody3D` | Quebra previsível, colisões convexas e controle de orçamento | Alta |
| Terra solta | `separate_floating_chunks()` só em pequenas AABBs; peças grandes por regras próprias | Ferramenta integrada; custo cresce com região | Média |
| Água | Híbrido: jatos/ondas procedurais com colisões e estados, poças de volumes simples; SPH como *spike* independente | Água global fisicamente exata + mundo editável é desafio grande | Alta para decisão de escopo |
| Fogo | Temperatura/combustibilidade por objeto e grade esparsa de células, VFX separadas | Incêndio sistêmico sem CFD | Projeto proposto |
| Ar | Campos analíticos de forças, amortecimento e vórtices; partículas apenas visuais | Impactos previsíveis sobre corpos reais | Alta |
| Visual | **Forward+**, shaders simples toon + outline seletivo, preset retro com escala nearest-neighbor | Compute para ensaios de fluido, leitura de normais e 3D pixelado | Alta |
| Persistência | `VoxelStreamSQLite`, saves/versionamento e reset por snapshot do mundo | Terreno salvo em blocos modificados; reset de objetos em separado | Alta para API; método de reset a validar |
| Design | **Primeiro experimento técnico: escavação + colisão + reset**, antes de implementar catálogo de poderes | Risco maior e novo requisito do jogo | Muito alta |

**Bibliotecas e referências:** [Godot releases](https://godotengine.org/download/archive/), [Voxel Tools](https://github.com/Zylann/godot_voxel), [Voxel Tools releases](https://github.com/Zylann/godot_voxel/releases), [Voxel Tools instalação](https://voxel-tools.readthedocs.io/en/latest/getting_the_module/), [Godot/Jolt](https://godotengine.org/releases/4.6/).

## 1. Terreno totalmente deformável — investigação e escolha

### 1.1 Comparação de representação
- **Heightmap/Terrain3D:** grava apenas uma altura por par XZ. Excelente para montanhas e vales, texturas e LOD, mas não representa sozinho cavidades sobrepostas, túneis atravessando morros e ilhas flutuantes. O Terrain3D oferece pintura e *holes*, mas não muda essa limitação matemática: uma caverna exige malha adicional. [Terrain3D](https://github.com/TokisanGames/Terrain3D).
- **Voxel blocky:** cada célula guarda sólido/vazio; fácil de escavar e reconstruir, mas aparência cúbica não combina tão bem com as encostas suaves de Sable.
- **Voxel SDF (signed distance field) + Transvoxel:** armazena valores contínuos de proximidade à superfície; superfícies suaves são extraídas por malhas de chunks; permite acrescentar e remover volumes arbitrários, túneis, plataformas e penhascos. A geometria é reconstruída nas áreas editadas. **Escolhido**. [Visão geral](https://voxel-tools.readthedocs.io/en/latest/overview/), [início rápido](https://voxel-tools.readthedocs.io/en/latest/quick_start/).
- **CSG/booleanos contínuos:** útil para algumas construções isoladas, mas não recomendado como base de um mundo escavável e extensivo. A documentação da Godot alerta sobre custo de malhas de colisão detalhadas. [CSGShape3D](https://docs.godotengine.org/en/4.7/classes/class_csgshape3d.html).

### 1.2 Pipeline correto
1. `VoxelGenerator` define topografia determinística (deserto, ruínas como *props* e rochas). **Separar gerador base de alterações do jogador**.
2. `VoxelLodTerrain` carrega os blocos próximos, usa LOD para distância e `VoxelMesherTransvoxel` para as superfícies. `VoxelViewer` acompanha jogador/câmera e pede regiões de renderização e colisão.
3. Raio da câmera determina ponto de impacto no mundo; converter ponto mundial para coordenada local do terreno (`terrain.to_local(hit)`), verificar alcance, material, permissões e `is_area_editable`.
4. O comando (`REMOVE`, `ADD`, *smooth*, *stamp* ou path) é executado via `VoxelTool`, que altera dados, agenda reconstrução de malha e, quando habilitada, a colisão do terreno.
5. Somente após confirmar a edição, aplicar resíduos e reações (`MaterialEvent`), partículas, câmera, som e efeitos de mundo. Não simular cada voxel como `RigidBody3D`.
6. Separadamente, testar volumes independentes da massa sólida e converter alguns em corpos físicos; material removido pode virar um projétil ou estoque de massa no modo de regras.

**Pontos críticos:** edições fora da área carregada podem falhar. A documentação esclarece que, com LOD, só áreas próximas em nível 0 são editáveis; usar `VoxelTool.is_area_editable()`. Geometria e colisão são reconstruídas assincronamente, logo *visual* e *física* podem estar momentaneamente desatualizados. Empurrar o jogador para fora de novos volumes ou atravessar a colisão desatualizada exige políticas próprias de segurança. [VoxelTool](https://voxel-tools.readthedocs.io/en/latest/api/VoxelTool/), [scripting](https://voxel-tools.readthedocs.io/en/latest/scripting/), [LOD terrain](https://voxel-tools.readthedocs.io/en/latest/api/VoxelLodTerrain/).

### 1.3 Brushes iniciais — todos alteram dados reais

| Ferramenta | Operação voxel | Exemplo de dobra | Observação |
|---|---|---|---|
| Escavar/retirar | `MODE_REMOVE` + `do_sphere()` | Cratera, buraco, captação de rocha | Editar região local; custo conforme raio/chunks afetados |
| Construir/erguer | `MODE_ADD` + `do_sphere()` / `do_box()` | Coluna, barreira, rampa | *Adicionar matéria* não a desloca automaticamente de outro lugar |
| Escavar túnel | `MODE_REMOVE` + `do_path()` | Abrir passagem subterrânea | Permite tubo contínuo; custo proporcional ao trajeto |
| Moldar gradualmente | `grow_sphere()` / `smooth_sphere()` | Elevar colina, suavizar margens | Limitar frequência e dimensões da operação |
| Moldar forma específica | `do_mesh()` / `do_graph()` | Domo, trincheira especializada | Mais complexo; validar performance |
| Pintar matéria | `MODE_TEXTURE_PAINT` | Rocha → areia/solo visual | **Pintura não altera automaticamente a física do material** |

**Esqueleto de chamada GDScript para revisar e validar no protótipo** (não é prova de execução):

```gdscript
# Script em nó que mantém referências válidas ao VoxelLodTerrain.
@export var terrain: VoxelLodTerrain

func dig_world_point(world_point: Vector3, radius: float) -> bool:
    var local_point: Vector3 = terrain.to_local(world_point)
    var tool: VoxelTool = terrain.get_voxel_tool()
    tool.channel = VoxelBuffer.CHANNEL_SDF
    tool.mode = VoxelTool.MODE_REMOVE
    var extent := Vector3.ONE * radius
    var affected_region := AABB(local_point - extent, extent * 2.0)
    if not tool.is_area_editable(affected_region):
        return false
    tool.do_sphere(local_point, radius)
    return true
```

**Detalhes ainda a verificar em Godot local:** unidade de tamanho dos voxels; coordenadas da `VoxelLodTerrain` se houver transformação; método de escolher apenas substratos permitidos; precisão real do AABB; sincronia das colisões com alterações; variações da API entre distribuição módulo/GDExtension. Evitar escala não uniforme no nó do terreno. [Terrenos suaves](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/).

### 1.4 Ilhas flutuantes, desmontagem e conservação de matéria
- **Pequenos blocos destacados:** `VoxelToolLodTerrain.separate_floating_chunks(AABB, parent_node)` encontra componentes desconectados **inteiramente contidos** naquela AABB e os converte em corpos físicos convexos. A documentação recomenda áreas de cerca de 30 voxels; não chamar em todo o mapa, nem a cada frame. [API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelToolLodTerrain/).
- **Grandes partes de montanhas:** não esperar desabamento global emergente sem implementar análise de conectividade/apoio. Alternativas: recortar volumes menores, eventos roteirizados para massas grandes, simulação simplificada de queda de talude e limites de deslocamento.
- **Conservação de matéria — decisão de gameplay:** no *Creative Mode* material é ilimitado. No *World Rules Mode*, cada `REMOVE` bem-sucedido acumula `VolumeToken` estimado (densidade×volume retirado); `ADD`, pedra levitada e projéteis o consomem. Medir volume exato de isosuperfícies a cada frame é caro: contabilidade aproximada por célula/brush basta para protótipo. Um bloco levantado não deve coexistir com uma cópia intacta no solo se modo de conservação estiver ativo.
- **Terrenos diferentes:** voxels SDF representam forma; tipo de matéria e propriedades podem vir de mapas/canais próprios e shader. Não presumir que alterar um índice de textura transforma granito em ferro ou muda dureza.

### 1.5 Salvamento, reset e estado
- `VoxelStreamSQLite` grava voxels modificados em arquivo único, em carregamento/gravacão por blocos; `save_modified_blocks()` agenda operações assíncronas. [Streams](https://voxel-tools.readthedocs.io/en/latest/streams/).
- No protótipo, optar por **mundo-base determinístico + arquivo de save temporário por sessão**. **Reset**: descarregar/limpar alterações e recarregar gerador/stream novo ou reabrir cena com dados temporários descartados; documentar procedimento e confirmar em jogo. Não inventar chamada `reset_world()` da biblioteca.
- Salvar também estruturas, fragmentos persistentes, estados térmicos e reservatórios em um `WorldSave` separado. O stream de voxels sozinho não guarda todos esses sistemas.
- **Repetição de reset:** 10 ciclos, confirmar que geometrias, colisões, arquivos, estados e contagem de nós retornam ao baseline.

## 2. Estruturas e física de impacto

### 2.1 Três camadas de destruição
1. **Terreno sólido estático**: superfície SDF reconstruída e collider estático por chunks. A volumetria não significa que todo terreno está fisicamente móvel.
2. **Arquitetura modular**: pilares, blocos, tábuas e telhas usam peças e conexões com `integrity`, `weight`, `anchors` e `support_links`. Uma peça sustentada por terreno verifica se sua base continua apoiada depois da escavação. Colapso causa ativação sequencial de `RigidBody3D`.
3. **Poeira e cascalho decorativo**: MultiMesh e partículas GPU sem centenas de corpos dinâmicos. Alguns fragmentos próximos são físicos; a maioria dos cacos de fundo é visual.

**Colisões:** `ConcavePolygonShape3D` destina-se sobretudo a geometria estática; `ConvexPolygonShape3D` ou formas primitivas para destroços móveis. O Jolt integrado é padrão em novos projetos desde Godot 4.6. [Concave](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html), [Jolt](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html).

### 2.2 Construções prontas versus fratura em runtime
- **Preferir** pré-fratura: Blender Cell Fracture → glTF de grupos de pedaços → Godot. Cada conjunto mantém mesh intacta para renderização barata e cena de fragmentos pré-preparada que substitui o modelo em ruptura. [Jummit destruction plugin](https://github.com/Jummit/godot-destruction-plugin) demonstra esse pipeline, mas avisa ter sido testado só em cenas pequenas; **referência de técnica, não dependência obrigatória**.
- **Alternativa** VoronoiShatter gera peças no editor e serve para investigar workflow; não usá-lo para fragmentar malhas enormes em runtime sem benchmark.
- **Links de suporte:** em estrutura pequena, cada peça contém ligações para outras e *anchors* ao terreno. Se sustentação cair abaixo de um limiar, ativar corpo rígido. Em grandes torres, avaliar conectividade por grupos de módulos em vez de visitar todas as peças a cada frame.
- **Impactos:** `apply_central_impulse()` para golpe instantâneo; `apply_central_force()` para vento e jatos sustentados. Impulsos aplicados a cada frame produzem aceleração incorreta dependente de taxa de atualização. [RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html).

### 2.3 Escavar abaixo de objetos
1. O sistema de terreno registra `TerrainChanged{AABB, revision}`.
2. `SupportResolver` identifica pilares/estruturas cuja base ou região de apoio intersecta AABB.
3. Aguarda/faz polling de atualização de colisão quando necessário, confirma `ground_contact` com consultas físicas e/or SDF.
4. Desativa âncoras invalidadas; componentes perdem integridade/estabilidade; libera corpos em lote sob limite.
5. Poeira + áudio + tremor seguem o **evento de quebra real**, não o contato de um VFX.

Evitar eventos de destruição em cascata infinitos; usar fila por prioridade e limite por tick.

## 3. Água, fogo, ar e terra — física, não somente efeitos

### 3.1 Terra — núcleo do jogo
- **Geometria:** CRUD de matéria em SDF; escavação, adição, suavização, túnel, coluna, muro, vala, elevar área, abrir rachadura.
- **Objetos móveis:** decolar rocha pela extração de região que desaparece do terreno e cria `RigidBody3D`/corpo controlado por forças; lançamento respeitando massa e impulso.
- **Subdobras:** areia = fricção e partículas granular simplificada; metal = itens etiquetados `bendable_metal`, não deformar todas as malhas automaticamente; lava = campo térmico e representação volumétrica simplificada com dano no contato; vidro = quebra frágil.
- **Questão da física:** só uma porcentagem do material removido vira objeto real; a maior parte pode ser inventário de massa ou cascalho decorativo (especialmente em modo criativo).

### 3.2 Água — 3 fidelidades
**Nível A, recomendado para primeiro jogo:** jatos por splines/meshes deformadas, volumes rígidos de água, `Area3D` para contato e forças, marcador de umidade em `MaterialState`. Volume visual é aproximado, não SPH. Suporta apagar fogo, golpear peças, empurrar, congelar e evaporar por regras.

**Nível B, depois:** células de fluxo simplificado sobre a superfície / reservatórios independentes, poças com `Area3D`, volumetria em cubas e cavernas pequenas; amostrar voxel SDF para encontrar fronteiras e impedir ocupar matéria sólida. Para túneis verticais/água em salas sobrepostas, uma grade 3D/simulador por regiões pode ser necessária; *shallow water 2D* isolado não resolve todos os casos.

**Nível C, experimento autônomo:** addon [3D SPH Fluid Simulation](https://godotengine.org/asset-library/asset/5116) (1.0.1, Godot 4.6, MIT, 2026-05-04), com compute GPU, *spatial hashing* e colisões SDF descritas pelo autor. **Requer prova**: atualizar colisão de fluido quando voxel muda; custo de GPU/transferência; exportação 4.7.2; delimitação e *readback* físico para objetos. A ficha informa capacidade nominal 32k+, mas não é benchmark reproduzido neste estudo. Outra opção é PBF comercial para comparação futura, sem torná-lo dependência.

**Limitação fundamental:** `GPUParticles3D` não são água física. Suas partículas vivem na GPU e não compartilham automaticamente o mundo de colisões da física; `GPUParticlesCollisionSDF3D` precisa de bake e **não acompanha terreno que muda em runtime**. Usar partículas para aparência, sistema próprio para líquidos. [Particle collision](https://docs.godotengine.org/en/4.7/tutorials/3d/particles/collision.html).

### 3.3 Fogo — sistema de temperatura e propagação
Estados principais: `temperature`, `heat_capacity`, `ignition_temperature`, `flammability`, `fuel`, `moisture`, `burning`, `conductivity`, `structural_integrity`. Cada objeto/fragmento guarda propriedades; regiões do mundo com vegetação podem usar grade esparsa, não nós para cada grama de madeira.

Regra: `heat_event` transfere calor; se combustível disponível e temperatura ultrapassa limiar, acende; chama acumula calor nos vizinhos expostos; consome combustível e danifica apoio; umidade e água retiram calor; vento altera intensidade e chance de transmissão. **Não é solver real de combustão**, é simulação de jogo por transições de estados e eventos.

Fogo não deve fazer toda rocha virar lava: lava é modo/técnica específica de grande intensidade. Para ataques de relâmpago futuros, condutividade e umidade podem produzir propagação no grafo de objetos/poças, sem simular equações de Maxwell.

### 3.4 Ar — campo vetorial
Campos espacialmente avaliados quando ativo: `AirField(position, radius, shape, strength, falloff, direction, swirl, lift, lifetime)`. Em cada passo de física, detectar corpos próximos e aplicar `F = m*a_desired*falloff`, com teto de impulso/velocidade; para vortex, combinar componente tangencial + centrípeta + vertical. Obstáculos precisam bloquear/atenuar o campo conforme raycast ou lógica de visibilidade.

**Pegadinha concreta:** o parâmetro de vento em `Area3D` aplica-se somente a `SoftBody3D`, segundo a documentação da Godot, **não empurra automaticamente `RigidBody3D`**. Para caixas e destroços precisamos aplicar forças explicitamente. [Area3D](https://docs.godotengine.org/en/4.7/classes/class_area3d.html).

### 3.5 Contrato universal de interação
Manter `AbilityCommand -> ElementalEvent -> WorldReaction -> VFX/SFX`. A fonte única do estado é o servidor/sistema que detém o material, não o shader.

```text
InputIntent {player, ability_id, aim_world, pressed, held, released}
    -> AbilityController (validar alcance, fonte, custos e intensidade)
    -> ElementalAction (shape, move, heat, cool, push, wet)
    -> TerrainService / RigidBodyService / MaterialReactionService
    -> WorldEvents {terrain_changed, body_impulsed, state_changed, structure_broken}
    -> FXManager + AudioManager + CameraFeedback + SaveSystem
```

Distinguir `MaterialDefinition` (densidade, durabilidade, reação), `MaterialInstanceState` (calor, umidade, rachaduras), `TerrainMaterialLayer` (textura e tags por região), `ElementalPayload` (calor, força, umidade) e `EffectView` (partículas). Não usar composição química fisicamente rigorosa como requisito.

### 3.6 Matriz resumida de reações (sistêmicas)
- Terra + rocha: remove/eleva/recorta volume, movimenta fragmentos, afeta pontos de apoio.
- Terra + areia: deixa superfície com menor atrito e cria poeira, muda visual da areia.
- Terra + água: solo úmido/lamacento; atrito baixo; alteração de textura.
- Terra + gelo: impacto fratura gelo conforme material, não pedra.
- Água + fogo: reduz temperatura, apaga se calor/fuel/fluxo permitirem; gera vapor.
- Água + gelo: congela volumes discretizados ou construções de gelo com colisão.
- Água + metal: umidade afeta condução futura (modelo de jogo, não condução elétrica rigorosa).
- Água + terra: jato erode solo sob limiar energético alto, com alteração SDF **somente** se habilitado; não toda gota escava.
- Fogo + madeira: chama persistente, perda de integridade, queda da estrutura.
- Fogo + gelo: derrete e transfere volume para água disponível; vapor se calor adicional.
- Fogo + água: evaporação local e efeito visual de vapor; conservar apenas estimativamente a massa.
- Ar + fogo: desvia chama; ar forte pode apagar foco pequeno, vento moderado espalha.
- Ar + água: desloca jato/projétil; levanta spray visual ou aplica força ao volume simplificado.
- Ar + poeira/areia: partículas reagem ao campo; a névoa torna visível o fluxo.
- Impacto + pedra: danos/rachaduras/fragmentos e escavação se energia atingir terreno elegível.
- Impacto + ponte: perda de integridade e apoio; liberar fragmentos.
- Lava + água: resfriamento, material solidificado definido por regra, vapor e fragmentação térmica.
- Relâmpago + água: propagação discreta pelo grafo de regiões molhadas (etapa futura).
- Frio + vapor: condensação local em gotículas/névoa (etapa futura).
- Frio + terra úmida: solidificação/endurecimento de superfície (etapa futura).
- Combustão + oxigênio/vácuo: supressão no campo de vácuo (etapa futura; contexto de lore diferenciado).

## 4. Controles, animação e sensação de poder

### 4.1 Câmera e movimentação
Usar `CharacterBody3D`, `SpringArm3D`, `Camera3D`, *aim assist* local, InputMap. O `SpringArm3D` move a câmera para a frente ao encontrar obstáculos, reduzindo *clipping*. [Camera Godot](https://docs.godotengine.org/en/4.7/tutorials/3d/spring_arm.html).

**Controles padrão propostos:** WASD mover, Shift correr, Espaço pular, mouse orbitar. 1/2/3/4 elemento; Q/E alternar técnica; LMB apontar/iniciar ou carregar, soltar executa; RMB entrar em modo de manipulação; roda com RMB controlar distância; F recolher objeto/volume elegível; Z reset; Tab ajuda; T câmera lenta de **jogo**. Modo criativo evita consumo e libera escalas de poder, mas não pula validação técnica de alcance/volume carregado.

### 4.2 Máquina de estados de habilidade
`IDLE -> AIMING -> ACQUIRING -> HOLDING -> SHAPING -> RELEASING -> RECOVERY -> IDLE`. Nem toda técnica exige todos os estados; parametrizar transições.

- **Extrair e levitar rocha:** mira pega ponto da superfície; manter botão remove pequena região do terreno e instancia objeto com massa; `HOLDING` aplica força amortecida (PD: proporcional ao erro e à velocidade) para objeto acompanhar um alvo na frente da câmera; release aplica impulso físico uma vez.
- **Coluna:** manter define altura/raio; editar terreno em passos controlados, não um `do_sphere()` para cada frame visual; animação de ascensão pode antecipar/acompanhar malha enquanto colisão se atualiza.
- **Escavar:** modo contínuo faz *sampling* ao longo do arrasto com intervalo espacial e temporal, alimenta fila coalescida de brushes; impede 60 reconstruções simultâneas sobre os mesmos chunks.
- **Jato d'água:** evento sustentado a cada passo de física, `Area3D`/raycasts e spline visual.

### 4.3 Animação e câmera
`AnimationTree`/AnimationPlayer para antecipação, sustentação, execução e recuperação; eventualmente IK/procedural arms apenas após controls estarem estáveis. Proporções iniciais **para afinação**, não fatos: pre-cast leve 80–180ms; telecinese mantém easing curto; impacto pesado tem abalo de câmera de baixa amplitude e duração ~100–250ms; *hitstop* opcional extremamente curto **apenas para impacto pontual**, jamais congelar rigid bodies durante uma simulação complexa sem teste. Áudio em 3 camadas: início de energia, deslocamento e impacto.

**Game feel como teste:** jogador distingue golpe leve e pesado sem UI; força não parece igual em bloco pequeno e torre; camera shake não atrapalha precisão de escavação; feedback tem leitura de direção e material.

## 5. Identidade visual: Sable + Mouthwashing, com identidade própria

**Modo ILUSTRADO:** malha low-poly estilizada, paleta pastel-terrosa, toon em 2–3 bandas, contorno seletivo em personagem/alvos, sombras duras moderadas e névoa suave. Cuidado com outline global desenhando cada aresta de pequenas pedras e tornando cenário ilegível.

**Modo RETRO:** mesma cena, texturas filtradas com nearest, opção de pixels grandes, 15-bit/quantização leve e dithering, granulação discreta e *vertex wobble* opcional somente em detalhes, não no chão escavável/na mira (para não causar trepidação de geometria física). Preferir recurso de escala 3D nearest introduzido na Godot 4.7, preservando UI 2D em resolução nativa. Não é obrigatório criar `SubViewport` para a opção retro. [Godot 4.7](https://godotengine.org/releases/), [resolução 3D](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html).

**Shading:** leitura de textura de profundidade e normal-rugosidade exige cuidados; textura normal/roughness está disponível em Forward+ e não em todos renderizadores. Outline pode ser por expansão invertida em malhas específicas ou por pós-processamento de profundidade/normais. Godot usa *reverse-Z*; shader copiando fórmula antiga pode quebrar. [Screen-reading](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html), [postprocessing](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html).

**Pesquisa útil para avaliar, não instalar cegamente:** [Ultimate Retro Shader Collection (MIT)](https://godotengine.org/asset-library/asset/2989) e [PSX Shader de Francisco Cidade, CC0, testado em Godot 4.6, marcado instável](https://store.godotengine.org/asset/fcidade/psx-godot-shader/). Usar como referências de técnicas — estética própria e compatibilidade real precedem pacote pronto.

**VFX de física:** 95% dos grãos/poeiras poderiam ser visuais por GPU (valor ilustrativo, não alvo fixo); poucos destroços realmente sólidos. Para fumaça em túneis alterados, `GPUParticlesCollisionHeightField3D` vê principalmente superfícies superiores e ignora teto de cavernas; `GPUParticlesCollisionSDF3D` é baked e não atualiza ao escavar. Usar colisões primitivas locais, partículas de curta duração, ou sistema customizado se desejar interação volumétrica precisa. [Particle collision](https://docs.godotengine.org/en/4.7/tutorials/3d/particles/collision.html).

## 6. Desempenho, arquitetura de filas e perfilamento

### 6.1 Custos dominantes previstos
1. **Meshing/recriação dos colliders de voxels**, potencialmente mais caro que a alteração SDF em si.
2. Muitos `RigidBody3D` acordados e contato entre pedaços empilhados.
3. Shader/pipeline compilation e partículas em sobreposição.
4. *Overdraw* de água, fumaça e partículas.
5. Chamadas GDScript *voxel-a-voxel* e frequentes reconstruções nos mesmos chunks.
6. Chunks gerados/destruídos ao se mover rapidamente; Voxel Tools relata picos por destruição de buffers e oferece mitigações: blocos de mesh 32 versus 16, menor distância LOD e velocidade de deslocamento sensata.

A documentação do Voxel Tools identifica explicitamente o alto custo de colliders e recomenda operações em lote (`do_sphere`, `do_box`, `copy/paste`), em lugar de loops intensivos por voxel. [Performance Voxel Tools](https://voxel-tools.readthedocs.io/en/latest/performance/).

### 6.2 Política de escalabilidade
- Aplicar brushes por lotes e por distância percorrida (por exemplo, no máximo um grande comando de escavação por região a cada X ms definido por benchmark); agregar chamadas enquanto o mouse está parado.
- Descartar/adiar cosméticos antes de reduzir fidelidade de colisão perto do jogador.
- Limitar `RigidBody3D` ativos; depois de repousar, adormecer/congelar se apropriado; objetos muito distantes converter para instância visual ou descartar se não persistente.
- `MultiMeshInstance3D` para cacos decorativos repetidos (eficiente para draw calls, **não** substitui física por objeto).
- Desativar simulação detalhada de incêndio/água fora da vizinhança ativa; usar eventos agregados e estado salvo.
- Delegar trabalho nativo ao Voxel Tools e física Jolt; GDScript como orquestrador. Não editar SceneTree/recursos compartilhados sem sincronização a partir de threads.
- Desenhar HUD só após renderização do mundo retro, para legibilidade.

### 6.3 Metas de primeiro benchmark (valores arbitrados para validar)
**Máquina e cena alvo devem ser registradas antes de medir.** Primeiro testar Godot 4.7.2 no hardware de desenvolvimento. Esperar **60 FPS a 1080p** no *vertical slice*, tempo médio <= 16,7 ms/quadro, percentil 99 de frame time registrado e picos durante edição documentados. Se não bater, ajustar distância de visão, número de corpos e taxa de edição.

| Cenário de carga | Exercício | Resultado de aprovação inicial sugerido |
|---|---|---|
| Solo livre | Andar 60s no cenário antes de editar | Não há clipping visível ou microtravamentos frequentes |
| Escavação | 100 operações de remoção em raios pequeno/médio | Sem buracos gráficos persistentes, erros ou aumento contínuo de memória |
| Túnel | `do_path()` abrindo passagem 20–40 m | Jogador passa por dentro; colisões atualizam; teto existe |
| Edificação | Retirar o suporte de torre de 30–60 componentes | Desaba em etapas, sem explosão numérica da física |
| Pico de fragmentos | 50/100/200 corpos ativos, comparando números | Limiar escolhido pelos perfis, sem alegar 200 garantidos |
| Fogo/água/ar | 20s de efeitos mistos sustentados | Estados coerentes, gameplay responsivo |
| Reset | 10 ciclos de deformação / colapso / reset | Estado e memória retornam perto do baseline |
| Salvar/carregar | Escavar e reiniciar o executável | Geometria, colisão e props persistem conforme design |

**Observabilidade:** debugger/profiler da Godot, Monitors (FPS/frame time, physics, memória), overlay de desempenho com `active_bodies`, `voxel_edits_queued`, `collider_updates_pending`, `debris_visual_instances`, `field_updates`, `fire_cells`, `water_cells`, `save_pending`. Não atribuir custo de GPU a um evento sem profiler/GPU capture. [Performance](https://docs.godotengine.org/en/4.7/tutorials/performance/), [Physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_quick_start_guide.html).

## 7. Projeto Godot — módulos recomendados

```text
scenes/
  main.tscn
  player/player.tscn
  world/voxel_lab.tscn
  world/buildings/tower_test.tscn
  props/breakable_part.tscn
  ui/sandbox_hud.tscn
scripts/
  world/terrain_service.gd          # abstrai VoxelTool e origem/coordenadas
  world/terrain_brush_queue.gd      # batch, edição, revision e zonas carregadas
  world/terrain_support_probe.gd    # avisa perda de sustentação
  world/terrain_save_service.gd     # salva/reset de dados de terreno
  physics/destruction_service.gd   # orçamento e ativação de RigidBodies
  physics/structure_integrity.gd   # peças/apoios/grafo
  physics/air_field_service.gd      # forças analíticas sobre corpos
  physics/water_volume_service.gd   # fontes/volume simplificado
  systems/material_response.gd      # temperatura, umidade, dano
  systems/fire_grid.gd              # propagação em eventos/ticks espaçados
  systems/elemental_event_bus.gd    # eventos do mundo
  ability/ability_controller.gd
  ability/abilities/earth_dig.gd
  ability/abilities/earth_raise.gd
  ability/abilities/earth_extract.gd
  ability/abilities/water_jet.gd
  ability/abilities/fire_burst.gd
  ability/abilities/air_burst.gd
  player/player_controller.gd
  player/third_person_camera.gd
  fx/fx_manager.gd
  fx/audio_feedback.gd
  fx/camera_feedback.gd
  dev/debug_overlay.gd
  dev/benchmark_scenarios.gd
resources/
  material_profiles/             # tipo, calor, densidade, dureza
  ability_definitions/           # configurações reusáveis
addons/
  zylann.voxel/                 # apenas se GDExtension foi validada
saves/                            # editor/testes; no export usar user://
```

**Interfaces propostas** (contratos *nossos*, não classes existentes da Godot):

```text
TerrainService.request_brush(TerrainBrushRequest) -> EditTicket
TerrainService.query_material(world_point) -> MaterialSample
TerrainService.try_extract(world_volume, mode) -> MassTicket
TerrainService.subscribe_terrain_changed(callback)
StructureService.on_terrain_changed(aabb, revision)
MaterialResponse.apply(event, target) -> MaterialTransition[]
ForceFieldService.register(field, duration)
WaterService.request_volume(source, amount) -> WaterTicket
WorldReset.reset_to_seed(seed, clear_edits=true)
WorldSave.request_save(slot)
```

**Não construir o atlas de Avatar dentro desses serviços:** atlas é taxonomia e referência. Cada habilidade aponta para um conjunto de operações físicas implementadas e testadas. O gênero sandbox se beneficia de operações universais combináveis.

## 8. Plano de experimentos — ordem é deliberada

### P0 — Certificar ferramenta voxel (bloqueante)
**Entregas:** abrir Godot 4.7.2 estável + Voxel Tools 1.7 GDExtension; se falhar, testar custom build 4.7.2 + módulo 1.7. Cena com `VoxelLodTerrain`, `VoxelMesherTransvoxel`, `VoxelGeneratorNoise`, `VoxelViewer`, câmera/personagem; terreno sólido com colisão; `is_area_editable` e `do_sphere` operacionais. **Provar também export Windows**.

**Aceite:** jogador caminha no terreno; tecla escava 2–3 m; tecla adiciona volume; ambos alteram malha *e* colisão, sem crash; logs de versão/plugin/caminho escolhido. **Não passar a P1 sem isso**.

### P1 — Laboratório de terreno (o verdadeiro alicerce)
**Entregas:** brushes `REMOVE/ADD/PATH/SMOOTH`, sequência de edições em lote, editor no modo sandbox, `TerrainChanged`, perfis básicos `soil/stone/sand`, reset. Túnel, cratera, rampa e pilar com jogador caminhando em cima/dentro; *ghost collision* tratada ou explicitada. Salvar/reabrir opcional no fim.

**Aceite:** cavar túnel atravessável, construir uma coluna, escavar 100 vezes, reset 10 vezes sem perda de controle.

### P2 — Destruição e extração
**Entregas:** torre com bases ancoradas ao terreno, extração de pequenas rochas e alguns `RigidBody3D`, `separate_floating_chunks` limitada por AABB, dano e suporte, poeira decorativa. **Aceite:** escavar embaixo da torre leva ao colapso; remover rocha gera peça que pode ser arremessada; caps e perfis visíveis.

### P3 — Vertical slice dos quatro elementos
**Terra:** escavar/erguer/extrair. **Água:** jato que molha e extingue. **Fogo:** rajada aquece e queima. **Ar:** campo que empurra fragmentos e desvia fogo. HUD, feedback áudio/animação, modo criativo. **Aceite:** sequência transversal de 20s modificando permanentemente cenário/props, reset correto.

### P4 — Visual e extensão
Dois presets visuais, toon/PSX discreto, 16 habilidades progressivamente, água pooling, lama, gelo, areia, lava, relâmpago e SPH experimental isolado. Não liberar 16 habilidades só porque aparecem no menu; implementar mecânica física antes.

## 9. Matriz de riscos e decisões em aberto

| Risco | Prob. | Impacto | Mitigação | Critério de parada |
|---|---|---|---|---|
| Voxel Tools não abre/exporta em 4.7.2 | Média | Bloqueante | Testar 1.7 GDExt; fallback custom 4.7.2; congelar versão validada | Se ambas falharem, implementar pequena grade voxel piloto ou escolher outra versão suportada antes de codificar habilidades |
| Colisão demora após escavar | Alta | Alta | Brush queue + controle de revisão, bloqueio de movimento local se necessário, testes P1 | Persistência de collider antigo longa/sem solução aceitável |
| Fragmentos demais | Alta | Alta | Corpos limitados, pooling e MultiMesh | Queda contínua abaixo da meta em cenário P2 |
| Desabamento global de montanhas | Alta | Muito alta | Limitar detecção regional, abstrair grandes colapsos por eventos | Desabamento geral da topografia fora do primeiro escopo |
| Fluido SPH não acompanha voxel dinâmico | Alta | Alta | Água nível A/B; SPH só P4 com contrato | Não ligar SPH ao core se readback/colisão falhar |
| Save + reset divergentes | Média | Alta | Stream SQLite por sessão/slot + reinicialização comprovada | Reset não reproduz o estado inicial após 10 ciclos |
| Visual retro prejudica mira | Média | Média | HUD nativa e modo Ilustrado limpo | Retículo ilegível, dificuldade de selecionar terreno |
| Vibe coding gera APIs imaginárias | Alta | Alta | Consultar docs e chamar Godot headless + smoke tests após marcos | Nunca aceitar implementação apenas pela existência de arquivos |

## 10. Fontes primárias e links para implementação
1. Godot arquivo releases 2026 (4.7.2 estável; 4.8 beta): https://godotengine.org/download/archive/
2. Anúncio Jolt default: https://godotengine.org/releases/4.6/
3. Voxel Tools repo: https://github.com/Zylann/godot_voxel
4. Voxel Tools releases, incluindo 1.7 custom 4.7.2 e GDExt 1.7: https://github.com/Zylann/godot_voxel/releases
5. Voxel Tools instalação e diferenças de builds: https://voxel-tools.readthedocs.io/en/latest/getting_the_module/
6. Voxel Tools quick start `VoxelLodTerrain`: https://voxel-tools.readthedocs.io/en/latest/quick_start/
7. VoxelTool API, modos/bulk editing: https://voxel-tools.readthedocs.io/en/latest/api/VoxelTool/
8. VoxelToolLodTerrain API e floating chunks: https://voxel-tools.readthedocs.io/en/latest/api/VoxelToolLodTerrain/
9. Voxel Tools performance (colisões/remesh/threads): https://voxel-tools.readthedocs.io/en/latest/performance/
10. Voxel tools views e terreno suave: https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/
11. VoxelStreamSQLite/save: https://voxel-tools.readthedocs.io/en/latest/streams/
12. Terrain3D heightmaps e holes: https://github.com/TokisanGames/Terrain3D
13. Godot concave collision: https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html
14. Godot Using Jolt: https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html
15. Godot RigidBody3D: https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html
16. Destruction plugin exemplar: https://github.com/Jummit/godot-destruction-plugin
17. Godot 3D SPH fluid asset: https://godotengine.org/asset-library/asset/5116
18. Godot GPU particle collision: https://docs.godotengine.org/en/4.7/tutorials/3d/particles/collision.html
19. Godot Area3D: https://docs.godotengine.org/en/4.7/classes/class_area3d.html
20. Godot SpringArm3D: https://docs.godotengine.org/en/4.7/tutorials/3d/spring_arm.html
21. Godot 4.7 release overview including nearest 3D scaling: https://godotengine.org/releases/
22. Godot resolution scaling: https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html
23. Godot screen-reading shaders: https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html
24. Godot perf overview: https://docs.godotengine.org/en/4.7/tutorials/performance/
25. Godot interp physics: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_quick_start_guide.html
26. Godot shaders PSX (referência, marcado instável): https://store.godotengine.org/asset/fcidade/psx-godot-shader/
27. Ultimate Retro Shader Collection: https://godotengine.org/asset-library/asset/2989
28. Godot GPUParticles vs simulação física: https://docs.godotengine.org/en/4.7/tutorials/3d/particles/collision.html

## 11. Checklist de descoberta ainda não resolvida por pesquisa documental
- [ ] **Instalação real** de Godot 4.7.2 + Voxel Tools 1.7 (GDExtension), IDs de classes e export Windows.
- [ ] Meshing/colisão/brush com 100 edições e percentis de frame time medidos.
- [ ] Tempo entre alteração voxel e atualização da malha/collider em diferentes tamanhos de região.
- [ ] Interação de `separate_floating_chunks` com SDF suave e Jolt integrado (versão 4.7.2) e limites reais.
- [ ] Coluna sob caixa física/torre e ativação de colapso estruturado.
- [ ] Aproximação de massa conservada e colisão com personagem ao erguer terreno.
- [ ] `VoxelStreamSQLite` + slot de save + reset robustos.
- [ ] Poças subterrâneas/túneis verticais e SPH com colisões dinâmicas em experimento isolado.
- [ ] Compatibilidade do preset retro com shaders de terreno e normal/depth Forward+.
- [ ] Desempenho no PC de destino e ajustes em qualidade.

**Conclusão:** o sistema de terreno editável passa a ser o núcleo tecnológico, não um recurso a adicionar depois. Se P0 e P1 funcionarem com boa resposta e colisão, a maior incerteza estrutural do jogo terá sido resolvida. Depois disso, cada elemento será principalmente um conjunto de comandos que operam sobre os mesmos materiais, corpos rígidos e estados de mundo.
