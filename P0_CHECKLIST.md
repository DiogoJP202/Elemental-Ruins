# Gate P0 — Critérios de aceite do protótipo

**Preencha estas linhas com PASSOU / FALHOU / NÃO TESTADO. Nenhum item é considerado concluído apenas por ter código criado.** Registro de testes e logs em `docs/voxel_spike_results.md`.

| Status | Critério | Como provar |
|---|---|---|
| NÃO TESTADO | Godot e Voxel Tools inicializam sem erro fatal | Versões e logs de editor/importação |
| NÃO TESTADO | Cena 3D nativa abre no Godot | Cena e screenshot local ou descrição clara de teste manual |
| NÃO TESTADO | WASD, pulo e câmera de terceira pessoa funcionam | Teste interativo |
| NÃO TESTADO | Terreno volumétrico gera colina com colisão sólida | Personagem fica sobre ela sem atravessar |
| NÃO TESTADO | Escavar remove matéria/colisão na mesma região após atualização | Cair/entrar na cratera e observar ausência do collider antigo |
| NÃO TESTADO | Túnel horizontal pode ser aberto **abaixo de teto sólido** | Caminhar de uma entrada a outra com solo acima da cabeça |
| NÃO TESTADO | Adicionar matéria forma coluna/rampa sólida | Construir e caminhar ou pousar um objeto sobre a forma nova |
| NÃO TESTADO | Múltiplas alterações no mesmo lugar não destroem a cena | Repetir escavação/adição 20 vezes |
| NÃO TESTADO | Reset restaura geometria E colisões originais | Reset após alterar e testar entrada/teto/chão restaurados |
| NÃO TESTADO | Não há erros fatais de importação/parser | Godot headless/GUI e relatório de erros |
| NÃO TESTADO | Dependências e execução estão documentadas | README.md do jogo e relatório técnico |

## Testes adicionais (recomendados; não bloqueiam a primeira tela jogável)
- 100 escavações em sequência com registro de pico de latência de reconstrução.
- 10 resets com comparação de estado inicial e número de nós.
- Export Windows com templates compatíveis, se disponíveis.
- Testar regiões não carregadas: editar deve falhar de modo seguro, não congelar.

## Modelo de evidência para docs/voxel_spike_results.md
- Data / OS / GPU / CPU/RAM (se a máquina fornecer sem extrapolar):
- Binário Godot exato / versão Voxel Tools / variante module ou GDExtension:
- Comandos executados / logs relevantes / links internos a screenshots, se houver:
- Testes manuais (quem, quando, resultado) e limites:
- Medições reais (FPS, tempos e memória) ou “não medido”:
- Bug encontrado / reprodução / correção tentada / status:
- Gate geral P0: PASSOU / FALHOU / NÃO TESTADO:
