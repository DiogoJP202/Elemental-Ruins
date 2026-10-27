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
	var absolute := ProjectSettings.globalize_path(dir)
	if FileAccess.file_exists(absolute):
		return ERR_ALREADY_EXISTS
	return DirAccess.make_dir_recursive_absolute(absolute)


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


## Publica uma cópia completa com rollback. No Windows, rename SOBRE arquivo existente
## remove o destino antes de mover: nunca o usamos assim. O backup é mantido se até o
## rollback falhar. Não é transação resistente a queda de energia; ver relatório P3.6.1.
static func publish_snapshot(src: String, dst: String) -> Dictionary:
	var suffix := ".%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temporary := dst + suffix + ".tmp"
	var backup := dst + suffix + ".previous"
	var result := {"error": OK, "rollback": OK, "recovery_file": ""}
	var err := DirAccess.copy_absolute(src, temporary)
	var had_previous := exists(dst)
	if err == OK and had_previous:
		err = DirAccess.rename_absolute(dst, backup)
	if err == OK:
		err = DirAccess.rename_absolute(temporary, dst)
		if err != OK and had_previous:
			result.rollback = DirAccess.rename_absolute(backup, dst)
			if result.rollback != OK:
				result.recovery_file = backup
		elif had_previous:
			# Publicação confirmada: só agora o backup deixa de ser necessário.
			DirAccess.remove_absolute(backup)
	if exists(temporary):
		DirAccess.remove_absolute(temporary)
	result.error = err
	return result


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
