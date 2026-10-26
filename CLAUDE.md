# ELEMENTAL // RUINS — instruções permanentes para Claude Code

> Leia este arquivo no início de toda sessão. Este repositório será um **jogo Godot 4**, não uma aplicação web. Idioma das explicações: português brasileiro; nomes de classes, nós, funções e arquivos em inglês quando fizer sentido.

## Estado vigente: continuação do P3.6 (26/10/2026)
- P0: terreno volumétrico; P1: fila, materiais e persistência; P2: sustentação e extração; P3: quatro elementos; P3.5: Terra em fases. Implementados, com relatórios em docs/. Não reiniciar essas fases.
- Trabalho autorizado: preparação do P3.6 → baseline corrigido → M0 investigação → M1 Água → M2 Fogo → M3 Ar → M4 integração. Commits incrementais; sem push ou merge na main.
- Worktree exclusiva: `C:/Users/dsoares/Documents/Projetos/game/.claude/worktrees/charming-mendel-4b469a`, branch `claude/charming-mendel-4b469a`. HEAD inicial: `08b6c6e`. Conferir Git e preservar alterações locais antes de editar.
- Stack vigente: Godot 4.7.2 custom + Voxel Tools 1.7 como módulo (D13). Editor e template release compatíveis. Não reintroduzir a GDExtension.
- Referências atuais: README.md, docs/decisions.md, docs/p35_earth_polish.md, docs/p36_baseline.md, docs/p36_progress.md e PROJETO_ROADMAP.md. O prompt inicial e o escopo da primeira entrega abaixo são históricos.
- Gates: zero erros e zero avisos. Nenhuma exceção ativa. Allowlist futura só com identificação exata, justificativa e documentação. Sem relaxar critérios para obter PASS.
- Em janela: intervalo entre quadros p95 ≤ 20 ms, p99 ≤ 33 ms, máximo ≤ 50 ms nos cenários T27/T37. Registrar hardware, resolução, renderer, cenário e metodologia. Headless não comprova renderização.
- Água, Fogo e Ar: Resources independentes editáveis pelo inspetor, seguindo EarthTuning. Separar comandos, simulação, materiais e VFX. Não criar habilidades novas.
- PvP nesta fase: timings configuráveis, eventos identificáveis, cancelamentos e telegraphs. Sem rede, rollback, servidores ou dano em jogadores; sem pausa/tempo global para impacto.
- Capturas e automação não são playtest humano. Controles, legibilidade e game feel: NÃO TESTADO até avaliação humana real.
- Raycasts: registrar tentativas, acertos e falhas por cenário, superfícies finas e corpos adjacentes. Amostra sem falhas não prova correção universal.
- Testes direcionados por marco, baseline após estabilização e bateria integral em M4. Evidências novas em docs/evidence/p36/, preservando as históricas.

## Visão do produto
Sandbox **3D em terceira pessoa**, focado em controle expressivo de terra, água, fogo e ar, destruição física e modificações persistentes do ambiente. Estética original inspirada no cel-shading/cores e contornos de *Sable* e no low-poly/texturas retro de *Mouthwashing*. **Nunca copiar assets, personagens, marcas, símbolos ou código proprietário dessas obras, nem de Avatar.** O atlas de Avatar é referência mecânica, não material para reprodução de propriedade intelectual.

## Requisito não negociável
**O terreno deve ser volumétrico e livremente modificável.** O usuário deve conseguir escavar uma cratera, abrir um túnel real sob uma colina (com teto e chão sólidos), atravessá-lo e acrescentar solo formando colunas ou rampas. Uma heightmap, decal, shader, buraco falso ou voxels apenas decorativos não atendem ao requisito.

## Stack e dependências
- **Godot 4.7.2 estável (Windows)**, GDScript para gameplay e sistemas de protótipo.
- **Jolt Physics integrado** da Godot; não instalar o addon legado Godot Jolt sem motivo comprovado.
- Candidato prioritário: **Voxel Tools 1.7** com **SDF + Transvoxel**, edição runtime e colisões atualizáveis. Testar primeiro **GDExtension** na Godot oficial; se inviável, investigar **custom build da Godot 4.7.2 com Voxel Tools 1.7**, documentando troca e implicações para exportação. **Não confiar que classes/APIs existam sem verificar versão de verdade.**
- Se a versão exata não estiver disponível no ambiente, registrar bloqueio e perguntar/explicar; **não trocar de engine ou reduzir terreno a heightmap**.
- Renderização inicial simples; pós-processamento, shaders e água volumétrica **não** devem bloquear P0.

