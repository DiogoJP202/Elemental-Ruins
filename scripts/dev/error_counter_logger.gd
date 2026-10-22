extends Logger
## Conta erros/avisos emitidos pelo motor e scripts durante o selftest.
## Pode ser chamado de qualquer thread (o Voxel Tools usa threads próprias).

var _mutex := Mutex.new()
var _errors := 0
var _warnings := 0
var _samples: PackedStringArray = []


# Parâmetros sem tipo de propósito: aceita a assinatura nativa de Logger.
func _log_error(function, file, line, code, rationale, _editor_notify, error_type, _script_backtraces) -> void:
	_mutex.lock()
	if error_type == ERROR_TYPE_WARNING:
		_warnings += 1
	else:
		_errors += 1
	if _samples.size() < 30:
		var msg := String(rationale) if String(rationale) != "" else String(code)
		_samples.append("%s: %s (%s:%s %s)" % ["WARN" if error_type == ERROR_TYPE_WARNING else "ERROR", msg, file, line, function])
	_mutex.unlock()


func _log_message(_message, _error) -> void:
	pass


func snapshot() -> Dictionary:
	_mutex.lock()
	var d := {"errors": _errors, "warnings": _warnings, "samples": _samples.duplicate()}
	_mutex.unlock()
	return d
