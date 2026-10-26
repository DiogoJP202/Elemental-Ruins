extends "res://scripts/dev/p2_selftest.gd"
## Roteiro automatizado do P3: roda P0 + P1 + P2 (regressão) e depois os testes dos quatro
## elementos, na mesma cena real.
##
##   godot --headless --path . res://scenes/main.tscn -- --p3-selftest
##   godot --path . res://scenes/main.tscn -- --p3-selftest --p3-screenshots
##   opcional: --report=<caminho.json>, --only=T38,T29 (T1 e baseline sempre rodam)
##
## Código de saída: 0 = todos PASS, 1 = algum FAIL, 2 = watchdog.

const P3_WATCHDOG_S := 2100.0
const LAB_P3 := Vector3(-34, 0.6, 60)

var materials: MaterialResponseSystem


func _ready() -> void:
	materials = get_parent().materials
	super._ready()
	if OS.get_cmdline_user_args().has("--p3-screenshots") and DisplayServer.get_name() != "headless":
		_screens = true


func _report_prefix() -> String:
	return super._report_prefix() if _persist_phase != "" else "p3_selftest"


func _watchdog_seconds() -> float:
	return P3_WATCHDOG_S


func _evidence_dir() -> String:
	return "res://docs/evidence/p3/" if OS.has_feature("editor") else "user://"


func _screens_dir() -> String:
	return "res://docs/evidence/p3/screens/" if OS.has_feature("editor") else "user://screens_p3/"


func _log(msg: String) -> void:
	print("[P3TEST] ", msg)


func _run_tests() -> bool:
	var ok: bool = await super._run_tests()
	if not ok or _persist_phase != "":
		return ok
	_log("--- testes P3 ---")
	if _should_run("T38"): await _t38_material_states()
	return true


# --- T38: máquina de estados de material (eventos aplicados direto) ----------------------

func _t38_material_states() -> void:
	await main.request_world_reset()
	await _prepare_area(LAB_P3 + Vector3(0, 0, 10), AABB(LAB_P3 - Vector3(6, 3, 6), Vector3(12, 6, 12)))
	var cases := {}
	var heat := func(body: Node3D, units: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.HEAT, body.global_position, units, 0.0, &"selftest")
		e.target = body
		materials.apply(e)
	var wet := func(body: Node3D, amount: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.WET, body.global_position, amount, 0.0, &"selftest")
		e.target = body
		materials.apply(e)
	var wind := func(body: Node3D, strength: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.AIRFLOW, body.global_position, strength, 0.0, &"selftest")
		e.target = body
		materials.apply(e)

	# a) Madeira seca: 200 não acende; +150 (370 °C ≥ 300) acende.
	var a := DebugProps.spawn_crate(props, LAB_P3)
	heat.call(a, 200.0)
	var a_temp1: float = materials.state_of(a).temperature
	var a_burn1: bool = materials.state_of(a).burning
	heat.call(a, 150.0)
	var a_ok: bool = not a_burn1 and absf(a_temp1 - 220.0) < 0.01 and materials.state_of(a).burning
	cases["a_madeira_acende_no_limiar"] = {"temp_apos_200": a_temp1, "acesa_apos_200": a_burn1,
		"acesa_apos_350": materials.state_of(a).burning, "ok": a_ok}

	# b) Pedra: 1000 unidades só aquecem (÷3), nunca acende.
	var b := DebugProps.spawn_crate(props, LAB_P3 + Vector3(4, 0, 0))
	b.set_meta("body_material", BodyMaterialLibrary.STONE)
	heat.call(b, 1000.0)
	var b_s: MaterialState = materials.state_of(b)
	var b_ok := not b_s.burning and absf(b_s.temperature - (20.0 + 1000.0 / 3.0)) < 0.01
	cases["b_pedra_so_aquece"] = {"estado": b_s.describe(), "ok": b_ok}

	# c) Madeira molhada (60%): a 1ª rajada (320) gasta 60 secando e não acende; a 2ª acende.
	var c := DebugProps.spawn_crate(props, LAB_P3 + Vector3(-4, 0, 0))
	wet.call(c, 0.6)
	heat.call(c, 320.0)
	var c_s: MaterialState = materials.state_of(c)
	var c_first: String = c_s.describe()
	var c_burn1 := c_s.burning
	heat.call(c, 320.0)
	var c_ok := not c_burn1 and c_s.burning
	cases["c_molhada_resiste_1a_rajada"] = {"apos_1a": c_first, "apos_2a": c_s.describe(), "ok": c_ok}

	# d) Água apaga (umidade > 30%).
	wet.call(a, 0.4)
	var d_ok: bool = not materials.state_of(a).burning
	cases["d_agua_apaga"] = {"estado": materials.state_of(a).describe(), "ok": d_ok}

	# e) Vento: fogo fraco (0,2) sob vento 0,8 apaga; fogo forte (0,6) aviva para 0,84.
	var c2 := DebugProps.spawn_crate(props, LAB_P3 + Vector3(0, 0, 4))
	heat.call(c2, 400.0)
	materials.state_of(c2).intensity = 0.2
	wind.call(c2, 0.8)
	var e_weak_out: bool = not materials.state_of(c2).burning
	heat.call(c, 0.0)
	materials.state_of(c).intensity = 0.6
	wind.call(c, 0.8)
	var e_strong: float = materials.state_of(c).intensity
	var e_ok := e_weak_out and materials.state_of(c).burning and absf(e_strong - 0.84) < 0.001
	cases["e_vento_apaga_fraco_aviva_forte"] = {"fraco_apagou": e_weak_out, "forte_intensidade": e_strong, "ok": e_ok}

	# f) Queima até o fim: combustível curto → consumida e removida.
	var f := DebugProps.spawn_crate(props, LAB_P3 + Vector3(0, 0, -4))
	heat.call(f, 400.0)
	materials.state_of(f).fuel = 0.5
	var f_ref: WeakRef = weakref(f)
	var burned := await _wait_until(func(): return f_ref.get_ref() == null, 5.0)
	cases["f_queima_ate_consumir"] = {"removida": burned, "ok": burned}

	# g) Impacto numa peça de pedra presa: Δv 3 m/s não solta, 7 m/s solta (limiar 6).
	await _go_to_tower()
	var crown: StructurePiece = structures.get_pieces().filter(func(p): return p.kind == "coroa")[0]
	var kin := func(piece: StructurePiece, dv: float):
		var e := ElementalEvent.make(ElementalEvent.Kind.KINETIC, piece.global_position, piece.mass * dv, 0.0, &"selftest", Vector3(1, 0, 0))
		e.target = piece
		materials.apply(e)
	kin.call(crown, 3.0)
	var g_weak: bool = crown.released
	kin.call(crown, 7.0)
	var g_ok: bool = not g_weak and crown.released
	cases["g_impacto_solta_peca_acima_do_limiar"] = {"solta_com_3": g_weak, "solta_com_7": crown.released,
		"stats": structures.get_stats().last_break, "ok": g_ok}

	var ok: bool = cases.values().all(func(v): return v.ok)
	_record("T38", "Estados de material: ignição, pedra só aquece, molhada resiste, água e vento apagam, queima consome, impacto solta", ok, cases)
	for ch in props.get_children():
		ch.queue_free()
	await main.request_world_reset()
