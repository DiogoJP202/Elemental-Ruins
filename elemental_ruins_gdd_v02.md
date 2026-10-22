# ELEMENTAL // RUINS — Game Design Document (GDD)
**Versão:** 0.2 — terreno volumétrico obrigatório • **Data:** 22/10/2026 • **Idioma:** Português (Brasil)  
**Proposta:** sandbox 3D em terceira pessoa para manipular quatro elementos, construir e destruir estruturas e gerar reações sistêmicas. Sem campanha, PvP ou narrativa obrigatória na primeira versão.

> **Mudança de escopo em v0.2:** primeiro validar **P0/P1 terreno escavável**. O antigo M0/M1 visual + quatro poderes vira **P3** depois de P0/P1/P2. Se houver divergência, prevalecem esta atualização, o item 6A e a pesquisa técnica.

> **Referência de conhecimento:** `avatar_atlas_poderes_sandbox.md` e `avatar_atlas_poderes_sandbox.json` (214 entradas, 22 interações, 32 feitos). São fontes de inspiração e taxonomia, não APIs nem contratos de implementação. O projeto deve ser uma obra original, sem copiar personagens, assets, símbolos ou nomes protegidos da franquia Avatar.

## 1. Fantasia central e princípios
A fantasia não é “apertar botão para exibir magia”; é sentir que você controla materiais do cenário. Um jogador consegue levantar o solo, extrair rochas, orientar sua trajetória, desmontar uma ponte, depois mandar os fragmentos pelo ar. O cenário deve **lembrar fisicamente** de parte do que foi feito até o usuário apertar Reset.

**Pilares**
1. **Manipulação contínua:** selecionar → captar material → modelar/manter → soltar, com controles previsíveis.
2. **Física com consequência:** impulsos, massa, resistência, colapso limitado por materiais e conexões.
3. **Interação emergente:** fogo, frio, vento, água e impactos compartilham regras de estado e se afetam entre si.
4. **Liberdade no laboratório:** cenário de testes aberto, recarga rápida, alvos e estruturas, nenhum inimigo obrigatório.
5. **Visual estilizado de produção viável:** low-poly, geometria simples, texturas leves e feedback expressivo; nunca realismo fotográfico.

**Não objetivos no MVP:** simulação completa de fluidos CFD, mundo voxel infinito, deformação volumétrica arbitrária de **todas as construções**, multiplayer, IA complexa, árvore de habilidades e 214 poderes funcionais desde o primeiro dia. **O próprio terreno é obrigatoriamente SDF volumétrico escavável desde P0/P1.**

## 2. Direção artística — Sable encontra Mouthwashing
**Referências de linguagem visual:**
- **Sable:** paisagens vastas, cores chapadas/desbotadas, silhuetas fortes, contornos artísticos, leitura clara de superfícies, sombras simples e luz poética.
- **Mouthwashing:** triangulação intencional, texturas pixeladas, granulação/dithering e baixa resolução como linguagem estética, leves imperfeições, direção atmosférica.
- **Proposta própria:** ruínas de uma civilização sem nome em deserto de argila, com blocos, pontes e torres modulares; personagem anônimo de manto e máscara geométrica simples; efeitos elementais mais vívidos que o mundo.

**Modos de apresentação (alternados nas opções; não mudar mecânica ou geometria):**
- `ILLUSTRATED` — render nativo, toon shading em 2–3 bandas, outline sutil (usar shader robusto que funcione com Forward+), sombras bem marcadas e névoa pastel.
- `RETRO` — mesma cena e iluminação base; renderização para SubViewport de resolução interna reduzida escalada com nearest, textura filtrada por nearest, dithering discreto, ruído seletivo e quantização opcional de cores. **Jamais degradar a legibilidade do HUD ou da mira** (desenhar HUD após upscale).

