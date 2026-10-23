# Resultados do P2 — sustentação, destroços e extração de rochas

**Data:** 23/10/2026 · **Execução:** Claude Code (sessão automatizada nesta máquina).
Mesma máquina e mesmo binário do P0/P1: Windows 11 Pro 10.0.26200, i5-1135G7, 15,7 GB, Intel Iris Xe (Vulkan 1.4.323),
`godot.windows.editor.x86_64.exe` **4.7.2.stable.custom_build.ed1daf0bf** com **Voxel Tools 1.7 como módulo**.
Todos os números vêm de execuções reais; logs e JSON em `docs/evidence/p2/`, capturas em `docs/evidence/p2/screens/`
(só as 8 dos testes do P2; as 16 das cenas P0/P1 que a rodada em janela também gera não foram versionadas, para não
duplicar as de `docs/evidence/p1/screens/`).

**Rodada de referência:** `tools/run_p2_tests.ps1 -Window -Export` no commit `752b78b`, 18:22–18:35, começando com
`.godot/` apagado. **14 de 14 passos com exit 0.** Depois dela só mudou a legenda do overlay (`d0dfc36`, §7).

**Pendente desde o P0:** o roteiro manual por uma pessoa (agora P0, P1 e P2) no editor custom. O usuário pediu para
seguir sem ele; continua NÃO TESTADO.

## 1. Gate do P2 (`PROJETO_ROADMAP.md`)

| Status | Critério | Prova |
|---|---|---|
| PASSOU | **Escavar o apoio de uma estrutura produz colapso coerente** | T20: escavar sob 1 pilar solta exatamente os 3 blocos desse pilar; a laje fica (as 2 placas vizinhas a sustentam). T21: escavar sob os outros 3 derruba as 36 peças em 6–7 quadros, no máximo 6 por quadro, de baixo para cima; nenhuma abaixo do terreno, nenhuma a mais de 15 m. T25: metade da torre (17 peças) cai do mesmo jeito em 10 ciclos. Nos 4 modos |
| PASSOU | **… sem destruir o FPS na cena-teste** | T27 em janela, os 4 pés escavados no mesmo quadro: intervalo entre quadros **p95 18,9 / p99 19,4 / máx. 20,1 ms** (editor) e **18,6 / 19,0 / 19,2 ms** (`.exe`), dentro do critério da D27 (p95 ≤ 20, p99 ≤ 33, máx. ≤ 50 ms) |

**Gate P2: PASSOU** nesta cena de laboratório, com as limitações da §8.

## 2. Escopo do P2

| Status | Item | Onde / prova |
|---|---|---|
| Implementado e testado | Torre modular apoiada no terreno, que perde sustentação | `scripts/structures/`; T19–T21, T25 |
| Implementado e testado | Grafo de apoio entre peças e terreno | `SupportGraph`; T19 (estrutura do grafo), T20 (regra lateral) |
| Implementado e testado | Âncoras pelos dados SDF + espera do collider | `StructureService`; T20/T21 com 0 timeouts de confirmação |
| Implementado e testado | Corpos acordam quando o chão some | `TerrainContactWaker`; T18 (spike I3 provou que sem ele a caixa flutua) |
| Implementado e testado | Limite de fragmentos/corpos ativos | `DebrisBudget`; T22 |
| Implementado, teste indireto | Culling por distância (estacionar > 80 m, `visibility_range_end`) | Código e contadores no overlay; nenhum teste afasta o jogador 80 m de destroços ativos |
| Implementado e testado | Colisões convexas | Peças `BoxShape3D`; rochas `ConvexPolygonShape3D` (T23) |
| Implementado e testado | `separate_floating_chunks` em caixa pequena, medido | Spike P2 (F1–F3, I2: 0,4–1,9 ms até 30³); extração T23 |
| Implementado e testado | Rocha extraída que pode ser arremessada | T23 (corpo real com massa do material), T24 (impulso de teste) |
| Implementado, só contador | Poeira decorativa | `DustFx`; o T27 conta os disparos, mas não conferi as partículas visualmente (as capturas são tiradas segundos depois da queda) |
| Implementado e testado | Reset, salvar e carregar com estruturas | T25, T26 |
| Não implementado | Fratura em tempo de execução, dano por impacto, juntas, re-ancoragem, persistência de destroços | Fora do escopo (D21, D26) |

## 3. Comandos executados (rodada de referência)

| # | Passo | Log / relatório | Resultado |
|---|---|---|---|
| 1 | `--import` (cache vazio) | `01_import.log` | exit 0, 1ª tentativa |
| 2–3 | `check_env`, dump da API | `02_…`, `03_…` | exit 0 |
| 4 | spike P2 | `04_spike_p2_api.log`, `00_spike_p2.txt` | exit 0, F1–F3 OK |
| 5 | selftest P0 sozinho | `05_…`, `p0_regressao_headless.json` | **12/12**, 0 erros/avisos |
| 6 | selftest P2 (editor, headless) | `06_…`, `p2_selftest_headless.json` | **33/33**, 0/0, 155 s |
| 7–8 | persistência entre processos (editor) | `07_…`, `08_…` | 2/2 e 2/2 |
| 9 | selftest P2 (editor, janela, capturas) | `09_…`, `p2_selftest_window.json`, `screens/` | **33/33**, 0/0, 189 s |
| 10 | export release | `10_…` | exit 0 |
| 11 | selftest P2 no `.exe` (headless) | `11_…`, `p2_selftest_export_headless.json` | **33/33**, 0/0 |
| 12–13 | persistência entre processos no `.exe` | `12_…`, `13_…` | 2/2 e 2/2 |
| 14 | selftest P2 no `.exe` (janela) | `14_…`, `p2_selftest_export_window.json` | **33/33**, 0/0 |

