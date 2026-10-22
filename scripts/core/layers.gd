class_name Layers
extends RefCounted
## Bits de camada de colisão usados no protótipo. Valores são máscaras (1 << n).

const TERRAIN := 1      # camada 1: colliders gerados pelo VoxelLodTerrain
const PLAYER := 2       # camada 2: CharacterBody3D do jogador
const PROPS := 4        # camada 3: RigidBody3D de teste (caixas)
