# ELEMENTAL // RUINS — Roadmap técnico

**Estado atual:** P0–P3.5 implementados. Trabalho autorizado: P3.6 (ver docs/p36_progress.md). Os gates históricos continuam preservados.

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

## P3.6 — Água, Fogo e Ar (TRABALHO ATUAL)
Preparação: contratos dos runners, brushes, raycasts e documentação. Baseline novo no HEAD corrigido, separado do histórico.
M0: auditoria, spikes comparativos, arquitetura e critérios mensuráveis. M1 Água, M2 Fogo, M3 Ar: simulação + Resources + VFX progressivos, testes e evidências por marco. M4: integração, regressões e gate integral. Não criar habilidades novas; preparar PvP sem implementar rede.

## P4 — 16 habilidades, combinações e visual
Expandir `elemental_abilities_mvp.json`; estados de materiais, gelo, lava, eletricidade, vórtices, shaders Ilustrado/Retro, áudio/animações e modos de jogo.

## P5+ — referências raras do atlas
Selecionar habilidades do `avatar_atlas_poderes_sandbox.json` sem tentar implementar as 214 de uma vez; documentar o que é adaptação autoral.

**Regra:** cada fase começa com avaliação de riscos/medição, termina com teste de aceite e relatório; proibir gates fictícios.
