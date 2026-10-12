class_name GradientNoise
extends RefCounted
## Seeded 2D gradient (Perlin-style) noise in plain GDScript, output about -1..1.
## Used instead of FastNoiseLite because that is a Resource, and worker threads must not touch Resources.

const _GRADIENTS: Array[Vector2] = [
	Vector2(1, 1),
	Vector2(-1, 1),
	Vector2(1, -1),
	Vector2(-1, -1),
	Vector2(1, 0),
	Vector2(-1, 0),
	Vector2(0, 1),
	Vector2(0, -1),
]
const _OUTPUT_SCALE: float = 1.4

var _frequency: float = 0.01
var _perm: PackedInt32Array = PackedInt32Array()


func _init(p_seed: int, p_frequency: float) -> void:
	_frequency = p_frequency
	var rng := Rng.new(p_seed)
	var table: Array[int] = []
	for i: int in 256:
		table.append(i)
	for i: int in range(255, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = table[i]
		table[i] = table[j]
		table[j] = tmp
	_perm.resize(512)
	for i: int in 512:
		_perm[i] = table[i & 255]


func sample(x: float, z: float) -> float:
	var fx: float = x * _frequency
	var fz: float = z * _frequency
	var x0: int = floori(fx)
	var z0: int = floori(fz)
	var xf: float = fx - float(x0)
	var zf: float = fz - float(z0)
	var xi: int = x0 & 255
	var zi: int = z0 & 255
	var g00: float = _grad(_perm[_perm[xi] + zi], xf, zf)
	var g10: float = _grad(_perm[_perm[xi + 1] + zi], xf - 1.0, zf)
	var g01: float = _grad(_perm[_perm[xi] + zi + 1], xf, zf - 1.0)
	var g11: float = _grad(_perm[_perm[xi + 1] + zi + 1], xf - 1.0, zf - 1.0)
	var u: float = _fade(xf)
	var v: float = _fade(zf)
	var value: float = lerpf(lerpf(g00, g10, u), lerpf(g01, g11, u), v) * _OUTPUT_SCALE
	return clampf(value, -1.0, 1.0)


func _grad(hash_value: int, dx: float, dz: float) -> float:
	var g: Vector2 = _GRADIENTS[hash_value & 7]
	return g.x * dx + g.y * dz


func _fade(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
