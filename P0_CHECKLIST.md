# Gate P0 — Critérios de aceite do protótipo

**Preencha estas linhas com PASSOU / FALHOU / NÃO TESTADO. Nenhum item é considerado concluído apenas por ter código criado.** Registro de testes e logs em `docs/voxel_spike_results.md`.

> Preenchido em 22/10/2026 por Claude Code, a partir de execuções reais nesta máquina (Godot 4.7.2.stable.official.ed1daf0bf + Voxel Tools GDExtension 1.7, Windows 11, Intel Iris Xe). IDs T* = selftest `scripts/dev/p0_selftest.gd`; logs em `docs/evidence/`.

| Status | Critério | Como provar |
|---|---|---|
| PASSOU | Godot e Voxel Tools inicializam sem erro fatal | `02_check_env.log`: extensão carregada, 11/11 classes Voxel, Jolt, Forward+. Jogo inicia em headless, em janela e no `.exe`, com 0 erros do motor (`Logger`). Ressalva: ver a linha de importação (B1) |
| PASSOU | Cena 3D nativa abre no Godot | `10_editor_open_main.log` (editor headless abre `main.tscn` sem erros); cena roda em janela, com 9 capturas em `docs/evidence/screens/`. Editor **com interface** não aberto por mim |
| PASSOU | WASD, pulo e câmera de terceira pessoa funcionam | Teste interativo com teclado/mouse reais do Windows (SendInput) no `.exe`: W ~5 m/s, Shift ~9 m/s, S/A/D ok, Espaço sobe a y=1,9 e volta ao chão; mouse gira yaw/pitch. **Sensação e sensibilidade do mouse não avaliadas** (pedem uma pessoa) |
| PASSOU | Terreno volumétrico gera colina com colisão sólida | T0: SDF −7 dentro / +8 acima; topo físico y=12,02. T1/T1b: jogador fica parado no chão (y=0,02) e no topo da colina (y=12,02) |
| PASSOU | Escavar remove matéria/colisão na mesma região após atualização | T2: collider desce de 0,02 para −3,05 em ~13–35 ms; jogador cai e fica no fundo (y=−3,04). Interativo: G abre cratera visível |
| PASSOU | Túnel horizontal pode ser aberto **abaixo de teto sólido** | T3a: eixo livre, topo da colina intacto (12,02), teto interno y=3,35, piso y=−0,35. T3b: jogador anda de boca a boca (z 19 → −37) com teto acima em 360/360 amostras. Capturas 04–06. Túnel aberto **à mão** com J e atravessado a pé: não testado (J testado no chão) |
| PASSOU | Adicionar matéria forma coluna/rampa sólida | T4: coluna até y=6,50; caixa `RigidBody3D` repousa em y=7,0 (vel. 0); jogador fica no topo. Captura 07. Interativo: H adiciona e recusa sobreposição com o jogador |
| PASSOU | Múltiplas alterações no mesmo lugar não destroem a cena | T5: 20 ciclos escavar+adicionar no mesmo ponto (40 edições), nós estáveis. Bug real encontrado e corrigido (película SDF=0, B2) |
| PASSOU | Reset restaura geometria E colisões originais | T7: 14 probes físicas idênticas ao baseline (tol. 5 cm), props removidas, nós = baseline. T7b: 10/10 ciclos. Interativo: Z restaura em 453 ms. Capturas 08–09 |
| FALHOU | Não há erros fatais de importação/parser | Parser: 0 erros (`--check-only` em todos os scripts; logs limpos). **Importação:** a primeira importação de um clone limpo (sem `.godot/`) fecha a Godot com segfault em 10/17 tentativas (B1; `14_b1_reproducao.log`). Mitigado: com `.godot/extension_list.cfg` pré-criado, 0/11 (feito por `tools/run_p0_tests.ps1`); com cache existente, nunca reproduziu |
| PASSOU | Dependências e execução estão documentadas | `README.md` (versões, instalação, controles, comandos, roteiro manual), `docs/voxel_spike_results.md`, `docs/decisions.md` |

## Testes adicionais (recomendados; não bloqueiam a primeira tela jogável)
- 100 escavações em sequência com registro de pico de latência de reconstrução: **PASSOU** (T5b). Latência edição→collider: máx. 27,3 ms (headless) e 38,6 ms (janela); p95 de 20,5 / 36,4 ms.
- 10 resets com comparação de estado inicial e número de nós: **PASSOU** (T7b). 10/10 iguais ao baseline; 342–518 ms em média, conforme o modo.
- Export Windows com templates compatíveis, se disponíveis: **PASSOU**. Templates oficiais 4.7.2 instalados; `build/elemental_ruins.exe` (release) roda o selftest 12/12 em headless e em janela.
- Testar regiões não carregadas: editar deve falhar de modo seguro, não congelar: **PASSOU** (T6). `outside_bounds` e `area_not_loaded` em < 20 ms.

## Modelo de evidência para docs/voxel_spike_results.md
- Data / OS / GPU / CPU/RAM (se a máquina fornecer sem extrapolar): 22/10/2026 · Windows 11 Pro 10.0.26200 · Intel Iris Xe (driver 32.0.101.7085, Vulkan 1.4.323) · i5-1135G7 4C/8T · 15,7 GB
- Binário Godot exato / versão Voxel Tools / variante module ou GDExtension: `Godot_v4.7.2-stable_win64` 4.7.2.stable.official.ed1daf0bf / Voxel Tools 1.7 (`v1.7x`) / **GDExtension**
- Comandos executados / logs relevantes / links internos a screenshots, se houver: `docs/voxel_spike_results.md` §3; `docs/evidence/*.log|*.json`; `docs/evidence/screens/*.png`
- Testes manuais (quem, quando, resultado) e limites: Claude via computer use (input sintético), 22/10/2026 ~18:01–18:06, resultados em §6. **Falta uma pessoa** avaliar a sensação de mouse e câmera e abrir/atravessar o túnel à mão.
- Medições reais (FPS, tempos e memória) ou “não medido”: FPS médio 55,8–58,1 e p95 61–62 durante o roteiro em janela; tempos de collider e reset na §4. **Memória: não medida.**
- Bug encontrado / reprodução / correção tentada / status: B1 segfault intermitente na 1ª importação limpa (mitigado, aberto); B2 película SDF=0 (corrigido); B3 toque rápido em G/H perdido (corrigido)
- Gate geral P0: **FALHOU por 1 critério (B1, importação limpa intermitente, mitigado).** Os demais 10 critérios PASSARAM. A sensação dos controles ainda pede validação humana.
