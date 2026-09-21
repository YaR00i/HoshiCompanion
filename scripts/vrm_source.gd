extends RefCounted
## Minimal, local VRM 1.0 adapter for this prototype, NOT a complete VRM runtime.
## Uses Godot's glTF importer for geometry/skin/textures. Reads humanoid and morph
## binds separately. MToon uses its authored glTF unlit fallback; no toon outline.
## Original bytes are never changed on disk. No plug-in, network or subprocess.

const MAX_BYTES: int = 128 * 1024 * 1024
const GLB_MAGIC: int = 0x46546C67
const JSON_CHUNK: int = 0x4E4F534A
const BIN_CHUNK: int = 0x004E4942

# Stable identities carried through glTF extras into the generated scene/resources.
# Added only to our in-memory copy; the supplied VRM is never edited on disk.
const NODE_MARKER: String = "_hoshi_source_node_v1"
const MESH_MARKER: String = "_hoshi_source_mesh_v1"

static func read_container(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Не удалось открыть модель: " + path}
	var count: int = file.get_length()
	if count < 28 or count > MAX_BYTES:
		return {"error": "Некорректный размер VRM (допустимо до 128 МиБ)."}
	var bytes: PackedByteArray = file.get_buffer(count)
	file.close()
	return parse_container(bytes)

static func parse_container(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 28:
		return {"error": "Слишком короткий GLB/VRM."}
	if bytes.decode_u32(0) != GLB_MAGIC or bytes.decode_u32(4) != 2:
		return {"error": "Ожидается двоичный glTF 2.0, экспортированный как VRM."}
	if bytes.decode_u32(8) != bytes.size():
		return {"error": "Файл обрезан или заголовок GLB повреждён."}
	var offset: int = 12
	var document: Dictionary = {}
	var binary: PackedByteArray = PackedByteArray()
	var seen_json: bool = false
	var seen_binary: bool = false
	while offset < bytes.size():
		if offset + 8 > bytes.size():
			return {"error": "Повреждён заголовок чанка GLB."}
		var chunk_size: int = bytes.decode_u32(offset)
		var chunk_type: int = bytes.decode_u32(offset + 4)
		offset += 8
		if chunk_size % 4 != 0 or chunk_size > bytes.size() - offset:
			return {"error": "Повреждена длина чанка GLB."}
		if chunk_type == JSON_CHUNK:
			if seen_json or offset != 20:
				return {"error": "JSON должен быть первым и единственным JSON-чанком."}
			var parser: JSON = JSON.new()
			var result: Error = parser.parse(bytes.slice(offset, offset + chunk_size).get_string_from_utf8())
			if result != OK or not parser.data is Dictionary:
				return {"error": "Не удалось разобрать JSON модели: " + parser.get_error_message()}
			document = parser.data
			seen_json = true
		elif chunk_type == BIN_CHUNK:
			if seen_binary:
				return {"error": "В этом прототипе поддержан один BIN-чанк."}
			binary = bytes.slice(offset, offset + chunk_size)
			seen_binary = true
		offset += chunk_size
	if not seen_json or not seen_binary:
		return {"error": "В модели нет JSON или встроенного BIN-чанка."}
	if str(document.get("asset", {}).get("version", "")) != "2.0":
		return {"error": "Поддержан только glTF 2.0."}
	var extension: Dictionary = document.get("extensions", {}).get("VRMC_vrm", {})
	if str(extension.get("specVersion", "")) != "1.0":
		return {"error": "Для этого прототипа нужен VRM 1.0. VRM 0.x пока не поддержан."}
	var buffers: Array = document.get("buffers", [])
	if buffers.size() != 1 or buffers[0].has("uri"):
		return {"error": "Нужен самостоятельный VRM со встроенным буфером, без внешних файлов."}
	if int(buffers[0].get("byteLength", 0)) > binary.size():
		return {"error": "Встроенный буфер модели обрезан."}
	for image in document.get("images", []):
		if image.has("uri"):
			return {"error": "Поддержаны встроенные текстуры VRM, без внешних URI."}
	if document.get("nodes", []).size() > 10000:
		return {"error": "Слишком много узлов для небольшого настольного прототипа."}
	return {"json": document, "binary": binary}

static func _strip_vrm_extensions(value: Variant) -> void:
	if value is Dictionary:
		if value.has("extensions") and value["extensions"] is Dictionary:
			var extensions: Dictionary = value["extensions"]
			for key in extensions.keys():
				if str(key).begins_with("VRMC_") or str(key) == "VRM":
					extensions.erase(key)
			if extensions.is_empty():
				value.erase("extensions")
		for key in value.keys():
			_strip_vrm_extensions(value[key])
	elif value is Array:
		for child in value:
			_strip_vrm_extensions(child)

static func make_native_glb(document: Dictionary, binary: PackedByteArray) -> PackedByteArray:
	# Preserve standard glTF fallbacks, skeleton names, morph indices and BIN bytes.
	var native: Dictionary = document.duplicate(true)
	_strip_vrm_extensions(native)
	var native_nodes: Array = native.get("nodes", [])
	for index in range(native_nodes.size()):
		var node: Dictionary = native_nodes[index]
		var extras: Dictionary = {}
		if node.get("extras") is Dictionary:
			extras = node["extras"]
		extras[NODE_MARKER] = index
		node["extras"] = extras
	var native_meshes: Array = native.get("meshes", [])
	for index in range(native_meshes.size()):
		var mesh: Dictionary = native_meshes[index]
		var extras: Dictionary = {}
		if mesh.get("extras") is Dictionary:
			extras = mesh["extras"]
		extras[MESH_MARKER] = index
		mesh["extras"] = extras
	for list_name in ["extensionsUsed", "extensionsRequired"]:
		var keep: Array = []
		for extension in native.get(list_name, []):
			if not str(extension).begins_with("VRMC_") and str(extension) != "VRM":
				keep.append(extension)
		if keep.is_empty():
			native.erase(list_name)
		else:
			native[list_name] = keep
	return pack_container(native, binary)

static func pack_container(document: Dictionary, binary: PackedByteArray) -> PackedByteArray:
	# Input BIN is already 4-byte aligned by read_container().
	var text: PackedByteArray = JSON.stringify(document).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(32)
	var data: PackedByteArray = PackedByteArray()
	data.resize(20)
	data.encode_u32(0, GLB_MAGIC)
	data.encode_u32(4, 2)
	data.encode_u32(8, 28 + text.size() + binary.size())
	data.encode_u32(12, text.size())
	data.encode_u32(16, JSON_CHUNK)
	data.append_array(text)
	var chunk_header: PackedByteArray = PackedByteArray()
	chunk_header.resize(8)
	chunk_header.encode_u32(0, binary.size())
	chunk_header.encode_u32(4, BIN_CHUNK)
	data.append_array(chunk_header)
	data.append_array(binary)
	return data

static func load_avatar(path: String) -> Dictionary:
	var container: Dictionary = read_container(path)
	if container.has("error"):
		return container
	var source: Dictionary = container["json"]
	var native_glb: PackedByteArray = make_native_glb(source, container["binary"])
	var state: GLTFState = GLTFState.new()
	state.create_animations = false
	state.use_named_skin_binds = true
	state.set_handle_binary_image(GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED)
	var importer: GLTFDocument = GLTFDocument.new()
	var result: Error = importer.append_from_buffer(native_glb, "", state)
	if result != OK:
		return {"error": "Godot не смог загрузить glTF-основу VRM: " + error_string(result)}
	var root: Node3D = importer.generate_scene(state) as Node3D
	if root == null:
		return {"error": "Импортёр не создал сцену модели."}
	root.name = "Avatar"
	var extension: Dictionary = source["extensions"]["VRMC_vrm"]
	return {"model": root, "state": state, "source": source, "vrm": extension}
