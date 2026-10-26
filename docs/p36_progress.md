# P3.6 — execução incremental

## Estado recuperado
Worktree `charming-mendel-4b469a`, branch `claude/charming-mendel-4b469a`, HEAD inicial `08b6c6e`. Único arquivo local inicial: `docs/p36_baseline.md`, preservado. Commits anteriores: runners `9788e7b`, fechamento de traço/raycast `08b6c6e`.

## Etapa A — concluída e testada
Contratos explícitos de IDs por bateria, resultados individuais, resumo coerente, identidade/frescor e zero erros/avisos. Nenhuma allowlist ativa. Diagnósticos de brushes e raycasts registrados em `docs/evidence/p36/preparation/`.

## Baselines
`docs/p36_baseline.md` é o histórico do P3.5, medido em `797c46c`. Não comprova o HEAD corrigido. Etapa B terá evidências separadas.

## Limites e avaliação
Gates em janela: p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms nos cenários existentes. Controles, legibilidade e game feel: **NÃO TESTADO por pessoa**. Capturas/automação são evidências técnicas, não playtest.

## Próximos marcos
B: baseline corrigido. M0: investigação comparativa e arquitetura. M1 Água, M2 Fogo, M3 Ar, M4 integração. Resources independentes; física e materiais separados dos VFX. Nenhuma habilidade nova, rede ou push.

Resultados: 26/26 casos de contrato/log; integração do runner 3/3 (normal 0, encerramento precoce 3, contrato errado 3); preparação 18/18; T1/T8/T8b 3/3. Zero erros/avisos nos cenários reais. Baseline histórico preservado.

Etapa B concluída: commit medido 8c4beaf, 51/51 nos quatro modos, zero erros/avisos. T37 janela: editor p95/p99/máx 19,67/21,23/30,13 ms; export 18,16/19,37/30,80 ms. Ver docs/p36_baseline_corrected.md. Próximo marco M0.


M0 concluído: auditoria de seis sistemas, revisão independente, consultas comparativas, força/massa, parede fina e controles visuais. Zero erros/avisos nos spikes válidos. Arquitetura: água por pacotes, fogo varrido com antecipação, ar por casca temporal; Resources independentes e limites em docs/p36_m0.md. Próximo: M1 Água.


M1 Água concluído: T1/T31/T33/T37/T46/T47/T48, 7/7 headless e janela, zero erros/avisos. T37 janela p95/p99/máx 18,92/19,91/38,37 ms. Resource, transporte, pressão, virada90°, parede fina e origem interna validados. Ver docs/p36_water_polish.md. Próximo M2 Fogo.

