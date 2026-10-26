# P3.6 M1 — Água: transporte, pressão e contato

Implementado em 26/10/2026. Resources: `scripts/abilities/water_tuning.gd` e `data/abilities/water_tuning.tres`, editáveis no inspetor. Controles preservados: 2 seleciona Água; segurar LMB emite, soltar interrompe.

## Simulação
- Pacotes a 30 Hz, velocidade 30 m/s, alcance 14 m, teto padrão 32 (limite absoluto 64). Cada pacote captura origem, direção, pressão e duração de emissão. Girar a mira não gira os pacotes já em voo.
- Varredura de cada deslocamento antes de efeitos. A mão dentro de prop também bloqueia o jato (`hit_from_inside`); normal zero recebe fallback contra o transporte.
- Pressão sobe em 0,12 s por smoothstep. Variação limitada de pressão representa turbulência; impulso = força de 300 N × duração do pacote × pressão, e WET = 0,5/s × a mesma duração. Não aplicar impulsos por frame sem considerar a duração emitida.
- Contato aplica molhamento, resfriamento e extinção no MaterialResponseSystem. Respingos verificam terreno/props por alvo a partir do lado livre do contato. Soltar, trocar elemento, reset/save/load descartam pacotes.
- Eventos recebem sequência, sessão, geração e tick para correlação local. Não é rede nem promessa de determinismo bit a bit.

## Apresentação
MultiMesh de até 24 volumes sobre os pacotes reais, variação de cor/raio, ondulação leve e respingo só no contato. Amostragem distribuída inclui frente e emissão quando o tuning usa mais pacotes que o teto visual. Resíduo visual desvanece em 0,12 s sem alterar física. Sem cilindro instantâneo cobrindo todo o alcance.

## Verificação
Comando: `powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage m1 -TestIds T31,T33,T37,T46,T47,T48 -Window`.
- Editor headless: 7/7 PASS, zero erros/avisos.
- Editor janela: 7/7 PASS, zero erros/avisos, capturas em docs/evidence/p36/m1/screens/.
- T46: contato físico a 4,90 m em 0,167 s; após virar 90°, novo alvo atingido em 0,183 s, sem efeito precoce. Pressão pronta em 0,133 s.
- T47: Resource variante a 12 m/s, rise 0,24 s, força zero e teto de 2 pacotes altera os resultados; release/cancel/clear não deixam contatos posteriores.
- T48: parede de 1 mm mantém o alvo atrás seco, lado exposto molha/resfria; origem dentro de prop é bloqueada, sem contato no corpo atrás. Massas 20/2000 kg obedecem Δv=impulso/massa (tolerância 12%).
- T33: extinção de fogo forte em 1,745 s na regressão inicial (<3 s), causa água e vapor.
- Origem interna foi adicionada durante a rodada headless inicial; também executada em uma verificação headless separada (inside_origin_headless.json).

## Desempenho
Mesma máquina e configuração do baseline: i5-1135G7, Iris Xe, Godot custom 4.7.2/Voxel Tools1.7, Jolt, Forward+, 1600×900. Método T37 agregado, quadro medido por process_frame; não é custo GPU isolado.
| T37 editor janela | p95 ms | p99 ms | máximo ms |
|---|---|---|---|
| Histórico P3.5 | 19,2 | 21,8 | 36,4 |
| HEAD corrigido | 19,67 | 21,23 | 30,13 |
| M1 | 18,92 | 19,91 | 38,37 |
Todos os limites 20/33/50 ms passaram. Variação entre rodadas não comprova ganho causal. Transporte padrão tem cerca de 14 pacotes em voo, não apenas um raycast por tick; o spike de 16 segmentos mediu 73 µs por lote CPU em headless. O gate real agregado acima prevalece.

## Limites
É transporte de jogo limitado, não solver volumétrico SPH. Os volumes visuais não são corpos físicos e os respingos decorativos não simulam gotas individuais. Os campos body_ticks/terrain_ticks mantêm nome histórico, mas agora contam contatos de pacotes. Avaliação humana de controles, legibilidade e game feel: **NÃO TESTADO**.