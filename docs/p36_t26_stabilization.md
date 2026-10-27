# P3.6.1 — estabilização do save com destroços (T26)

**Data:** 26–27/10/2026. **Gate técnico P3.6/P3.6.1: PASSOU nos protocolos corrigidos.**

A intervenção `freeze → thaw` acordava corpos em equilíbrio precário e foi suficiente para produzir deslocamento de **0,533 m sem reconstruir terreno**. A correção mantém terreno, colliders e corpos vivos durante o save. Uma segunda causa de falso repouso no T26 foi corrigida na preparação do teste, mantendo seu limite de **0,1 m** e sua medição pós-save de **1,5 s**.

A nova série prospectiva passou **30/30**, com oito ordens de colapso, zero falhas de preparação e **pico de deslocamento 0,000 m em cada repetição**. A bateria P0–P3.6 passou **64/64 nos quatro modos**, zero erros e avisos, incluindo os limites de desempenho. Persistência entre processos passou nas quatro fases; E1–E7 passaram. A primeira série ampliada continua **59 PASS e 1 FAIL**, e a série diagnóstica legada continua incompleta com **10 PASS e 1 FAIL**: nenhuma falha foi apagada ou convertida em aprovação retrospectiva.

Base de trabalho: branch `codex/p36-t26-stabilization`, criada de `657ccb38cfcc516d38474aca0d40eae390aadfe1`, correspondente a `claude/charming-mendel-4b469a`. Runtime: Godot **4.7.2.stable.custom_build.ed1daf0bf**, Voxel Tools **1.7 como módulo**, Jolt Physics. Cada experimento preserva seu `environment.json`, com os hashes dos scripts executados; o nome da branch sozinho não identifica código com alterações locais.

## 1. Falha e reprodução

A versão legada do T26, em `scripts/dev/p2_selftest.gd`, derruba a torre de 36 peças, aguarda velocidades lineares abaixo de 0,05 m/s em uma observação, observa um controle sem save de 2 s, salva e compara posições após 1,5 s. O limite continua **estritamente menor que 0,1 m**. O teste também verifica carregar o terreno escavado e carregar um slot sem escavação. A verificação legada de repouso não exige `sleeping` nem velocidade angular nula e não revalida o repouso após o controle.

| Evidência | Resultado observado |
|---|---|
| [Final P3.6 anterior](evidence/p36/final/editor_headless.json) | T26 FAIL: `P30_coroa`, 0,590413 m após o save; controle sem save 0,001014 m; movimento durante o save 0 m |
| [Oito repetições históricas](evidence/p36/final/t26_repeticoes/resumo_8_execucoes.txt) | 1/8 FAIL: `P19_pilar1`, 0,159278 m; sete passes entre aproximadamente 0,004 e 0,019 m |
| [Nova baseline do T26 original](evidence/p36/t26_stabilization/baseline_t26/summary.json) | 8/8 PASS; deslocamentos entre **0,001905 e 0,074144 m**; controle sem save chegou a 0,064804 m |

A nova baseline sem falha não invalida as falhas preservadas nem estabelece uma frequência confiável: são oito amostras, com colapsos e estados de contato variáveis. Nenhuma dessas séries autoriza aumentar a tolerância.

## 2. Experimento causal: física normal, suspensão e save

O probe separado `scripts/dev/t26_physics_probe.gd` usa a cena e os serviços reais. Cada combinação roda num **processo novo**, sequencialmente. Não substitui o T26 de regressão.

| Cenário | Intervenção |
|---|---|
| A | Física normal, pelo mesmo intervalo de observação |
| B | `Main._freeze_props` + `StructureService.suspend/resume`, sem recriar terreno nem salvar |
| C | Save completo de produção; na rodada causal inicial ainda era a implementação antiga |
| D | Diagnóstico adicional: pausar o espaço físico, salvar diretamente e reativar; mantém o tipo dos corpos |

A rodada [causal_v1](evidence/p36/t26_stabilization/causal_v1/environment.json) fez duas repetições por cenário e disposição, totalizando 16 processos, com contatos do solver **desligados**. A tabela registra os maiores valores entre as duas repetições de cada grupo, em metros; o [resumo individual](evidence/p36/t26_stabilization/causal_v1/summary.json) contém todos os casos.

