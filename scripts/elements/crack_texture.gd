class_name CrackTexture
extends RefCounted
## Textura de rachadura gerada em runtime (sem assets): ramos que saem do centro, ficam mais
## finos e se bifurcam. Canal alfa = rachadura; cor escura. Usada por decals (P3.5).

const COLOR := Color(0.07, 0.05, 0.04, 1.0)


## `seed` muda o desenho; `branches` = ramos principais; `width` em pixels (0 = size / 40: com
## size / 70 as rachaduras sumiam a 15 m na captura do spike P3.5).
static func make(size := 256, seed := 1, branches := 7, width := 0.0) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(COLOR.r, COLOR.g, COLOR.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var c := Vector2(size, size) * 0.5
	var w := width if width > 0.0 else maxf(2.0, size / 40.0)
	for i in branches:
		var ang := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / branches
		_branch(img, rng, c + Vector2.from_angle(ang) * size * 0.04, ang, size * rng.randf_range(0.32, 0.46), w, 2)
	return ImageTexture.create_from_image(img)


static func _branch(img: Image, rng: RandomNumberGenerator, from: Vector2, ang: float, length: float,
		width: float, depth: int) -> void:
	var p := from
	var step := 4.0
	var steps := int(length / step)
	for s in steps:
		ang += rng.randf_range(-0.35, 0.35)
		var q := p + Vector2.from_angle(ang) * step
		var t := float(s) / steps
		_stroke(img, p, q, width * (1.0 - 0.7 * t), 1.0 - 0.5 * t)
		p = q
		if depth > 0 and rng.randf() < 0.07:
			_branch(img, rng, p, ang + rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0),
				length * (1.0 - t) * 0.6, width * 0.6, depth - 1)


static func _stroke(img: Image, a: Vector2, b: Vector2, width: float, alpha: float) -> void:
	var n := int(maxf(1.0, a.distance_to(b)))
	var r := int(ceil(width * 0.5))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var d := Vector2(dx, dy).length() / maxf(width * 0.5, 0.5)
				if d > 1.0:
					continue
				var prev := img.get_pixel(x, y).a
				img.set_pixel(x, y, Color(COLOR.r, COLOR.g, COLOR.b, maxf(prev, alpha * (1.0 - d * d))))
