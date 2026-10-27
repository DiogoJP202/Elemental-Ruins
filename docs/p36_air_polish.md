# P3.6 M3 — Ar: frente de pressão, exposição e resposta por massa

Implementado em 26/10/2026. Resource: `scripts/abilities/air_tuning.gd` + `data/abilities/air_tuning.tres`, editável no
inspetor (grupos Frente, Impulso e materiais, Apresentação). Controles preservados: 4 seleciona Ar; LMB é toque. Nenhuma
habilidade nova.

## Simulação
- **Frente como casca móvel:** o clique captura a origem (mão) e a direção (mira); a casca esférica, recortada por um cone de
  35°, avança a 30 m/s até 10 m (≈ 0,33 s). Corpos a até 1,5 m contam mesmo fora do ângulo (padrão do P3).
- **Uma decisão por corpo por onda:** no tick em que a casca alcança o centro do corpo (raio anterior < d ≤ raio atual), o corpo
  é marcado como tratado, inclusive se estiver bloqueado ou fora do cone. Não há nova tentativa. Corpo que entra na esteira
  depois da casca não é atingido retroativamente.
- **Exposição:** 5 raios (centro e quatro pontos da silhueta perpendicular à frente, a 70% da menor meia-extensão),
  máscara TERRAIN|PROPS, alvo excluído, `hit_from_inside`/`hit_back_faces` e testemunhas de ±1 mm (D44) só em falha.
  Exposição = fração de raios livres. Zero = nenhum efeito; parcial reduz impulso e AIRFLOW na mesma proporção.
- **Resposta por massa:** impulso = min(massa × 12 m/s, 1500 N·s) × força × exposição, força = 1 − (d/10)². Caixa leve atinge o
  teto de Δv; acima de 125 kg vale o teto de impulso (Δv inverso à massa). AIRFLOW = força × exposição (apaga fogo fraco,
  aviva o forte, seca umidade), uma vez por corpo por onda.
- **Obstáculos estáticos** (sem RigidBody3D) bloqueiam visadas, mas não recebem contato, AIRFLOW nem poeira.
- **Limites:** até 4 ondas simultâneas (teto do pool de anéis); recuperação de 0,15 s entre toques (recusas contadas). A troca de
  elemento não cancela uma frente já emitida (não há antecipação); reset/save/load descartam frentes e recuperação no sinal
  de início do comando.
- Eventos `air_launch`, `air_contact` (com onda, corpo, distância, força, exposição, impulso e massa) e `air_end`, todos com id,
  sessão, geração e tick do contexto do controlador. Observabilidade local; não é rede nem rollback.

## Apresentação (só lê estado)
Sopro curto na mão ao emitir; anel na seção do cone acompanhando a casca real (um por onda, slot estável, alfa decresce com
o alcance, turbulência só visual na seção); poeira em cada contato efetivo e no chão a cada 2 m de passagem da frente
(consulta somente leitura). Pools fixos: 4 anéis, 6 emissores de poeira, 2 sopros.

## Verificação
Comando: `powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage m3 -TestIds T31,T32,T33,T34,T35,T36,T37,T46,T47,T48,T49,T50,T51,T52,T53,T54,T56,T57 -Window`.
Contrato `p36` atualizado com T52, T53, T54 e T56 (T57 passou a cobrir Fogo e Ar).
- Editor headless: 19/19 PASS, zero erros/avisos. Editor janela: 19/19 PASS, zero erros/avisos; capturas em
  `docs/evidence/p36/m3/screens/`.
- **T52**: caixas a 3,00/6,32/9,37 m recebem a frente em 0,100/0,217/0,317 s (esperado d/30 = 0,100/0,211/0,312 s; prazo + 2
  ticks); velocidade zero antes do contato e primeiro movimento no tick seguinte ao impulso; 3 contatos na onda.
- **T53**: mesma distância (5 m, força 0,75, exposição 1): 20 kg → Δv 9,00 m/s (teto de Δv), 200 kg → 5,625 m/s e 2000 kg →
  0,5625 m/s (teto de 1500 N·s); erro < 0,0001 m/s; razões 1,60 e 10,0. 3 contatos, 3 eventos AIRFLOW, um por corpo.
