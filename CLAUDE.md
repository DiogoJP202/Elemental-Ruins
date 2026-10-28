# ELEMENTAL // RUINS — instruções permanentes para Claude Code

> Leia este arquivo no início de toda sessão. Este repositório será um **jogo Godot 4**, não uma aplicação web. Idioma das explicações: português brasileiro; nomes de classes, nós, funções e arquivos em inglês quando fizer sentido.

## Pasta de trabalho
Usar o checkout existente de `DiogoJP202/Elemental-Ruins`, confirmando caminho, remote e estado Git em cada computador. Na retomada de 28/10/2026: `C:\Users\dsoares\Documents\Projetos\game`. Trabalhar com branches nessa mesma pasta; não criar worktrees, clones ou cópias paralelas sem pedido explícito do usuário. Trabalho não publicado de outra máquina é indisponível.

## Estado vigente: P4G — Gelo persistente e derretimento, pronto para playtest (28/10/2026)
- P0–P3.6.1 implementados. Base `codex/p36-t26-stabilization`, referência `180ec59`: salvar preserva terreno, colisores e física viva. Não reiniciar fases anteriores.
- P4A fechado: 66/66 nos quatro modos, export e persistência aprovados, zero erros/avisos e feedback humano positivo; integrado à main em `9103bee`. Histórico no README e em `docs/evidence/p4a/integration/`.
- P4B integrado à main em `266627d`: captura da mesma rocha, preservando massa/inércia e controles P4A. Playtest recebeu feedback positivo do usuário em 27/10/2026 ("está funcionando"), sem avaliação detalhada por cenário.
- P4B com checkpoint fechado: resultado integral final 68/68 nos quatro modos, export e persistência aprovados, zero erros/avisos; fontes e limites intactos. O editor em janela exigiu rechecagens após picos de desempenho, sem causa exata confirmada; preservar esse histórico no README e em `docs/evidence/p4b/integration/`.
- P4C implementado: pilar permanente por RMB (segurar prévia/soltar criar), usando PATH aditivo e os componentes existentes de Terra/terreno. Alcance, altura e raio em EarthTuning. Respeitar obstáculos/jogador e cancelar prévia/pedido pendente; save/load usam o terreno existente. Não erguer o próprio jogador nem criar expiração, managers, outras habilidades ou arquitetura genérica. Playtest P4C com feedback positivo do usuário em 27/10/2026 ("Funcionou, testei aqui!"), sem avaliação detalhada por cenário.
- P4C com checkpoint fechado e integrado à main pela PR #4 em `b84b4c6`: 70/70 nos quatro modos, uma execução por modo, export e persistência write/read entre processos aprovados, zero erros/avisos. T27/T37/T59/T61/T63 nas duas janelas dentro de 20/33/50 ms; fontes e limites intactos, preset e fixtures preservados. Raio padrão 2 m para apoio no topo arredondado. Histórico direcionado e integral no README e em `docs/evidence/p4c/`; preservar o estado histórico do playtest nos relatórios automatizados.
- P4D implementado e integrado à main pela PR #5 em `80f2a08`: primeira fatia da Fissura de Terra. F segurado mostra prévia; soltar abre uma vala permanente por PATH subtrativo, reutilizando EarthLiftThrow, EarthTuning, EarthFx, TerrainBrushQueue e TerrainService. Piso contínuo e alcance validado em todo o caminho; pode remover apoios de estruturas. Rocha, pilar e fissura são exclusivos. Cancelar prévia/pedido pendente nos contratos existentes. Sem compressão, outros poderes novos, managers ou refatoração paralela.
- Histórico direcionado P4D: T65/T66 aprovados; regressão 18/20 (T21 sem T20 e T61 em one_new_impact), rechecagem contextual 5/5. Tentativa inicial T65, correção da sonda SDF e todos os FAIL preservados no README e em `docs/evidence/p4d/`. Feedback humano positivo em 28/10/2026 ("sim, pode subir"), sem avaliação detalhada por cenário.
- Retomada em 28/10/2026: **checkpoint P4D FALHOU**. Contrato daquela execução: 72 testes, uma integral por modo: editor headless 71/72, editor janela 72/72, export headless 72/72 e export janela 71/72. As duas falhas são T26: repouso natural insuficiente em 15 s, antes do save; não comprovam defeito do salvamento. Três rechecagens T14/T26 passaram 3/3 cada, sem causa isolada. Não reclassificar os FAIL nem repetir integrais até verde. Persistência write/read entre processos 2/2 nas quatro etapas, zero erros/avisos em todos os logs e benchmarks das duas janelas dentro de 20/33/50 ms. Evidências em `docs/evidence/p4d/integration/`.
- T61: falha física histórica não reproduzida em dez repetições (5 headless + 5 janela), na checagem contextual e nas quatro integrais. Um impacto por lançamento e caixa deslocada > 0,5 m; callbacks limpos. Uma repetição em janela falhou apenas por p95=20,14 ms, preservada. Teste agora registra separadamente hits, deslocamento e monitoramento, sem alterar física, esperas ou PASS. A pendência de preparação do T26 permanece registrada, sem relaxar 15 s/60 ticks ou forçar sono.
- P4E autorizado explicitamente apesar do FAIL P4D: **Orbe de Água implementado e pronto para playtest**, sem aprovação de gate integral. Não investigar T26 nem repetir quatro baterias completas nesta fatia. P4E recebeu feedback humano positivo informado pelo usuário em 28/10/2026, sem avaliação detalhada por cenário; isso não aprova o gate integral.
- Água: LMB preserva o jato; segurar RMB forma/sustenta um único orbe, câmera orienta o alvo horizontal, Q/E regulam altura e roda regula distância somente no hold; soltar RMB lança. Modos exclusivos: o primeiro botão aceito vence. Troca de elemento, Esc, input desabilitado e reset/save/load limpam controle e voo. `WaterOrb` compõe `WaterJet` e reutiliza Ability/controller, MaterialResponseSystem e ElementalFx. Posição/velocidade de gameplay com esfera varrida; sem corpo rígido de água. Reserva abstrata do Criativo, 150 L nominais por formação em `data/abilities/water_orb_tuning.tres`; sem captura de reservatório, conservação volumétrica, poças ou edição do terreno.
- Validação P4E: T67–T69 com T1, 4/4 headless e 4/4 em janela; regressão dirigida T1/T46/T47/T48/T60/T64/T66, 7/7 headless. Execuções aprovadas sem erros/avisos. Benchmark curto com controle/lançamento: p95 18,05 ms, p99 18,76 ms e máximo 21,65 ms. Evidências em `docs/evidence/p4e/`; os relatórios preservam o estado anterior ao feedback humano positivo. Contrato daquela entrega: 75 IDs; bateria integral P4E NÃO EXECUTADA, FAIL P4D intacto.
- P4F: o mesmo WaterOrb alterna LIQUID/FROZEN. C físico (`water_freeze`) congela uma vez durante hold válido, preservando posição/velocidade/raio e os controles P4E. Gelo lança a 26 m/s com gravidade 9,8 m/s², impulso até 3000 N·s limitado a massa × 12 m/s, sem WET. Reutiliza varredura, KINETIC e limpeza; a peça estrutural não recebe impulso duplicado. Transição visual 0,18 s, cristal facetado opaco, até 12 fragmentos cosméticos. Parâmetros no Resource existente; sem outro controlador, gelo persistente, derretimento ou estruturas de gelo.
- Validação P4F: import/parse, T1/T70/T71 3/3 headless e 3/3 janela; regressão T1/T46/T48/T49/T52/T60/T67/T68/T69 9/9 headless, zero erros/avisos. Benchmark incluindo congelamento/controle/voo: p95 18,13, p99 18,86, máximo 18,94 ms. Contrato daquela entrega: 77 IDs, não executado; P4D FAIL preservado e T26 não investigado. Evidências em `docs/evidence/p4f/` preservam o estado anterior ao feedback humano positivo informado pelo usuário em 28/10/2026; não equivale a gate integral.
- P4G: impacto congelado materializa `IceBody` em `props_root`, reutilizando a esfera segura da varredura, cristal P4F, layers e DebrisBudget. RigidBody com CCD, 137,55 kg para 150 L/917 kg/m³; nasce sem velocidade residual para não repetir o KINETIC já aplicado. Sem espaço, mantém impacto e fragmenta, com motivo registrado no estado/HUD. Limite padrão oito: remove mais antigo elegível com efeito; respeita marca de controle existente e recusa se todos protegidos. Não possui `volume_m3`, portanto Terra não o captura como rocha; Ar/Água/Fogo usam os consumidores existentes.
- Fusão P4G: `BodyMaterialLibrary.ICE`, temperatura inicial -20 °C, limiar 0 °C, resistência térmica 30. Piso de resfriamento próprio por material; os demais mantêm 20 °C. Só HEAT suficiente consome gelo, sem fusão passiva. Estado primeiro, remoção imediata da colisão e corpo; ElementalFx mantém apenas uma cópia visual limitada que encolhe em 0,45 s e vapor breve. Sem segundo sistema térmico, poça, água física resultante ou serialização nova. Save preserva corpos vivos; reset/load removem os da sessão anterior. Seleção/Esc não apagam gelo já materializado.
- Validação P4G: import/parse; T1/T72/T73 3/3 headless e 3/3 janela; regressão T1/T38/T46/T48/T49/T52/T60/T67/T68/T69/T70/T71 12/12 headless. Execuções finais sem erros/avisos. T72 mede impacto único/240 N·s/12 m/s, repouso/colisão, Ar, exclusão P4B e teto; T73 usa duas rajadas reais de Fogo e verifica fusão/limpeza/save/reset/load. Tentativa inicial falhou nas sondas novas (velocidade no mesmo callback e lambda capturando corpo destruído); dados preservados e medições corrigidas sem mudar física ou PASS. Benchmark janela com oito corpos e hold/voo: p95 17,60 / p99 17,96 / máximo 18,32 ms. Evidências em `docs/evidence/p4g/`. Contrato atual 79 IDs, integral/export NÃO EXECUTADOS; P4D FAIL/T26 intactos. Próximo passo único: playtest humano P4G, sem iniciar P4H.
- Branch de trabalho: `codex/p4g-persistent-ice`, base `origin/codex/p4f-ice-orb` em `88d71e3`. Conferir checkout, branch e Git antes de editar; preservar alterações locais. Push autorizado exclusivamente para essa branch. Sem reset destrutivo, merge ou push direto na main.
- Stack vigente: Godot 4.7.2 custom + Voxel Tools 1.7 como módulo (D13). Editor e template release compatíveis. Não reintroduzir a GDExtension.
- Referências atuais: README.md e PROJETO_ROADMAP.md; contratos existentes em docs/decisions.md, docs/p35_earth_polish.md e docs/p36_t26_stabilization.md. O prompt inicial e o escopo da primeira entrega abaixo são históricos.
- Gates: zero erros e zero avisos. Nenhuma exceção ativa. Allowlist futura só com identificação exata, justificativa e documentação. Sem relaxar critérios para obter PASS.
- Em janela: intervalo entre quadros p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms nos cenários T27/T37. Registrar hardware, resolução, renderer, cenário e metodologia. Headless não comprova renderização.
- Água, Fogo e Ar: Resources independentes editáveis pelo inspetor, seguindo EarthTuning. Separar comandos, simulação, materiais e VFX. Não ampliar habilidades além da fase autorizada.
- PvP nesta fase: timings configuráveis, eventos identificáveis, cancelamentos e telegraphs. Sem rede, rollback, servidores ou dano em jogadores; sem pausa/tempo global para impacto.
- Capturas e automação não são playtest humano. P4A: feedback humano positivo dos controles em 27/10/2026; legibilidade PvP e avaliações dos demais elementos continuam NÃO TESTADO.
- Raycasts: registrar tentativas, acertos e falhas por cenário, superfícies finas e corpos adjacentes. Amostra sem falhas não prova correção universal.
- Testes proporcionais ao risco: `git diff --check` e parse/import quando necessário; IDs direcionados para o comportamento alterado e consumidores reais; benchmark em janela ao alterar o caminho físico. Bateria integral nos quatro modos somente no checkpoint de integração, alteração sistêmica de alto risco ou candidata a merge.

