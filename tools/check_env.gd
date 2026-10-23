extends SceneTree
## Diagnóstico de ambiente. Uso:
##   godot --headless --path . --script res://tools/check_env.gd
## Não depende de classes do Voxel Tools em tempo de parse (usa ClassDB),
## para dar diagnóstico claro mesmo se a extensão não carregar.

const VOXEL_CLASSES := [
	"VoxelLodTerrain", "VoxelNode", "VoxelTool", "VoxelToolLodTerrain",
	"VoxelViewer", "VoxelMesherTransvoxel", "VoxelGeneratorGraph",
	"VoxelGraphFunction", "VoxelBuffer", "VoxelEngine", "VoxelStreamSQLite",
]


func _initialize() -> void:
	var ok := true
	var info := Engine.get_version_info()
	print("[check_env] Godot: ", info.string, " (hash ", info.hash, ")")
	print("[check_env] OS: ", OS.get_name(), " ", OS.get_version(), " | CPU: ", OS.get_processor_name(), " x", OS.get_processor_count())
	print("[check_env] Renderer setting: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("[check_env] Physics 3D setting: ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("[check_env] PhysicsServer3D class: ", PhysicsServer3D.get_class())

	var loaded := GDExtensionManager.get_loaded_extensions()
	print("[check_env] GDExtensions carregadas: ", loaded)
	var voxel_ext := false
	for path: String in loaded:
		voxel_ext = voxel_ext or path.contains("zylann.voxel")
	var variant := "GDExtension" if voxel_ext else ("módulo embutido no executável" if ClassDB.class_exists("VoxelLodTerrain") else "AUSENTE")
	print("[check_env] Voxel Tools: ", variant)

	for cls: String in VOXEL_CLASSES:
		var exists := ClassDB.class_exists(cls)
		print("[check_env] class ", cls, ": ", "OK" if exists else "AUSENTE")
		if not exists and cls != "VoxelStreamSQLite":
			ok = false

	if Engine.has_singleton("VoxelEngine"):
		var ve := Engine.get_singleton("VoxelEngine")
		if ve.has_method("get_version_info"):
			print("[check_env] VoxelEngine.get_version_info(): ", ve.call("get_version_info"))
		if ve.has_method("get_stats"):
			print("[check_env] VoxelEngine.get_stats(): ", ve.call("get_stats"))
	else:
		print("[check_env] singleton VoxelEngine: AUSENTE")

	print("[check_env] RESULTADO: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)
