# ELEMENTAL // RUINS — Roadmap técnico

**Estado atual:** P0–P4A integrados à main (`9103bee`). **P4B implementado em branch**, com 18/18 headless e 5/5 em janela, zero erros/avisos e feedback humano positivo em 27/10/2026 ("está funcionando"). Próximo passo: **checkpoint de integração P4B**. Checkpoint P4A e resultados históricos preservados.

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

## P4B — reutilizar rochas existentes (implementado; integração pendente)
Capturar uma rocha extraída já existente, preservando instância, massa e velocidade. Reutilizar hold, câmera, Q/E, roda e lançamento do P4A; primeiro obstáculo bloqueia seleção. Sem novas classes de física ou alteração de terreno ao capturar.

**Aceite:** captura/relançamento sem duplicação, sem teleporte, sem callbacks de impacto antigos; rocha controlada não é estacionada pelo orçamento e volta ao ciclo normal ao soltar/cancelar. Testes direcionados e benchmark em janela; playtest com feedback positivo do usuário em 27/10/2026, sem avaliação detalhada por cenário.

**Validação:** 18/18 headless e 5/5 em janela, zero erros/avisos; T27/T37/T61 dentro de 20/33/50 ms. Evidências em `docs/evidence/p4b/` e resultados no README. Bateria completa/export reservados ao checkpoint de integração.

## P4 posterior — 16 habilidades, combinações e visual (futuro)
Expandir `elemental_abilities_mvp.json`; estados de materiais, gelo, lava, eletricidade, vórtices, shaders Ilustrado/Retro, áudio/animações e modos de jogo.

## P5+ — referências raras do atlas
Selecionar habilidades do `avatar_atlas_poderes_sandbox.json` sem tentar implementar as 214 de uma vez; documentar o que é adaptação autoral.

**Regra:** ler antes de editar, reutilizar antes de criar, fazer a menor mudança eficaz e testar conforme o risco. Registrar somente decisões, contratos, limitações e resultados reais. Bateria completa reservada ao checkpoint de integração; proibir gates fictícios.
