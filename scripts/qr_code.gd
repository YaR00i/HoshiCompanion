extends RefCounted
## Маленький генератор QR-кодов (байтовый режим, уровень коррекции M,
## версии 1–10 — до ~200 символов). Нужен, чтобы телефон привязывался к Хоши
## по камере: в QR лежит адрес пульта с одноразовым кодом.
## Алгоритм по стандарту ISO/IEC 18004 (как в открытом генераторе Nayuki).

const MAX_VERSION: int = 10
## Уровень M: байт коррекции на блок и число блоков для версий 1..10.
const ECC_PER_BLOCK: Array[int] = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const NUM_BLOCKS: Array[int] = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const FORMAT_BITS_M: int = 0

## Матрица модулей: Array[Array[bool]], true — тёмный. Пусто — не поместилось.
static func encode(text: String) -> Array:
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = 0
	for candidate in range(1, MAX_VERSION + 1):
		var count_bits: int = 8 if candidate <= 9 else 16
		if 4 + count_bits + data.size() * 8 <= _data_codewords(candidate) * 8:
			version = candidate
			break
	if version == 0:
		return []
	var bits: Array[int] = []
	_append_bits(bits, 0x4, 4)
	_append_bits(bits, data.size(), 8 if version <= 9 else 16)
	for value in data:
		_append_bits(bits, value, 8)
	var capacity: int = _data_codewords(version) * 8
	_append_bits(bits, 0, mini(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad: int = 0xEC
	while bits.size() < capacity:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var codewords: Array[int] = []
	for index in range(0, bits.size(), 8):
		var byte: int = 0
		for bit in range(8):
			byte = (byte << 1) | bits[index + bit]
		codewords.append(byte)
	var all_codewords: Array[int] = _add_ecc_and_interleave(codewords, version)

	var size: int = version * 4 + 17
	var modules: Array = []
	var is_function: Array = []
	for y in range(size):
		var row: Array = []
		var row_function: Array = []
		row.resize(size)
		row.fill(false)
		row_function.resize(size)
		row_function.fill(false)
		modules.append(row)
		is_function.append(row_function)
	_draw_function_patterns(modules, is_function, version)
	_draw_codewords(modules, is_function, all_codewords)
	var best_mask: int = 0
	var best_penalty: int = 1 << 30
	for mask in range(8):
		_apply_mask(modules, is_function, mask)
		_draw_format_bits(modules, is_function, mask)
		var penalty: int = _penalty(modules)
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
		_apply_mask(modules, is_function, mask) # XOR снова — отменить
	_apply_mask(modules, is_function, best_mask)
	_draw_format_bits(modules, is_function, best_mask)
	return modules

## Картинка QR: scale пикселей на модуль, border модулей белой рамки.
static func to_image(text: String, scale: int = 6, border: int = 4, dark: Color = Color("3b3449"), light: Color = Color.WHITE) -> Image:
	var modules: Array = encode(text)
	if modules.is_empty():
		return null
	var size: int = modules.size()
	var pixels: int = (size + border * 2) * scale
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	image.fill(light)
	for y in range(size):
		for x in range(size):
			if modules[y][x]:
				image.fill_rect(Rect2i((x + border) * scale, (y + border) * scale, scale, scale), dark)
	return image

# ------------------------------------------------------------------ данные

static func _append_bits(bits: Array[int], value: int, length: int) -> void:
	for index in range(length - 1, -1, -1):
		bits.append((value >> index) & 1)

static func _raw_data_modules(version: int) -> int:
	var result: int = (16 * version + 128) * version + 64
	if version >= 2:
		var num_align: int = version / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if version >= 7:
			result -= 36
	return result

static func _data_codewords(version: int) -> int:
	return _raw_data_modules(version) / 8 - ECC_PER_BLOCK[version] * NUM_BLOCKS[version]

static func _add_ecc_and_interleave(data: Array[int], version: int) -> Array[int]:
	var num_blocks: int = NUM_BLOCKS[version]
	var block_ecc_len: int = ECC_PER_BLOCK[version]
	var raw_codewords: int = _raw_data_modules(version) / 8
	var num_short_blocks: int = num_blocks - raw_codewords % num_blocks
	var short_block_len: int = raw_codewords / num_blocks
	var divisor: Array[int] = _rs_divisor(block_ecc_len)
	var blocks: Array = []
	var k: int = 0
	for index in range(num_blocks):
		var data_len: int = short_block_len - block_ecc_len + (0 if index < num_short_blocks else 1)
		var block_data: Array[int] = []
		for j in range(data_len):
			block_data.append(data[k + j])
		k += data_len
		var ecc: Array[int] = _rs_remainder(block_data, divisor)
		var block: Array[int] = block_data.duplicate()
		if index < num_short_blocks:
			block.append(-1) # место под байт, которого нет в коротком блоке
		block.append_array(ecc)
		blocks.append(block)
	var result: Array[int] = []
	for column in range(blocks[0].size()):
		for index in range(blocks.size()):
			if column != short_block_len - block_ecc_len or index >= num_short_blocks:
				result.append(blocks[index][column])
	return result

static func _rs_multiply(x: int, y: int) -> int:
	var z: int = 0
	for index in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> index) & 1) * x
	return z & 0xFF