## Engenharia — Senior Lazy, Not Junior Busy
- Antes de criar código, buscar funções semelhantes e ler seus pontos reais de chamada. Estender os 20% faltantes quando o código existente já resolve os outros 80%.
- Preferir ajustar função, reutilizar componente e estender classe pequena antes de criar responsabilidade nova. Sem managers, interfaces duplicadas, refatorações paralelas ou abstrações especulativas.
- Reutilizar runners e IDs; novos testes somente para lacunas reais, sem executar a bateria completa a cada commit. Nunca alterar limites, desativar testes ou declarar PASS sem execução.
- Documentar somente decisões não óbvias, contratos, limitações, uso e resultados executados. Preservar histórico; não criar relatórios, ferramentas ou evidências redundantes.
- Perguntar internamente: já existe, há forma menor, resolve problema real, o jogador percebe o benefício? Preferir a solução mais simples que atende ao jogo.

## Visão do produto
Sandbox **3D em terceira pessoa**, focado em controle expressivo de terra, água, fogo e ar, destruição física e modificações persistentes do ambiente. Estética original inspirada no cel-shading/cores e contornos de *Sable* e no low-poly/texturas retro de *Mouthwashing*. **Nunca copiar assets, personagens, marcas, símbolos ou código proprietário dessas obras, nem de Avatar.** O atlas de Avatar é referência mecânica, não material para reprodução de propriedade intelectual.

