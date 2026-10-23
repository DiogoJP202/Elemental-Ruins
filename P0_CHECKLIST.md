# Gate P0 — Critérios de aceite do protótipo

**Preencha estas linhas com PASSOU / FALHOU / NÃO TESTADO. Nenhum item é considerado concluído apenas por ter código criado.** Registro de testes e logs em `docs/voxel_spike_results.md`.

> Preenchido por Claude Code a partir de execuções reais nesta máquina (Windows 11, Intel Iris Xe). **Estado atual (23/10/2026): Godot 4.7.2.stable.custom_build.ed1daf0bf com Voxel Tools 1.7 como módulo** (`docs/decisions.md`, D13). A rodada de 22/10 com a GDExtension está nas §2–10 do relatório. IDs T* = selftest `scripts/dev/p0_selftest.gd`; logs em `docs/evidence/`.

| Status | Critério | Como provar |
|---|---|---|
| PASSOU | Godot e Voxel Tools inicializam sem erro fatal | `02_check_env.log`: `Voxel Tools: módulo embutido no executável`, 11/11 classes, Jolt, Forward+. Jogo inicia em editor headless, editor em janela, `.exe` headless e `.exe` em janela, com 0 erros do motor (`Logger`). Ressalva: ver a linha de importação (B1) |
| PASSOU | Cena 3D nativa abre no Godot | `10_editor_open_main.log` (editor custom headless abre `main.tscn` sem erros); cena roda em janela, com 9 capturas em `docs/evidence/screens/` (rodada com o módulo) |
| PASSOU | WASD, pulo e câmera de terceira pessoa funcionam | 22/10, build GDExtension: teste interativo com teclado e mouse reais do Windows no `.exe` (W ~5 m/s, Shift ~9 m/s, S/A/D, pulo até y=1,9, mouse gira yaw/pitch) e roteiro manual do usuário (sensação ok). Mesmo código com o módulo; T3b (input simulado) PASS. **Revalidação manual no editor custom ainda não feita** |
| PASSOU | Terreno volumétrico gera colina com colisão sólida | T0: SDF −7 dentro / +8 acima; topo físico y=12,02. T1/T1b: jogador fica parado no chão (y=0,02) e no topo da colina (y=12,02) |
| PASSOU | Escavar remove matéria/colisão na mesma região após atualização | T2: collider desce de 0,02 para −3,05 em ~12–33 ms; jogador cai e fica no fundo (y=−3,04) |
| PASSOU | Túnel horizontal pode ser aberto **abaixo de teto sólido** | T3a: eixo livre, topo da colina intacto (12,02), teto interno y=3,35, piso y=−0,35. T3b: jogador anda de boca a boca (z 19 → −37) com teto acima em 360/360 amostras. Capturas 04–06. Túnel com J à mão: validado pelo usuário em 22/10 (build GDExtension) |
| PASSOU | Adicionar matéria forma coluna/rampa sólida | T4: coluna até y=6,50; caixa `RigidBody3D` repousa em y=7,0 (vel. 0); jogador fica no topo. Captura 07 |
| PASSOU | Múltiplas alterações no mesmo lugar não destroem a cena | T5: 20 ciclos escavar+adicionar no mesmo ponto (40 edições), nós estáveis. Bug real encontrado e corrigido (película SDF=0, B2) |
| PASSOU | Reset restaura geometria E colisões originais | T7: 14 probes físicas idênticas ao baseline (tol. 5 cm), props removidas, nós = baseline. T7b: 10/10 ciclos. Capturas 08–09 |
| FALHOU (risco aceito) | Não há erros fatais de importação/parser | **Risco aceito pelo usuário em 23/10/2026.** Parser: 0 erros. **Importação:** resta um crash raro da Godot no **encerramento** do `--import` em clone limpo: **1/50** com o módulo (`planb_modulo/m01_import_limpo_crash.log`, `14_b1_modulo_importacao_limpa.log`), contra 10/17 com a GDExtension. A importação em si conclui; `run_p0_tests.ps1` repete uma vez se cair. B4 (import com outra Godot aberta) não se aplica mais: 0/3 |
| PASSOU | Dependências e execução estão documentadas | `README.md` (editor custom, hashes, instalação, controles, comandos, roteiro manual, export), `docs/voxel_spike_results.md`, `docs/decisions.md` |

## Testes adicionais (recomendados; não bloqueiam a primeira tela jogável)
- 100 escavações em sequência com registro de pico de latência de reconstrução: **PASSOU** (T5b). Latência edição→collider p95/máx: 20,5/20,6 ms (headless) e 34,5/36,8 ms (janela).
- 10 resets com comparação de estado inicial e número de nós: **PASSOU** (T7b). 10/10 iguais ao baseline; média de 227–465 ms, conforme o modo.
- Export Windows com templates compatíveis, se disponíveis: **PASSOU**. Template custom release da `v1.7`; `build/elemental_ruins.exe` (88,5 MB, sem DLL) roda o selftest 12/12 em headless e em janela. Export **debug**: não disponível (não há template debug Windows na release).
- Testar regiões não carregadas: editar deve falhar de modo seguro, não congelar: **PASSOU** (T6). `outside_bounds` e `area_not_loaded` em < 20 ms.

## Modelo de evidência para docs/voxel_spike_results.md
- Data / OS / GPU / CPU/RAM (se a máquina fornecer sem extrapolar): 22–23/10/2026 · Windows 11 Pro 10.0.26200 · Intel Iris Xe (driver 32.0.101.7085, Vulkan 1.4.323) · i5-1135G7 4C/8T · 15,7 GB
- Binário Godot exato / versão Voxel Tools / variante module ou GDExtension: `godot.windows.editor.x86_64.exe` 4.7.2.stable.custom_build.ed1daf0bf / Voxel Tools 1.7 (release `v1.7`) / **módulo** (até 22/10: Godot oficial + GDExtension `v1.7x`)
- Comandos executados / logs relevantes / links internos a screenshots, se houver: `docs/voxel_spike_results.md` §3 e §12; `docs/evidence/*.log|*.json`; `docs/evidence/screens/*.png`; `docs/evidence/planb_modulo/`
- Testes manuais (quem, quando, resultado) e limites: Claude via computer use (input sintético), 22/10 ~18:01–18:06, §6; usuário seguiu o roteiro manual do README em 22/10 (~18:25) e tudo funcionou. Ambos com a build GDExtension; **com o editor custom ainda não houve teste manual**.
- Medições reais (FPS, tempos e memória) ou “não medido”: FPS médio 56,9–58,7 e p95 60–61 durante o roteiro em janela (módulo); tempos de collider e reset na §12. **Memória: não medida.**
- Bug encontrado / reprodução / correção tentada / status: B1 crash no encerramento do `--import` em clone limpo (bug da Godot; 1/50 com o módulo; repetição automática); B2 película SDF=0 (corrigido); B3 toque rápido em G/H perdido (corrigido); B4 import com outra Godot aberta (eliminado pela troca para o módulo)
- Gate geral P0: **PASSOU com ressalva aceita pelo usuário (23/10/2026).** 10 de 11 critérios PASSARAM; o critério de importação segue registrado como falha residual (B1: 1 crash em 50 importações limpas, no encerramento do `--import` da Godot, mitigado por repetição automática), aceita como risco conhecido. Pendência não bloqueante: repetir o roteiro manual no editor custom.
