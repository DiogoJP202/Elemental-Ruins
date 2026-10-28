# ELEMENTAL // RUINS — Roadmap técnico

**Estado atual:** P0–P4D integrados à main (`80f2a08`, PR #5). P4E — Orbe de Água implementado na branch `codex/p4e-water-orb`, base `codex/p4d-integration` em `b1efae9`, pronto para playtest humano. Validação dirigida aprovada; gate integral P4E não executado.

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

## P4E — Orbe de Água (implementado; pronto para playtest)
Com Água selecionada, LMB mantém o jato existente. Segurar RMB forma um único orbe; câmera orienta o alvo horizontal, Q/E ajustam altura e roda aproxima/afasta somente durante o controle. Soltar RMB lança com direção da mira e herança limitada da velocidade. O primeiro modo de Água aceito bloqueia o outro; troca de elemento, Esc, input desabilitado e reset/save/load limpam hold e voo.

`WaterOrb` compõe `WaterJet`, reutilizando Ability/controller, eventos de materiais e ElementalFx. Posição e velocidade contínuas, controle suavizado e colisão esférica varrida; contato único aplica impulso e WET/resfriamento/extinção antes do respingo. Parâmetros próprios em `data/abilities/water_orb_tuning.tres`. Reserva abstrata do Criativo: 150 L nominais por formação, sem simulação conservativa, corpo rígido de água, captação de reservatórios, poças ou edição do terreno.

**Validação dirigida:** T1/T67/T68/T69, 4/4 headless e 4/4 em janela; regressão T1/T46/T47/T48/T60/T64/T66, 7/7 headless. Execuções aprovadas sem erros/avisos. Benchmark curto de controle/lançamento em janela: p95 18,05 ms, p99 18,76 ms, máximo 21,65 ms, dentro de 20/33/50 ms. Evidências em `docs/evidence/p4e/`. Contrato `p36`: 75 IDs, **integral não executada**; checkpoint P4D permanece FAIL. **Próximo passo: playtest humano do orbe (NÃO TESTADO)**, sem iniciar outra habilidade automaticamente.

## P4 posterior — 16 habilidades, combinações e visual (futuro)
Expandir `elemental_abilities_mvp.json`; estados de materiais, gelo, lava, eletricidade, vórtices, shaders Ilustrado/Retro, áudio/animações e modos de jogo.

## P5+ — referências raras do atlas
Selecionar habilidades do `avatar_atlas_poderes_sandbox.json` sem tentar implementar as 214 de uma vez; documentar o que é adaptação autoral.

**Regra:** ler antes de editar, reutilizar antes de criar, fazer a menor mudança eficaz e testar conforme o risco. Registrar somente decisões, contratos, limitações e resultados reais. Bateria completa reservada ao checkpoint de integração; proibir gates fictícios.