## Requisito não negociável
**O terreno deve ser volumétrico e livremente modificável.** O usuário deve conseguir escavar uma cratera, abrir um túnel real sob uma colina (com teto e chão sólidos), atravessá-lo e acrescentar solo formando colunas ou rampas. Uma heightmap, decal, shader, buraco falso ou voxels apenas decorativos não atendem ao requisito.

## Stack e dependências
- **Godot 4.7.2 estável (Windows)**, GDScript para gameplay e sistemas de protótipo.
- **Jolt Physics integrado** da Godot; não instalar o addon legado Godot Jolt sem motivo comprovado.
- **Voxel Tools 1.7 como módulo** na build custom da Godot 4.7.2, com **SDF + Transvoxel**, edição runtime e colisões atualizáveis (D13). A investigação de GDExtension é histórica; não repeti-la nem reinstalar o addon. **Não confiar que classes/APIs existam sem verificar a versão real.**
- Se a versão exata não estiver disponível no ambiente, registrar bloqueio e perguntar/explicar; **não trocar de engine ou reduzir terreno a heightmap**.
- Renderização inicial simples; pós-processamento, shaders e água volumétrica **não** devem bloquear P0.

## Precedência e ordem de leitura
1. `CLAUDE.md` (este arquivo).
2. `README.md` e `PROJETO_ROADMAP.md` (fase e instruções atuais); consultar `PROMPT_INICIAL_CLAUDE_CODE.txt` somente como histórico da primeira execução.
3. `pesquisa_tecnica_elemental_ruins_godot_2026.md` (riscos, APIs candidatas, links e alternativas).
4. `elemental_ruins_gdd_v02.md` (GDD atualizado e referência de longo prazo).
5. `P0_CHECKLIST.md` (contrato de aceitação do protótipo).
6. `MATRIZ_REACOES_ELEMENTAIS.md` e `elemental_abilities_mvp.json` (design FUTURO).
7. `avatar_atlas_poderes_sandbox.md` / `.json` (consulta FUTURA, **não** implementar agora).
8. `prompt_claude_spike_voxel_godot.md` (aprofundamento técnico e diagnóstico para P0/P1/P2; prevalece o escopo limitado do prompt inicial para o primeiro ciclo).