| Disposição | Cenário | PASS/total | Endpoint em 1,5 s | Pico nos 90 ticks |
|---|---|---:|---:|---:|
| Torre caída | A | 2/2 | 0 | 0 |
| Torre caída | B | **1/2** | **0,523727** | **0,532618** |
| Torre caída | C antigo | 2/2 | 0,013564 | 0,013568 |
| Torre caída | D | 2/2 | 0 | 0 |
| Duas pilhas | A | 2/2 | 0 | 0 |
| Duas pilhas | B | 2/2 | 0,002190 | 0,002994 |
| Duas pilhas | C antigo | 2/2 | 0,002744 | 0,003937 |
| Duas pilhas | D | 2/2 | 0 | 0 |

No [B002 da torre](evidence/p36/t26_stabilization/causal_v1/headless_tower_B_002.json), `P16_pilar1` atingiu o pico de **0,532618403 m no tick 77**; o controle sem intervenção ficou em 0,002269 m. Não houve mudança de posição durante a suspensão. O [trace ZIP](evidence/p36/t26_stabilization/causal_v1/headless_tower_B_002_trace.zip) mostra:

- Antes: 36 corpos dormindo no estado direto do PhysicsServer; imediatamente após thaw: **0 dormindo**. O campo `sleeping` do nó ainda mostrava 36 naquele instante, antes da sincronização; ler somente o nó esconderia essa transição.
- Terreno não foi recriado em B; os raios continuaram encontrando as mesmas superfícies de apoio. A peça problemática estava junto à borda escavada, sem vizinho de caixa próximo no diagnóstico geométrico.
- A maior penetração caixa–caixa por SAT era **0,0200022035 m antes e imediatamente depois**, com 37 pares penetrantes. Não surgiu uma grande penetração inicial durante o congelamento.
- O movimento posterior é gradual. Os dados não demonstram uma explosão do solver, desaparecimento do chão ou teleporte.