**Paleta sugerida:** areia `#DCC7A7`; terracota `#B87968`; verde mineral `#65786A`; grafite `#343740`; fogo `#A84437`; água `#67AFC3`; brilho solar `#D4A546`.

**Linguagem de VFX:** partículas triangulares/grãos, fragmentos sólidos coloridos, linhas de energia em arcos, transparência parcial apenas onde essencial, distorção discreta de calor, nuvens de poeira em superfícies partidas. Efeitos baratos que indicam direção, pressão, temperatura e intensidade.

**Evitar:** pixelização extrema durante mira, telas confusas, pós-processamento pesado, copiar modelos e elementos de UI dos jogos de referência, ambientes escuros em que os alvos desapareçam.

## 3. Mundo/laboratório: mapa `Desert Lab`
Área inicial compacta (~150 × 150 unidades de jogo, ajustar após testes), com relevo **volumétrico SDF** e pelo menos uma colina atravessável por túnel, dividida visualmente, sem loading entre zonas:
1. **Pátio de impacto** — dummies geométricos, cubos e esferas móveis, parede de blocos com marcas de choque.
2. **Ruínas estruturais** — torre modular com pilares de sustentação, ponte de lajes, arco frágil, estátuas quebráveis.
3. **Bacia aquática** — lago artificial raso e tanque; fontes de água manipuláveis, gelo e evaporação visíveis.
4. **Jardim térmico** — madeira, pedra, metal impuro, plataformas de areia e marcadores térmicos.
5. **Campo aberto** — espaço seguro para tornados, voos, propulsão e projéteis de longa distância.

Distribuir a cena para que o jogador enxergue diferentes experimentos de qualquer ponto alto; sem dezenas de rigid bodies ativos à distância. **Reset World** restaura tudo do estado original sem recarregar o aplicativo.

## 4. Personagem, câmera e controles
**Locomoção:** WASD relativo à câmera; Shift correr; Espaço pular; rampa/piso; aceleração e desaceleração responsivas; animação simples fallback aceitável no começo (modelo geométrico/cápsula com braços). Evitar movimento deslizante em excesso.
**Câmera:** orbit em terceira pessoa (mouse), câmera ligeiramente acima do ombro ou centrada, ajuste de distância, colisão para não atravessar paredes, rotação suave com limite vertical, mira no centro.

| Comando | Comportamento |
|---|---|
| WASD / mouse | Mover / orbitar câmera |
| Shift / Espaço | Correr / pular |
| 1 2 3 4 | Terra / Água / Fogo / Ar |
| Q / E | Técnica anterior / próxima no elemento |
| LMB, toque | Executar a habilidade no ponto de mira |
| LMB, segurar e soltar | Carregar intensidade e soltar (quando habilidade aceita carga) |
| RMB, segurar | Modo de manipulação fina: mirar e guiar matéria selecionada (quando compatível) |
| Roda do mouse com RMB | Aproximar ou afastar o objeto suspenso, com limites |
| F | Captar/recolher material elegível próximo, quando a habilidade permite |
| T | Alternar tempo normal / câmera lenta (simulação inteira) |
| Z | Reset World com confirmação curta (exceto em modo de testes) |
| Tab | Abrir catálogo e dicas de controles |
| Esc | Pausar / liberar cursor |

Quando uma ação não se aplica, mostrar ajuda contextual e não executá-la silenciosamente. Menu de controles editáveis no futuro. **No primeiro protótipo de **terreno** (P0), usar atalhos de engenharia G/H/J para escavar/construir/abrir túnel; controles elementais entram na fase P3. Expandir gestos com critério.**

## 5. Esquema universal de manipulação
Cada técnica é construída com operações reutilizáveis, não uma animação totalmente independente:
- **Locate** (detectar volumes/superfícies permitidos, raio/volume e linha de visão)
- **Acquire** (extrair matéria de uma fonte; reservar volume ou força)
- **Shape** (bola, jato, onda, parede, tentáculo, coluna, anel, lâmina etc.)
- **Maintain** (sustentar posição/forma, consumir recurso/tempo se aplicável)
- **Transform** (mudar estado térmico ou composição quando permitido)
- **Release** (aplicar força, soltar projétil, pousar peça ou dissipar)