## Precedência e ordem de leitura
1. `CLAUDE.md` (este arquivo).
2. `PROMPT_INICIAL_CLAUDE_CODE.txt` (escopo da primeira execução).
3. `pesquisa_tecnica_elemental_ruins_godot_2026.md` (riscos, APIs candidatas, links e alternativas).
4. `elemental_ruins_gdd_v02.md` (GDD atualizado e referência de longo prazo).
5. `P0_CHECKLIST.md` (contrato de aceitação do protótipo).
6. `MATRIZ_REACOES_ELEMENTAIS.md` e `elemental_abilities_mvp.json` (design FUTURO).
7. `avatar_atlas_poderes_sandbox.md` / `.json` (consulta FUTURA, **não** implementar agora).
8. `prompt_claude_spike_voxel_godot.md` (aprofundamento técnico e diagnóstico para P0/P1/P2; prevalece o escopo limitado do prompt inicial para o primeiro ciclo).

Em caso de conflito: **requisito explícito do usuário > CLAUDE.md > P0_CHECKLIST.md > GDD v0.2 > pesquisa > documentos históricos**. Nunca trabalhar baseado no GDD antigo `elemental_ruins_gdd.md` nem no prompt antigo `prompt_claude_elemental_ruins.md`, que não estão neste pacote.

## Histórico: escopo da primeira entrega (P0 concluído)
1. Inspecionar máquina/projeto, versões da Godot, Git, ferramentas e dependências sem instalar silenciosamente nada importante.
2. Criar projeto nativo `.godot` e uma cena de laboratório técnico com personagem `CharacterBody3D`, câmera de terceira pessoa e WASD/Space/mouse.
3. Integrar terreno SDF volumétrico com geração de malha e colisão.
4. Remover e adicionar matéria por mira e raio. Demonstrar **túnel sob teto sólido** sem atravessar colisão antiga.
5. Separar adaptação ao plugin em `TerrainService` e controles dos comandos de edição, evitando APIs fictícias.
6. Criar reset funcional de alterações no mundo ou documentar como bloqueio explícito se impossível no primeiro ciclo.
7. Validar empiricamente importação, abertura da cena, colisor e comportamento; reportar o que não foi possível executar sem fingir que testou.
8. Preencher `docs/voxel_spike_results.md` com versões, logs e observações reais.

**Não avance para P1, P2 ou poderes sem que P0 passe nos gates ou o usuário autorize uma mudança de escopo.** Para tarefas bloqueadas, ofereça diagnóstico com próximos comandos verificáveis em vez de criar uma maquete enganosa.

## Padrões de implementação
- Árvore de cenas mínima: `Main`, `Player`, `World`, `HUD`/`DebugOverlay`; nomes exatos podem evoluir se documentados.
- Distinguir dados/edições voxel de objetos móveis. Manter operações em coordenadas do mundo na API pública e adaptar coordenadas locais internamente.
- Fazer controle por físicas, `RayCast3D`, input map e ações explícitas; evitar ler input em dezenas de nós aleatórios.
- Atualizações de SDF e colisores podem ser assíncronas. Não presumir que render e colisão se atualizam no mesmo frame. Evitar edição de volumes gigantes a cada `_process`.
- `RigidBody3D` deve ser movido por forças/impulsos quando cabível; não teleportar por `position` em cada frame.
- Evitar grandes loops por voxel em GDScript no runtime; usar operações eficientes disponibilizadas pelo plugin, batches e limites configuráveis.
- Versionar código em Git. Não sobrescrever conteúdo já existente sem inspecionar; pedir autorização em ações destrutivas de arquivos do usuário.
- Registre decisões e trade-offs em `docs/decisions.md`; instruções de execução em `README.md` (gerado pelo projeto), não substitua o arquivo `INICIO_AQUI.md` do pacote.
- Separar claramente: implementado+testado / implementado+não testado / não implementado / bloqueado.
- Não inventar links, resultados de benchmark, logs, imagens ou evidência de execução.

## Controles temporários do teste P0
- WASD andar, mouse orbitar, Space pular, Shift correr.
- `G`: escavar, `H`: acrescentar matéria, `Z`: reset.
- Marcador de mira e raio configurável; `J` para perfurar caminho/túnel é opcional até o controle básico funcionar.
- Esses atalhos são provisórios, diferentes do futuro sistema de 4 elementos do GDD. Não implementar seleção 1–4 antes de P3.

## Aceite e relatório ao fim da sessão
Responder com: arquivos criados/alterados, instruções para abrir na Godot, versões reais, checkboxes de `P0_CHECKLIST.md` com PASSOU/FALHOU/NÃO TESTADO, provas/logs, riscos e **um único próximo passo recomendado**. Não dizer 'terminado' só porque criou `project.godot` ou scripts.
