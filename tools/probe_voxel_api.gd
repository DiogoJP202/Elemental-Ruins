extends SceneTree
## Extrai a API REAL do Voxel Tools carregado (não a documentação).
## Uso: godot --headless --path . --script res://tools/probe_voxel_api.gd
## Saída: stdout + res://docs/evidence/voxel_api_probe.txt

const OUT_PATH := "res://docs/evidence/voxel_api_probe.txt"

const CLASSES := [
	"VoxelNode", "VoxelLodTerrain", "VoxelTool", "VoxelToolLodTerrain",
	"VoxelViewer", "VoxelMesherTransvoxel", "VoxelGenerator",
	"VoxelGeneratorGraph", "VoxelGraphFunction", "VoxelRaycastResult",
	# P1: persistência, formato de canais e buffers.
	"VoxelStream", "VoxelStreamSQLite", "VoxelStreamMemory",
	"VoxelSaveCompletionTracker", "VoxelFormat", "VoxelBuffer",
]

const GRAPH_NODE_ENUMS := [
	"NODE_CONSTANT", "NODE_INPUT_X", "NODE_INPUT_Y", "NODE_INPUT_Z",
	"NODE_OUTPUT_SDF", "NODE_ADD", "NODE_SUBTRACT", "NODE_MULTIPLY", "NODE_MIN",
	"NODE_SDF_PLANE", "NODE_SDF_SPHERE", "NODE_SDF_BOX", "NODE_SDF_SMOOTH_UNION",
	"NODE_EXPRESSION",
	# P1: material por voxel (modo Single).
	"NODE_SELECT", "NODE_CLAMP", "NODE_OUTPUT_SINGLE_TEXTURE", "NODE_OUTPUT_WEIGHT",
	"NODE_OUTPUT_TYPE",
]

## Enums conferidos além das classes (classe, nome do enum).
const ENUMS := [
	["VoxelTool", "Mode"],
	["VoxelBuffer", "ChannelId"],
	["VoxelBuffer", "Depth"],
	["VoxelLodTerrain", "StreamingSystem"],
	["VoxelMesherTransvoxel", "TexturingMode"],
	["VoxelGeneratorGraph", "TextureMode"],
	["VoxelStreamSQLite", "CoordinateFormat"],
]

var _lines: PackedStringArray = []


func _out(s: String) -> void:
	print(s)
	_lines.append(s)


func _initialize() -> void:
	_out("# Voxel Tools API probe — %s" % Time.get_datetime_string_from_system())
	_out("# Godot %s" % Engine.get_version_info().string)
	for cls: String in CLASSES:
		_dump_class(cls)
	_dump_graph_nodes()
	for e: Array in ENUMS:
		_dump_enum(e[0], e[1])

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		print("[probe] escrito em ", ProjectSettings.globalize_path(OUT_PATH))
	else:
		push_error("[probe] não foi possível escrever %s: %s" % [OUT_PATH, FileAccess.get_open_error()])
	quit(0)


func _dump_class(cls: String) -> void:
	_out("")
	if not ClassDB.class_exists(cls):
		_out("## %s — AUSENTE" % cls)
		return
	_out("## %s (extends %s)" % [cls, ClassDB.get_parent_class(cls)])
	var props := ClassDB.class_get_property_list(cls, true)
	for p: Dictionary in props:
		if p.usage & PROPERTY_USAGE_EDITOR or p.usage & PROPERTY_USAGE_STORAGE:
			_out("  prop %s: %s" % [p.name, type_string(p.type) if p.class_name == &"" else String(p.class_name)])
	var methods := ClassDB.class_get_method_list(cls, true)
	methods.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for m: Dictionary in methods:
		if String(m.name).begins_with("_") and not (m.flags & METHOD_FLAG_VIRTUAL):
			continue
		var args: PackedStringArray = []
		for a: Dictionary in m.args:
			var t := type_string(a.type) if String(a.class_name) == "" else String(a.class_name)
			args.append("%s: %s" % [a.name, t])
		var ret: Dictionary = m.get("return", {})
		var rt := "void"
		if ret.size() > 0 and ret.type != TYPE_NIL:
			rt = type_string(ret.type) if String(ret.class_name) == "" else String(ret.class_name)
		var defaults: Array = m.get("default_args", [])
		var suffix := "" if defaults.is_empty() else "  defaults=%s" % [defaults]
		var virt := " [virtual]" if m.flags & METHOD_FLAG_VIRTUAL else ""
		_out("  func %s(%s) -> %s%s%s" % [m.name, ", ".join(args), rt, virt, suffix])


func _dump_enum(cls: String, enum_name: String) -> void:
	_out("")
	if not ClassDB.class_exists(cls) or not ClassDB.class_has_enum(cls, enum_name):
		_out("## enum %s.%s — AUSENTE" % [cls, enum_name])
		return
	_out("## enum %s.%s" % [cls, enum_name])
	for c: String in ClassDB.class_get_enum_constants(cls, enum_name):
		_out("  %s = %d" % [c, ClassDB.class_get_integer_constant(cls, c)])


func _dump_graph_nodes() -> void:
	_out("")
	if not ClassDB.class_exists("VoxelGraphFunction"):
		_out("## VoxelGraphFunction node types — AUSENTE")
		return
	_out("## VoxelGraphFunction node types (get_node_type_info)")
	var fn: Object = ClassDB.instantiate("VoxelGraphFunction")
	for const_name: String in GRAPH_NODE_ENUMS:
		if not ClassDB.class_has_integer_constant("VoxelGraphFunction", const_name):
			_out("  %s: AUSENTE" % const_name)
			continue
		var type_id := ClassDB.class_get_integer_constant("VoxelGraphFunction", const_name)
		var info: Dictionary = fn.call("get_node_type_info", type_id)
		var inputs: PackedStringArray = []
		for i: Dictionary in info.get("inputs", []):
			inputs.append(String(i.get("name", "?")))
		var outputs: PackedStringArray = []
		for o: Dictionary in info.get("outputs", []):
			outputs.append(String(o.get("name", "?")))
		var params: PackedStringArray = []
		for p: Dictionary in info.get("params", []):
			params.append("%s=%s" % [p.get("name", "?"), p.get("default_value", "?")])
		_out("  %s (%d) name=%s inputs=[%s] outputs=[%s] params=[%s]" % [
			const_name, type_id, info.get("name", "?"),
			", ".join(inputs), ", ".join(outputs), ", ".join(params)])