Técnicas são `AbilityDefinition` com `id`, `element`, `atlas_refs`, `input_mode`, `cast_mode`, `costs`, `range`, `power`, `radius`, `cooldown`, `vfx`, `tags`, `behavior` e `params`. **Poderes novos devem reutilizar serviços.**

### 5.1 Recursos elementais e regras do mundo
- **Terra:** requer substrato mineral válido; escava, adiciona e remodela o **terreno SDF real**, cria túneis, crateras, pilares e fragmentos físicos locais. No modo de regras, conservar massa de forma aproximada; metal é ramo separado com limitações de material. Não criar blocos infinitos do nada no modo canônico.
- **Água:** precisa de reservatório, poça, gelo, chuva ou fontes apropriadas. “Captação livre” pode ser opção de sandbox. Volume conservado aproximadamente em cada habilidade (reservatório/efeito/poça/descarte), sem resolver Navier–Stokes.
- **Fogo:** criado no personagem; consome energia da habilidade; aquece/queima conforme resposta do material. Distinguir VFX de incêndio persistente.
- **Ar:** sempre disponível salvo regra especial; aplica força, pressão e perturba partículas/fogo/água. Simular campos de força locais, **não uma simulação atmosférica completa**.
- **Modo Criativo:** recurso infinito, sem cooldown, poder multiplicável, ajustável por menu. **Modo Regras do Mundo:** capacidades e restrições inspiradas no atlas; ambos usam o mesmo core.

### 5.2 Contrato de interação
`ElementalEvent` é um evento de jogo, sem instanciar partículas diretamente: `{kind, origin, direction, magnitude, radius, duration, source_ability, tags}`. `kind`: `kinetic`, `heat`, `cold`, `wet`, `airflow`, `electric`, `mineral_shift`. Um mesmo impacto pode conter múltiplos componentes num payload de efeitos.

`MaterialState` contém `material_id`, `integrity`, `temperature`, `wetness`, `burning`, `frozen`, `mass`, `flammability`, `conductivity`, `bendable_tags` e `support_links` (quando existirem).

`MaterialResponseSystem` recebe eventos e atualiza materiais ANTES de pedir VFX e som. Exemplos:
- Rocha + `kinetic`: reduz integridade, racha, troca mesh intacta por partes pré-fraturadas após limiar.
- Madeira + `heat`: sobe temperatura, inflama se limiar alcançado, perde integridade até colapsar.
- Água + `cold`: congela num volume/placa simplificado; gelo + `kinetic`: estilhaça.
- Água + `heat`: reduz volume e cria nuvem visual de vapor.
- Solo mineral + `wet`: ganha estado de lama na região atingida, baixa atrito e altera cor; reduzir temperatura pode solidificar superfície.
- Chama + `airflow`: muda direção e intensidade (ar forte pode apagar chama pequena; fluxo moderado pode espalhá-la).
- Pedra + calor: **não virar lava automaticamente com qualquer bola de fogo**; lava depende de regra/técnica específica ou aquecimento extremo parametrizado, como escolha de jogo.
- Eletricidade + poça: propagação regional aproximada, feature avançada, sem resolver eletrodinâmica real.

**Separar** o que é explicitamente confirmado pelo universo Avatar do que é mecânica original do sandbox. Combos multi-elemento podem ser realizados pelo próprio personagem alternando elementos, sem pressupor que tais técnicas sejam normais para todos os dobradores.