- **T54**: parede de 1 mm: exposição zero (5 raios), velocidade 0, nenhum AIRFLOW, contato ou poeira. Borda da parede cobrindo
  só a amostra esquerda: exposição 0,8 contra 1,0 da gêmea, Δv 5,544 contra 6,930 m/s (razão 0,800). Morro de terreno: velocidade
  0 e nenhum AIRFLOW. Poeira: 2 de contato para 2 contatos efetivos; 11 de passagem (teto 15 em 3 ondas); anéis voltam a 0.
- **T56**: variante 15 m/s / 6 m / 300 N·s: chegada 0,283 s (esperado 0,270 s + 2 ticks), 200 kg com Δv 0,818 m/s (= 300/200 ×
  força), caixa a 7 m (além do alcance) parada. Limite de 2 ondas: 2 aceitas, 1 recusa. Recuperação 0,15 s (padrão 0,15 s). 17
  eventos com ids únicos e crescentes, sessão atual, onda, tick e habilidade.
- **T57**: reset/save/load com frente viva (além dos três casos do Fogo): nenhuma frente no sinal de início, sessão trocada,
  nenhum contato, evento de material ou FX depois; a caixa preservada pelo save fica parada.
- **T34** (adaptado): caixa 9,27 m/s e 6,2 m; escondida atrás do morro 0; fogo fraco apaga; fogo forte vai a 1,0; rocha de
  6973 kg a 0,093 m/s (< 1/10 da caixa). **T36**: passos de ar empurram a caixa 4,5 m e alcançam os 2 destroços com visada.
- Regressões de Água e Fogo (T31–T33, T35, T46–T51) seguem PASS com o ElementalFx compartilhado.
- Capturas revisadas: anel da frente na seção do cone a meio caminho com poeira de contato e caixas empurradas; caixas após a
  passagem; resposta por massa; exposição parcial atrás da borda da parede.

## Desempenho
Mesma máquina e método do M2 (T37 agregado em janela, 1600×900, Forward+, Jolt; não é custo GPU isolado).

| T37 editor janela | p95 ms | p99 ms | máximo ms |
|---|---|---|---|
| HEAD corrigido (8c4beaf) | 19,67 | 21,23 | 30,13 |
| M1 | 18,92 | 19,91 | 38,37 |
| M2 final | 18,64 | 20,06 | 30,29 |
| M3 final | 18,45 | 19,73 | 32,68 |

Limites 20/33/50 ms passaram. CPU por sistema na janela do T37 (janela, médias): avanço do fogo 41 µs/tick ativo; tick térmico
1,88 ms a cada 0,2 s (propagação 1,79 ms; 2036 consultas, 176 bloqueadas); VFX de fogo/ar 41 µs por quadro (máximo acumulado
1,8 ms). As quatro rajadas do T37 são curtas; o custo da exposição (5 raios por corpo alcançado, testemunhas só em falha)
aparece no avanço do ar, sem contador separado no T37. A rodada anterior (antes da tolerância de 1 µs no cooldown) teve
18,58/20,05/31,41 ms.

## Mudanças semânticas e limites
- T34 e T36 liam a resposta no tick seguinte ao clique. Com a frente progressiva, leem no tick seguinte ao contato (T34) ou
  depois que a frente percorre o alcance (T36). Prazo de chegada exigido pelo T52; limiares físicos inalterados.
- `last_gust.hit` cresce durante a onda; `blocked` passa a contar corpos com exposição zero por terreno **ou** corpos opacos.
- Frente é modelo de jogo (casca + amostragem), não CFD: não há esteira, sucção, contorno de obstáculos nem pressão
  acumulada em espaços fechados.
- Exposição por 5 amostras é aproximação; corpos muito finos ou rotacionados podem ter pontos de silhueta fora do volume.
- Raycasts: as amostras sem falha não provam correção universal.
- Avaliação humana de controles, legibilidade e game feel: **NÃO TESTADO**.