Em caso de conflito: **requisito explícito do usuário > CLAUDE.md > P0_CHECKLIST.md > GDD v0.2 > pesquisa > documentos históricos**. Nunca trabalhar baseado no GDD antigo `elemental_ruins_gdd.md` nem no prompt antigo `prompt_claude_elemental_ruins.md`, que não estão neste pacote.

## Histórico: escopo da primeira entrega (P0 concluído)
1. Inspecionar máquina/projeto, versões da Godot, Git, ferramentas e dependências sem instalar silenciosamente nada importante.
2. Criar projeto nativo `.godot` e uma cena de laboratório técnico com personagem `CharacterBody3D`, câmera de terceira pessoa e WASD/Space/mouse.
3. Integrar terreno SDF volumétrico com geração de malha e colisão.
4. Remover e adicionar matéria por mira e raio. Demonstrar **túnel sob teto sólido** sem atravessar colisão antiga.
5. Separar adaptação ao plugin em `TerrainService` e controles dos comandos de edição, evitando APIs fictícias.
6. Criar reset funcional de alterações no mundo ou documentar como bloqueio explícito se impossível no primeiro ciclo.
7. Validar empiricamente importação, abertura da cena, colisor e comportamento; reportar o que não foi possível executar sem fingir que testou.
8. Preencher `docs/voxel_spike_results.md` com versões, logs e observações reais.