33 testes = 12 do P0 + 11 do P1 (T8–T17, com T8b) + 10 do P2 (T18–T27).

## 4. Testes do P2 (editor headless; os 4 modos deram o mesmo resultado)

| ID | Observado |
|---|---|
| T18 | caixa dormindo; escavação embaixo; começa a cair 270 ms depois do pedido e repousa no fundo (y 0,52 → −1,85); o despertador acordou 1 corpo |
| T19 | 36 peças congeladas e paradas 5 s; 4 pés, 8 placas com 1 apoio embaixo e 2 laterais, 4 blocos de coroa sobre 2 placas; todas apoiadas |
| T20 | soltas = exatamente os 3 blocos do pilar escavado; demais peças no lugar; 0 timeouts de confirmação do collider |
| T21 | 33 peças restantes soltas em 7 quadros (máx. 6 por quadro); 0 abaixo do chão; 0 a mais de 15 m |
| T22 | 150 caixas + 36 peças = 186 corpos → **64 ativos** e 122 estacionados, todos já parados (maior velocidade ao estacionar 0,005 m/s headless, 0,05 no `.exe` em janela); **pico de 150–154 ativos** enquanto as caixas caíam juntas (o teto não congela corpos em movimento) |
| T23 | rocha de solo extraída: 1 corpo convexo na camada PROPS, **9,78 m³ de malha** (a esfera nominal de r = 1,5 tem 14,1), **14 670 kg** = volume × 1500; pousada a 5,7 m do buraco (fundo da malha 0,019, chão 0,020) |
| T24 | impulso de teste a 45°: a rocha sobe 2,4 m, voa 9,3 m e repousa no terreno |
| T25 | 10 ciclos (17 peças caem por ciclo) → reset: 36 peças de volta ao lugar e congeladas, 0 destroços, nós = baseline (150) |
| T26 | A) salvar com a torre caída: 0,0 m durante o save; maior ajuste depois de descongelar 0,7 cm (headless) a 1,1 cm (janela). B) reset → carregar o slot escavado → as 36 caem de novo em 86–100 ms. C) carregar um slot sem escavação perto → 0 peças soltas |
| T27 | §5 |

## 5. Medições

| Medida | Editor headless | Editor janela | `.exe` headless | `.exe` janela |
|---|---|---|---|---|
| T27 intervalo entre quadros no colapso total (p50 / p95 / p99 / máx., ms) | sem render | **16,5 / 18,9 / 19,4 / 20,1** | sem render | **16,7 / 18,6 / 19,0 / 19,2** |
| T27 TIME_PHYSICS_PROCESS (méd. / p95 / máx., ms) | 2,5 / 4,3 / 13,3 | 1,7 / 2,2 / 10,8 | 2,6 / 4,3 / 9,1 | 1,3 / 1,9 / 10,5 |
| T27 peças dinâmicas no pico | 36 | 36 | 36 | 36 |
| T25 reset com a torre (méd. / máx., ms) | 255 / 273 | 430 / 445 | 247 / 274 | 422 / 430 |
| T26 B: carregar → 36 peças soltas (ms) | 86 | 100 | 96 | 100 |
| T18 escavação → caixa começa a cair (ms) | 270 | 280 | 276 | 284 |
| FPS no roteiro inteiro (méd. / p95) | — | 58,7 / 61 | — | 59,6 / 60 |
| P1 T15 (100 edições) intervalo entre quadros p95 / máx. (ms), com a torre na cena | — | 19,1 / 20,6 | — | 18,3 / 20,9 |

`separate_floating_chunks` (spike): 0,37 / 0,52 / 0,96 ms com caixas de 8³ / 16³ / 30³ contendo um pedaço; 0,01–0,5 ms
sem pedaço. Extração completa no jogo (T23): 1,8 ms (headless) a 11,4 ms (`.exe` em janela).

Poeira (T27, contadores acumulados do roteiro): 136 disparos e 178 descartados pelo teto de 2 por quadro (a torre
solta até 6 peças por quadro). Não medi o custo de GPU das partículas separadamente.

Leitura honesta: a cena tem 1 torre de 36 peças e até ~190 corpos no T22. O critério de FPS foi cumprido **nesta**
cena, com vsync, nesta máquina; não garante cenas com várias torres ou com centenas de corpos em movimento.

## 6. Spike P2 (`tools/spike_p2_api.gd`, `docs/evidence/p2/00_spike_p2.txt`)

