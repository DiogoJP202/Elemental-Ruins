# ELEMENTAL // RUINS — Roadmap técnico

**Estado atual:** P0–P4D integrados à main (`80f2a08`, PR #5). P4E–P4H receberam feedback humano positivo inicial; feedback específico P4I não informado. P4J recebeu feedback humano positivo inicial; P4K — Espinhos de Terra em `codex/p4k-earth-spikes`, base P4J `0334cc9`. Sem gate integral.

**Checkpoint P4D em 28/10/2026: FALHOU.** Editor headless e export janela: 71/72 por timeout de preparação do T26 antes do save. Editor janela e export headless: 72/72. Persistência entre processos e benchmarks aprovados, zero erros/avisos; detalhamento abaixo. O usuário autorizou P4E apesar desse FAIL, que permanece preservado. T26 não foi investigado nesta fatia.

## P0 — prova de terreno volumétrico (concluído)
Terreno SDF + colisão, personagem 3D, câmera, escavação/adição, túnel sob teto, reset e relatório de compatibilidade/execução. Não fazer poderes completos.

**Gate:** `P0_CHECKLIST.md`.

## P1 — ferramentas, materiais e persistência
Brushes contínuos, tamanho e forma, fila de edições, 3 materiais físicos simplificados, eventos de terreno, salvar e carregar, observabilidade com latência real e testes de stress.

**Gate:** 100 alterações e 10 resets observados; persistência recupera estados idênticos sem duplicar geometria; documentar limitações.

## P2 — sustentação, destroços e extração de rochas
Corpos físicos extraídos localmente, apoio entre terreno e estruturas, torre modular que perde sustentação, limite de fragmentos, colisões convexas e LOD/culling.

**Gate:** escavar apoio de estrutura produz colapso coerente sem destruir FPS na cena-teste.

## P3 — quatro elementos iniciais
Terra levanta e lança rocha; água projeta jato com força, molhamento e regras térmicas; fogo causa calor/ignição; ar causa campos de força. Integrar habilidades por interface comum; no máximo 4 poderes inicialmente.

**Gate:** cada elemento gera um efeito físico real verificável, com mínimo de VFX.

## P3.5 — Terra polida (implementado)
Fases, antecipação, desprendimento, levantamento, hold, lançamento e impacto. Referência histórica: 51/51 nos quatro modos; playtest humano NÃO TESTADO. Ver docs/p35_earth_polish.md.

## P3.6 — Água, Fogo e Ar (implementado)
Simulação, Resources e VFX progressivos, com histórico em `docs/p36_progress.md` e `docs/p36_elemental_polish.md`. Avaliação humana de controles e legibilidade: NÃO TESTADO.

## P3.6.1 — salvamento com física viva (implementado)
Salvar conserva o terreno e seus colisores, sem congelar ou recriar os corpos vivos. Cancelamentos dos poderes continuam ativos. Base `180ec59`; evidências históricas em `docs/p36_t26_stabilization.md`.

## P4A — manipulação livre de Terra (checkpoint fechado e integrado)
Uma única rocha: câmera orienta o movimento horizontal; Q/E ajustam altura, roda ajusta distância somente no hold, e soltar LMB continua lançando. Reutilizar `EarthLiftThrow`, sua mola, `EarthTuning`, input, HUD e contratos de cancelamento existentes.

**Aceite:** movimento por forças, limites configuráveis, colisão preservada, toque curto e impactos mantidos, comandos limpos ao cancelar e roda do pincel preservada fora do hold. Testes direcionados e T37 em janela; resultados no README. Playtest dos controles: feedback positivo do usuário em 27/10/2026, sem avaliação detalhada por cenário. Sem múltiplas rochas, novas habilidades, rede ou arquitetura genérica.

**Validação automatizada:** direcionados 11/11 headless e 4/4 em janela; integração 66/66 em cada um dos quatro modos, export e persistência write/read no editor e export aprovados. Zero erros/avisos; T27/T37/T59 em janela dentro de 20/33/50 ms. Resultados no README e em `docs/evidence/p4a/integration/`. Gate completo executado uma vez por modo, sem repetição.

## P4B — reutilizar rochas existentes (checkpoint fechado e integrado)
Capturar uma rocha extraída já existente, preservando instância, massa e velocidade. Reutilizar hold, câmera, Q/E, roda e lançamento do P4A; primeiro obstáculo bloqueia seleção. Sem novas classes de física ou alteração de terreno ao capturar.

**Aceite:** captura/relançamento sem duplicação, sem teleporte, sem callbacks de impacto antigos; rocha controlada não é estacionada pelo orçamento e volta ao ciclo normal ao soltar/cancelar. Testes direcionados e benchmark em janela; playtest com feedback positivo do usuário em 27/10/2026, sem avaliação detalhada por cenário.

**Validação direcionada inicial:** 18/18 headless e 5/5 em janela, zero erros/avisos; T27/T37/T61 dentro de 20/33/50 ms. Evidências em `docs/evidence/p4b/` e resultados no README.

**Integração:** resultado integral final 68/68 em cada um dos quatro modos; export e persistência write/read no editor e export aprovados. O editor em janela teve duas falhas de desempenho em tentativas anteriores e passou na última integral, com fontes e limites intactos; causa exata dos picos não confirmada. Relatórios completos e rechecagens em `docs/evidence/p4b/integration/`.

## P4C — Pilar de Terra (checkpoint fechado e integrado)
RMB segurado mostra uma prévia de volume; soltar cria um único PATH aditivo vertical, permanente até escavar/resetar. Reutiliza EarthLiftThrow, EarthTuning, EarthFx, TerrainBrushQueue e TerrainService; nenhum controlador novo. Material do chão, altura/raio/alcance configuráveis. Primeiro obstáculo bloqueia a mira; volume ocupado ou sobreposição com o jogador é recusado. Não ergue o jogador sob os próprios pés nem cria várias habilidades de uma vez.

**Aceite:** terreno volumétrico com colisão real, apoio de caixa/jogador, save/load/reset existentes, comando exclusivo do ciclo da rocha e cancelamento de prévia/pedido pendente. T63/T64 no runner existente, regressão dos consumidores de PATH/Terra e benchmark em janela. Playtest com feedback positivo do usuário em 27/10/2026 ("Funcionou, testei aqui!"), sem avaliação detalhada por cenário. Integrado pela PR #4 em `b84b4c6`.

**Validação da fatia:** 3/3 headless nos novos cenários com T1, regressão relacionada 17/17 headless e export 4/4 em janela, zero erros/avisos. T37 e T63 dentro de 20/33/50 ms. Raio padrão 2 m mantém apoio da caixa no topo arredondado; resultados e tentativas anteriores preservados no README e em `docs/evidence/p4c/`. Bateria completa e persistência entre processos não executadas nesta fatia.

**Integração:** 70/70 em cada um dos quatro modos, uma execução por modo; export e persistência write/read entre processos aprovados no editor e export. Zero erros/avisos, fontes e limites intactos, preset e fixtures preservados. T27/T37/T59/T61/T63 nas duas janelas dentro de 20/33/50 ms. Relatórios em `docs/evidence/p4c/integration/` e resultados no README.

## P4D — Fissura de Terra (implementado e integrado; feedback humano positivo)
Terra selecionada: segurar F mostra a prévia; soltar solicita uma vala permanente de 6 m, raio 1 m e centro 0,35 m abaixo do piso. PATH subtrativo pela fila existente, na direção horizontal da câmera. Alcance de 18 m em todo o caminho, amostras de piso a cada 1 m e recusa de saltos de altura maiores que 1 m. Primeiro obstáculo bloqueia o alvo; remover o solo pode derrubar caixas e estruturas apoiadas ao longo do trajeto.

**Aceite:** cavidade e colisão reais, limites/material/área carregada validados, operação única dentro do limite da fila, save/load/reset existentes e exclusão mútua com rocha/pilar. Troca de elemento, Esc, input desabilitado e reset/save/load cancelam prévia e pedido ainda pendente. Reutilizar EarthLiftThrow, EarthTuning, EarthFx, TerrainBrushQueue e TerrainService. Sem compressão ou ampliação dos outros elementos.

**Histórico direcionado:** T65/T66 aprovados em headless e janela; editor em janela 4/4 (T1/T37/T65/T66), zero erros/avisos, T37/T65 dentro de 20/33/50 ms. Regressão relacionada 18/20: T21 sem pré-requisito T20 e T61 na verificação one_new_impact; rechecagem contextual 5/5. A variação de T61 não foi isolada e o FAIL foi preservado. Tentativa inicial de T65 e correção da sonda SDF documentadas no README, sem relaxar tolerâncias. Evidências em `docs/evidence/p4d/`. Naquela fatia não houve export, persistência entre processos ou bateria completa. Feedback humano positivo em 28/10/2026 ("sim, pode subir"), sem avaliação detalhada por cenário. Implementação integrada pela PR #5 em `80f2a08`.

**Integração da retomada: FALHOU.** Uma integral por modo, contrato de 72 IDs: 71/72 editor headless, 72/72 editor janela, 72/72 export headless e 71/72 export janela. T26 falhou antes do save por não confirmar 60 ticks consecutivos de repouso natural em 15 s; três rechecagens T14/T26 passaram 3/3 cada, sem causa comprovada. T61 físico passou dez repetições, checagem contextual e quatro integrais; uma repetição direcionada falhou somente por p95=20,14 ms. Diagnóstico separado adicionado ao T61, sem alterar critérios. Persistência entre processos 2/2 nas quatro etapas, zero erros/avisos e seis benchmarks em cada janela dentro de 20/33/50 ms. Relatórios completos e FAILs preservados em `docs/evidence/p4d/integration/`. A preparação do T26 continua como dívida registrada, fora do escopo da fatia P4E. Compressão permanece futura.

## P4E — Orbe de Água (implementado; feedback humano positivo)
Com Água selecionada, LMB mantém o jato existente. Segurar RMB forma um único orbe; câmera orienta o alvo horizontal, Q/E ajustam altura e roda aproxima/afasta somente durante o controle. Soltar RMB lança com direção da mira e herança limitada da velocidade. O primeiro modo de Água aceito bloqueia o outro; troca de elemento, Esc, input desabilitado e reset/save/load limpam hold e voo.

`WaterOrb` compõe `WaterJet`, reutilizando Ability/controller, eventos de materiais e ElementalFx. Posição e velocidade contínuas, controle suavizado e colisão esférica varrida; contato único aplica impulso e WET/resfriamento/extinção antes do respingo. Parâmetros próprios em `data/abilities/water_orb_tuning.tres`. Reserva abstrata do Criativo: 150 L nominais por formação, sem simulação conservativa, corpo rígido de água, captação de reservatórios, poças ou edição do terreno.

**Validação dirigida:** T1/T67/T68/T69, 4/4 headless e 4/4 em janela; regressão T1/T46/T47/T48/T60/T64/T66, 7/7 headless. Execuções aprovadas sem erros/avisos. Benchmark curto de controle/lançamento em janela: p95 18,05 ms, p99 18,76 ms, máximo 21,65 ms, dentro de 20/33/50 ms. Evidências em `docs/evidence/p4e/`. Contrato P4E: 75 IDs, **integral não executada**; checkpoint P4D permanece FAIL. Feedback humano positivo informado pelo usuário em 28/10/2026, sem avaliação detalhada por cenário; os relatórios mantêm o estado histórico anterior.

## P4F — Congelamento e Lançamento de Gelo (implementado; feedback humano positivo)
Água selecionada: C durante RMB congela uma vez o mesmo orbe, com posição/velocidade preservadas. Controle suspenso P4E mantido; soltar RMB lança gelo balístico a 26 m/s, gravidade 9,8 m/s², KINETIC mais intenso (até 3000 N·s e massa × 12 m/s), sem WET. Mesma esfera varrida, contato único e consumidor estrutural sem duplicação de impulso. Cristal facetado opaco, transição de 0,18 s e fragmentos visuais limitados a 12. Cancelar/finalizar restaura LIQUID; C fora do hold é ignorado. Resource existente, sem gelo persistente, derretimento ou estruturas de gelo.

**Validação dirigida:** T1/T70/T71 3/3 headless e 3/3 janela; regressão 9/9 headless (jato, líquido, Terra/Fogo/Ar e controles). Zero erros/avisos. Benchmark: p95 18,13 / p99 18,86 / máximo 18,94 ms, dentro de 20/33/50. Evidências em `docs/evidence/p4f/`. Contrato daquela entrega: 77 IDs não executado; P4D continua FAIL e T26 não foi investigado. Feedback humano positivo informado pelo usuário em 28/10/2026, sem avaliação detalhada por cenário nem aprovação integral; evidências históricas preservadas.

## P4G — Gelo Persistente e Derretimento (implementado; feedback humano positivo)
O impacto congelado conserva KINETIC único e materializa um `IceBody` com colisão esférica/CCD, massa de 137,55 kg para 150 L, cristal facetado P4F e repouso natural. Reutiliza props_root/DebrisBudget, materiais e VFX. Ar/Água empurram; Terra não captura como rocha. Teto configurável de oito, removendo mais antigo elegível; se não houver espaço ou todos estiverem protegidos, mantém impacto e fragmenta sem spawn inválido.

Fogo usa HEAT no mesmo MaterialResponseSystem: gelo começa a -20 °C, funde a 0 °C, sem aquecimento ambiente automático. Colisão removida ao confirmar fusão; cópia visual encolhe em 0,45 s com vapor limitado. Seleção/Esc preservam gelo do mundo; save não altera a física viva, reset/load removem a sessão. Sem serialização de corpos, poças, água física ou estruturas de gelo.

**Validação dirigida:** import/parse; T1/T72/T73 3/3 headless e 3/3 janela; regressão 12/12 headless de materiais/jato/líquido/congelamento/controles/Terra/Fogo/Ar. Execuções finais sem erros/avisos. Tentativa inicial com falhas das sondas corrigidas permanece registrada. Benchmark de 185 ticks com oito corpos e orbe ativo/lançado: **17,60 / 17,96 / 18,32 ms** (p95/p99/máximo), dentro de 20/33/50. Evidências e metodologia em `docs/evidence/p4g/`. Contrato daquela entrega: 79 IDs; integral/export não executados. P4D FAIL preservado; T26 não modificado/investigado. Feedback humano positivo inicial informado em 28/10/2026, sem avaliação detalhada ou aprovação integral; relatórios históricos preservados.

## P4H — Muralha de Gelo (implementada; feedback humano positivo)
RMB/C/V alterna painel/projétil congelado; mira mostra prévia azul/vermelha sem collider. Release válido constrói uma única muralha e consome o orbe; inválido recusa sem lançar. Painel 1,40 × 1,50 m, espessura derivada do volume (150 L → 0,071429 m, massa 137,55 kg), mínimo 0,04 m; alcance 10 m. Mesmo IceBody, material/fusão, orçamento misto oito e efeitos; sem Ability/manager novo.

Âncora estática enquanto seis apoios de base e SDF a 0,6 m continuam válidos; bordas/solo raso são recusados conservadoramente. Os pulsos existentes de TerrainContactWaker liberam a física ao escavar. Collider real bloqueia jogador/props; Fogo funde, Ar empurra após desancorar com visada. Seleção/Esc/save preservam muralhas prontas; reset/load removem a sessão, sem serialização de props.

**Validação dirigida:** import/parse; T1/T74/T75 3/3 headless e 3/3 janela; regressão 12/12 de Waker/Terra/jato/orbes/gelo, execuções finais sem erros/avisos. Tentativas iniciais preservadas: anotação de tipo no parse e sonda de Ar ocluída no fundo da cratera; painel dinâmico acessível recebe impulso real, sem ajuste de física. Benchmark de 185 ticks, quatro muralhas/quatro esferas e duas rajadas: **17,64 / 18,46 / 19,54 ms**, dentro de 20/33/50. Evidências em `docs/evidence/p4h/`. Contrato daquela entrega: 81 IDs; integral/export/persistência entre processos não executados. P4D continua FAIL; T26 intacto. Feedback humano positivo confirmado em 29/10/2026, sem avaliação detalhada nem aprovação integral; evidências preservadas.

## P4I — Vórtice de Ar (implementado; pronto para playtest)
Ar selecionado: segurar RMB em chão livre até 10 m cria um campo fixo de raio 2,5 m/altura 4 m; soltar dissipa preservando inércia e gravidade. AirVortex compõe AirGust, com forças centrais de atração/circulação/sustentação, teto 2500 N e até 12 corpos. LMB continua rajada fora do campo; ondas anteriores terminam normalmente. Cache limitado/WeakRef e exposição existente, com nova visada central a cada tick. AIRFLOW a 1 Hz usa os materiais existentes. Âncoras/held/jogador não são levantados; muralha desancorada é elegível. Sem centro móvel, múltiplos campos, fluidos ou destruição automática.

**Validação dirigida:** import/parse; T1/T76/T77 3/3 headless e 3/3 janela; regressão 10/10 de rajada/exposição/materiais/VFX/cancelamentos/Terra/Água/muralha. Execuções finais sem erros/avisos. Tentativa inicial preservada: duas fixtures bloqueavam a própria formação pela mira; preparação corrigida sem alterar física ou limites. Benchmark com 16 caixas de 0,4 m/20 kg, até 12 influenciadas: **19,62 / 20,65 / 21,75 ms**, p95/p99/máximo, dentro de 20/33/50. Evidências em `docs/evidence/p4i/`. Contrato daquela entrega: 83 IDs; integral/export/persistência entre processos não executados. P4D continua FAIL, T26 não investigado. Playtest humano específico P4I permanece não informado.

## P4J — Fluxo Contínuo de Fogo (implementado; pronto para playtest)
Fogo selecionado: LMB preserva bola; segurar RMB emite corrente direcionável com frente 25 m/s até 12 m. Pulsos 0,1 s aplicam 240 HEAT/s pelo tempo real de contato, sem depender do FPS. Obstáculo atual limita a corrente e usa visada do MRS; mudar alvo/cancelar descarta crédito não emitido. Madeira seca/molhada, pedra e gelo seguem as mesmas regras térmicas. Origem lateral local validada fisicamente; VFX limitado ao segmento, sem decidir calor. Sem lava, terreno incendiável, propulsão ou vento deformando a corrente.

**Validação dirigida:** import/parse; T1/T78/T79 3/3 headless e 3/3 janela; regressão 9/9 de bola, materiais, VFX e controles/cancelamentos dos elementos. Runs finais sem erros/avisos. Dose equivalente 30/60/120 Hz; ignição seca 1,5 s/molhada 2,9 s; gelo/muralha fundem, parede/voxel bloqueiam e visual desligado mantém HEAT. Ajuste local da origem após inspeção de visibilidade revalidado, sem relaxar critérios. Cenário pareado de seis caixas e alvo pedra: fluxo p95/p99/máximo **17,60/18,17/18,39 ms**, baseline **17,48/18,28/19,11 ms**; componente **0,097 ms/tick** de CPU média. Evidências em `docs/evidence/p4j/`. Contrato daquela entrega: 85 IDs, integral/export/persistência entre processos não executados. P4D FAIL/T26 preservados; P4I segue com feedback humano específico não informado. P4J recebeu feedback humano positivo inicial informado na missão P4K (29/10/2026), sem aprovação integral.

## P4K — Espinhos de Terra (implementado; pronto para playtest)
Terra/X: prévia verde/vermelha de três volumes; release captura direção e posições. PATHs aditivos afunilados são revalidados individualmente, aplicados pela fila e separados por confirmação física mais 0,14 s. Reusa EarthLiftThrow/Tuning/Fx e terreno/persistência existentes. Recusa props/jogador, chão ausente, teto/parede e mudanças SDF ainda sem collider. Falha/cancelamento conserva o que já foi aplicado e descarta o restante. Sem dano, elevação artificial ou rollback.

Padrão: três, espaçamento 1,8 m, altura nominal 3 m, raios 0,9→0,75 m, alcance 14 m. A grade de 1 m arredonda o topo; altura física observada 2,27–2,81 m. Ponta 0,5 m foi subamostrada, portanto o padrão local é 0,75 m sem reduzir o mínimo global. Contrato atual 87 IDs; P4D FAIL/T26 intactos, P4I sem feedback humano específico e P4J com feedback positivo inicial. Próximo passo: playtest P4K, sem P4L automático.

**Validação dirigida:** import/parse; novos T80/T81 em headless e janela, regressão Terra 7/7; runs aceitos completos sem erros/avisos. Benchmark incluindo três edições e colliders: **17,55/17,82/19,03 ms**; rechecagem **19,97/26,15/27,20 ms**, dentro de 20/33/50. Edição 1,872/0,107/0,101 ms; collider 29/34/32 ms. Pico inicial 81,96 ms e outras tentativas preservados, sem causa de desempenho isolada. Evidências em `docs/evidence/p4k/`. Integral/export/persistência entre processos não executados; não é gate integral.

## P4 posterior — 16 habilidades, combinações e visual (futuro)
Expandir `elemental_abilities_mvp.json`; estados de materiais, gelo, lava, eletricidade, vórtices, shaders Ilustrado/Retro, áudio/animações e modos de jogo.

## P5+ — referências raras do atlas
Selecionar habilidades do `avatar_atlas_poderes_sandbox.json` sem tentar implementar as 214 de uma vez; documentar o que é adaptação autoral.

**Regra:** ler antes de editar, reutilizar antes de criar, fazer a menor mudança eficaz e testar conforme o risco. Registrar somente decisões, contratos, limitações e resultados reais. Bateria completa reservada ao checkpoint de integração; proibir gates fictícios.
