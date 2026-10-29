# ELEMENTAL // RUINS — protótipo técnico (P0–P4K)

Laboratório de **terreno volumétrico escavável** em Godot 4.7.2 + Voxel Tools 1.7 (SDF + Transvoxel).

**Status: gate P0 PASSOU em 23/10/2026, com ressalva aceita** (crash raro da Godot no fim do `--import`; ver `P0_CHECKLIST.md`).
**P1 (ferramentas, materiais e persistência):** resultado e gate em [`docs/p1_results.md`](docs/p1_results.md).
**P2 (sustentação, destroços e extração):** resultado e gate em [`docs/p2_results.md`](docs/p2_results.md).
**P3 (quatro elementos iniciais):** resultado e gate em [`docs/p3_results.md`](docs/p3_results.md).
**P3.5 (Terra polida: fases, peso, telegraph):** resultado e parâmetros em [`docs/p35_earth_polish.md`](docs/p35_earth_polish.md).
**P3.6.1:** base `180ec59`; salvar preserva terreno, colisores e física viva (ver [`docs/p36_t26_stabilization.md`](docs/p36_t26_stabilization.md)).
**P4A — checkpoint fechado em 27/10/2026 e integrado à main (`9103bee`):** controle livre de uma rocha suspensa, 66/66 testes nos quatro modos, export e persistência entre processos aprovados, zero erros/avisos. Playtest dos controles com feedback positivo do usuário na mesma data ("acho que ficou bom").
**P4B — checkpoint fechado e integrado à main (`266627d`) em 27/10/2026:** capturar e reutilizar uma rocha extraída já existente, com a mesma mola e os controles P4A. Resultado integral final: 68/68 nos quatro modos, export e persistência aprovados, zero erros/avisos; o editor em janela exigiu rechecagens de desempenho, preservadas abaixo. Playtest com feedback positivo do usuário ("está funcionando").
**P4C — checkpoint fechado e integrado à main (`b84b4c6`, PR #4) em 27/10/2026:** Pilar de Terra por RMB, reutilizando o PATH aditivo, fila, validação e persistência do terreno. 70/70 nos quatro modos, export e persistência entre processos aprovados, zero erros/avisos. Playtest com feedback positivo do usuário ("Funcionou, testei aqui!"), sem avaliação detalhada por cenário.
**P4D — Fissura de Terra implementada e integrada à main (`80f2a08`, PR #5), com feedback humano positivo:** vala permanente por F (segurar prévia/soltar aplicar), reutilizando PATH subtrativo e os sistemas existentes. O checkpoint de integração é registrado abaixo, separadamente da implementação já integrada. Feedback humano positivo em 28/10/2026 sobre posição e controle, sem avaliação detalhada por cenário.
**Checkpoint P4D na retomada de 28/10/2026: FALHOU** no preparo do T26 em dois modos; os demais testes, persistência entre processos e benchmarks passaram. Esse FAIL está preservado; o usuário autorizou avançar para P4E sem investigar T26 nesta tarefa.
**P4E — Orbe de Água implementado e pronto para playtest:** segurar RMB forma uma massa da reserva abstrata do Criativo; câmera, Q/E e roda controlam sua posição com atraso; soltar lança. Feedback humano positivo informado pelo usuário em 28/10/2026, sem avaliação detalhada por cenário; checkpoint integral P4E não executado.

**P4F — Congelamento e Lançamento de Gelo implementado, com feedback humano positivo:** C durante RMB transforma o mesmo orbe; voo balístico, impacto cinético próprio e cristal facetado. Feedback informado pelo usuário em 28/10/2026; gate integral não executado.
**P4G — Gelo persistente e derretimento:** o impacto congelado deixa um corpo físico no mundo; Fogo aquece e funde pelo sistema de materiais existente. Branch `codex/p4g-persistent-ice`, base P4F `88d71e3`. O FAIL histórico P4D permanece.
**P4H — Muralha de Gelo com feedback humano positivo:** V durante o controle congelado alterna um molde de painel; soltar RMB constrói somente se válido. Reutiliza IceBody e depende de apoio do terreno. Branch `codex/p4h-ice-wall`, base P4G `1fa3c90`; validação dirigida aprovada, sem gate integral. O usuário confirmou funcionamento no playtest em 29/10/2026, sem avaliação detalhada por cenário nem aprovação integral.
**P4I — Vórtice de Ar pronto para playtest:** RMB cria um campo fixo de forças que atrai, faz circular e sustenta corpos físicos. Branch `codex/p4i-air-vortex`, base P4H `33719e4`; validação dirigida aprovada, sem integração integral.
**P4J — Fluxo Contínuo de Fogo com feedback humano positivo inicial:** segurar RMB emite corrente direcionável, com alcance crescente e aquecimento proporcional ao contato. LMB preserva a bola. Feedback informado na missão P4K em 29/10/2026, sem aprovação integral. O feedback humano específico do P4I permanece não informado.

**P4K — Espinhos de Terra prontos para playtest:** branch `codex/p4k-earth-spikes`, base P4J `0334cc9`; X prepara uma sequência de três formações voxel reais. Esc/troca de elemento cancelam apenas o que ainda não foi aplicado. Validação dirigida abaixo; sem integração integral.

P0: personagem em terceira pessoa, colina voxel com colisão, escavar e adicionar matéria pela mira, túnel real sob
teto sólido e reset de verdade do mundo. P1: fila de brushes contínuos (REMOVE/ADD/PATH/SMOOTH), materiais
solo/areia/pedra com propriedades físicas gravadas nos voxels, evento `TerrainChanged`, salvar/carregar com
`VoxelStreamSQLite`, overlay de observabilidade e benchmarks. P2: torre modular de 36 peças que perde apoio quando
se escava sob ela e cai em etapas, corpos que acordam quando o chão some, teto de corpos ativos, poeira decorativa e
extração de rocha real do terreno. P3: um poder por elemento pela mesma interface (`AbilityController` → `Ability` →
`ElementalEvent` → `MaterialResponseSystem`): Terra ergue e arremessa uma rocha real (dano cinético na torre), Água
empurra, molha e apaga, Fogo acende madeira que queima, carboniza e espalha (o 2º andar da torre é de madeira e cai
quando queima), Ar empurra pela massa e apaga fogo fraco; FX mínimos. Não há arte final, menus, áudio nem simulação
de fluidos.

> Comece por [`INICIO_AQUI.md`](INICIO_AQUI.md) e [`CLAUDE.md`](CLAUDE.md) (requisitos). Resultados e provas estão em
> [`docs/voxel_spike_results.md`](docs/voxel_spike_results.md) (P0), [`docs/p1_results.md`](docs/p1_results.md) (P1), [`docs/p2_results.md`](docs/p2_results.md) (P2) e [`docs/p3_results.md`](docs/p3_results.md) (P3),
> decisões em [`docs/decisions.md`](docs/decisions.md) e o gate do P0 em [`P0_CHECKLIST.md`](P0_CHECKLIST.md).

## Versões usadas (verificadas nesta máquina)

| Item | Versão / origem |
|---|---|
| Editor Godot | **Godot 4.7.2.stable.custom_build.ed1daf0bf + Voxel Tools 1.7 como módulo** (release `v1.7` do Voxel Tools, `godot.windows.editor.x86_64.exe.zip`, sha256 `e2292adb…6f1956b`). Mesmo commit da Godot oficial 4.7.2; binário **não assinado** |
| Template de export | `godot.windows.template_release.x86_64.exe.zip` da mesma release (sha256 `86fe371e…2f0775`); só **release** no Windows |
| Física 3D | Jolt Physics integrado (`physics/3d/physics_engine="Jolt Physics"`) |
| Renderer | Forward+ (Vulkan 1.4.323 na Intel Iris Xe testada) |

> **Por que não a Godot oficial + GDExtension?** Funcionava, mas a primeira importação de um clone limpo derrubava a
> Godot em 10 de 17 tentativas, e qualquer import com outra Godot aberta no projeto também caía. Com o módulo, o
> resultado foi 1 em 50 e 0 em 3, respectivamente, com os mesmos testes 12/12. Detalhes em `docs/decisions.md` (D13).
> **A Godot oficial não abre este projeto corretamente:** ela não tem as classes Voxel. **Não reextraia a GDExtension
> (`addons/zylann.voxel/`) neste projeto:** módulo e GDExtension juntos registram as mesmas classes e conflitam.

## Requisitos e instalação

1. Windows 10/11 x64.
2. Baixe da release **v1.7** do Voxel Tools (<https://github.com/Zylann/godot_voxel/releases/tag/v1.7>):
   - `godot.windows.editor.x86_64.exe.zip` (editor)
   - `godot.windows.template_release.x86_64.exe.zip` (template de export)
3. Confira os SHA-256 acima e extraia os dois `.exe` numa pasta fora do projeto. Nesta máquina:
   `C:\Users\dsoares\Tools\Godot\4.7.2-voxel1.7\`.
4. Se usar outra pasta, ajuste `custom_template/release` em `export_presets.cfg` (caminho absoluto) e passe
   `-Godot <caminho do editor>` ao script de testes (ou defina `$env:GODOT`).
5. Como o binário não é assinado, o Windows SmartScreen pode avisar na primeira execução.

## Abrir e rodar no editor

1. Execute **`open_editor.cmd` nesta pasta**. Ele valida as classes Voxel antes de abrir o projeto no editor custom. Usa `GODOT` se definido; o caminho padrão é `%USERPROFILE%\Tools\Godot\4.7.2-voxel1.7\godot.windows.editor.x86_64.exe`.
2. Para abrir manualmente, execute `godot.windows.editor.x86_64.exe` (o editor **custom**), clique em **Importar**, escolha `project.godot` desta pasta e depois **Importar e editar**. Abrir `project.godot` por associação do Windows pode iniciar a Godot oficial, que não contém as classes Voxel e gera erros de tipo em cascata. O launcher não altera essa associação.
   O projeto já aparecia na lista do editor oficial; os dois editores compartilham essa lista, então confira
   qual executável está aberto.
3. Pressione **F5** (cena principal `res://scenes/main.tscn`).
   O terreno é **criado em código** ao rodar (`LabTerrainFactory`), por isso a colina não aparece na viewport do editor.

## Controles (provisórios, conforme CLAUDE.md)

| Tecla | Ação |
|---|---|
| **1 / 2 / 3 / 4** | escolher o elemento: Terra / Água / Fogo / Ar (P3; o HUD mostra o poder atual) |
| **LMB** | usar o poder do elemento. Terra (segurar; P3.5): mire o chão a 2,5–7 m. O chão racha (~0,1 s), a rocha se solta (~0,1 s) e sobe (~0,16 s), pronta em ~0,37 s (o anel da retícula enche); soltar arremessa no ponto mirado. Um toque curto arranca e lança assim que fica pronta; impacto forte no chão abre cratera. Água (segurar): jato até 14 m que empurra, molha e apaga. Fogo (toque; P3.6): a bola se forma na mão por ~0,08 s com a mira do clique, voa a 35 m/s e aquece no primeiro contato; no fim dos 30 m só se dissipa; nova rajada após ~0,14 s; madeira acende e o fogo não atravessa paredes. Ar (toque; P3.6): uma frente de pressão sai da mão a 30 m/s em cone de 10 m e decide cada corpo uma vez; empurra pela massa, é bloqueada por terreno e corpos (exposição parcial reduz o empurrão), apaga fogo fraco e aviva o forte; nova rajada após ~0,15 s |
| WASD | andar, relativo à câmera |
| Shift | correr |
| Espaço | pular |
| Mouse | orbitar a câmera; em hold da Terra, desloca a rocha horizontalmente com massa e atraso (Esc solta/prende o mouse; clique recaptura) |
| **Q / E**, durante hold da Terra | abaixar / elevar o alvo da rocha a 2 m/s; altura inicial 2 m, limites 1–6 m sobre os pés do jogador |
| **LMB mirando uma rocha solta** (Terra; P4B) | capturar o mesmo corpo físico, preservando massa e velocidade, até 7 m do jogador ao centro da rocha; Q/E, roda e lançamento iguais ao P4A |
| **RMB** (Terra parada; P4C) | segurar mostra a prévia; soltar cria um pilar permanente. Altura 4,5 m, raio 2 m; chão entre 2,5 m horizontais e 18 m em 3D. Trocar elemento ou Esc cancela |
| **F** (Terra parada; P4D) | segurar mostra a prévia; soltar abre uma fissura permanente de 6 m, raio 1 m e centro 0,35 m abaixo do piso, para longe na direção horizontal da câmera; todo o caminho deve estar a até 18 m |
| **X** (Terra parada; P4K) | segurar mostra três espinhos; soltar confirma a formação válida. Cada PATH é revalidado e aguarda collider antes do próximo; Esc/troca de elemento cancelam o restante |
| **RMB** (Água; P4E) | segurar forma/sustenta um orbe; mouse orienta o alvo horizontal, Q/E regulam altura, roda aproxima/afasta; soltar lança. O primeiro botão mantido vence o conflito com o jato LMB; não há comando enfileirado |
| **C** (Água; P4F) | congela uma vez o orbe suspenso durante RMB; preserva posição e controle. Ignorado fora do hold ou após congelar; soltar RMB lança gelo balístico |
| **V** (Água; P4H) | durante RMB congelado, alterna muralha/projétil; mire chão livre e solte RMB para construir. Prévia inválida consome/cancela o molde, sem lançar |
| **RMB** (Ar; P4I) | segure mirando chão livre para manter um vórtice fixo; solte para dissipar. LMB fica bloqueado durante o campo, rajadas anteriores terminam normalmente |
| **RMB** (Fogo; P4J) | segure para fluxo contínuo que acompanha a mira; solte para parar. LMB fica bloqueado durante o fluxo; antecipação LMB bloqueia RMB, voos anteriores continuam |
| **G** (segurar) | escavar em traço contínuo: carimbos a cada 0,15 s × dureza do material (areia 2× mais rápido, pedra 3× mais lento), vala contínua ao varrer a mira |
| **H** (segurar) | adicionar matéria do material atual em traço contínuo (recusa se for prender o personagem) |
| **N** (segurar) | suavizar (SMOOTH) quinas e degraus no ponto mirado (raio até 4 m) |
| **J** | abrir túnel de 10 m na direção horizontal da câmera, na altura da mira |
| **K** | erguer rampa de 8 m que sobe 3 m na direção da câmera, com o material atual |
| **M** | trocar o material do H/K: solo → areia → pedra |
| **F5** | salvar as edições do terreno no slot `slot1`, mantendo terreno, colisores e física viva; cancela o poder e solta a rocha suspensa com gravidade (P3.6.1) |
| **F9** | carregar o slot `slot1` (jogador volta ao spawn; caixas somem) |
| **Z** | **reset do mundo**: recria o terreno do gerador, apaga todas as edições, devolve o jogador ao spawn e remove as caixas (o slot salvo fica intacto) |
| Roda do mouse | durante hold da Terra ou orbe de Água: subir aproxima / descer afasta o alvo 0,5 m (Terra 2,5–7 m; Água 2–7 m); fora desses contextos: raio do pincel (0,5–6 m; padrão 2 m) |
| `[` `]` | raio do pincel, inclusive durante hold |
| **R** | extrair uma rocha logo abaixo da mira (raio do pincel limitado a 1–2 m): o núcleo vira um corpo físico real, com a massa do material, e pousa ao lado do buraco |
| **T** | impulso de teste (lançamento a 45°) no corpo físico mirado: rocha, caixa ou peça já caída da torre |
| B | soltar uma caixa `RigidBody3D` de teste no ponto mirado (máx. 10) |

> F5 dentro do **jogo** salva; F5 no **editor** continua sendo "rodar o projeto". As caixas de teste não são salvas
> (o slot persiste somente terreno). Os arquivos ficam em `%APPDATA%\Godot\app_userdata\ELEMENTAL -- RUINS\`
> (`world/` = sessões temporárias, `saves/` = slots).

O marcador esférico na mira fica **verde** quando a área é editável e **vermelho** quando não é. O overlay mostra
FPS e tempo de quadro (média e pico do último segundo), estado do terreno e da sessão, a fila de brushes (pendentes,
aplicadas, recusadas, fundidas, divididas), o último brush (AABB, material, massa estimada, tempo), o material sob a
mira com dureza/densidade, tarefas e memória do motor voxel, corpos físicos ativos e os resultados de reset/salvar/carregar.

### Roteiro manual sugerido (≈ 3 min)
1. Ande até a colina (W) e erga a câmera até a mira cair na encosta, a cerca de 1,5 m do chão.
2. Raio 2 m (padrão). Aperte **J**, ande para dentro do túnel e aperte J de novo lá dentro para continuar até sair do outro lado. Confira que há teto sobre a cabeça e que você não atravessa o chão.
3. Fora da colina, segure **G** sobre o chão para abrir uma cratera e pule dentro dela.
4. Mire no chão a uns 4–5 m e segure **H** para formar uma coluna; suba nela (pulo) ou solte uma caixa com **B**.
5. Repita G/H no mesmo ponto várias vezes.
6. Aperte **Z**: cratera, túnel e coluna devem sumir, e o jogador volta ao spawn.

### Roteiro manual do P1 (≈ 4 min)
1. Segure **G** e varra a mira pelo chão: deve sair uma vala contínua. Faça o mesmo na faixa de areia (leste, clara)
   e no fundo de uma cratera funda (pedra, verde, abaixo de y = −6): a areia cava mais rápido e a pedra mais devagar.
   O overlay mostra o material sob a mira.
2. Aperte **M** até "areia" e segure **H**: a matéria nova aparece na cor da areia. Aperte **K** para uma rampa e suba nela.
3. Segure **N** numa quina (borda de cratera ou coluna): ela arredonda.
4. Aperte **F5** (salvar), depois **Z** (reset: tudo some) e **F9** (carregar): as edições voltam iguais.
5. Feche o jogo, abra de novo e aperte **F9**: as edições do último F5 voltam.

### Roteiro manual do P2 (≈ 4 min)
1. A torre fica a ~24 m do spawn, à direita (x = 19, z = 14). Ande até ela.
2. Escave (**G**) embaixo de um pilar do térreo: só aquele pilar cai; a laje continua.
3. Escave sob o pilar vizinho do mesmo lado: metade da torre cai em etapas, com poeira; as peças param sobre o terreno.
4. Mire no chão e aperte **R**: uma rocha sai do buraco e pousa ao lado. Mire nela e aperte **T**: ela é lançada.
5. Solte uma caixa (**B**), espere ela parar e escave embaixo: ela cai na cratera (não fica flutuando).
6. **F5**, **Z** (torre de pé de novo) e **F9**: a torre cai de novo, porque o terreno salvo não tem o apoio.

### Roteiro manual do P3 (≈ 5 min)
O LMB só age com o mouse preso (o clique que prende o mouse não lança poder). O HUD mostra o elemento, o resultado do
último uso e o estado do corpo mirado (`MADEIRA • 470 °C • EM CHAMAS 40%`).
1. Ande até ~16 m da frente da torre. **1** (Terra), mire o chão a uns 5 m e **segure LMB**: a rocha sobe e fica à
   frente. Mire o pé do pilar de pedra da frente e **solte**: o pilar perde blocos e o de cima cai.
2. **3** (Fogo), mire o bloco de baixo de um pilar de **madeira** (2º andar, marrom) e clique: ele acende. Acenda
   também o outro pilar de madeira da frente e espere ~15 s: os blocos queimam até sumir e as placas de cima caem.
3. Solte duas caixas (**B**) lado a lado com ~0,5 m de vão e acenda uma: em alguns segundos a vizinha pega fogo e
   ambas escurecem (carbonizadas).
4. **2** (Água), segure LMB numa caixa em chamas: ela apaga com vapor e é empurrada. Molhe uma caixa e tente acendê-la
   (**3**): a 1ª bola só a seca.
5. **4** (Ar), clique perto de caixas e de destroços: as caixas voam, os blocos de pedra mal se mexem; uma caixa atrás
   de um morro (**H**) não é atingida. Fogo fraco apaga; fogo forte cresce.
6. **Z**: torre de pé, sem fogo nem estados, poderes parados.

### Roteiro manual do P3.5 — Terra (≈ 3 min)
Parâmetros em `data/abilities/earth_tuning.tres` (abra no inspetor da Godot; ver `docs/p35_earth_polish.md`).
1. **1** (Terra) e mire o chão a ~4–5 m: o anel verde no chão mostra de onde a rocha sai (vermelho = inválido).
2. **Segure LMB**: anel âmbar + rachadura e poeira (antecipação); o chão abre e pedrinhas saltam (desprendimento); a
   rocha sobe e para à frente (levantamento). O anel em volta da retícula enche e fica branco quando pronta.
3. Ainda segurando, gire a câmera rápido: a rocha acompanha com atraso e balança de leve (peso). Ande: você fica mais lento.
4. Mire o chão a ~12 m e **solte**: a rocha recua, sai com giro, deixa rastro e abre uma cratera onde bate.
5. **Toque curto** no LMB mirando o chão: a rocha é arrancada e lançada sozinha assim que fica pronta.
6. Mire o céu, o chão a 1 m ou a 10 m e clique: X vermelho na retícula, nada acontece.
7. Mude `anticipation_s`, `rise_s` ou `throw_speed` no `.tres`, rode de novo e compare a sensação.

### Roteiro manual do P4A — controle livre de Terra

1. **1**, mire o chão a 2,5–7 m e segure **LMB** até a rocha ficar pronta. Gire a câmera: ela acompanha com inércia.
2. Use **Q/E** para baixar/subir e a **roda** para aproximar/afastar. O HUD mostra altura, distância e limites; parâmetros em `EarthTuning`, editáveis por `data/abilities/earth_tuning.tres`.
3. Empurre o alvo contra terreno ou parede: a rocha continua física, sem teleporte. Solte **LMB** para lançar; toque curto mantém o lançamento automático.
4. Troque elemento, salve, resete ou carregue durante o controle: os comandos cessam. Salvar solta a rocha com gravidade e preserva os corpos vivos; reset/carregar recriam a sessão.
5. Fora do hold, confira a roda regulando o pincel; **[ ]** continuam regulando-o durante hold. Playtest dos controles em 27/10/2026: feedback positivo do usuário ("acho que ficou bom"), sem avaliação detalhada por cenário.

Os limites restringem o alvo da mola: a posição real pode atrasar ou apresentar sobressinal físico. Contra um obstáculo, a rocha permanece bloqueada pelas colisões/CCD e recebe força limitada; não há teleporte nem desvio automático. O lançamento mantém a trajetória existente, calculada do centro atual com impulso que considera a velocidade corrente.

### Roteiro manual do P4B — reutilizar uma rocha

1. Extraia uma rocha com Terra ou com **R**. Com Terra selecionada, mire a rocha solta e segure **LMB**: a mesma rocha entra no hold, sem editar o terreno ou criar outra.
2. Use câmera, Q/E e roda; solte LMB para lançar. Após a recuperação, mire a mesma rocha para capturá-la novamente, inclusive em voo se ainda estiver no alcance.
3. O primeiro obstáculo visível bloqueia a seleção. Caixas e peças da torre não são rochas capturáveis. O alcance de captura usa a distância 3D ao centro, limitado por `EarthTuning.max_range`; o alvo do hold continua limitado por `min_range/max_range` horizontalmente.
4. A captura entra direto no hold, sem antecipação/desprendimento de terreno; a mola faz a transição desde a posição atual e preserva a inércia. O controle impede estacionamento automático pelo orçamento de destroços até lançar/cancelar.
5. Trocar elemento, salvar, resetar e carregar encerram o controle. Capturar/expirar/limpar encerra o monitoramento do voo anterior para não acumular contatos. Playtest P4B em 27/10/2026: feedback positivo do usuário ("está funcionando"), sem avaliação detalhada por cenário.

### Roteiro manual do P4C — Pilar de Terra

1. Selecione **1**, mire chão livre e segure **RMB**: a prévia indica o volume aproximado (verde válido, vermelho recusado). Solte para criar; não há criação enquanto só segura.
2. O topo fica 4,5 m acima do chão mirado, com extremidade arredondada pelo PATH. O pilar é terreno SDF real e pode apoiar jogador/caixas; colisão e malha atualizam de forma assíncrona depois da edição. A prévia cilíndrica mostra altura/raio, sem reproduzir o arredondamento voxel.
3. Parede/objeto sob a mira bloqueia a seleção. O espaço futuro precisa estar livre de corpos; sobreposição com o jogador também é recusada na aplicação. Não ergue o jogador sob os próprios pés. Limites em `EarthTuning`: `pillar_range`, `pillar_radius`, `pillar_height`; reutiliza `min_range` e `min_floor_normal_y`.
4. Durante prévia do pilar, LMB não inicia extração. Durante o ciclo da rocha, RMB não cria pilar. Troca de elemento, perda de captura do mouse, input desabilitado, reset/save/load cancelam a prévia e o pedido ainda pendente, sem apagar edições já aplicadas.
5. **F5/Z/F9** salva/remove/restaura o pilar pelo sistema existente. Ele permanece até escavar ou resetar; não há temporizador de desaparecimento. O material vem do chão mirado, independentemente do material do pincel **M**.

Playtest humano do P4C em 27/10/2026: feedback positivo do usuário ("Funcionou, testei aqui!"), sem avaliação detalhada por cenário.

O raio padrão de 2 m usa a mesma escala já validada pela coluna do laboratório. Com 1,1 m, a caixa escorregou do topo arredondado nos testes; os critérios de apoio foram mantidos.

### Roteiro manual do P4D — Fissura de Terra

Feedback humano positivo em 28/10/2026 sobre posição e controle da fissura ("sim, pode subir"), sem avaliação detalhada por cenário.

1. Selecione **1**, mire chão livre e segure **F**. Confira a prévia na direção horizontal da câmera; solte para abrir a vala. Apenas segurar não edita o terreno.
2. O caminho nominal tem 6 m, raio 1 m e centro 0,35 m abaixo do piso amostrado. O alcance de 18 m vale para todo o trajeto; piso ausente, inclinação inválida ou salto de altura maior que 1 m recusam o pedido. Dimensões em `EarthTuning`.
3. Objetos e paredes sob a mira bloqueiam o alvo. Uma fissura válida pode remover o apoio de caixas/estruturas adiante; a queda deve vir da sustentação e da física existentes. Malha e colisão atualizam de forma assíncrona.
4. Rocha, pilar e fissura não iniciam simultaneamente. Trocar elemento, Esc, input desabilitado e reset/save/load cancelam a prévia e o pedido pendente. Cancelar não desfaz edições já aplicadas.
5. Use **F5/Z/F9** para salvar/remover/restaurar a fissura. Esta fatia não implementa compressão de rochas.

### Roteiro manual do P3.6 — Água, Fogo e Ar (≈ 6 min)
Parâmetros em `data/abilities/water_tuning.tres`, `fire_tuning.tres` e `air_tuning.tres` (inspetor da Godot); detalhes em
`docs/p36_elemental_polish.md`. Use **B** para criar caixas de teste e **H** para levantar um morro de terreno.
1. **2** (Água), segure LMB numa caixa a ~6 m: o jato avança (não nasce inteiro) e a pressão sobe em ~0,1 s. Gire 90° segurando:
   a água já lançada segue a direção antiga e a nova chega depois. Solte: para na hora.
2. Com uma caixa atrás de um morro ou de outra caixa, molhe a da frente: a de trás não molha através do obstáculo.
3. **3** (Fogo), clique numa caixa e gire a câmera logo em seguida: a bola se forma na mão (~0,08 s) e segue a mira do clique.
   Clique várias vezes: no máximo 8 bolas e uma nova a cada ~0,14 s. Troque de elemento logo após clicar: a bola não sai.
4. Mire o céu: a bola some numa baforada de fumaça no fim dos 30 m, sem aquecer nada.
5. Acenda uma caixa encostada em outra e uma terceira separada por um morro: a encostada pega fogo, a de trás do morro não.
   Atire numa caixa molhada: sai vapor, ela seca e só a 2ª bola acende.
6. **4** (Ar), toque perto de um grupo de caixas: o anel avança e as caixas reagem na ordem da distância; uma caixa escondida
   atrás de outra ou de um morro fica (total ou parcialmente) protegida; a rocha extraída (**R**) mal se mexe.
7. Ar em fogo fraco apaga; em fogo forte aviva e a caixa voa queimando. A água apaga com vapor.
8. Com bolas de fogo ou frentes de ar em andamento, aperte **Z**, **F5** ou **F9**: os poderes são cancelados. **F5** preserva a física dos corpos já existentes; **Z/F9** recriam a sessão.
9. Avalie (como jogador e como observador de outro ângulo, pensando em PvP): legibilidade das antecipações e frentes, peso,
   clareza de limites e recuperação. **NÃO TESTADO** por pessoas até aqui.

## Testes automatizados

### P4K — Espinhos de Terra

Selecione **1**, mire chão livre, **segure X** para a prévia verde/vermelha e **solte X** para confirmar. A formação segue a direção horizontal da câmera e fica capturada no release. Um espinho por pedido: retorno SDF real → confirmação do collider no próprio volume → intervalo → próximo. Uma falha interrompe a sequência, conserva o que já foi aplicado e mostra o resultado parcial. LMB/RMB/F ficam exclusivos durante preparo e execução; os controles anteriores permanecem.

`EarthLiftThrow`, `EarthTuning` e `EarthFx` foram estendidos, reutilizando PATH, TerrainBrushQueue/epochs, TerrainService, materiais, TerrainContactWaker e save/load voxel. Nenhuma nova classe ou collider permanente auxiliar. Cada volume é validado contra jogador/props, terreno/teto, apoio e dados SDF ainda sem collider atualizado. Esc, seleção, perda de captura/input e reset/save/load cancelam o restante; edições prontas permanecem até escavação/reset/load.

Parâmetros no Resource existente: **3 espinhos**, espaçamento **1,8 m**, altura nominal **3 m**, raios **0,9 → 0,825 → 0,75 m**, alcance **14 m**, intervalo **0,14 s** após confirmação física e desnível máximo **0,75 m**. O topo físico depende da grade voxel de 1 m: nesta fixture mediu **2,27–2,81 m**, com afunilamento e colisão observáveis. O raio 0,5 m continua permitido pelo terreno, mas perdeu partes superiores entre amostras; o padrão local 0,75 m evita essa perda. A prévia representa o PATH nominal, sem ponta cosmética permanente. Construção discreta em três operações, sem dano, impulso de emergência ou rollback.

**Validação dirigida (29/10/2026):** import/parse custom aprovados; [T1/T80/T81 headless 3/3](docs/evidence/p4k/02_headless.json), [regressão Terra 7/7](docs/evidence/p4k/03_related_headless.json) (T1/T59/T60/T63/T64/T65/T66). Em janela, [T1/T80 2/2](docs/evidence/p4k/05_window_probe.json) e [T1/T81 final 2/2](docs/evidence/p4k/10_guards_window.json); T81 final também [2/2 headless](docs/evidence/p4k/09_guards_headless.json). Runs aceitos completos e sem erros/avisos, validados pelo runner existente com IDs/run_ids externos. Cobrem volume/colisão/afunilamento, bloqueio de jogador/caixa/Fogo, save/reset/load, recusa/revalidação SDF e resultado parcial/cancelamentos.

Benchmark em janela desde antes do release até as três edições/confirmações, mais 185 ticks, sem excluir amostras: **17,55/17,82/19,03 ms**, p95/p99/máximo (227 intervalos). Edições **1,872/0,107/0,101 ms**; collider após **29/34/32 ms**, separadamente. Rechecagem com captura fora da medição: **19,97/26,15/27,20 ms**; ambas dentro de 20/33/50. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900, uma Godot por vez, sem processos shell/CIM durante amostragem. Captura opcional tem 12 ticks de preparo antes da ativação; criação/reconstrução ficam integralmente medidas. [Ambiente, fontes e tentativas](docs/evidence/p4k/result.json).

FAILs preservados: ponta inicial perdeu altura; Esc dependia da captura; revisão encontrou confirmação ausente no último espinho e fortaleceu o teste antes de aceitar o candidato. As sondas temporais da prévia agora esperam estado real; cancelar notifica o VFX imediatamente. O primeiro benchmark atingiu **81,96 ms de máximo**, sem causa isolada; as rechecagens não apagam essa ocorrência nem demonstram otimização causal. **Integral de 87 IDs, export, persistência entre processos e playtest humano P4K não executados. P4D continua FAIL; T26 não investigado.** Próximo passo: experimentar os espinhos.

### P4J — Fluxo Contínuo de Fogo

**Playtest:** selecione **3**, mantenha **RMB** sobre madeira e mova a câmera para varrer outros alvos. Solte para parar a emissão; a temperatura aplicada e a combustão pertencem ao mundo. Compare madeira seca/molhada e aqueça gelo físico/muralha até fundir. LMB mantém a bola existente: sua antecipação bloqueia começar o fluxo, mas projéteis já em voo podem terminar normalmente. Esc, troca de elemento, perda de captura/input e reset/save/load cancelam a corrente.

`FireBurst` compõe `FireStream` sem novo slot selecionável, reutilizando Ability/controller/mira, cast_segment, HEAT/MaterialResponseSystem e ElementalFx. `FireTuning` mantém a bola intacta e acrescenta `stream_range=12` m, `stream_front_speed=25` m/s, `stream_interval_s=0.1`, `stream_heat_per_s=240`, `stream_contact_radius=0.35` m e `stream_visual_enabled`. Alcance operacional cresce no início; mira e primeiro contato são recalculados a cada tick. Dose = taxa × tempo real de contato, inclusive fração do tick posterior à chegada da frente. Pulsos limitam eventos; quadros longos são integrados em uma dose, sem explosão de callbacks. Ao mudar alvo/perder contato/cancelar, o crédito parcial não emitido é descartado, sem dano residual ou transferência ao novo alvo. Não se faz flush de calor no release.

Origem do HEAT fica no lado livre do contato; área pequena usa queda/visada existentes. Passagem peito→mão obstruída recusa/cancela para não começar através de uma parede próxima. Madeira seca incendeia, umidade absorve calor pela evaporação existente e gelo funde pelo mesmo estado térmico. Pedra aquece sem combustão; terreno bloqueia sem edição SDF. Malhas leves limitadas ao segmento físico e contato com até oito partículas apenas representam a emissão; desligar o visual não interrompe calor. Sem combustão volumétrica, lava, propulsão, desvio do fluxo por Ar ou nova arquitetura térmica.

**Validação dirigida (29/10/2026):** import/parse custom aprovados; [T1/T78/T79 finais headless 3/3](docs/evidence/p4j/02_headless.json), [regressão headless 9/9](docs/evidence/p4j/03_related_headless.json) (T1/T38/T49/T50/T57/T58/T60/T69/T76), [T1/T78/T79 finais janela 3/3](docs/evidence/p4j/04_window.json). Runs finais sem erros/avisos. Dosagem isolada com raycast/corpo reais e sem avanço do relógio térmico global: **508,834 HEAT** em 2,4 s lógicos, com **2,12014 s de contato**, igual a 30/60/120 atualizações por segundo. Madeira seca incendiou em **1,5 s**, molhada em **2,9 s**; pedra aqueceu sem queimar com VFX off; esfera e muralha de gelo fundiram e perderam colisão. Mira/oclusão por parede de 1 mm/voxel, release, alvo removido, exclusão com LMB e oito cancelamentos passaram.

Benchmark pareado, mesmas seis caixas físicas e alvo de pedra, 185 ticks/184 intervalos por fase: baseline **17,48/18,28/19,11 ms**, fluxo ativo **17,60/18,17/18,39 ms** (p95/p99/máximo), dentro de 20/33/50. CPU média medida dentro da atualização do componente: **0,097 ms/tick**, incluindo queries, HEAT e callbacks de contato. Diferenças entre percentis incluem variação entre as duas amostras; não são comparação com o cenário P4I. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; uma Godot por vez, materiais estáveis sem nova ignição, captura fora da amostragem e imagem histórica restaurada. [Captura final inspecionada](docs/evidence/p4j/screens/fire_stream.png), [ambiente e consolidação](docs/evidence/p4j/result.json).

A inspeção inicial revelou que a cápsula encobria a emissão central; a origem física agora tem deslocamento lateral local de **0,8 m**, com a mesma origem para queries/VFX e validação peito→mão. Rechecagens finais passaram; versões anteriores e diagnóstico de projeção permanecem como evidência. A primeira tentativa do diagnóstico temporário não compilou por inferência de tipo e expirou sem relatório; não conta como PASS. O ramo temporário foi removido do selftest. **Naquela sessão, integral de 85 IDs, export, persistência entre processos e playtest humano P4J não executados.** Feedback humano positivo inicial foi informado posteriormente, na missão P4K. P4D continua FAIL; T26 não investigado; P4I sem feedback humano específico informado. P4J preservado como base do P4K, sem aprovação integral.

### P4I — Vórtice de Ar

**Playtest:** selecione **4**, mire chão livre até 10 m e segure **RMB** perto de caixas, rochas ou gelo dinâmico. O campo permanece fixo enquanto o personagem pode se mover. Soltar RMB, Esc, troca de elemento, perda de input/captura e reset/save/load param as forças e limpam o visual; objetos conservam inércia e gravidade, sem impulso final. LMB mantém a rajada existente quando o campo está inativo; frentes emitidas antes do RMB continuam.

`AirVortex` compõe `AirGust`, pelo mesmo contrato de Ability/eventos usado no orbe. Reutiliza `MaterialResponseSystem.bodies_in_sphere`/visada, exposição da rajada e `DebrisBudget.unpark`. Forças centrais contínuas combinam atração regularizada, circulação X→+Z, sustentação e amortecimento; nenhuma escrita de posição/velocidade. `AirTuning` acrescenta raio **2,5 m**, altura **4 m**, alcance **10 m**, acelerações radial/tangencial/vertical **14/8/24 m/s²**, teto **2500 N**, referência suave de velocidade **10 m/s**, até **12 corpos** (limite absoluto 24) e consultas a cada **0,1 s** (0,05–0,25 s). Os valores da rajada não foram alterados. Corpos pesados podem permanecer no chão; a referência de velocidade freia por força e não limita impulsos externos.

Consulta ampla limitada a 64 resultados, candidatos próximos com WeakRef e exposição de silhueta espaçada; visada central nova a cada tick suspende imediatamente força bloqueada. Essa regra é conservadora quando só a lateral está exposta. Material recebe AIRFLOW no máximo uma vez por segundo, ponderado por exposição/borda, preservando secagem e vento que apaga fogo fraco ou intensifica o forte. Âncoras/estruturas presas e corpos sob controle de Terra são preservados. Só estacionamento por orçamento é reativado pelo campo perto do jogador; estacionamento por distância permanece sob a política do DebrisBudget. Muralha que perde apoio pode reagir enquanto seu centro estiver dentro do campo e visível. O jogador é excluído. Visual tem três fitas helicoidais, anel de base e até 32 partículas, sem decidir forças. Sem centro móvel, múltiplos campos, edição de terreno, consumo automático de objetos ou simulação de fluido.

**Validação dirigida (29/10/2026):** import/parse custom aprovados; [T1/T76/T77 headless 3/3](docs/evidence/p4i/02_headless.json), [regressão headless 10/10](docs/evidence/p4i/03_related_headless.json) (T1/T52/T53/T54/T56/T57/T58/T60/T69/T74), [T1/T76/T77 janela 3/3](docs/evidence/p4i/04_window.json). Execuções finais sem erros/avisos. T76 cobre formação/input real, centro fixo, exclusão LMB, frentes anteriores, recusas e oito cancelamentos. T77 mede atração, elevação de **2,49 m** e velocidade tangencial **3,44 m/s** na caixa de 20 kg; a de 2000 kg não subiu. Verifica força nominal ≤2500 N com tolerância numérica, inércia ao liberar, parede móvel bloqueando, reativação de orçamento, âncora de gelo preservada, painel liberado por escavação e AIRFLOW fraco/forte a 1 Hz. A [tentativa inicial FAIL](docs/evidence/p4i/02_headless_initial_fail.json) foi preservada: fixtures de material/benchmark ocupavam o chão da mira e não formavam o campo. Ajustados só os cenários (combustão isolada por massa de fixture; benchmark formado em chão livre antes dos corpos), sem mudar runtime ou relaxar os critérios físicos.

Benchmark janela: **16 caixas físicas de 0,4 m/20 kg**, gravidade/colisões reais, até **12 recebendo força**, **185 ticks/184 intervalos**, p95 **19,62 ms**, p99 **20,65 ms**, máximo **21,75 ms**, limites 20/33/50. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; process_frame após preparação, uma Godot por vez, captura fora da amostragem e imagem histórica restaurada. [Captura inspecionada](docs/evidence/p4i/screens/air_vortex.png), [consolidação/ambiente](docs/evidence/p4i/result.json). **Integral de 83 IDs, export, persistência entre processos e playtest humano P4I não executados.** P4D permanece FAIL, T26 intacto. Próximo passo: experimentar o vórtice.

### P4H — Muralha de Gelo (feedback humano positivo)

**Playtest:** **2 → segure RMB → C → V**, mire chão próximo e livre. Azul indica posição válida, vermelho recusa com motivo no HUD. Solte RMB para criar uma muralha; **V novamente antes de soltar** retorna ao projétil congelado. Fora do molde, câmera/Q/E/roda e lançamento P4F/P4G são preservados. LMB continua sendo o jato exclusivo. Troca de elemento, Esc, perda de captura/input e reset/save/load cancelam somente a prévia; muralhas prontas sobrevivem à seleção/Esc/save e são removidas por reset/load.

`WaterOrbTuning`: `wall_width=1.40`, `wall_height=1.50`, `wall_range=10` m, `wall_min_thickness=0.04` m. Espessura = litros × 0,001 / (largura × altura): **150 L → 0,071429 m**, massa **137,55 kg** na densidade P4G. Configuração abaixo da espessura mínima é recusada, sem inventar volume. `IceBody.ShapeKind.WALL` usa caixa nominal e painel com bordas facetadas; mesma fusão HEAT/material, cristalização e dissolução existentes. Esferas/muralhas compartilham o teto padrão de **oito** e a remoção do mais antigo elegível.

Posição usa o primeiro obstáculo da mira, chão com normal Y ≥ 0,85, área carregada, seis apoios físicos próximos da base, caixa livre de terreno/jogador/props e caminho da mão desobstruído. A parede fica vertical, perpendicular à direção horizontal da câmera. **É uma âncora estrutural (`freeze` estático), não repouso natural:** seis pontos de base precisam de chão a até 0,12 m e SDF sólido 0,6 m abaixo, como a âncora conservadora das estruturas existentes (dados amostrados em voxels de 1 m). Isso recusa bordas/solo raso; não prova suporte contínuo entre amostras. TerrainContactWaker reavalia nos pulsos existentes após edição, sem omitir muralhas quando a consulta geral de 64 props satura; perder apoio libera gravidade definitivamente. A muralha ancorada resiste ao Ar; a dinâmica recebe impulso quando houver visada. Fogo funde pelo estado térmico real e remove a colisão antes do efeito final. Sem grafo novo, gelo voxel ou serialização de corpos; save mantém a sessão viva, load/reset limpam.

**Validação dirigida (28/10/2026):** import/parse custom aprovados; [T1/T74/T75 headless 3/3](docs/evidence/p4h/02_headless.json), [regressão headless 12/12](docs/evidence/p4h/03_related_headless.json) (T1/T18/T46/T60/T63/T67/T68/T69/T70/T71/T72/T73), [T1/T74/T75 janela 3/3](docs/evidence/p4h/04_window.json). Execuções finais sem erros/avisos. T74 cobre V contextual/toggle/voo, prévia azul/vermelha, consumo único, volume/massa, bloqueio de jogador/caixa, estabilidade ancorada, recusas e teto misto/proteção. T75 cobre duas rajadas reais de Fogo/fusão/remoção da colisão, escavação/desancoragem/queda, Ar acessível e cancelamentos/save/load/reset. O [FAIL inicial](docs/evidence/p4h/02_headless_initial_fail.json) foi preservado: a sonda de Ar mirava o painel já no fundo da cratera. A rechecagem registra visada falsa/blocked=1 ali e contato com impulso positivo no painel dinâmico acessível. Corrigida a fixture sem alterar física nem relaxar critérios. O parse inicial exigiu anotação explícita de Dictionary; log preservado.

Benchmark janela: quatro muralhas/quatro esferas inicialmente, duas rajadas de Fogo e fusão, **185 ticks / 184 intervalos**, **p95 17,64 / p99 18,46 / máximo 19,54 ms**, limites 20/33/50. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; process_frame após preparação dos corpos, uma Godot por vez, captura fora da amostragem e imagem histórica restaurada. [Captura inspecionada](docs/evidence/p4h/screens/ice_wall.png), [consolidação/ambiente](docs/evidence/p4h/result.json). **Integral de 81 IDs, export, persistência entre processos e playtest humano P4H não executados naquela entrega.** Em 29/10/2026 o usuário confirmou funcionamento no playtest; feedback inicial positivo, sem avaliação detalhada ou aprovação integral. Evidências preservadas, P4D FAIL/T26 intactos.

### P4G — Gelo persistente e derretimento (feedback humano positivo)

**Playtest:** selecione **2**, segure **RMB**, pressione **C** e solte mirando o chão ou uma caixa. O cristal permanece, cai e repousa; repita para acumular até **oito**. Selecione **4** para empurrá-lo com Ar e **3** para aquecer com Fogo: duas rajadas próximas fundem um gelo seco novo nos valores padrão. Trocar elemento/Esc preserva o gelo já materializado. Compare com RMB sem C e LMB: orbe líquido e jato mantêm impulso/WET. Reset/load removem os corpos da sessão; save preserva a física viva, mas não serializa gelo entre sessões.

`WaterOrb` conserva movimento, varredura e impacto único P4F. Após aplicar KINETIC, materializa `IceBody` (pequeno `RigidBody3D`) no centro seguro da esfera, com velocidade inicial zero para não repetir a pancada. Colisor esférico, CCD e layers existentes de terreno/jogador/props; malha facetada P4F compartilhada com ElementalFx. Sem espaço livre, mantém o impacto e fragmenta visualmente, registrando `no_space` no estado/HUD. O orçamento usa `DebrisBudget`; no teto, remove o gelo mais antigo elegível com efeito breve. Corpos com a marca de controle existente são preservados; se todos estiverem protegidos, recusa a materialização. Terra não captura gelo como rocha.

Parâmetros em `WaterOrbTuning`/Resource existente: `ice_density=917` kg/m³ (**137,55 kg** para 150 L nominais), `ice_max_bodies=8`, `ice_initial_temperature=-20`, `ice_melt_temperature=0` °C e `ice_melt_duration_s=0.45`. `BodyMaterialLibrary.ICE`, `MaterialState` e `MaterialResponseSystem` recebem HEAT/WET/KINETIC pelos consumidores existentes. O piso térmico inicial é próprio por material (outros continuam em 20 °C); gelo não derrete passivamente no ambiente. HEAT suficiente marca fusão e remove imediatamente a colisão; uma cópia puramente visual encolhe/desaparece em 0,45 s, com vapor do pool existente. Não há água física resultante, poça, gelo voxel, fusão volumétrica conservativa ou salvamento novo. A esfera de colisão envolve a malha facetada, como no projétil anterior.

**Validação dirigida (28/10/2026):** import/parse custom aprovados; [T1/T72/T73 headless 3/3](docs/evidence/p4g/02_headless.json), [regressão headless 12/12](docs/evidence/p4g/03_related_headless.json) (T1/T38/T46/T48/T49/T52/T60/T67/T68/T69/T70/T71) e [T1/T72/T73 janela 3/3](docs/evidence/p4g/04_window.json). Execuções finais sem erros/avisos. T72 verifica lançamento real, único impulso de 240 N·s/12 m/s na caixa de 20 kg, corpo com massa/colisão/repouso, bloqueio do jogador, Ar e teto/proteção; fixtures pela mesma factory preenchem o orçamento sem repetir oito lançamentos. T73 verifica -20 → -5 °C → fusão por duas rajadas reais de Fogo, retirada da colisão/estado/sinal, save/seleção/Esc/load/reset e recusa por espaço ocupado. A [tentativa inicial FAIL](docs/evidence/p4g/02_headless_initial_fail.json) está preservada: a sonda lia velocidade dentro do callback (0 m/s; depois de quatro ticks, 12 m/s) e outra lambda capturava o corpo após destruído. Corrigidas apenas as medições, sem relaxar critérios ou mudar a física. Uma chamada com parâmetros CLI incorretos foi interrompida sem relatório e não conta como teste.

Benchmark em janela, oito corpos e controle/lançamento de outro gelo, 185 ticks / 184 intervalos: **p95 17,60 / p99 17,96 / máximo 18,32 ms**, limites 20/33/50. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; process_frame após preparação dos corpos, uma Godot por vez, captura após a medição e captura histórica restaurada. [Captura inspecionada](docs/evidence/p4g/screens/persistent_ice.png) e [consolidação/ambiente](docs/evidence/p4g/result.json). **Integral de 79 IDs, export, persistência entre processos e playtest humano P4G não executados.** P4D continua FAIL; T26 não foi investigado. Implementação pronta para playtest, sem aprovação de integração integral.

### P4F — Congelar e lançar gelo: feedback humano positivo

Selecione **2**, segure **RMB** e pressione **C**: o mesmo orbe cristaliza sem mudar de posição ou velocidade. Câmera, Q/E e roda continuam controlando-o. Solte RMB para lançar e mire um pouco acima de alvos distantes para compensar a gravidade. Compare com uma nova formação sem C: água voa reta, molha/resfria/apaga; gelo tem queda balística e golpe maior, sem WET automático. C só age uma vez no hold válido; durante voo, jato ou outro elemento é ignorado. Cancelar ou concluir volta ao estado inicial líquido.

Foram estendidos `WaterOrb` e seu Resource existente, sem outra Ability/controlador ou cálculo duplicado de movimento/colisão. Parâmetros novos em `water_orb_tuning.tres`: `freeze_transition_s=0.18` (visual), `ice_launch_speed=26` m/s, `ice_gravity=9.8` m/s², `ice_impulse_ns=3000`, `ice_max_target_delta_v=12` m/s e `ice_color`. O controle suspenso usa os valores P4E; alcance de percurso 24 m e herança limitada da velocidade são compartilhados. Esfera varrida por tick para água/gelo; KINETIC respeita o impulso já aplicado pelo consumidor estrutural. Gelo usa um octaedro opaco com normais por face, sem oscilação líquida; cristalização e fragmentos cosméticos reutilizam ElementalFx (um emissor, até 12 lascas). [Captura inspecionada](docs/evidence/p4f/screens/ice_hold.png). Sem gelo persistente, derretimento sob Fogo, estruturas de gelo ou física dos fragmentos.

**Testes dirigidos (28/10/2026):** import/parse custom aprovados; [T1/T70/T71 headless 3/3](docs/evidence/p4f/ice_headless.json), [regressão headless 9/9](docs/evidence/p4f/related_headless.json) (T1/T46/T48/T49/T52/T60/T67/T68/T69) e [T1/T70/T71 janela 3/3](docs/evidence/p4f/ice_window.json). Zero erros/avisos. T70 cobre C contextual/uma vez, posição/velocidade preservadas, controle, parede e gravidade; T71 cobre contato único sem WET, peça estrutural sem impulso duplicado, parede de 1 mm a 60 m/s, terreno voxel, alcance e 14 cancelamentos em hold/voo (seleção/input/captura/Esc/reset/save/load), reiniciando líquido. Caixa de 20 kg recebeu 240 N·s e 12 m/s; a peça estrutural de 20 kg recebeu os 120 N·s/6 m/s aplicados pelo consumidor existente. A regressão líquida manteve 160 N·s/8 m/s, WET e extinção.

Benchmark T70 com congelamento/controle/lançamento em janela: **p95 18,13 / p99 18,86 / máximo 18,94 ms**, limites 20/33/50. i5-1135G7/Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; intervalos de process_frame, execuções sequenciais sem outra Godot, captura depois de encerrar amostragem. [Consolidação e ambiente](docs/evidence/p4f/result.json). Três execuções dirigidas; **export, contrato integral de 77 IDs e playtest humano P4F não executados naquela entrega**. Posteriormente, o usuário informou feedback humano positivo em 28/10/2026; isso não substitui validação integral. P4D permanece FAIL; T26 não foi investigado. Evidências históricas preservadas.

### P4E — Orbe de Água: feedback humano positivo

Selecione **2** e segure **RMB**: o orbe se forma junto à mão e acompanha o alvo com atraso. Gire a câmera, ande, use **Q/E** para baixar/subir e a **roda** para aproximar/afastar. Solte RMB mirando caixa, rocha, terreno ou corpo em chamas. Trocar elemento, Esc, perder captura/input e reset/save/load dissipam controle e voo. LMB mantém o jato existente; enquanto um modo está ativo, o outro é recusado, inclusive durante o voo do orbe. Solte e pressione de novo para iniciar o outro modo.

Parâmetros próprios em [`data/abilities/water_orb_tuning.tres`](data/abilities/water_orb_tuning.tres), separados do jato: volume nominal **150 L** (raio ~0,33 m), distância do alvo **2–7 m**, altura do alvo **0,6–4 m**, controle limitado a **8 m/s** e **55 m/s²**, lançamento **22 m/s** mais até **5 m/s** da velocidade acumulada, alcance de percurso **24 m**. O raio/volume são capturados por formação; a edição do volume vale para a próxima massa. Intensidade: até **1800 N·s**, limitada a massa do alvo × **8 m/s**; WET **0,9**, respingo **1,8 m**, com a oclusão existente. Peças presas recebem KINETIC pelo sistema de materiais; corpos livres recebem impulso, sem teleporte nem impacto duplicado. WET atualiza umidade, temperatura e combustão antes do respingo visual.

`WaterOrb` tem posição/velocidade próprias e usa esfera varrida tanto no controle quanto no voo, com teste explícito de sobreposição inicial; não usa o corpo rígido nem a mola da Terra. Forma somente com espaço livre e trajeto desobstruído do peito à mão. Os limites regulam o alvo; a massa real pode atrasar ou ficar bloqueada sem teleporte. Parede bloqueia/desliza o controle; se geometria móvel invadir a massa, ela é cancelada em vez de teleportada para fora. Colisão sem testemunho de contato é dissipada de forma conservadora. O lançamento é retilíneo, sem gravidade nesta fatia; o primeiro contato válido encerra a massa. Nenhuma escavação, poça, reservatório captável ou simulação conservativa de líquido. Os litros são um recurso nominal da reserva Criativo, não água extraída do cenário.

`WaterJet`, controller/mira/input, `Ability`/identidade de eventos, `MaterialResponseSystem` e `ElementalFx` foram reutilizados. O núcleo translúcido, brilho interno e oscilação são malhas nativas; trilha até 12 partículas e pool de dois respingos. `trail_amount=0` preserva o núcleo sem partículas; `visual_enabled=false` desliga apresentação sem alterar o estado/colisão do gameplay. [Captura do núcleo suspenso](docs/evidence/p4e/screens/orb_hold.png), inspecionada visualmente; não equivale a playtest humano.

**Validação direcionada em 28/10/2026:** import/parse custom sem erros/avisos; [T1/T67–T69 inicial headless, 4/4](docs/evidence/p4e/orb_headless_initial.json); [regressão headless, 7/7](docs/evidence/p4e/related_headless.json): T1, T46/T47/T48 (jato), T60/T64/T66 (controles/cancelamentos de Terra); [T1/T67–T69 em janela, 4/4](docs/evidence/p4e/orb_window.json); [T1/T67–T69 final headless, 4/4](docs/evidence/p4e/orb_headless_final.json); [contato final T1/T68, 2/2](docs/evidence/p4e/contact_headless_final.json). T67 cobre controle, parede, ausência de teleporte e benchmark. T68 verifica impacto único, impulso em 20/2000 kg, WET/extinção antes do FX com visual desativado, oclusão por parede de 1 mm a **60 m/s** (1 m/tick, maior que o diâmetro) e alcance sem contato remoto. A conferência final inclui contato com o collider voxel real, sem editar o terreno, e formação de 10 L bloqueada por parede fina entre o personagem e a mão. T69 cobre exclusão, pincel fora do contexto, reinício e cancelamento em hold/voo por seleção, input, captura, Esc real e reset/save/load. Esc/60 m/s estão na janela e em `orb_headless_final`. [Ambiente/resultados](docs/evidence/p4e/result.json).

Benchmark T67 em janela: **p95 18,05 ms / p99 18,76 ms / máximo 21,65 ms** (limites 20/33/50). i5-1135G7, Iris Xe, Forward+/Vulkan 1.4.323, Jolt, 1600×900; intervalos de `process_frame` durante controle/lançamento, sem captura de imagem na amostragem e sem outra Godot concorrente. Captura histórica restaurada; evidências anteriores intactas. Cinco execuções direcionadas concluídas, sem repetir integrais. Uma tentativa adicional não iniciou por inferência de tipo no teste; anotação booleana corrigida e contato reexecutado 2/2, sem erros/avisos. O [log da tentativa interrompida](docs/evidence/p4e/contact_headless.log) foi preservado e não conta como PASS. Na entrega P4E, o contrato tinha **75 IDs**; **export, bateria integral, T26 e playtest humano não foram executados naquela sessão**. Depois, o usuário informou feedback humano positivo, sem avaliação detalhada por cenário. P4D permanece FAIL; P4E está implementado para experimentar, sem aprovação de integração.

### P4D — validação direcionada e feedback humano

- [Import](docs/evidence/p4d/01_import.log): saída 0 em uma tentativa.
- [Regressão relacionada headless](docs/evidence/p4d/related_headless.json): **18/20**, com T65/T66 aprovados e zero erros/avisos do motor. T21 falhou porque a seleção omitiu T20, seu pré-requisito; T61 falhou em `one_new_impact`, com as demais verificações verdadeiras.
- [Rechecagem contextual headless](docs/evidence/p4d/context_headless.json): **5/5** para T1/T19/T20/T21/T61, zero erros/avisos. A causa da variação de T61 não foi isolada; não se atribui a resultado preexistente ou regressão, nem se reclassifica o FAIL anterior.
- [Editor em janela](docs/evidence/p4d/fissure_window.json): **4/4** para T1/T37/T65/T66, zero erros/avisos. T65 confirmou um PATH subtrativo, queda da caixa de **1,16044 m**, três fundos de colisão em **−1,2954/−1,2542/−1,2383 m** (antes: +0,02 m), seis verificações de save/reset/load verdadeiras e SDF restaurado idêntico.

| Cenário em janela | p95 | p99 | Máximo |
|---|---:|---:|---:|
| T37, quatro poderes | 18,96 ms | 21,36 ms | 44,18 ms |
| T65, prévia/criação/apoio da fissura (128 quadros) | 17,90 ms | 19,48 ms | 19,52 ms |

Ambos atendem a 20/33/50 ms. [Ambiente registrado](docs/evidence/p4d/environment.json): Ryzen 7 5825U, AMD Radeon Graphics (driver 31.0.21925.1001), 1600×900, Vulkan 1.3.260, Forward+ e Jolt. Os hashes das 52 fontes permaneceram iguais desde esse registro. Não se infere ganho causal em relação ao hardware dos checkpoints anteriores.

**Tentativa inicial preservada:** [2/3 headless](docs/evidence/p4d/fissure_headless_initial.json), com FAIL em T65. O testemunho SDF usava o centro a aproximadamente −0,33 m, arredondado para o voxel Y=0 (SDF=0) após reset. A sonda foi deslocada 0,5 m para dentro do solo e todas as verificações passaram a ser registradas, sem alterar tolerâncias. Os resultados acima incluem essa correção do testemunho.

As capturas foram inspecionadas: a [prévia](docs/evidence/p4d/screens/03_p4d_fissure_preview.png) mostra a fita verde e a [fissura aplicada](docs/evidence/p4d/screens/04_p4d_fissure.png) mostra a vala. Os PNGs foram movidos do destino fixo do runner para `docs/evidence/p4d/screens/`; os relatórios brutos mantêm os caminhos originais. A captura histórica do P3.6 foi restaurada.

Naquela fatia não foram executados export, persistência entre processos ou bateria completa. Save/reset/load de T65 ocorreram na mesma execução; o checkpoint permaneceu aberto para investigar T61. O usuário confirmou feedback humano positivo em 28/10/2026 ("sim, pode subir"), sem avaliação detalhada por cenário. Os campos de playtest dos relatórios automatizados preservam o estado histórico da execução. Compressão continua futura.

### P4D — checkpoint da retomada em 28/10/2026: FALHOU

Checkout existente recuperado em `C:\Users\dsoares\Documents\Projetos\game`, inicialmente limpo; `origin/main` confirmado em `80f2a08` e `main` atualizada por fast-forward. Trabalho na branch `codex/p4d-integration`, sem clone, worktree ou instalação. Editor custom 4.7.2 `ed1daf0bf`, classes Voxel embutidas e template release compatível confirmados. [Ambiente e hashes](docs/evidence/p4d/integration/environment.json), [resultado consolidado](docs/evidence/p4d/integration/final_result.json) e [passos do runner](docs/evidence/p4d/integration/steps.json).

**T61:** o relatório histórico não separava as duas condições de `one_new_impact`; não permite saber qual falhou. O teste agora registra delta de impactos, deslocamento da caixa, timeout e monitoramento, mantendo esperas e PASS intactos. Dez processos direcionados (5 headless + 5 janela) tiveram exatamente um impacto, caixa deslocada 1,35–5,69 m e zero callbacks/voos restantes. Falha física histórica **não reproduzida; causa não estabelecida**. Nove relatórios direcionados passaram; [janela 4](docs/evidence/p4d/integration/t61/window_4.json) falhou somente por p95=20,14 ms, preservado sem mudar o limite. [Checagem contextual](docs/evidence/p4d/integration/context_window.json): 6/6 PASS. T61 também passou nas quatro integrais.

Reutilizado `tools/run_p361_tests.ps1`, com editor/template custom e `-EvidenceDirectory docs/evidence/p4d/integration`. Contrato vigente: **72 IDs**. Uma bateria integral por modo, sem repetir integrais:

| Modo | Resultado |
|---|---|
| [Editor headless](docs/evidence/p4d/integration/editor_headless.json) | 71/72 — FAIL T26 |
| [Editor em janela](docs/evidence/p4d/integration/editor_window.json) | 72/72 PASS |
| [Export headless](docs/evidence/p4d/integration/export_headless.json) | 72/72 PASS |
| [Export em janela](docs/evidence/p4d/integration/export_window.json) | 71/72 — FAIL T26 |

**Bloqueio do gate:** nas duas falhas, T26 recusou a preparação por `natural_rest_timeout`, **antes de salvar**: não atingiu 60 ticks consecutivos de sono natural em 15 s. No editor headless, maior sequência 21 ticks; no export janela, zero, com peças ainda acordadas e P33 girando a 0,166 rad/s no snapshot final. Não é evidência de falha do save. Inspeção não encontrou alteração de `can_sleep`, parâmetros físicos vazando ou defeito comprovado do runtime. [Três rechecagens direcionadas](docs/evidence/p4d/integration/t26/steps.json), com T14 criando o slot exigido: 3/3 em cada processo (duas editor headless, uma export janela). O timeout não reapareceu; causa não isolada. Os FAILs integrais permanecem válidos e o checkpoint **não está aprovado**. Sem forçar sono, ampliar prazos, mudar física ou repetir até verde.

286/288 verificações integrais aprovadas. Persistência write/read entre processos passou 2/2 em cada uma das quatro etapas editor/export. Todos os relatórios completos, com IDs do contrato; `Invoke-SelftestStep` validou run_id, frescor, contadores, resultados individuais e logs, rejeitando os três relatórios FAIL (dois integrais e um direcionado). Zero erros/avisos nos 26 logs, incluindo import/export. As 52 fontes permaneceram com os mesmos hashes durante as execuções; preset e fixture histórica de persistência intactos. Nenhuma captura ou playtest humano novo.

| Cenário | Editor: p95 / p99 / máximo | Export: p95 / p99 / máximo |
|---|---|---|
| T27 — colapso | 18,46 / 19,42 / 19,72 ms | 19,04 / 20,02 / 21,05 ms |
| T37 — quatro poderes | 18,93 / 21,48 / 31,53 ms | 19,09 / 21,10 / 31,78 ms |
| T59 — controle livre | 17,90 / 18,57 / 19,22 ms | 17,51 / 18,20 / 23,42 ms |
| T61 — recaptura | 18,57 / 20,09 / 24,34 ms | 17,45 / 18,13 / 24,14 ms |
| T63 — pilar | 18,33 / 19,21 / 19,55 ms | 17,50 / 18,36 / 18,75 ms |
| T65 — fissura | 18,93 / 19,76 / 20,12 ms | 17,45 / 18,04 / 18,83 ms |

As duas integrais em janela atendem a 20/33/50 ms em todos esses cenários. Máquina: i5-1135G7, 16 GB RAM, Iris Xe (driver 32.0.101.7085), Vulkan 1.4.323/Forward+, Jolt; janela configurada 1600×900, display 1920×1200, plano Equilibrado. Execuções sequenciais, sem outra Godot aberta; acompanhamento por leitura do log sem criar processos shell/CIM durante medições. Intervalos reais de `process_frame` nos runners existentes. A validação direcionada anterior usou outro hardware AMD; nenhuma diferença é atribuída causalmente ao código. Caminhos locais nas novas evidências foram normalizados para publicação; medições e IDs preservados.

**Pendência daquele checkpoint:** isolar o timeout de preparação do T26 no contexto integral, preservando 15 s/60 ticks, antes de revalidar os modos que falharam. P4E foi autorizado posteriormente, mantendo essa dívida fora da fatia de gameplay. Os checkpoints abaixo são históricos.

### P4C — validação direcionada e checkpoint de integração

- [T1/T63/T64 headless: 3/3 PASS](docs/evidence/p4c/pillar_radius2_headless.json): RMB real, um único PATH aditivo, apoio físico de caixa/jogador, save/reset/load, recusas e cancelamentos de prévia/fila. Um corpo que entra no volume depois da confirmação cancela somente esse pedido, antes da fila processá-lo.
- [Regressão relacionada: 17/17 PASS](docs/evidence/p4c/related_headless.json): T1, T4, T11, T13, T14, T28–T30, T39, T40, T42–T44 e T59–T62. Cobre os consumidores reais da validação PATH e o ciclo da rocha.
- [Export em janela: 4/4 PASS](docs/evidence/p4c/candidate_window.json): T1, T37, T63, T64; zero erros/avisos em todos os resultados finais. Import, export Windows, inspeção e `git diff --check` aprovados; preset preservado.

| Cenário em janela | p95 | p99 | Máximo |
|---|---:|---:|---:|
| T37, base P4B `266627d` | 18,92 ms | 20,26 ms | 25,27 ms |
| T37, P4C | 18,47 ms | 20,76 ms | 30,68 ms |
| T63, prévia/criação/apoio do pilar | 17,97 ms | 19,87 ms | 22,67 ms |

[Ambiente e fontes](docs/evidence/p4c/environment.json), [baseline](docs/evidence/p4c/baseline_p4b_window.json): mesma máquina i5-1135G7/Iris Xe, Godot custom 4.7.2 + Voxel Tools 1.7, Forward+, viewport configurada 1600×900 e Jolt. Execuções sequenciais de export, sem outra Godot ativa. Gates 20/33/50 ms intactos; a variação do T37 não demonstra ganho ou regressão causal. T63 coleta intervalo real entre quadros, incluindo prévia, edição e confirmação do collider; save/load ficam fora dessa janela de desempenho.

As [duas primeiras](docs/evidence/p4c/pillar_headless.json) [execuções headless](docs/evidence/p4c/pillar_recheck_headless.json) ficaram em 2/3 por a caixa escorregar do topo com raio 1,1 m, inclusive com 3 s de assentamento. Raio padrão ajustado para 2 m; mesmos critérios de apoio e sem mudança nos limites de desempenho.

Na fatia direcionada acima não foram executados bateria integral e persistência entre processos; esses passos foram executados no checkpoint abaixo, após o feedback humano positivo. O campo de playtest no ambiente direcionado preserva o estado histórico daquela execução. Para repetir somente os testes novos, usar `--p36-selftest --only=T63,T64`; T1 é obrigatório e incluído automaticamente. Reutilizar `Invoke-SelftestStep` com pasta/relatório novos para preservar evidências.

**Checkpoint de integração — 27/10/2026:** [resumo validado](docs/evidence/p4c/integration/final_result.json), [passos do runner](docs/evidence/p4c/integration/steps.json).

| Modo | Resultado integral |
|---|---|
| [Editor headless](docs/evidence/p4c/integration/editor_headless.json) | 70/70 PASS |
| [Editor em janela](docs/evidence/p4c/integration/editor_window.json) | 70/70 PASS |
| [Export headless](docs/evidence/p4c/integration/export_headless.json) | 70/70 PASS |
| [Export em janela](docs/evidence/p4c/integration/export_window.json) | 70/70 PASS |

280 execuções de teste aprovadas, zero erros/avisos. Cada modo integral foi executado uma única vez, sem rechecagens. Export Windows e persistência write/read em processos separados passaram no editor e no export (2/2 em cada uma das quatro etapas). Import/export sem erros/avisos; 52 scripts conferem com os hashes do [ambiente](docs/evidence/p4c/integration/environment.json). Preset e fixtures anteriores restaurados exatamente; nenhuma captura nova.

| Cenário | Editor: p95 / p99 / máximo | Export: p95 / p99 / máximo |
|---|---|---|
| T27 — colapso | 17,73 / 18,20 / 18,44 ms | 17,98 / 18,43 / 18,86 ms |
| T37 — quatro poderes | 18,50 / 20,30 / 32,18 ms | 18,98 / 20,08 / 32,23 ms |
| T59 — controle livre | 17,90 / 18,46 / 19,09 ms | 17,86 / 18,20 / 19,17 ms |
| T61 — recaptura da rocha | 17,67 / 18,57 / 24,67 ms | 17,76 / 19,02 / 23,52 ms |
| T63 — pilar | 17,82 / 18,33 / 19,54 ms | 17,73 / 18,15 / 21,50 ms |

Todos atendem a 20/33/50 ms, em i5-1135G7/Iris Xe, Forward+, 1600×900 e Jolt, com execuções sequenciais e sem outra Godot aberta no início. Acompanhamento por leitura de log sem abrir processos shell/CIM durante as janelas de medição. Sem inferência de ganho causal entre amostras. Para um próximo checkpoint, reutilizar `tools/run_p361_tests.ps1` com `-Template <template-custom>` e `-EvidenceDirectory <pasta-nova>`. P4C integrado à main pela PR #4 em `b84b4c6`; histórico preservado.

### P4B — validação direcionada e checkpoint de integração

Reutiliza o selftest existente: T61 cobre captura/relançamento da mesma instância; T62 cobre seleção, alcance, orçamento e cancelamentos. Sem runner ou controlador físico novo.

- [18/18 headless](docs/evidence/p4b/editor_headless.json): T1, T19–T22 (preparação e orçamento), T28–T30, T39–T44 e T59–T62 (Terra/P4A/P4B).
- [5/5 em janela](docs/evidence/p4b/editor_window.json): T1, T27, T37, T61 e T62. Zero erros/avisos nos dois modos; parse/inicialização, parse do selftest e `git diff --check` passaram.

| Cenário em janela | p95 | p99 | Máximo |
|---|---:|---:|---:|
| T37, base main `9103bee` | 18,53 ms | 20,84 ms | 34,49 ms |
| T27, P4B — colapso | 18,48 ms | 19,77 ms | 24,79 ms |
| T37, P4B — quatro poderes | 18,68 ms | 20,81 ms | 33,62 ms |
| T61, P4B — capturar/relançar | 18,55 ms | 21,02 ms | 25,18 ms |

[Ambiente e hashes](docs/evidence/p4b/environment.json), [baseline](docs/evidence/p4b/baseline_window_T37.json): i5-1135G7/Iris Xe, Forward+, 1600×900, Godot custom 4.7.2 + Voxel Tools 1.7, Jolt. Gates 20/33/50 ms preservados; esta amostra não demonstra ganho causal.

Na preparação, T22 isolado foi executado sem sua torre previamente derrubada; a seleção final inclui T19–T21. Os eventos brutos de mouse do novo selftest são despachados antes das comparações imediatas, sem avançar a física.

Para repetir: `--p36-selftest --only=T19,T20,T21,T22,T28,T29,T30,T39,T40,T41,T42,T43,T44,T59,T60,T61,T62` em headless; em janela `--only=T27,T37,T61,T62`, usando o helper de validação existente e `--report=<novo_caminho.json>`.

Na fatia inicial acima não foram executados bateria completa, export ou persistência entre processos; esses passos foram executados no checkpoint posterior abaixo. Playtest humano P4B: feedback positivo do usuário em 27/10/2026; avaliações detalhadas por cenário não registradas.

**Gate de integração — resultado final:** [resumo validado por contratos e run_ids reais](docs/evidence/p4b/integration/final_result.json), com fontes idênticas aos hashes do [ambiente original](docs/evidence/p4b/integration/environment.json).

| Modo | Resultado integral final |
|---|---|
| [Editor headless](docs/evidence/p4b/integration/editor_headless.json) | 68/68 PASS |
| [Editor em janela — última verificação](docs/evidence/p4b/integration/recheck/editor_window_quiet.json) | 68/68 PASS |
| [Export headless](docs/evidence/p4b/integration/export_headless.json) | 68/68 PASS |
| [Export em janela](docs/evidence/p4b/integration/export_window.json) | 68/68 PASS |

Zero erros/avisos nos resultados finais. Export Windows e persistência write/read em processos separados no editor e export passaram (2/2 IDs em cada uma das quatro etapas). Logs de import/export conferidos; preset e fixtures anteriores restaurados. Nenhuma captura nova.

**Histórico de desempenho preservado:** a [primeira execução do editor em janela](docs/evidence/p4b/integration/editor_window.json) ficou em 67/68 por T61 (p95 33,49 ms, p99 45,17 ms, máximo 114,13 ms). A [primeira repetição integral](docs/evidence/p4b/integration/recheck/editor_window_full.json) ficou em 67/68 por T27 (p95 20,51 ms), com T61 aprovado. A [rechecagem contextual](docs/evidence/p4b/integration/recheck/editor_window_context.json) passou 7/7; T27 curto passou na base e no P4B com p95 de 17,76 ms. A última integral passou 68/68, acompanhada por leitura do log sem abrir processos shell/CIM durante a medição. Fontes e limites permaneceram iguais; a causa exata dos picos não foi confirmada. [Passos originais](docs/evidence/p4b/integration/steps.json), [rechecagens](docs/evidence/p4b/integration/recheck/steps.json) e [condições da comparação](docs/evidence/p4b/integration/recheck/comparison_environment.json) mantêm os resultados anteriores.

| Cenário | Editor final: p95 / p99 / máximo | Export: p95 / p99 / máximo |
|---|---|---|
| T27 — colapso | 17,81 / 18,56 / 19,79 ms | 18,80 / 20,48 / 21,15 ms |
| T37 — quatro poderes | 18,86 / 23,48 / 38,99 ms | 19,12 / 21,42 / 32,47 ms |
| T61 — reutilização | 17,98 / 23,50 / 23,93 ms | 18,72 / 20,17 / 22,77 ms |

Todos os resultados finais atendem a 20/33/50 ms, em i5-1135G7/Iris Xe, Forward+, 1600×900 e Jolt. Para outro checkpoint, reutilizar `tools/run_p361_tests.ps1` com `-Template <template-custom>` e `-EvidenceDirectory <pasta-nova>`. P4B integrado à main em `266627d`; histórico preservado.

### P4A — validação direcionada e checkpoint de integração

Executado com `Invoke-SelftestStep` de `tools/lib_godot_process.ps1`, sem runner novo: valida exit code, relatório novo/run_id, IDs explícitos e zero erros/avisos. Evidências em [`docs/evidence/p4a/`](docs/evidence/p4a/); históricos anteriores preservados.

| Verificação | Risco coberto | Resultado |
|---|---|---|
| T59/T60 | altura/distância, forças sem teleporte, limites, parede, cancelamento e input contextual | PASS headless e janela |
| T28/T29/T30/T39/T40/T42/T43/T44 | regressão da Terra: ciclo, lançamento, impacto, mola e Resource | PASS headless |
| T37 em janela, base e versão final | custo no caminho físico, mesmo ambiente e cenário | PASS nas duas versões |

Checkpoint final: [11/11 headless](docs/evidence/p4a/editor_headless.json) e [4/4 em janela](docs/evidence/p4a/editor_window.json), incluindo T1 obrigatório; zero erros e zero avisos. Import da base, parse/inicialização de produção, parse do selftest e `git diff --check` também passaram.

| Cenário em janela | p95 | p99 | Máximo |
|---|---:|---:|---:|
| T37, base `180ec59` | 18,63 ms | 20,33 ms | 34,86 ms |
| T37, P4A | 18,47 ms | 20,95 ms | 37,01 ms |
| T59, manipulação ativa P4A | 17,93 ms | 18,79 ms | 19,32 ms |

Godot 4.7.2 custom + Voxel Tools 1.7, Jolt, Forward+, 1600×900; i5-1135G7 e Iris Xe (driver 32.0.101.7085). [Ambiente](docs/evidence/p4a/environment.json) e [baseline](docs/evidence/p4a/baseline_window_T37.json). As duas versões atendem aos gates; esta amostra não demonstra ganho ou regressão causal.

Para repetir somente esta cobertura, usar `--p36-selftest --only=T28,T29,T30,T39,T40,T42,T43,T44,T59,T60` em headless; em janela, `--only=T37,T59,T60`. Passar `--report=<novo_caminho.json>` e validar pelo helper existente; não sobrescrever as evidências históricas do runner P3.6.

Limites preservados: p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms. O checkpoint direcionado acima foi seguido pelo gate completo abaixo. Playtest humano dos controles P4A: feedback positivo do usuário em 27/10/2026; as avaliações humanas dos outros elementos permanecem pendentes.

**Gate de integração — 27/10/2026:** uma execução completa por modo, sem falhas ou repetição da bateria. Mesma máquina/configuração descrita acima; [ambiente e hashes dos scripts executados](docs/evidence/p4a/integration/environment.json).

| Modo | Resultado |
|---|---|
| [Editor headless](docs/evidence/p4a/integration/editor_headless.json) | 66/66 PASS |
| [Editor em janela](docs/evidence/p4a/integration/editor_window.json) | 66/66 PASS |
| [Export headless](docs/evidence/p4a/integration/export_headless.json) | 66/66 PASS |
| [Export em janela](docs/evidence/p4a/integration/export_window.json) | 66/66 PASS |

264 testes aprovados, zero erros/avisos. Export Windows e persistência write/read em processos separados no editor e export também passaram (2/2 IDs em cada uma das quatro etapas); [passos do runner](docs/evidence/p4a/integration/steps.json). Logs de import/export conferidos sem erros/avisos. Fixtures históricas e preset de export restaurados; hashes dos scripts conferidos após o gate. Não foram geradas novas capturas.

| Cenário | Editor: p95 / p99 / máximo | Export: p95 / p99 / máximo |
|---|---|---|
| T27 — colapso | 17,58 / 18,27 / 18,80 ms | 17,38 / 18,14 / 21,94 ms |
| T37 — quatro poderes | 18,28 / 19,93 / 32,60 ms | 18,80 / 21,07 / 28,49 ms |
| T59 — manipulação ativa | 17,66 / 18,22 / 18,73 ms | 17,85 / 18,61 / 31,07 ms |

Comando usado neste checkpoint; ao repetir, escolher outra pasta para preservar este histórico:

```powershell
./tools/run_p361_tests.ps1 -Template 'C:\Users\dsoares\Tools\Godot\4.7.2-voxel1.7\godot.windows.template_release.x86_64.exe' -EvidenceDirectory 'docs/evidence/p4a/integration'
```

O parâmetro `EvidenceDirectory` só altera a saída das evidências; o destino padrão e todos os contratos do runner anterior foram preservados. Este checkpoint P4A já foi integrado à main em `9103bee`; a fase atual é P4D.

### P3.6 — Água, Fogo e Ar polidos (inclui as regressões do P0 ao P3.5)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p36_tests.ps1 -Stage final -Window -Export
```

Grava em `docs/evidence/p36/final/`: import, selftest P3.6 (P0–P3.5 + T46–T58) no editor e no export, headless e em janela,
com contrato explícito de IDs, zero erros/avisos e capturas em janela. `-Stage m1|m2|m3` grava as evidências de cada marco;
`-TestIds T49,T50` limita a IDs do contrato (T1 sempre incluso). Direto: `... -- --p36-selftest --evidence-stage=final`
(opções `--only=`, `--p36-screenshots`).

### P3.5 — Terra polida (inclui as regressões do P0 ao P3)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p35_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p35/`: import, `check_env`, dump da API, spike da Terra (`tools/spike_p35_earth.gd`:
Timer do Voxel Tools, cavidade, levantamento e separação sub-voxel; custo de GPU só em janela), selftest P0 sozinho,
selftest P3.5 (P0–P3 + T39–T45) e a persistência entre processos; `-Window` inclui as capturas de cada fase da Terra
(T45). Direto: `... -- --p35-selftest` (opções `--only=T39,T43`, `--p35-screenshots`, `--report=`).

### P3 (inclui as regressões do P0, P1 e P2)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p3_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p3/`: import, `check_env`, dump da API, spike de física do P3 (`tools/spike_p3_physics.gd`,
`00_spike_p3.txt`), selftest P0 sozinho, selftest P3 (P0 + P1 + P2 + T28–T38) e a persistência entre processos;
`-Window` roda o selftest P3 em janela com capturas (os critérios de FPS do T27 e do T37 só valem aí) e `-Export`
repete tudo no `.exe`. Direto: `... -- --p3-selftest` (opções `--only=T31,T35`, `--p3-screenshots`, `--report=`).

### P2 (inclui as regressões do P0 e do P1)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p2_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p2/`: import, `check_env`, dump da API, spike da API P2 (`tools/spike_p2_api.gd`), selftest P0
sozinho, selftest P2 (P0 + P1 + T18–T27) e a persistência entre processos; `-Window` roda o selftest P2 em janela com
capturas (o critério de FPS do T27 só vale aí) e `-Export` repete tudo no `.exe`. Direto: `... -- --p2-selftest`.

### P1 (inclui a regressão do P0)

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p1_tests.ps1 -Window -Export
```

Grava em `docs/evidence/p1/`: import (com repetição se a Godot cair no encerramento, B1), `check_env`, dump da API,
spike da API P1 (`tools/spike_p1_api.gd`), selftest P0 sozinho (12 testes), selftest P1 (P0 + T8–T17) e a
persistência entre processos (`--p1-persist=write` num processo, `--p1-persist=read` noutro). `-Window` roda o
selftest P1 em janela com capturas em `docs/evidence/p1/screens/` (só aí FPS e tempo de quadro valem algo);
`-Export` exporta e repete selftest P1 e persistência no `.exe`. Feche o editor deste projeto antes de rodar.
Cada passo tem limite de tempo (`-StepTimeoutSec`, padrão 600 s; 0 desliga): se estourar (por exemplo, um script
que não compila deixa a cena rodando sem o selftest), o processo é encerrado, o log ganha uma linha `TIMEOUT` e o passo
sai com exit 124. O `run_p0_tests.ps1` aceita o mesmo parâmetro.

Direto, num terminal bash:

```bash
"C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe" --headless --path . res://scenes/main.tscn -- --p1-selftest
```

Opções depois de `--`: `--p1-screenshots` (janela), `--only=T8,T14` (T1 e baseline sempre rodam),
`--report=<caminho>`, `--p1-persist=write|read`. Relatório JSON em `docs/evidence/p1/p1_selftest_<modo>.json`.

### P0

O jeito recomendado é o script, que espera cada processo terminar e grava os logs em UTF-8 em `docs/evidence/`:

```bash
powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Window -Export
```

Ele importa o projeto (com uma nova tentativa automática se a Godot cair no encerramento do `--import`, bug B1),
roda `check_env`, o dump da API, o selftest headless e em janela, exporta e roda o selftest no `.exe`.
Sem `-Window`/`-Export`, roda só os passos headless. Feche o editor deste projeto antes de rodar.

O selftest (T0–T7b) roda dentro da cena real, com o mesmo `TerrainService`, a mesma física e o mesmo
`CharacterBody3D` do jogo. Para chamá-lo direto (num terminal bash; o editor custom é um executável de
subsistema GUI e no `cmd`/PowerShell a saída não aparece sem redirecionamento):

```bash
"C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe" --headless --path . res://scenes/main.tscn -- --p0-selftest
```

Saída `[P0TEST] ...`, relatório JSON em `docs/evidence/p0_selftest_<modo>.json` e código de saída 0 quando tudo passa.
Opções depois de `--`: `--p0-screenshots` (só em janela; salva PNGs em `docs/evidence/screens/`), `--only=T2,T5`,
`--report=<caminho>`.

Ferramentas avulsas (mesmo executável, `--headless --path . --script ...`):
- `res://tools/check_env.gd`: versão, variante do Voxel Tools (módulo/GDExtension), classes, física, renderer.
- `res://tools/probe_voxel_api.gd`: dump da API **real** do binário → `docs/evidence/voxel_api_probe.txt`.

## Export Windows

PowerShell, na raiz do projeto (o helper aguarda o processo GUI e grava o log):

```powershell
. .\tools\lib_godot_process.ps1
$root = (Get-Location).Path
$godot = Resolve-Godot $env:GODOT
New-Item -ItemType Directory -Force build | Out-Null
$log = Join-Path $root 'build/export.log'
$code = Invoke-Native $godot @('--headless', '--path', '.', '--export-release',
    'Windows Desktop', 'build/elemental_ruins.exe') $log $root 180
if ($code -ne 0 -or (Test-GodotLog $log)) { throw 'Export falhou; confira build/export.log' }
```

Gera `build/elemental_ruins.exe` (template custom, 88,5 MB, com o Voxel Tools embutido) e `build/elemental_ruins.pck`.
O template oficial **não** serve, porque não contém o Voxel Tools. **Export debug** não está disponível: a release só
traz template de release para Windows, e o debug exigiria compilar o template.
O selftest também roda no executável: `build/elemental_ruins.exe --headless -- --p0-selftest --report=<caminho.json>`.

## Estrutura

```
project.godot, export_presets.cfg (template custom com caminho absoluto desta máquina)
scenes/main.tscn                  Main → World (voxel_lab) + Player + TerrainEditController + AbilityController + ElementalFx + EarthFx + HUD
scenes/world/voxel_lab.tscn       ambiente, sol, TerrainService, TerrainBrushQueue, TerrainRoot, SpawnPoint, Props, Structures, StructureService, ContactWaker, DebrisBudget, DustFx, MaterialResponseSystem
scenes/player/player.tscn         CharacterBody3D + VoxelViewer + CameraRig (SpringArm3D + Camera3D)
scenes/ui/debug_hud.tscn          overlay de engenharia (montado em código)
scripts/world/terrain_service.gd  ÚNICO ponto que conhece o Voxel Tools (API em coordenadas do mundo; stream SQLite)
scripts/world/terrain_brush_queue.gd  fila de brushes: traços contínuos, orçamento por quadro, divisão e fusão
scripts/world/terrain_brush_request.gd  pedido REMOVE/ADD/PATH/SMOOTH
scripts/world/terrain_material*.gd  TerrainMaterial (dureza, densidade, dobrável, cor) e a biblioteca soil/sand/stone
scripts/world/terrain_save_files.gd  caminhos e arquivos de sessão/slot (sem Voxel Tools)
scripts/world/lab_terrain_factory.gd  VoxelLodTerrain + Transvoxel + VoxelGeneratorGraph (plano + colina + materiais)
scripts/gameplay/terrain_edit_controller.gd  atalhos, mira e marcador → TerrainBrushQueue
scripts/player/*.gd               locomoção e câmera
scripts/dev/p0_selftest.gd        roteiro automatizado de aceite do P0
scripts/dev/p1_selftest.gd        P0 + testes do P1 (herda o anterior)
scripts/dev/p2_selftest.gd        P0 + P1 + testes do P2 (herda o anterior)
scripts/dev/p3_selftest.gd        P0 + P1 + P2 + testes do P3 (herda o anterior)
scripts/dev/p35_selftest.gd       P0–P3 + testes do P3.5 (fases da Terra; herda o anterior)
scripts/abilities/*.gd            AbilityController (1–4 + LMB), base Ability, os 4 poderes e EarthTuning (parâmetros da Terra)
data/abilities/earth_tuning.tres  valores da Terra polida (tempos, forças, alcance, cratera)
scripts/elements/*.gd             ElementalEvent, BodyMaterial(+biblioteca), MaterialState, MaterialResponseSystem, ElementalFx, EarthFx, CrackTexture
scripts/ui/ready_ring.gd          anel de prontidão da Terra em volta da retícula
scripts/structures/*.gd           peça, fábrica da torre, grafo de apoio e StructureService (âncoras, soltura em etapas)
scripts/physics/*.gd              TerrainContactWaker, DebrisBudget (teto de corpos, culling) e DustFx
materials/terrain_lab.gdshader    cor do material (CUSTOM1) + grade 1 m/4 m + costura LOD oficial do Transvoxel
tools/                            check_env, probe_voxel_api, spike_p1_api, spike_p2_api, spike_p3_physics, spike_p35_earth, run_p0/p1/p2/p3/p35_tests.ps1
docs/                             decisões, resultados e evidências (logs, JSON, PNG); ignorada pela Godot (.gdignore)
```

API pública do `TerrainService` (mundo): `dig_sphere(p, r)`, `add_sphere(p, r, material)`, `dig_path(points, radii)`,
`add_path(points, radii, material)`, `smooth_area(p, r)`, `get_material_at(p)`, `can_edit_area(aabb)`,
`raycast_terrain(from, to)`, `sample_sdf(p)`, `reset_world()`, `save_world(slot)`, `load_world(slot)` (os três
assíncronos), `has_saved_world(slot)`, `is_ready()`. Sinais: `terrain_ready`, `terrain_changed(aabb, revision)`
(o evento TerrainChanged: os dados já mudaram, o collider ainda não), `edit_rejected(op, reason, aabb)`,
`world_reset_started/finished`, `world_save_started/world_saved`, `world_load_started/world_loaded`.
Gameplay edita pela `TerrainBrushQueue` (`enqueue`, `begin_stroke/update_stroke/end_stroke`, sinal `brush_applied`).
P2: `TerrainService.extract_rock(p, normal, raio, pai, direção)`; `StructureService.build/check_all/suspend/resume`, sinal `piece_released`.
P3: `AbilityController.select(i)/use_pressed()/use_released()`, sinais `element_changed` e `ability_used`;
`MaterialResponseSystem.apply(ElementalEvent)`, `state_of(corpo)`, sinais `ignited`, `extinguished`, `burned_out`,
`kinetic_break`; `StructureService.break_piece(peça, impulso, motivo)` e `consume_piece(peça, motivo)`.
P3.5: `Ability.fx_event(kind, data)` (ganchos de FX/áudio); `EarthLiftThrow.phase`, `is_ready()`, `ready_progress()`,
`validate_target()`; `TerrainService.can_extract_rock(p, normal, raio)`, `cavity_confirmed(p)` e
`extract_rock(..., hold_kinematic)`; `ThirdPersonCamera.add_trauma(x)`.

## P3.6 — polimento incremental
M0–M4 concluídos (relatório final em docs/p36_elemental_polish.md); baseline corrigido em docs/p36_baseline_corrected.md, arquitetura em docs/p36_m0.md, Água em docs/p36_water_polish.md, Fogo em docs/p36_fire_polish.md e Ar em docs/p36_air_polish.md (parâmetros em data/abilities/*_tuning.tres; testes por marco: `tools/run_p36_tests.ps1 -Stage m2|m3 -Window`). Capturas e automação não são playtest humano.

P3.6.1: save preserva o mundo físico e o T26 confirma repouso natural antes da medição.
30/30 repetições prospectivas (pico 0 m), bateria 64/64 nos quatro modos, zero erros/avisos
e limites de desempenho preservados. Diagnóstico, falhas exploratórias mantidas e comandos
em [`docs/p36_t26_stabilization.md`](docs/p36_t26_stabilization.md).