| ID | Resultado |
|---|---|
| F1 | matéria flutuante (ADD no ar) → 1 `RigidBody3D` e a matéria sai do terreno (SDF −1,5 → +100) |
| I1 | o corpo vem com **camada e máscara 1** (as do terreno), **massa 1 kg**, `ConvexPolygonShape3D`, malha **sem material** e um `Timer` que troca `freeze` cinemático por rígido em < 0,5 s |
| F2 | depois de sair da camada do terreno, cai e repousa (fundo da malha 3,5 → 0,0; chão 0,02) |
| I2 | custo 0,4–1,9 ms até 30³ |
| F3 | núcleo recriado numa cavidade do chão vira 1 corpo e responde a impulso |
| I3 | **caixa dormindo não acorda quando o chão embaixo é escavado (fica flutuando)**; acordada, cai |

## 7. Bugs e achados durante o P2

- **Âncoras a 0,5 m invalidavam todos os pés (corrigido).** `sample_sdf` arredonda para o voxel mais próximo; y = −0,45
  cai no voxel y = 0, a superfície (SDF 0). Escavar sob 1 pé derrubou a torre inteira, com 3 timeouts de confirmação
  (os pés intactos nunca mostraram buraco). Pontos a 1 m. Achado no T20.
- **Corpos criados por `separate_floating_chunks` na camada do terreno (contornado).** Raycasts "de terreno" batiam na
  rocha (o primeiro F2 do spike reprovou por isso). O serviço passa o corpo para PROPS logo após criar.
- **Rocha presa na cavidade (contornado).** A boca da cavidade esférica é mais estreita que a cavidade; o impulso
  levantava a rocha só 4–58 cm (T24 reprovou duas vezes). A rocha agora é posicionada, ainda cinemática, ao lado do buraco.
- **Peças podiam cair ao descongelar depois do save (corrigido).** `save_world` espera o terreno só em volta do ponto de
  prontidão; o descongelamento agora espera collider de terreno sob cada corpo. Na investigação, o deslocamento medido
  (1,9–2,3 m) era quase todo de peças ainda deslizando 4 s após o colapso (controle sem save: 3,5 m em 2 s); o T26 passou
  a esperar a cena parar.
- **Legenda de controles fora da tela desde o P0 (corrigido depois da bateria).** `position` depois de ancorar embaixo a
  punha acima da borda de cima. Agora fica presa embaixo por offsets. Conferido numa captura em janela e com T7/T17/T19
  em headless; a bateria completa não foi repetida depois disso. As capturas em `docs/evidence/p2/screens/` mostram a
  legenda antiga cortada no topo.
- **Erro de digitação que travou uma rodada isolada:** um `sed` inseriu `\n` literal no selftest; a checagem acusou o
  erro de parse, mas o comando seguinte rodou e ficou 400 s aberto até o `timeout`. É o caso que o timeout por passo dos
  runners passou a cobrir.

## 8. Limitações e riscos

- **Uma torre, 36 peças, sem fratura:** as peças caem inteiras. Sem dano por impacto (uma peça presa atingida por
  destroços não se solta), sem juntas, sem re-ancoragem.
- **Regra de apoio simplificada:** 1 apoio embaixo, ou 2 laterais. Não considera centro de massa nem balanço; um bloco de
  coroa pode ficar meio no ar sobre uma placa.
- **Âncoras só nos pés do térreo:** escavar ao lado, sem tirar o chão sob os pés, não afeta a torre.
- **Teto de corpos só vale para corpos parados:** durante uma queda simultânea o número de ativos passa do teto (T22).
- **Corpos estacionados são estáticos:** o jogador não os empurra; voltam a ser dinâmicos só por escavação embaixo
  (despertador), por proximidade (os estacionados por distância) ou pelo impulso de teste.
- **Culling por distância não foi exercitado em teste** (nenhum teste afasta o jogador 80 m de destroços ativos).
- **Persistência:** o estado da torre é derivado do terreno salvo; posições de destroços, rochas e caixas não são salvas.
- **Extração:** casco convexo do Transvoxel com 1 voxel por metro sai grosseiro (9,8 m³ contra 14,1 m³ da esfera
  nominal). A rocha "salta" para o lado do buraco (posicionamento único, D25), não sai empurrada fisicamente.
- **R e T são ferramentas de laboratório**, não as habilidades de terra do P3.
- Poeira: só visual, sem custo de GPU medido; até 2 disparos por quadro.
- B1 (crash raro no fim do `--import`) continua aceito; nesta rodada não ocorreu.

## 9. Não testado

- **Teste manual por pessoa** (P0, P1 e P2) no editor custom: roteiros no README.
- Culling por distância dos destroços (estacionar a 80 m e voltar a 64 m).
- Várias estruturas ao mesmo tempo; centenas de corpos em movimento contínuo; custo de GPU da poeira.
- Abrir o projeto no editor com interface depois do P2 (só editor headless e o jogo rodando).

## 10. Próximo passo recomendado

Rodar os roteiros manuais do README (P0, P1 e P2) no editor custom, com teclado e mouse reais, antes de iniciar o P3.
