# P3.6 — polimento elemental (Água, Fogo e Ar): relatório final

Concluído em 26/10/2026 na worktree `charming-mendel-4b469a`, branch `claude/charming-mendel-4b469a`. Sem push e sem merge
na `main`. Nenhuma habilidade nova; Terra (P3.5) intacta. Avaliação humana de controles, legibilidade e game feel:
**NÃO TESTADO**.

## Commits
| Etapa | Commit | Conteúdo |
|---|---|---|
| Preparação | `9788e7b`, `08b6c6e`, `84aaf69`, `7f3701d` | Runners sem falso sucesso, contrato de IDs e zero erros/avisos; fim de traço e raio sobre vértice (T8); estabilização |
| Baseline corrigido | `8c4beaf`, `b3a2380` | 51/51 nos quatro modos (`docs/p36_baseline_corrected.md`) |
| M0 | `32fdf18` | Auditoria, spikes comparativos e contratos (`docs/p36_m0.md`) |
| M1 Água | `1670325` | Pacotes, pressão, respingos com visada (`docs/p36_water_polish.md`) |
| M2 Fogo | `33d26ba` | Antecipação, varredura recortada, impacto único, propagação com visada (`docs/p36_fire_polish.md`) |
| M3 Ar | `6167e97` | Casca de pressão, exposição, resposta por massa (`docs/p36_air_polish.md`) |
| M4 | este commit | T55/T58, bateria completa nos quatro modos, este relatório, README |

## Arquitetura resultante
```
WaterTuning / FireTuning / AirTuning (.tres, inspetor)   ← tempos, velocidades, tetos e apresentação
        ↓
WaterJet / FireBurst / AirGust (Ability)                 ← simulação limitada: pacotes, projéteis, frentes
        ↓ ElementalEvent (id, sessão, geração, tick)
MaterialResponseSystem                                    ← calor, umidade, combustível, AIRFLOW, propagação com visada
        ↓ sinais / fx_event (só leitura)
ElementalFx                                               ← VFX em pools fixos, slots estáveis por id
```
- Comandos (AbilityController: seleção, LMB, cancelamento, sessão) separados da simulação; materiais separados dos VFX.
- Reset/save/load: `cancel_all` incrementa a sessão e cada poder limpa sua simulação no sinal de início do comando (T57).
- PvP preparado, sem rede: tempos configuráveis e determinísticos a partir do clique, eventos identificáveis, cancelamento
  antes da emissão (Fogo), recuperação contada, sem pausa nem `time_scale` global.

## Resumo por elemento
| Elemento | Antes (P3) | Depois (P3.6) |
|---|---|---|
| Água | Raio único instantâneo de 14 m; força absoluta | Pacotes a 30 Hz e 30 m/s com origem/direção/pressão capturadas; pressão em 0,12 s; impulso ∝ duração × pressão; respingos só com visada; MultiMesh ≤ 24 |
| Fogo | Explodia também no fim do alcance (calor remoto); área atravessava paredes | Antecipação 80 ms com mira do clique; uma varredura por tick recortada em 30 m; calor uma vez no contato; dissipação sem calor; propagação com visada; recuperação 0,14 s |
| Ar | Cone instantâneo no clique; só terreno bloqueava | Casca a 30 m/s; uma decisão por corpo por onda; exposição por 5 raios (terreno e corpos); impulso min(m·12, 1500)·força·exposição; 4 ondas; recuperação 0,15 s |

## Testes do P3.6
| ID | Prova | Resultado |
|---|---|---|
| T46–T48 | Água: transporte, cancelamento/tuning, parede fina, origem dentro de prop, massa | PASS nos 4 modos |
| T49 | Fogo: antecipação sem calor, mira do clique, cancelamento, recuperação, limites, tuning | PASS nos 4 modos |
| T50 | Fogo: parede de 1 mm, corpos adjacentes, alcance recortado, dissipação sem calor remoto | PASS nos 4 modos |
| T51 | Propagação com parede e terreno; umidade, combustível, carbonização, resfriamento | PASS nos 4 modos |
| T52 | Ar: nada antes da casca; chegada em d/v + 2 ticks | PASS nos 4 modos |
| T53 | Ar: tetos de Δv e impulso; resposta inversa à massa; um contato por corpo/onda | PASS nos 4 modos |
| T54 | Ar: parede, exposição parcial, terreno; poeira só de contatos e passagem | PASS nos 4 modos |
| T55 | Interações cruzadas Água/Fogo/Ar | PASS nos 4 modos |
| T56 | Ar: tuning usado, limite de ondas, recuperação, eventos identificáveis | PASS nos 4 modos |
| T57 | Reset/save/load sem antecipações, voos, frentes ou eventos tardios | PASS nos 4 modos |
| T58 | VFX limitados sob estresse e sem vazamento após reset | PASS nos 4 modos |

## Bateria final
Comando: `powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage final -Window -Export` (contrato `p36`:
P0–P3.5 + T46–T58, 64 testes). Evidências em `docs/evidence/p36/final/`. Mesma máquina do baseline (i5-1135G7, Iris Xe,
1600×900, Forward+, Jolt). Headless não aprova renderização.

