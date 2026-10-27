# ELEMENTAL // RUINS — Roadmap técnico

**Estado atual:** P0–P4B integrados à main (`266627d`). Histórico do checkpoint P4B preservado no README. **Checkpoint P4C fechado em branch:** 70/70 nos quatro modos, export e persistência entre processos aprovados, zero erros/avisos e feedback humano positivo em 27/10/2026. Próximo passo: publicar a branch e abrir a PR para revisão.

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

## P4C — Pilar de Terra (checkpoint fechado; publicação pendente)
RMB segurado mostra uma prévia de volume; soltar cria um único PATH aditivo vertical, permanente até escavar/resetar. Reutiliza EarthLiftThrow, EarthTuning, EarthFx, TerrainBrushQueue e TerrainService; nenhum controlador novo. Material do chão, altura/raio/alcance configuráveis. Primeiro obstáculo bloqueia a mira; volume ocupado ou sobreposição com o jogador é recusado. Não ergue o jogador sob os próprios pés nem cria várias habilidades de uma vez.

**Aceite:** terreno volumétrico com colisão real, apoio de caixa/jogador, save/load/reset existentes, comando exclusivo do ciclo da rocha e cancelamento de prévia/pedido pendente. T63/T64 no runner existente, regressão dos consumidores de PATH/Terra e benchmark em janela. Playtest com feedback positivo do usuário em 27/10/2026 ("Funcionou, testei aqui!"), sem avaliação detalhada por cenário. Próximo passo: publicar a branch e revisar a PR, sem ampliar o escopo automaticamente.

**Validação da fatia:** 3/3 headless nos novos cenários com T1, regressão relacionada 17/17 headless e export 4/4 em janela, zero erros/avisos. T37 e T63 dentro de 20/33/50 ms. Raio padrão 2 m mantém apoio da caixa no topo arredondado; resultados e tentativas anteriores preservados no README e em `docs/evidence/p4c/`. Bateria completa e persistência entre processos não executadas nesta fatia.

**Integração:** 70/70 em cada um dos quatro modos, uma execução por modo; export e persistência write/read entre processos aprovados no editor e export. Zero erros/avisos, fontes e limites intactos, preset e fixtures preservados. T27/T37/T59/T61/T63 nas duas janelas dentro de 20/33/50 ms. Relatórios em `docs/evidence/p4c/integration/` e resultados no README.

## P4 posterior — 16 habilidades, combinações e visual (futuro)
Expandir `elemental_abilities_mvp.json`; estados de materiais, gelo, lava, eletricidade, vórtices, shaders Ilustrado/Retro, áudio/animações e modos de jogo.

## P5+ — referências raras do atlas
Selecionar habilidades do `avatar_atlas_poderes_sandbox.json` sem tentar implementar as 214 de uma vez; documentar o que é adaptação autoral.

**Regra:** ler antes de editar, reutilizar antes de criar, fazer a menor mudança eficaz e testar conforme o risco. Registrar somente decisões, contratos, limitações e resultados reais. Bateria completa reservada ao checkpoint de integração; proibir gates fictícios.