**Não avance para P1, P2 ou poderes sem que P0 passe nos gates ou o usuário autorize uma mudança de escopo.** Para tarefas bloqueadas, ofereça diagnóstico com próximos comandos verificáveis em vez de criar uma maquete enganosa.

## Padrões de implementação
- Árvore de cenas mínima: `Main`, `Player`, `World`, `HUD`/`DebugOverlay`; nomes exatos podem evoluir se documentados.
- Distinguir dados/edições voxel de objetos móveis. Manter operações em coordenadas do mundo na API pública e adaptar coordenadas locais internamente.
- Fazer controle por físicas, `RayCast3D`, input map e ações explícitas; evitar ler input em dezenas de nós aleatórios.
- Atualizações de SDF e colisores podem ser assíncronas. Não presumir que render e colisão se atualizam no mesmo frame. Evitar edição de volumes gigantes a cada `_process`.
- `RigidBody3D` deve ser movido por forças/impulsos quando cabível; não teleportar por `position` em cada frame.
- Evitar grandes loops por voxel em GDScript no runtime; usar operações eficientes disponibilizadas pelo plugin, batches e limites configuráveis.
- Versionar código em Git. Não sobrescrever conteúdo já existente sem inspecionar; pedir autorização em ações destrutivas de arquivos do usuário.
- Registre decisões e trade-offs em `docs/decisions.md`; instruções de execução em `README.md` (gerado pelo projeto), não substitua o arquivo `INICIO_AQUI.md` do pacote.
- Separar claramente: implementado+testado / implementado+não testado / não implementado / bloqueado.
- Não inventar links, resultados de benchmark, logs, imagens ou evidência de execução.

## Histórico: controles temporários do teste P0
- WASD andar, mouse orbitar, Space pular, Shift correr.
- `G`: escavar, `H`: acrescentar matéria, `Z`: reset.
- Marcador de mira e raio configurável; `J` para perfurar caminho/túnel é opcional até o controle básico funcionar.
- Esses atalhos são provisórios, diferentes do futuro sistema de 4 elementos do GDD. Não implementar seleção 1–4 antes de P3.

## Aceite e relatório ao fim da sessão
Responder com: o que foi reutilizado/criado, controles, testes realmente executados e omitidos, desempenho quando medido, commit, limitações e **um único próximo passo recomendado**. Informar NÃO TESTADO quando aplicável; não refazer os checklists das fases anteriores por padrão.