| Modo | Testes | Erros/avisos | T27 p95/p99/máx ms | T37 p95/p99/máx ms | Duração s |
|---|---|---|---|---|---|
| editor_headless | **FAIL 63/64 (T26)** | 0/0 | 8,05/8,60/12,75 | 8,41/9,71/14,88 | 332 |
| editor_window | PASS 64/64 | 0/0 | 17,73/18,49/20,13 | 18,51/19,63/34,77 | 395 |
| export_headless | PASS 64/64 | 0/0 | 7,69/7,94/8,35 | 8,16/9,69/12,87 | 333 |
| export_window | PASS 64/64 | 0/0 | 17,57/17,98/18,36 | 18,99/21,34/30,44 | 393 |

Limites em janela (p95 ≤ 20, p99 ≤ 33, máx ≤ 50 ms) passaram nos dois modos de janela. Baseline corrigido (8c4beaf), T37:
editor 19,67/21,23/30,13 e export 18,16/19,37/30,80 ms; M2/M3 em janela 18,64/20,06/30,29 e 18,45/19,73/32,68 ms. Rodadas
diferentes; não há atribuição causal.

**O gate final não foi cumprido**: o T26 (P2, salvar/carregar com a torre caída; não usa os poderes) falhou no editor
headless: depois do save, a peça `P30_coroa` caiu 0,59 m (limite 0,1 m), embora não tenha se mexido durante o save, a espera
por collider tenha passado em 0 quadros e o controle sem save tenha ficado parado (0,001 m). Repetido isolado no mesmo HEAD:
**1 falha em 8** (0,159 m, `P19_pilar1`); as outras 7 ficaram entre 0,004 e 0,019 m (`docs/evidence/p36/final/t26_repeticoes/`).
Histórico de passes desde o P2: pior peça 0,004–0,072 m, quase sempre coroas ou pilares apoiados em destroços — o T26 tinha
margem pequena antes do P3.6. A causa não foi isolada; o critério não foi relaxado. Hipótese a investigar: após recriar o
terreno do disco no save, uma peça apoiada em borda escavada ou em outra peça escorrega quando todas são descongeladas ao
mesmo tempo (a espera só confere terreno sob cada corpo, não apoios entre peças).

## Raycasts e visibilidade (amostras, não prova universal)
| Cenário | Tentativas | Acertos | Falhas | Testemunhas de 1 mm usadas |
|---|---|---|---|---|
| Fogo × parede de 1 mm (T50, por modo) | 6 | 6 | 0 | 0 |
| Fogo × corpos adjacentes (T50) | 1 | 1 | 0 | 0 |
| Fogo × face além do alcance, recorte (T50) | 1 | dissipação correta | 0 | — |
| Água × parede de 1 mm e origem dentro de prop (T48) | contato contínuo | PASS | 0 | — |
| Ar × parede de 1 mm (T54) | 5 raios | 5 bloqueados | 0 | 0 |
| Ar × exposição parcial (T54) | 5 raios | 4 livres / 1 bloqueado (esperado) | 0 | 0 |
| Propagação × parede de 1 mm (T51) | 156 consultas | 44 bloqueadas (corretas) | 0 | — |

Amostras sem falha não provam correção universal.

## Mudanças semânticas documentadas
- T37: o Fogo conta disparos aceitos, lançamentos e conclusões (impactos + dissipações), porque o fim do alcance não aquece
  mais; limites de FPS inalterados; T50 cobre impacto e dissipação separadamente.
- T34: observa a resposta no tick seguinte ao contato da frente; separado em duas rajadas porque corpos agora bloqueiam o ar
  (as caixas em chamas do P3 deixavam a caixa de massa com exposição zero). Limiares inalterados.
- T36: lê a lista de corpos da rajada depois que a frente percorre o alcance.
- Campos legados mantidos: `exploded` (= impactos), `last_gust.hit/blocked`; `body_ticks/terrain_ticks` da Água contam
  contatos de pacotes.

## Situação
- **Implementado e testado (automação):** tudo listado acima; T46–T58 PASS nos quatro modos. A bateria completa passou em 3 de 4 modos; o editor headless falhou no T26 (intermitente, pré-P3.6 em origem, causa não isolada).
- **Implementado e não testado por pessoas:** controles, legibilidade das antecipações/frentes, game feel e leitura em PvP.
  A antecipação do Fogo fica atrás do capsule na câmera do próprio jogador (retorno local pelo HUD); para observadores ela é
  visível na mão. Precisa de avaliação humana.
- **Não implementado (fora do escopo):** rede, rollback, dano em jogadores, áudio, SPH/CFD, habilidades novas.
- **Pendente:** T26 intermitente (1/8 isolado); o gate final do P3.6 só fica cumprido quando a bateria passar nos quatro modos com a causa corrigida.

## Riscos
- Tick térmico com visibilidade custa ~1,8–2 ms a cada 0,2 s com ~13 corpos em chamas (T37). Cabe no gate, mas cresce com o
  número de corpos; se necessário, espalhar a propagação entre ticks.
- Pico isolado de 109,5 ms no avanço do Fogo em uma rodada de janela do M2 (callbacks de impacto/ignição), não reproduzido
  nas rodadas seguintes; causa não isolada.
- Exposição do Ar por 5 amostras e visibilidade centro→centro do calor são aproximações conservadoras.

## Próximo passo recomendado
Investigar e corrigir a causa do T26 intermitente (apoio entre peças ao descongelar depois do save) e repetir a bateria nos
quatro modos; em seguida, playtest humano pelo roteiro do P3.6 no README.