## 6. Destruição: satisfação, verossimilhança e desempenho
**Estratégia realista para construções:** quebráveis modulares e pré-fraturados, **não** boolean meshes em todo impacto ou voxels universais.
1. Objetos intactos são preferencialmente estáticos (`StaticBody3D`) com integridade e material.
2. Ao atingir limiar, ocultar mesh intacta, desativar colisão e instanciar N fragmentos (`RigidBody3D`) pré-produzidos ou blocos modulares.
3. Distribuir impulso conforme vetor, distância e massa. Peças pesadas deslocam menos.
4. Remover/hibernar fragmentos menores depois de certo tempo ou distância; limite de corpos ativos e instâncias visuais.
5. **Colapso por suporte:** colunas com nós/conexões de sustentação; ao perder suporte, liberar grupos superiores, não aplicar magia de desaparecimento.
6. Depressões no solo inicialmente são **pedaços de terreno ativáveis**, rachaduras/elevação local e decalques; edição volumétrica contínua fica para fase posterior.
7. Reinício determinístico: original e fragmentos devem ser restituídos, com estados restaurados.

**Ordem de prioridade:** 1) feedback de impactos, 2) objetos realmente móveis, 3) paredes e torres quebráveis, 4) suportes estruturais, 5) terreno modelável amplo, 6) fluidos fisicamente simulados.

**Métricas indicativas, não garantias:** monitorar FPS (alvo perceptivo 60 no desktop de desenvolvimento), P95 do frame, total de corpos físicos ativos, tempo do reset e número de partículas. Começar com orçamento provisório de 100–200 `RigidBody3D` simultâneos no laboratório, ajustando após profiling. Preferir pools/LOD para detritos cosméticos.


## 6A. NOVO — Mundo volumétrico, escavação e sua relação com construções
Este item é **obrigatório** e prevalece sobre quaisquer referências antigas a crateras simuladas. O mapa de jogo usa `VoxelLodTerrain` + `VoxelMesherTransvoxel` e dados `VoxelBuffer.CHANNEL_SDF` via Voxel Tools 1.7. `VoxelViewer` acompanha jogador para ativar dados/render/collisions. Operações localizadas por `VoxelTool.MODE_REMOVE` e `MODE_ADD` com `do_sphere`, `do_path`, `grow_sphere` e `smooth_sphere` alteram a matéria de verdade, **não apenas a aparência**. Área fora de LOD0 carregada deve falhar sem corromper o mundo.

**Edição e colisão:** a reconstrução das malhas e colisores é assíncrona. `TerrainService` concentra transformação de coordenadas, valida área, enfileira brushes, publica AABB/revisão e trata atraso de colisão; serviços de suporte escutam `TerrainChanged` e só verificam apoio quando houver colisão/consulta confiável. Nunca tentar recriar todos os colliders do mundo em um frame.

**Volume e física:** o terreno é em geral **estático e editável**, não milhões de corpos rígidos. Apenas volumes pequenos separados do restante podem ser transformados em corpos físicos; testar `VoxelToolLodTerrain.separate_floating_chunks()` com AABBs pequenas (documentação sugere cerca de 30 voxels). Para uma torre ruir, suas peças modulares têm nós de sustentação que deixam de existir quando solo é escavado. Grandes desabamentos de montanha devem ter aproximações ou limites.

**Save e reset:** `VoxelStreamSQLite` guarda blocos editados; props/fraturas têm saves próprios. O reset precisa apagar/descartar edições do solo e restaurar a estrutura inicial, não apenas reposicionar o jogador.

**Fonte técnica primária:** `pesquisa_tecnica_elemental_ruins_godot_2026.md`.

