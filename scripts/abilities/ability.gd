class_name Ability
extends RefCounted
## Interface comum dos poderes (P3). O AbilityController chama on_press / on_hold / on_release
## conforme o LMB e physics_tick em todo quadro de física (efeitos que continuam depois de soltar,
## como projétil e rocha em voo). Um poder age no mundo só por:
##   - TerrainService (matéria do terreno),
##   - forças/impulsos em corpos (nunca position por quadro),
##   - ElementalEvent no MaterialResponseSystem (estado dos materiais),
## e só depois pede VFX.

var id: StringName
var element: StringName
var display_name := ""
## "hold" (segurar) ou "tap" (toque).
var input_mode := "tap"
var controller  # AbilityController (sem tipo para evitar referência circular de class_name)
var last_result := ""


func setup(p_controller) -> void:
	controller = p_controller


func on_press() -> void:
	pass


func on_hold(_delta: float) -> void:
	pass


func on_release() -> void:
	pass


func physics_tick(_delta: float) -> void:
	pass


## Interrompe a ação em curso do botão (troca de elemento, reset, salvar/carregar).
func cancel() -> void:
	pass


## Descarta também o que já está em voo (reset, salvar/carregar): projéteis, rochas lançadas.
func clear() -> void:
	pass


## Linha curta para o HUD.
func status() -> String:
	return last_result


func emit_event(event: ElementalEvent) -> Array[Node3D]:
	return controller.materials.apply(event)
