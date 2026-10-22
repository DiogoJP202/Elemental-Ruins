# ELEMENTAL // RUINS — Matriz de reações e prioridades

**Legenda:** `P1` núcleo após terreno; `P2` destruição; `P3` quatro elementos; `P4` expansões. Esta matriz é **game design** original. Não atribua estas reações literalmente ao cânone de Avatar sem consultar o atlas.

| Origem | Alvo | Evento físico/estado | Resultado observável | Fase |
|---|---|---|---|---|
| Terra (escavar) | Solo SDF | `subtract_mass` | Cratera e túnel real | P1 |
| Terra (erguer) | Solo SDF | `add_mass` | Pilar com colisão real | P1 |
| Terra (extrair) | Rocha SDF | `mass_transfer` | Pequena cavidade + rocha física | P2 |
| Terra (pressão) | Parede modular | `kinetic/support_damage` | Rachadura e queda parcial | P2 |
| Terra (escavar) | Torre ancorada | `support_lost` | Colapso progressivo | P2 |
| Pedra lançada | Gelo | `brittle_fracture` | Estilhaços + perda de volume | P3 |
| Água (jato) | Madeira | `wet+kinetic` | Madeira úmida, arrasto | P3 |
| Água (jato) | Incêndio | `cool+wet` | Apaga conforme energia e tempo | P3 |
| Água | Solo | `wet+friction_change` | Lama e escorregamento | P4 |
| Água | Caverna escavada | `fill_region` | Enchimento simples de cavidade | P4 |
| Frio | Água/poça | `freeze` | Gelo com colisão | P4 |
| Calor | Gelo | `melt` | Recupera água em volume estimado | P4 |
| Fogo | Madeira | `heat+ignite` | Queima, carboniza, perde suporte | P3 |
| Fogo | Rocha | `heat` | Escurece/aumenta temperatura, NÃO vira lava automaticamente | P3 |
| Ar (rajada) | Caixa/fragmentos | `airflow+kinetic` | Impulso proporcional ao contexto | P3 |
| Ar (vórtice) | Fragmentos | `swirl+lift` | Sobe e gira objetos leves | P4 |
| Ar | Fogo | `airflow+oxygen_game_rule` | Desvia chama/espalha ou apaga conforme intensidade | P3 |
| Ar | Água | `airflow+displacement` | Muda direção do spray/jato | P4 |
| Lava | Água | `thermal_quench` | Vapor + solidificação de material | P4 |
| Relâmpago | Água | `electrical_region` | Descarga simplificada em áreas molhadas | P4 |
| Ar (vácuo) | Chama | `oxygen_suppression` | Fogo perde força no campo | P4 |
| Água | Areia/solo | `erosion_threshold` | Remoção limitada do SDF com força elevada | P4 |

**Contrato de teste comum**: a fonte altera o estado do mundo *antes* da emissão de VFX. Uma partícula que toca a parede não significa que uma colisão física ocorreu. Eventos únicos, com `source_id`, `timestamp_tick`, `world_position`, `radius`, `material_tags`, `strength`, `duration`, dão origem às transições e aos VFX.