## 7. Catálogo inicial de habilidades (16 técnicas, todas com referência ao atlas)
| Elemento | Técnica do MVP | Atlas | Operação | Evidência visível de funcionamento |
|---|---|---|---|---|
| Terra | Levantar pilar | `te-007` | Shape + Maintain | piso sobe e ergue caixa acima dele |
| Terra | Extrair / segurar rocha | `te-001` | Acquire + Maintain | fragmento removido do substrato fica suspenso seguindo retículo |
| Terra | Arremessar rocha | `te-001` | Release | acertar torre desloca peças conforme massa |
| Terra | Compressão / fissura | `te-003`, `te-010` | Shape + Kinetic | pedra racha, parede rompe no impacto |
| Água | Orbe líquido | `ag-001` | Acquire + Shape | capta do tanque, esfera segue objetivo |
| Água | Jato pressurizado | `ag-003` | Maintain + Release | empurra caixas, molha materiais e apaga focos de fogo |
| Água | Parede de gelo | `ag-024`, `ag-028` | Transform + Shape | água retirada do tanque cria barreira física estilhaçável |
| Água | Onda curta | `ag-017` | Shape + Release | empurra caixas em área e altera umidade do chão |
| Fogo | Rajada | `fo-002` | Release | aquece e marca superfície atingida |
| Fogo | Lança-chamas | `fo-003` | Maintain | incendeia madeira por exposição suficiente |
| Fogo | Explosão carregada | `fo-004` | Release com charge | força radial cresce com tempo de carga |
| Fogo | Propulsão | `fo-028` | Movement + Release | movimento aéreo curto com emissão de chama |
| Ar | Rajada | `ar-001` | Release | desloca corpos e poeira, pouco efeito em rocha maciça |
| Ar | Vórtice | `ar-015`, `ar-016` | Maintain | objetos leves giram e sobem em campo radial |
| Ar | Lâmina de pressão | `ar-005` | Release | golpe estreito com corte/impacto em alvo frágil |
| Ar | Impulso / salto aéreo | `ar-010` | Movement | salto amplificado e aterrissagem suavizada |

**Sequência de implementação:** Vertical slice com 4 poderes (pilar, jato, rajada de fogo, rajada de ar) + materiais/destruição; segundo marco implementa os 12 restantes; depois subdobras progressivamente pelo atlas. Não tentar apresentar todas como já implementadas.

## 8. Interações demonstráveis na arena
1. Fogo atinge madeira → carbonização progressiva → perde suporte → cai.
2. Água no foco de fogo → reduz temperatura, apaga, gera vapor breve.
3. Água + superfície mineral → cria região de lama escorregadia visual e fisicamente.
4. Água + frio (poder de gelo) → parede/bloco congelado com colisão.
5. Golpe cinético forte sobre gelo → fragmentação específica, não igual à pedra.
6. Ar em torno de fogo → desloca jato/chama; força alta pode extinguir foco pequeno.
7. Vórtice perto de fragmentos → aspira, gira e lança peças leves.
8. Pilar de terra destrói apoio → ponte ou torre colapsa em seções físicas.
9. Fogo + água → vapor (não tratar como névoa idêntica à dobra de água).
10. Terra + calor extremo/técnica especializada → lava (versão posterior; exige regras explícitas).

Exemplo emergente de 20 segundos: levantar pilar sob ponte → quebrar pilar com rocha → destroços caem → puxar detritos num vórtice → espalhá-los com rajada. Esse exemplo deve virar um **teste de aceitação manual**.

## 9. Interface
**HUD discreto:** retículo no centro, canto inferior direito com elemento/técnica e modo de cast, barra de carga curta no centro apenas ao carregar, dica contextual de material selecionado (`ROCHA • 400 kg • DANO 62%`). Ao atingir objeto, pequeno feedback de tipo de reação (`rachou`, `molhado`, `incendiou`, `congelou`). Um painel opcional exibe FPS, rigid bodies e tempo de simulação.

**Sandbox Controls:** reset, tempo 0.25x/1x, recurso infinito, multiplicador de força 0.5x–5x, intensidade VFX, troca de preset visual, spawn de módulos de teste básicos. Não é ferramenta de level designer no MVP.

## 10. Arquitetura de projeto (Godot 4.x estável / GDScript / desktop Windows)
Escolha recomendada: **Godot 4.7.2 estável**, Jolt integrado, renderer Forward+ em desktop e GDScript. O terreno SDF requer como dependência técnica **Voxel Tools 1.7** (primeira tentativa GDExtension compatível com a engine oficial; alternativa build custom 4.7.2 + módulo). Validar addon e export antes de poderes, sem misturar edições módulo e GDExtension.

Proposta de arquivos e cenas:
```text
project.godot
README.md
scenes/
  main.tscn
  world/desert_lab.tscn
  player/player.tscn
  props/breakable_wall.tscn
  props/structure_tower.tscn
  props/water_source.tscn
  ui/hud.tscn
scripts/
  player/player_controller.gd
  player/third_person_camera.gd
  ability/ability_controller.gd
  ability/ability_definition.gd
  ability/ability_context.gd
  ability/ability_registry.gd
  ability/behaviors/earth_pillar.gd
  ability/behaviors/water_jet.gd
  ability/behaviors/fire_burst.gd
  ability/behaviors/air_push.gd
  systems/elemental_event.gd
  systems/material_response_system.gd
  systems/resource_sources.gd
  systems/destruction_service.gd
  systems/world_reset.gd
  systems/visual_settings.gd
  props/destructible_object.gd
  props/structural_support.gd
  ui/hud.gd
assets/
  materials/
  effects/
  models/
data/
  abilities_mvp.json
  material_rules.json
  avatar_atlas_poderes_sandbox.json  # opcional, importado como referência, não para execução direta
```

**Módulos com responsabilidades estritas**
- `AbilityController`: seleção, inputs, custos e cooldown; não sabe sobre VFX específicos ou estrutura da cena.
- `AbilityRegistry`: valida IDs e despacha `behavior` de forma explícita; sem execução dinâmica de código/strings.
- `AbilityBehavior`: implementa operação específica com `AbilityContext`; chama serviços ao invés de acoplar nós aleatórios.
- `MaterialResponseSystem`: sole authority para mudanças térmicas, umidade, resistência.
- `DestructionService`: troca estado inteiro/fraturado e calcula impulsos; controla orçamento de objetos.
- `ResourceSources`: responde se há terra/água extraível no ponto sem inventar fonte em modo regras.
- `WorldReset`: registra estado inicial e restaura sem reiniciar jogo.
- `VisualSettings`: combina preset Ilustrado/Retro com shaders e post-fx independentes.

**Godot primitives:** `VoxelLodTerrain`, `VoxelMesherTransvoxel`, `VoxelViewer`, `VoxelTool`, `VoxelStreamSQLite`, `CharacterBody3D`, `SpringArm3D` + `Camera3D`, `StaticBody3D`, `RigidBody3D`, `CollisionShape3D`, `RayCast3D` ou `PhysicsRayQueryParameters3D`, `GPUParticles3D` (Forward+), `WorldEnvironment`, `AnimationPlayer`, `MultiMeshInstance3D` em detritos decorativos. escalonamento 3D nearest-neighbor nativo (preferido à criação obrigatória de SubViewport) no preset Retro. Não deformar CollisionShapes em loop sem custo medido.

## 10A. Cronograma técnico revisado (prevalece sobre o cronograma antigo abaixo)

- **P0 — Certificação Voxel**: abrir Godot 4.7.2 + Voxel Tools 1.7, provar escavação/adição/túnel com colisão e export Windows. Este é **bloqueante**.
- **P1 — Terreno deformável com controle**: brushes em lote, movimento no terreno modificado, materiais solo/pedra/areia, reset 10 vezes e benchmark de 100 escavações.
- **P2 — Estruturas e matéria extraível**: ponte/torre com suporte sensível à escavação, fragmentos físicos limitados, extrair pedra do chão e arremessar.
- **P3 — Quatro elementos**: terra escava/eleva/extrai; água jato/molha/apaga; fogo esquenta/queima; ar empurra/desvia. Aqui estão os quatro poderes da primeira versão anterior.
- **P4 — Estética e expansão**: Ilustrado/Retro, mais técnicas, água em regiões, gelo/areia/lava, estudo SPH.

