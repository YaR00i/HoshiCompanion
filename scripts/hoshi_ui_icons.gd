extends RefCounted
## Маленькие собственные векторные значки для нативных кнопок Хоши.

const PATHS: Dictionary = {
	"star": "<path d='m12 2 2.2 7.8L22 12l-7.8 2.2L12 22l-2.2-7.8L2 12l7.8-2.2L12 2Z'/>",
	"moon": "<path d='M20.5 15.2A9 9 0 0 1 8.8 3.5 9 9 0 1 0 20.5 15.2Z'/>",
	"sun": "<circle cx='12' cy='12' r='4'/><path d='M12 2v2m0 16v2M2 12h2m16 0h2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4'/>",
	"chat": "<path d='M4 4h16v12H9l-5 4V4Z'/><path d='M8 9h8m-8 3h5'/>",
	"play": "<path d='m7 4 13 8-13 8V4Z'/>",
	"voice": "<rect x='9' y='3' width='6' height='12' rx='3'/><path d='M5 11a7 7 0 0 0 14 0M12 18v3m-4 0h8'/>",
	"home": "<path d='m3 11 9-8 9 8v9H3v-9Z'/><path d='M9 20v-6h6v6'/>",
	"window": "<rect x='3' y='4' width='18' height='16' rx='2'/><path d='M3 9h18M8 4v5'/>",
	"walk": "<circle cx='13' cy='4' r='2'/><path d='m10 21 1.5-6-3-3-2 3H3m18 6-4-4-1-5-4-3-2 3m2-3 3-2'/>",
	"stop": "<rect x='5' y='5' width='14' height='14' rx='3'/>",
	"folder": "<path d='M3 6h7l2 2h9v12H3V6Z'/>",
	"sound": "<path d='M4 9h4l5-4v14l-5-4H4V9Z'/><path d='M17 9a4 4 0 0 1 0 6m2-9a8 8 0 0 1 0 12'/>",
	"sparkle": "<path d='m12 2 2 8 8 2-8 2-2 8-2-8-8-2 8-2 2-8Z'/>",
	"move": "<rect x='4' y='5' width='16' height='14' rx='2'/><path d='m12 8-3 3 3 3m0-6 3 3-3 3'/>",
	"restart": "<path d='M20 11a8 8 0 1 1-3-6M20 3v5h-5'/>",
	"link": "<path d='M10 13a5 5 0 0 0 7 .4l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7-.4l-3 3a5 5 0 0 0 7 7l2-2'/>",
}

static var _cache: Dictionary = {}

static func texture(name: String, color: String = "#665479") -> Texture2D:
	var key: String = name + color
	if _cache.has(key):
		return _cache[key]
	var shape: String = str(PATHS.get(name, PATHS["sparkle"]))
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='%s' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [color, shape]
	var image := Image.new()
	if image.load_svg_from_buffer(svg.to_utf8_buffer(), 1.0) != OK:
		return null
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result