O mecanismo de mudança de estado é confirmado no código da versão usada: `JoltBody3D::set_mode` chama `SetMotionType`, acorda o corpo ao retornar de Static e executa `_mode_changed`, que também acorda. Na implementação de Jolt embutida, entrar em Static zera velocidades linear/angular e limpa forças/torques. Portanto, `freeze` não é uma pausa transparente de um corpo dinâmico. Fontes: [integração Jolt da Godot, commit ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/jolt_physics/objects/jolt_body_3d.cpp#L1071), [Body::SetMotionType](https://github.com/godotengine/godot/blob/ed1daf0bf/thirdparty/jolt_physics/Jolt/Physics/Body/Body.cpp#L34).

**Conclusão sustentada:** a transição de modo e o despertar produzidos pela suspensão antiga bastam para desencadear reacomodação excessiva; recriar o terreno não é condição necessária. **Não ficou provado** um defeito específico de manifold/cache/solver. Duas amostras de A/C/D também não excluem outros caminhos de falha.

A primeira tentativa de isolar a pose, [wake_pose.json](evidence/p36/t26_stabilization/wake_pose.json), tem `experiment_valid=false`, motivo `initial_pose_or_sleep_not_preserved`, e não serve como prova. A execução corrigida [wake_pose_final.json](evidence/p36/t26_stabilization/wake_pose_final.json) validou o estado inicial e a hipótese (`experiment_valid=true`, `hypothesis_supported=true`, zero erros/avisos):

| Intervenção na pose isolada de P16 | Pico em 90 ticks | Endpoint | Sono direto imediatamente após |
|---|---:|---:|---|
| Controle, sem intervenção | 0 m | 0 m | Preservado |
| Apenas acordar | **0,532663524 m** | 0,523893654 m | Acordado |
| Freeze/thaw | **0,532663524 m** | 0,523893654 m | Acordado |

O corpo começa dormindo na pose registrada, sem vizinhos físicos e sobre o terreno intacto. Acordar sozinho é suficiente **nesse experimento de pose**; não é prova sobre a frequência de falhas no colapso completo. A tentativa anterior em `causal_neutral/` falhou ao carregar um probe ainda incompleto (`_box_geometry` ausente), não gerou relatório válido e foi excluída das contagens. O spike aceita o JSON original ou seu ZIP arquivado e registra o SHA256 dos bytes do trace usado.

### Contatos do solver: observação com efeito sobre a simulação

`contact_monitor` e `max_contacts_reported` ficam nos valores originais por padrão. Habilitar relato de contatos pode alterar o comportamento do backend e, por isso, esses casos são diagnósticos separados. As duas execuções [contacts](evidence/p36/t26_stabilization/contacts/summary.json), cenário B na torre, passaram com máximos finais 0,019189/0,020967 m e picos 0,019729/0,021494 m. Não reproduzir a falha nessas duas execuções instrumentadas não corrige nem refuta B002.

## 3. Correção implementada: salvar preservando o mundo vivo

`Main.request_world_save` chama o serviço sem congelar jogador, props ou estruturas. O save deixa de liberar/recriar `VoxelLodTerrain`; não altera `MotionType`, `sleeping`, velocidades, transforms nem metadados de estacionamento para manter destroços no lugar. Um corpo ativo continua seguindo a física normal durante os quadros assíncronos do save.

O fluxo em `TerrainService.save_world` é:

1. Entrar no estado ocupado de save, bloquear novas edições pelos contratos existentes e desabilitar temporariamente o processamento **do nó de terreno**, impedindo novo agendamento regular.
2. Esperar `_flush_modified_blocks`, incluindo a gravação em voo de um save anterior abortado.
3. Esperar dois ticks consecutivos com contadores globais de `streaming` e `generation` zerados em `VoxelEngine`.
4. Sem `await` no trecho crítico: fechar as conexões do stream com `database_path=""`, publicar uma cópia da sessão e reabrir o mesmo caminho.
5. Restaurar o modo de processamento anterior e liberar o estado ocupado, tanto no sucesso quanto nos retornos de falha previstos.

Isso preserva os mapas de dados, malhas e colliders existentes. O tracker do save não substitui a drenagem: podem existir loads ou saves de unload anteriores. O setter do caminho protege seu pool e fecha conexões disponíveis, mas não constitui uma barreira para conexões já emprestadas a workers. A implementação deve ser reavaliada se mudar a versão do plugin. Fontes Voxel Tools v1.7: [stream SQLite](https://github.com/Zylann/godot_voxel/blob/v1.7/streams/sqlite/voxel_stream_sqlite.cpp#L77), [save do terreno](https://github.com/Zylann/godot_voxel/blob/v1.7/terrain/variable_lod/voxel_lod_terrain.cpp), [estatísticas do engine](https://github.com/Zylann/godot_voxel/blob/v1.7/engine/voxel_engine.cpp).

### Publicação do slot e falhas de I/O

`TerrainSaveFiles.publish_snapshot` copia primeiro para um temporário, move o slot anterior para um backup e publica o temporário no destino. Se a publicação falhar, tenta restaurar o backup; se até o rollback falhar, mantém o caminho de recuperação no resultado.

Não se usa rename sobre um destino já existente: no backend Windows desta Godot essa operação remove o destino antes de chamar `MoveFileW`. A publicação com backup reduz perda em falhas retornadas de I/O, mas **não é uma transação resistente a crash ou falta de energia**. Existe um intervalo em que o nome final pode estar ausente; recuperação automática após interrupção abrupta não foi implementada nem testada. Fonte: [DirAccessWindows::rename](https://github.com/godotengine/godot/blob/ed1daf0bf/drivers/windows/dir_access_windows.cpp#L288).

## 4. Medição e cobertura posteriores à correção

O probe conserva o endpoint de 1,5 s e acrescenta o **pico de deslocamento em cada um dos primeiros 90 ticks**. Ambos devem ficar abaixo de 0,1 m; movimento que volte ao ponto inicial também pode reprovar. O trace detalhado captura seis ticks anteriores, todos durante a operação, os primeiros 30 posteriores e o endpoint, sem adiar o começo da medição.

Cada snapshot registra transform, freeze/mode, sleeping do nó e do estado direto, velocidades, raios de apoio contra terreno e corpos, pares de sobreposição e SAT de caixas. O SAT usa 15 eixos, com gap assinado; não inclui margens de colisão e seu gap positivo não é distância euclidiana. Os raios são amostras, não uma prova universal de sustentação.

As 30 repetições variam oito ordens cíclicas/invertidas de escavação dos pés da torre. As pilhas são duas colunas de quatro caixas, com deslocamentos alternados de até 0,04 m por nível. `layout_variant` registra a disposição concreta. O caso de pilhas exige pelo menos quatro corpos apoiados em outros corpos e dois apoiados no terreno; uma pilha já desfeita não satisfaz a cobertura.

Antes, imediatamente depois e no endpoint são registrados `terrain_instance_id` e RIDs dos colliders atingidos. O resumo também informa mudanças de sleeping/freeze/velocidades. Identidade preservada é verificada nas amostras observadas; igualdade dos RIDs de alguns raios não cobre todos os colliders do mundo.

Os traces são compactados após o processo. O runner verifica entrada única, tamanho e SHA256 do conteúdo descomprimido antes de remover o JSON raw. [trace_archives.json](evidence/p36/t26_stabilization/post_fix_30/trace_archives.json) e `summary[].trace_archive` mapeiam o caminho original para o ZIP. `-KeepRawTrace` mantém ambos; `-Trace:$false` desliga somente o trace detalhado, preservando pico e resumos. Os relatórios brutos não são reescritos para fabricar caminhos posteriores.

### Primeira série ampliada: 59 PASS e 1 FAIL preservado

A série [post_fix_30](evidence/p36/t26_stabilization/post_fix_30/summary.json) terminou os 60 processos previstos: 30 pilhas PASS e 29/30 torres PASS. Todos os 59 passes tiveram pico e endpoint 0 m. **A série completa falhou.**

O caso `headless_tower_C_024` teve endpoint **2,131323338 m** e pico **2,136294127 m**, no tick 54, em `P11_pilar0`. Seu controle anterior sem save já havia deslocado a mesma peça **0,512438893 m**. No snapshot antes do save, P11 estava acordado com velocidade linear **1,438 m/s** e angular aproximada de **0,382 rad/s**; P09 e P10 também estavam ativos. P11 já acelerava nos cinco ticks anteriores. O save durou três ticks e o deslocamento imediato foi 0,076232 m, mantendo tipos e estados de sono, a instância do terreno e os RIDs observados antes/imediatamente depois. Um RID adicional aparece no endpoint após a peça mudar de região; não se afirma igualdade de todo o conjunto final.

Isso mostra que `settled=true` legado não garante cena parada no momento do save. A falha continua FAIL; os dados não isolam uma contribuição do save sobre uma queda que já ocorria. Não se usa o controle como filtro retrospectivo: 15/30 torres moveram mais de 5 mm no controle, e o C013 passou após controle de 0,103565 m. Esses casos permanecem no denominador original.

Uma segunda série com o T26 legado, [original_post_fix_30](evidence/p36/t26_stabilization/original_post_fix_30/summary.json), foi deliberadamente interrompida após **11 dos 30 processos planejados: 10 PASS, 1 FAIL**. O FAIL, trial 3, moveu `P28_coroa` **0,206406087 m**; a velocidade antes do save já era 0,085586 m/s e o controle moveu 0,044245 m. [interruption.json](evidence/p36/t26_stabilization/original_post_fix_30/interruption.json) registra execução incompleta. Não é uma série aprovada de 30 casos.

### Nova pré-condição prospectiva, sem grace após o save

O probe agora oferece **`-NaturalRest` / `--probe-natural-rest` opt-in**, preservando seu default legado e os resultados anteriores. Depois do preparo e do predicado legado, observa até **60 ticks consecutivos** de sono natural no estado direto do PhysicsServer, sem freeze/estacionamento e com velocidades linear/angular até `1e-5`, dentro de prazo fixo de **30 s**. Nunca força `sleeping`.

Segue-se um controle de 2 s que mede pico em cada tick, eventos de despertar e velocidades. O controle deve permanecer naturalmente adormecido, sem despertar nem movimento acima de 5 mm. Os seis ticks do trace anterior e uma consulta imediatamente antes da intervenção revalidam o estado. Se qualquer pré-condição falhar, o caso é **`SETUP_UNSTABLE` / FAIL**, preserva observações, controle e trace, não executa a intervenção e não recria a disposição para tentar passar.

As tentativas de setup são contabilizadas separadamente das intervenções executadas. A medição após uma intervenção válida começa imediatamente, mantém os 90 ticks e o limite de 0,1 m. O protocolo novo não transforma C024 ou a série anterior em passes e não autoriza ocultar futuras instabilidades de preparo.

### Dois defeitos e duas mudanças distintas

1. **Produção:** o save antigo mudava o tipo dos corpos e acordava peças em repouso; a pose isolada reproduziu a reacomodação. A correção do runtime remove a suspensão/recriação do save e preserva a física viva.
2. **Preparação do teste:** um único instante com velocidade linear pequena era aceito como repouso, mesmo quando a cena voltava a se mover durante o controle. A correção prospectiva do T26 confirma **60 ticks consecutivos de sono natural dentro dos mesmos 15 s de prazo**, usando estado direto, velocidades linear/angular finitas até `1e-6`, peças soltas e sem freeze artificial. Seu controle de 2 s exige repouso em todos os ticks; registra a primeira violação e os máximos. Se falhar, o teste falha sem salvar e sem repetir o colapso.

A segunda mudança corrige a premissa de uma medição de save em repouso; **não é uma correção de física em produção**. O T26 continua medindo a partir da chamada de save, espera os mesmos **1,5 s** depois e exige o mesmo **`max_shift < 0.1`**. Não foi inserido grace após o save. Corpos intencionalmente ativos são cobertos separadamente por E2, comparados com um gêmeo em física normal, em vez de serem parados para passar no teste.

## 5. Testes de borda concluídos

O spike `tools/spike_t26_save.gd` roda a cena real com sessões/slots próprios. A rodada ampliada [edge_save_7.json](evidence/p36/t26_stabilization/edge_save_7.json) passou **7/7**; o [log](evidence/p36/t26_stabilization/edge_save_7.log) não contém linhas de erro, script error ou aviso do motor. A rodada anterior 6/6 e as tentativas exploratórias permanecem preservadas.

| Caso | Prova e resultado final |
|---|---|
| E1 — pilha dormindo | Três corpos mantêm modo e sono; deslocamento em 30 frames 0 m; impulso move o de cima 0,821 m; escavar a base acorda e faz cair; mesma instância de terreno |
| E2 — corpo ativo | Comparado com gêmeo seguindo física normal fora de Props: erro de posição 0,00008392 m; erros linear/angular/rotação 0; save levou dois frames |
| E3 — estacionado | Mantém freeze estático e marca `budget`; escavação depois remove estacionamento e faz cair |
| E4 — slot inválido | Retorna false com mundo pronto, corpo em movimento e terreno preservado |
| E5 — timeout real | Blocos sujos e prazo zero produzem `flush_incomplete`; slot anterior e mundo ficam íntegros; retry espera gravação anterior; reset/carregar recupera o SDF salvo idêntico |
| E6 — destino inválido | Arquivo usado como diretório provoca falha real de I/O; mundo/slot anterior permanecem íntegros e retry válido funciona |
| E7 — timeout de drenagem | `io_timeout` real observado; mundo, colliders, slot anterior, flags e estados físicos preservados; erro contra gêmeo normal 0,00000763 m, velocidades linear/angular idênticas; retry funciona |

O [smoke do T26 original após a mudança](evidence/p36/t26_stabilization/candidate_smoke/summary.json) passou 2/2, com deslocamento final 0 m. É verificação preliminar, não substitui a série ampliada nem os quatro modos.

## 6. Validação final

| Verificação | Estado deste documento | Evidência de acompanhamento |
|---|---|---|
| Primeiros 30 processos com torre caída, preparo legado | **FAIL: 29/30 PASS; C024 preservado** | [summary.json](evidence/p36/t26_stabilization/post_fix_30/summary.json), [environment.json](evidence/p36/t26_stabilization/post_fix_30/environment.json) |
| Primeiros 30 processos com pilhas e variações, preparo legado | **30/30 PASS; não aprova a série conjunta** | Mesmo resumo; cada repetição tem JSON próprio e trace ZIP |
| T26 legado, 30 planejados | **INCOMPLETO: 11 executados, 10 PASS e 1 FAIL** | [Registro de interrupção](evidence/p36/t26_stabilization/original_post_fix_30/interruption.json) |
| Nova série de 30 torres, `NaturalRest` prospectivo | **30/30 PASS, zero setups instáveis, oito ordens de colapso** | [Resumo por repetição](evidence/p36/t26_stabilization/stationary_post_fix_30/summary.json); endpoint e pico de todos os 90 ticks = 0 m em cada caso |
| Estados e identidade durante os 30 saves | **PASS** | Zero mudanças de sleeping/freeze, zero delta de velocidades linear/angular; mesmo nó e todos os RIDs de apoio observados antes/imediatamente depois em 30/30 |
| T26 com preparo prospectivo de cena parada | **PASS nos quatro modos, deslocamento 0 m** | 60 ticks naturais em prazo de 15 s e controle de 2 s; medição/limite após o save inalterados |
| P0–P3.6 completo, editor headless e janela | **64/64 em cada modo, 0 erros / 0 avisos** | [Editor headless](evidence/p36/t26_stabilization/full/editor_headless.json), [editor janela](evidence/p36/t26_stabilization/full/editor_window.json) |
| P0–P3.6 completo, export headless e janela | **64/64 em cada modo, 0 erros / 0 avisos** | [Export headless](evidence/p36/t26_stabilization/full/export_headless.json), [export janela](evidence/p36/t26_stabilization/full/export_window.json) |
| Persistência entre processos | **2/2 em cada fase, 0 erros / 0 avisos** | Editor write/read e export write/read em `full/`; fixture esperada desta execução copiada para lá, bytes anteriores restaurados |
| Critérios de desempenho | **PASS** | T27 e T37 nas duas janelas: p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms |
| Roteiro por pessoa com teclado e mouse | **NÃO TESTADO** | Não é substituído por automação |

Os máximos **de cada repetição**, sem arredondamento na fonte, estão nos JSON individuais e no [CSV de 130 casos](evidence/p36/t26_stabilization/repetition_maxima.csv), incluindo os três FAIL exploratórios/legados. A consolidação [fullsummary.json](evidence/p36/t26_stabilization/fullsummary.json) verifica os resultados individuais e não aceita relatórios ausentes ou incompletos. O runner exige run_id novo, frescor, contrato de IDs, zero erros/avisos no JSON e no log; os nove passos terminaram com exit 0. O preset local de export e a fixture histórica foram restaurados byte a byte. Nenhum arquivo em `scripts/` mudou entre o início da bateria e sua conclusão, conforme os hashes de `full/environment.json`.

Máquina desta validação: **AMD Ryzen 7 5825U, AMD Radeon Graphics, 1600×900, Forward+, Jolt**, diferente da máquina i5/Iris Xe do P3.6 original. Os números não demonstram ganho de desempenho causado pela correção.

| Modo | Testes | Erros/avisos | T26 máximo m | T27 p95 / p99 / máximo ms | T37 p95 / p99 / máximo ms | Duração do selftest s |
|---|---:|---:|---:|---|---|---:|
| Editor headless | 64/64 | 0/0 | 0 | sem render; 8,12 / 8,43 / 9,76 | sem render; 8,00 / 9,63 / 13,53 | 334,166 |
| Editor janela | 64/64 | 0/0 | 0 | 17,50 / 18,18 / 19,59 | 18,57 / 19,60 / 26,42 | 359,892 |
| Export headless | 64/64 | 0/0 | 0 | sem render; 7,56 / 7,71 / 8,65 | sem render; 7,97 / 9,51 / 12,85 | 333,021 |
| Export janela | 64/64 | 0/0 | 0 | 17,42 / 17,94 / 18,61 | 18,46 / 18,98 / 26,66 | 355,496 |

A aprovação é da correção física e dos protocolos prospectivos de cena parada. Não reclassifica a primeira série 59/60 nem pretende fazer uma peça em queda parar ao salvar. E2 e a continuidade do movimento de C024 mostram por que preservar a física exige conservar também corpos ativos.

## 7. Comandos reproduzíveis

Executar na raiz da worktree, com uma instância de teste por vez. O caminho abaixo é o runtime custom instalado nesta máquina; não usar Godot oficial sem o módulo. Os diretórios `repro_*` evitam sobrescrever as evidências de referência.

```powershell
$godotExe = 'C:\Users\diogo\Tools\Godot\4.7.2-voxel1.7\godot.windows.editor.x86_64.exe'
$templateExe = 'C:\Users\diogo\Tools\Godot\4.7.2-voxel1.7\godot.windows.template_release.x86_64.exe'

# T26 da árvore atual, com T14 criando seu slot limpo obrigatório.
# As séries legadas anteriores têm código/resultado próprios preservados.
& .\tools\run_t26_reference.ps1 -Godot $godotExe -Count 8 -Label repro_reference

# Comparação causal. C executa o save da árvore de código atual.
& .\tools\run_t26_probe.ps1 -Godot $godotExe -Repetitions 2 `
    -Scenarios @('A','B','C','D') -Layouts @('tower','stack') `
    -OutputDirectory 'docs/evidence/p36/t26_stabilization/repro_causal'

# Reproduz o protocolo legado da primeira série ampliada: 60 processos.
& .\tools\run_t26_probe.ps1 -Godot $godotExe -Repetitions 30 `
    -Scenarios C -Layouts @('tower','stack') `
    -OutputDirectory 'docs/evidence/p36/t26_stabilization/repro_post_fix_30'

# Nova hipótese prospectiva: save de torre em repouso natural, sem retry do setup.
& .\tools\run_t26_probe.ps1 -Godot $godotExe -Repetitions 30 `
    -Scenarios C -Layouts tower -NaturalRest `
    -OutputDirectory 'docs/evidence/p36/t26_stabilization/repro_natural_rest_30'

# Contatos do solver são um diagnóstico explícito, separado da série neutra.
& .\tools\run_t26_probe.ps1 -Godot $godotExe -Repetitions 2 `
    -Scenarios B -Layouts tower -Contacts `
    -OutputDirectory 'docs/evidence/p36/t26_stabilization/repro_contacts'

# Quatro modos com o template custom; o runner restaura o preset original.
& .\tools\run_p361_tests.ps1 -Godot $godotExe -Template $templateExe

# Arquivar traces existentes: não inicia Godot e não altera relatórios de resultado.
& .\tools\run_t26_probe.ps1 -ArchiveOnly `
    -OutputDirectory 'docs/evidence/p36/t26_stabilization/repro_causal'
```

Para executar somente os casos de borda e esperar corretamente o executável GUI no PowerShell:

```powershell
. .\tools\lib_godot_process.ps1
$projectRoot = (Get-Location).Path
$edgeDirectory = Join-Path $projectRoot 'docs/evidence/p36/t26_stabilization/repro_edge'
New-Item -ItemType Directory -Force -Path $edgeDirectory | Out-Null
$edgeReport = Join-Path $edgeDirectory 'edge.json'
$edgeLog = Join-Path $edgeDirectory 'edge.log'
Invoke-Native $godotExe @('--headless','--path',$projectRoot,'--script',
    'res://tools/spike_t26_save.gd','--',"--report=$edgeReport") $edgeLog $projectRoot 240
```

Para inspecionar os máximos individuais da série sem ler traces inteiros:

```powershell
$runs = Get-Content 'docs/evidence/p36/t26_stabilization/post_fix_30/summary.json' -Raw | ConvertFrom-Json
$runs | Select-Object name,status,exit_code,
    @{Name='endpoint_m'; Expression={$_.details.after_1_5s.max_m}},
    @{Name='peak_m'; Expression={$_.details.peak_after_1_5s.max_m}},
    @{Name='worst_body'; Expression={$_.details.peak_after_1_5s.worst_body}}
```

## 8. Limites restantes

O diagnóstico causal inicial tem somente duas repetições por grupo. Pilhas de caixas e uma torre não representam todas as geometrias e equilíbrios possíveis. A primeira série ampliada é headless e contém um FAIL; não aprova desempenho de renderização nem o gate completo. O teste final de pose isola um mecanismo de despertar, sem estabelecer a incidência no jogo ou alegar um defeito interno do Jolt. O B1 de importação e os demais riscos já documentados permanecem fora desta intervenção.

A drenagem usa contadores globais do VoxelEngine no laboratório com um terreno; múltiplos terrenos ou produtores externos de I/O exigem nova avaliação da barreira. Durante a drenagem, novos pedidos do terreno ficam suspensos e a física continua; travessia para fora da região já carregada durante I/O excepcionalmente lento não foi avaliada. O setter/flush nativo do SQLite retorna void: erros nativos aparecem no logger e invalidam a automação, sem nova garantia contra disco cheio.

Foram exercitados destino inválido e ambos os timeouts reais. Não foram injetadas falhas internas de rename/rollback nem desligamento abrupto no intervalo de publicação. A política de backup permite recuperação, mas não promete transação resistente a queda de energia. Esta mudança não passa a salvar objetos/estados térmicos e não altera poderes, fratura ou regras de sustentação. Playtest humano não substituído pela automação.
