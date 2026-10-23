class_name TerrainSaveFiles
extends RefCounted
## Caminhos e operações de arquivo da persistência do terreno. Não conhece o Voxel Tools.
##
## Sessão: arquivo SQLite que o terreno VIVO usa como stream. Nome único por processo e por
## instância de terreno, para que um save assíncrono atrasado de um terreno liberado nunca
## caia no arquivo do terreno novo. Slot: cópia fechada de uma sessão, feita ao salvar.

const SESSION_PREFIX := "session_"
const EXT := ".sqlite"


static func session_path(world_dir: String, index: int) -> String:
	return ProjectSettings.globalize_path(world_dir).path_join(
		"%s%d_%d%s" % [SESSION_PREFIX, OS.get_process_id(), index, EXT])


static func slot_path(saves_dir: String, slot: String) -> String:
	return ProjectSettings.globalize_path(saves_dir).path_join(slot + EXT)


## Nome de slot seguro para arquivo: letras, dígitos, '_' e '-'.
static func is_valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 40:
		return false
	for ch in slot:
		if not (ch.is_valid_identifier() or ch == "-" or (ch >= "0" and ch <= "9")):
			return false
	return true


static func ensure_dir(dir: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


## Copia `src` sobre `dst` (sobrescreve). Os dois arquivos precisam estar fechados pelo stream.
static func copy(src: String, dst: String) -> Error:
	if exists(dst):
		var err := DirAccess.remove_absolute(dst)
		if err != OK:
			return err
	return DirAccess.copy_absolute(src, dst)


## Apaga o arquivo. No Windows falha enquanto um stream o mantém aberto.
static func remove(path: String) -> Error:
	if not exists(path):
		return OK
	return DirAccess.remove_absolute(path)


static func list_sessions(world_dir: String) -> PackedStringArray:
	var dir := ProjectSettings.globalize_path(world_dir)
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for name in DirAccess.get_files_at(dir):
		if name.begins_with(SESSION_PREFIX) and name.ends_with(EXT):
			out.append(dir.path_join(name))
	return out
