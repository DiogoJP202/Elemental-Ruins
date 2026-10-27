class_name PhysicsRayHelper
extends RefCounted
## Fallback conservador para arestas: só aceita dois raios testemunha de ±1 mm
## que concordam no RID, na normal e na distância. Mantém máscara/exclusões.
## Não amplia o alcance nem transforma ausência de contato em um shape cast.

const OFFSET_M := 0.001


static func intersect(space, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		return hit
	var start := query.from
	var end := query.to
	var direction := (end - start).normalized()
	if direction.is_zero_approx():
		return {}
	var offset := Vector3(1.0, 0.0, 0.7)
	offset -= direction * offset.dot(direction)
	if offset.length_squared() < 0.01:
		offset = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	offset = offset.normalized() * OFFSET_M
	query.from = start + offset
	query.to = end + offset
	var a: Dictionary = space.intersect_ray(query)
	query.from = start - offset
	query.to = end - offset
	var b: Dictionary = space.intersect_ray(query)
	query.from = start
	query.to = end
	if a.is_empty() or b.is_empty() or a.rid != b.rid:
		return {}
	if (a.normal as Vector3).dot(b.normal) < 0.95 or (a.position as Vector3).distance_to(b.position) > OFFSET_M * 4.0:
		return {}
	a["ray_fallback"] = true
	a["ray_offset_m"] = OFFSET_M
	return a
