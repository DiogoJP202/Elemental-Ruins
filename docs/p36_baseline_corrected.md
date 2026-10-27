# P3.6 — baseline do HEAD corrigido

Fonte medida: commit `8c4beafea376f5a79760a6057177b76e3422825d`, execução sequencial em 26/10/2026. Comandos: `powershell -ExecutionPolicy Bypass -File tools/run_p36_baseline.ps1`. Evidências: `docs/evidence/p36/baseline/`.

Hardware: Windows 11 Pro, i5-1135G7 (4C/8T), Intel Iris Xe, driver 32.0.101.7085, 15,7 GB de RAM. Godot 4.7.2 custom + Voxel Tools 1.7, Jolt, Forward+, viewport configurado 1600×900, vsync padrão do projeto. Editor existente preservado (PID e comando em environment.json). Sem capturas durante esta medição.

Método: processos sequenciais; física real; intervalo entre process_frame medido em T27 (colapso) e T37 (colapso + 12 fogos + quatro poderes). Headless mede lógica/física, não aprova GPU. Limites inalterados em janela: p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms.

| Modo | Testes | Erros/avisos | T27 p95/p99/máx ms | T37 p95/p99/máx ms | Duração s |
|---|---|---|---|---|---|
| editor_headless | PASS 51/51 | 0/0 | 16.09/16.97/18.09 | 8.58/11.37/27.49 | 278.61 |
| editor_window | PASS 51/51 | 0/0 | 17.97/18.73/19.36 | 19.67/21.23/30.13 | 287.976 |
| export_headless | PASS 51/51 | 0/0 | 8.06/8.3/10.57 | 8.63/11.08/14 | 269.212 |
| export_window | PASS 51/51 | 0/0 | 18.06/19.07/19.66 | 18.16/19.37/30.8 | 285.011 |

Comparação histórica (797c46c): T37 p95 editor janela 19,2 → 19,67 ms (+0,47 ms); export janela 17,9 → 18,16 ms (+0,26 ms). São rodadas diferentes, não atribuição causal por efeito. Todos os limites passaram; o editor mantém apenas 0,33 ms de margem no p95.

Resultado técnico: PASS nos quatro modos. Playtest humano, legibilidade percebida e game feel: NÃO TESTADO. O histórico original em docs/p36_baseline.md foi preservado.