O cronograma antigo M0–M3 a seguir é histórico de design, NÃO substitui os gates P0–P4.

## 11. Marcos e critérios de aceitação
### M0 — “Pisa no cenário”
- Iniciar projeto sem erros, rodar janela 3D; WASD + mouse + pulo + câmera collision.
- Personagem original temporário e mapa estilizado inicial; `ILLUSTRATED` e `RETRO` alternáveis.
- Retículo, 4 elementos selecionáveis, painel simples de ajuda.

### M1 — “Destruição satisfatória” (primeira versão realmente jogável)
- Quatro poderes: pilar de terra, jato de água, rajada de fogo, rajada de ar.
- Pelo menos três materiais (`rock`, `wood`, `ice/water`) respondem diferentemente ao impacto.
- Parede ou torre modular se quebra, peças reagem fisicamente e não atravessam chão.
- Fogo pode queimar madeira; água apaga; ar empurra fragmentos; pilar desloca estruturas.
- Reset restaura corpos/temperatura/umidade/estruturas. Nenhuma duplicação após múltiplos resets.

### M2 — “Quatro estilos jogáveis”
- 16 habilidades do catálogo, alternância e cargas, vórtice e manipulação de rocha.
- Cinco ou mais reações cruzadas estáveis. Barras/contexto UI e recursos opcionais.
- Profiling, budgets, fallback LOD e opções visuais confiáveis.

### M3 — “Subdobras e escala”
- Metal, lava, areia, gelo avançado, relâmpagos, combustão, técnicas aéreas e outras do atlas conforme capacidade.
- Primitivas reutilizáveis de modelagem, fluídos aproximados, areia particulada e variações climáticas.
- Bibliotecas de cenários e spawn de estruturas; export desktop.

**Definição de pronto do protótipo:** outra pessoa consegue iniciar o jogo pelo README, andar livremente, selecionar quatro elementos, executar quatro poderes com efeitos funcionais distintos, derrubar uma estrutura e resetar sem reiniciar. Código deve manter fronteiras claras para expansão via atlas.

## 12. Qualidade e riscos
- **Risco: escopo inviável** — não implementar 214 técnicas antes de terminar M1. Catálogo é roadmap, não lista de features garantidas.
- **Risco: “efeitos que não afetam nada”** — todo poder do MVP deve emitir evento físico/material e alterar pelo menos um objeto do cenário.
- **Risco: física cara** — modelo pré-fraturado, caps configuráveis, hibernação, partículas decorativas com pooling, profiling.
- **Risco: identidade visual incoerente** — diferença de presets é pós-processamento/iluminação, não modelos totalmente diferentes; legibilidade sempre vence fidelidade retrô.
- **Risco: dados de Avatar confundidos com canon** — `sandbox_mechanic` do atlas é derivação de game design; status de combos fica preservado; não inventar lore nem rotular mecânica autoral como cânone.
- **Risco: possível IP de terceiros** — usar atlas apenas como análise de mecânicas; jogo terá personagens, nomes, mundo e assets próprios.

## 13. Referências verificadas
- Sable, entrevistas com Shedworks (arte e produção): https://www.cookandbecker.com/en/article/170/sable-exploration-through-line-art.html
- Sable e abordagem modular low-poly: https://unity.com/resources/shedworks-sable-modular-design-approach
- Mouthwashing, entrevista de direção de arte: https://skyboxcritics.com/2025/07/14/mouthwashings-genesis-sick-jokes-and-the-thin-line-between-goofy-and-grotesque-an-interview-with-wrong-organ/
- Godot renderizadores: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- Godot CharacterBody3D: https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- Godot RigidBody3D: https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html
- Godot decals: https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html
