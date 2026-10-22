# ELEMENTAL // RUINS — Comece aqui (pacote de handoff para Claude Code)

**Este pacote NÃO contém jogo implementado.** Contém os requisitos, estudos, referências, critérios de validação e instruções que permitirão ao Claude Code construir o primeiro protótipo técnico.

## Objetivo
Criar um sandbox 3D em terceira pessoa em **Godot** onde o jogador possa manipular quatro elementos, escavar terreno volumétrico e destruir estruturas. A primeira entrega é mais estreita: provar tecnicamente **escavação e adição de terreno com colisão real**, incluindo um túnel transitável sob o solo.

## 1. Pré-requisitos
- Windows 10/11 64 bits, Git, Claude Code autenticado e **Godot 4.7.2 (preferida)**.
- Internet para obter **Voxel Tools 1.7** (não incluído neste ZIP) pelos releases oficiais.
- Se o `godot` não estiver no PATH, informe ao Claude onde está o executável. Para o módulo integrado, use o binário próprio da release Voxel Tools; para GDExtension, copie o conteúdo da release para a raiz do projeto conforme README do plugin.
- Documentação/release oficial: https://github.com/Zylann/godot_voxel/releases
- Instalação: https://voxel-tools.readthedocs.io/en/latest/getting_the_module/
- Documentação Godot: https://docs.godotengine.org/en/stable/
- Claude Code: https://code.claude.com/docs/en/overview

## 2. Instalação da pasta (Windows)
1. Crie uma pasta vazia, por exemplo `C:\Projetos\elemental-ruins`.
2. Extraia **todo o conteúdo do ZIP diretamente nessa pasta**, mantendo `CLAUDE.md`, `PROMPT_INICIAL_CLAUDE_CODE.txt` e o GDD lado a lado na **raiz**.
3. Abra a pasta no VS Code ou Terminal do Windows.
4. No PowerShell: `git init` (opcional mas recomendado); então `claude` para entrar no Claude Code (se CLI instalado).
5. Cole **todo** o texto de `PROMPT_INICIAL_CLAUDE_CODE.txt` na conversa com Claude. Não precisa copiar e colar todos os documentos individualmente: eles estão na pasta para o Claude lê-los.
6. Alternativa: no Claude Desktop > Code, selecione uma sessão **Local** e a mesma pasta, envie o conteúdo do prompt; confirme que o app tem acesso local aos arquivos.

## 3. Estrutura do pacote
- `CLAUDE.md` — instruções permanentes e regras de não-negociáveis; leitura automática esperada pelo Claude Code quando o arquivo está na raiz.
- `PROMPT_INICIAL_CLAUDE_CODE.txt` — única mensagem inicial a enviar.
- `P0_CHECKLIST.md` — testes que definem o mínimo funcional.
- `pesquisa_tecnica_elemental_ruins_godot_2026.md` — pesquisa de tecnologias, trade-offs e APIs candidatas (revalidar com documentação instalada).
- `elemental_ruins_gdd_v02.md` — GDD vigente; estética, mecânicas, futuro roadmap.
- `MATRIZ_REACOES_ELEMENTAIS.md` — reações físicas planejadas para fases posteriores.
- `avatar_atlas_poderes_sandbox.md` + `.json` — 214 referências de Avatar, 32 feitos e 22 combinações catalogadas, com ressalvas de cânone.
- `elemental_abilities_mvp.json` — 16 técnicas planejadas, não implementadas.
- `prompt_claude_spike_voxel_godot.md` — prompt técnico detalhado de apoio ao Claude.
- `PROJETO_ROADMAP.md` — fases e dependências.
- `.gitignore` — itens transitórios de Godot/Claude/Windows para não versionar.

## 4. Qual é a primeira entrega aceitável?
Um projeto Godot abre; você movimenta o personagem em terceira pessoa e consegue **remover solo, abrir túnel sob um teto, passar dentro dele, acrescentar solo e restaurar o terreno**. O próprio Claude deve demonstrar com logs/execução o que foi comprovado; onde a GUI não puder rodar, ele deve entregar checklist manual e declarar **NÃO TESTADO**.

## 5. Por que não começamos com os poderes?
O ponto mais arriscado é atualizar a geometria volumétrica **e colisões** em tempo real. Se isso falhar, todos os poderes que mudam solo ficarão comprometidos. O protótipo P0 reduz esse risco antes de gastar tempo com VFX, menus e sistemas de água/fogo/ar.

## 6. Atualizações e divergências
Este pacote substitui os pacotes anteriores que ainda sugeriam iniciar por arte ou habilidades. Na dúvida vale `CLAUDE.md`, seguido de `P0_CHECKLIST.md` e GDD v0.2. Para entregar fases novas, abra outra sessão de Claude e peça para ler `CLAUDE.md` e `PROJETO_ROADMAP.md`, junto dos relatórios realmente produzidos.