static func _rs_divisor(degree: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root: int = 1
	for index in range(degree):
		for j in range(degree):
			result[j] = _rs_multiply(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _rs_multiply(root, 0x02)
	return result

static func _rs_remainder(data: Array[int], divisor: Array[int]) -> Array[int]:
	var result: Array[int] = []
	result.resize(divisor.size())
	result.fill(0)
	for value in data:
		var factor: int = value ^ result[0]
		result.remove_at(0)
		result.append(0)
		for index in range(result.size()):
			result[index] ^= _rs_multiply(divisor[index], factor)
	return result

# ------------------------------------------------------------------ рисование

static func _set_function(modules: Array, is_function: Array, x: int, y: int, dark: bool) -> void:
	modules[y][x] = dark
	is_function[y][x] = true

static func _alignment_positions(version: int) -> Array[int]:
	var result: Array[int] = []
	if version == 1:
		return result
	var num_align: int = version / 7 + 2
	var step: int = (version * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	result.resize(num_align)
	result[0] = 6
	var pos: int = version * 4 + 17 - 7
	for index in range(num_align - 1, 0, -1):
		result[index] = pos
		pos -= step
	return result

static func _draw_function_patterns(modules: Array, is_function: Array, version: int) -> void:
	var size: int = modules.size()
	for index in range(size):
		_set_function(modules, is_function, 6, index, index % 2 == 0)
		_set_function(modules, is_function, index, 6, index % 2 == 0)
	for center in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = center.x + dx
				var y: int = center.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var distance: int = maxi(absi(dx), absi(dy))
					_set_function(modules, is_function, x, y, distance != 2 and distance != 4)
	var positions: Array[int] = _alignment_positions(version)
	var count: int = positions.size()
	for i in range(count):
		for j in range(count):
			if (i == 0 and j == 0) or (i == 0 and j == count - 1) or (i == count - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_function(modules, is_function, positions[i] + dx, positions[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format_bits(modules, is_function, 0) # резервирует место
	if version >= 7:
		var rem: int = version
		for index in range(12):
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits: int = (version << 12) | rem
		for index in range(18):
			var dark: bool = ((bits >> index) & 1) != 0
			var a: int = size - 11 + index % 3
			var b: int = index / 3
			_set_function(modules, is_function, a, b, dark)
			_set_function(modules, is_function, b, a, dark)

static func _draw_format_bits(modules: Array, is_function: Array, mask: int) -> void:
	var size: int = modules.size()
	var data: int = (FORMAT_BITS_M << 3) | mask
	var rem: int = data
	for index in range(10):
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits: int = ((data << 10) | rem) ^ 0x5412
	var bit := func(i: int) -> bool: return ((bits >> i) & 1) != 0
	for index in range(0, 6):
		_set_function(modules, is_function, 8, index, bit.call(index))
	_set_function(modules, is_function, 8, 7, bit.call(6))
	_set_function(modules, is_function, 8, 8, bit.call(7))
	_set_function(modules, is_function, 7, 8, bit.call(8))
	for index in range(9, 15):
		_set_function(modules, is_function, 14 - index, 8, bit.call(index))
	for index in range(0, 8):
		_set_function(modules, is_function, size - 1 - index, 8, bit.call(index))
	for index in range(8, 15):
		_set_function(modules, is_function, 8, size - 15 + index, bit.call(index))
	_set_function(modules, is_function, 8, size - 8, true)

static func _draw_codewords(modules: Array, is_function: Array, codewords: Array[int]) -> void:
	var size: int = modules.size()
	var index: int = 0
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(size):
			for j in range(2):
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = size - 1 - vert if upward else vert
				if not is_function[y][x] and index < codewords.size() * 8:
					modules[y][x] = ((codewords[index >> 3] >> (7 - (index & 7))) & 1) != 0
					index += 1
		right -= 2

static func _apply_mask(modules: Array, is_function: Array, mask: int) -> void:
	var size: int = modules.size()
	for y in range(size):
		for x in range(size):
			if is_function[y][x]:
				continue
			var invert: bool = false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y][x] = not modules[y][x]

## Упрощённая оценка из стандарта: длинные ряды, квадраты 2×2, похожие на
## искатели узоры и баланс тёмного/светлого. Меньше — лучше.
static func _penalty(modules: Array) -> int:
	var size: int = modules.size()
	var result: int = 0
	var dark_count: int = 0
	for pass_index in range(2):
		for a in range(size):
			var run: int = 0
			var previous: bool = false
			var line: Array[bool] = []
			for b in range(size):
				var value: bool = modules[a][b] if pass_index == 0 else modules[b][a]
				line.append(value)
				if b > 0 and value == previous:
					run += 1
				else:
					if run >= 5:
						result += run - 2
					run = 1
				previous = value
			if run >= 5:
				result += run - 2
			for start in range(size - 10):
				var slice: Array = line.slice(start, start + 11)
				if slice == [true, false, true, true, true, false, true, false, false, false, false] or slice == [false, false, false, false, true, false, true, true, true, false, true]:
					result += 40
	for y in range(size):
		for x in range(size):
			if modules[y][x]:
				dark_count += 1
			if x < size - 1 and y < size - 1:
				var color: bool = modules[y][x]
				if color == modules[y][x + 1] and color == modules[y + 1][x] and color == modules[y + 1][x + 1]:
					result += 3
	var total: int = size * size
	var k: int = (absi(dark_count * 20 - total * 10) + total - 1) / total - 1
	result += maxi(0, k) * 10
	return result
