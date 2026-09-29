@tool
extends EditorPlugin
## Только редактор: кольца-контроллеры костей и автоключ для сцены авторинга анимаций.

const BoneRingGizmo = preload("res://addons/hoshi_authoring/bone_ring_gizmo.gd")

var _rings: EditorNode3DGizmoPlugin
var _clip_snapshot: int = 0
var _clip_name: String = ""
var _auto_key_pending: bool = false

func _enter_tree() -> void:
	_rings = BoneRingGizmo.new()
	add_node_3d_gizmo_plugin(_rings)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	EditorInterface.get_editor_undo_redo().history_changed.connect(_on_history_changed)

func _exit_tree() -> void:
	EditorInterface.get_editor_undo_redo().history_changed.disconnect(_on_history_changed)
	EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	remove_node_3d_gizmo_plugin(_rings)
	_rings = null

func _on_selection_changed() -> void:
	# Выбранное кольцо рисуется ярче — перерисовать прошлое и новое выделение.
	for node in _rings.last_selected:
		if is_instance_valid(node):
			(node as Node3D).update_gizmos()
	_rings.last_selected.clear()
	for node in EditorInterface.get_selection().get_selected_nodes():
		if _rings.is_ring_target(node):
			_rings.last_selected.append(node)
			(node as Node3D).update_gizmos()
	_clip_snapshot = _snapshot()
	_clip_name = _selected_clip()

## Автоключ. Любое действие в редакторе (поворот кольца мышью или в инспекторе)
## попадает в историю. Если после него кольцо стоит не так, как говорит клип, —
## пишем ключ. Если же изменились сами ключи (правка на шкале, Ctrl+Z ключа) —
## ничего не пишем: просмотр сам переставит кольцо по клипу.
func _on_history_changed() -> void:
	if not _auto_key_pending:
		_auto_key_pending = true
		_auto_key.call_deferred()

func _auto_key() -> void:
	_auto_key_pending = false
	var snapshot: int = _snapshot()
	var keys_changed: bool = snapshot != _clip_snapshot and _selected_clip() == _clip_name
	_clip_snapshot = snapshot
	_clip_name = _selected_clip()
	if keys_changed:
		return
	for node in EditorInterface.get_selection().get_selected_nodes():
		if not _rings.is_ring_target(node):
			continue
		var scene_root: Node = node.call("_scene_root")
		if scene_root == null or not bool(scene_root.get("auto_key")):
			continue
		if bool(node.call("needs_key")):
			node.call("record_rotation_key", true)
	_clip_snapshot = _snapshot()

func _selected_clip() -> String:
	var scene: Node = EditorInterface.get_edited_scene_root()
	var player: Node = scene.get_node_or_null("AnimationPlayer") if scene != null else null
	return str(player.call("selected_clip_name")) if player != null and player.has_method("selected_clip_name") else ""

func _snapshot() -> int:
	var scene: Node = EditorInterface.get_edited_scene_root()
	var player: AnimationPlayer = scene.get_node_or_null("AnimationPlayer") as AnimationPlayer if scene != null else null
	if player == null or not player.has_method("selected_clip_name") or not scene.has_method("_clip_key_snapshot"):
		return 0
	var selected: String = player.selected_clip_name()
	if selected.is_empty():
		return 0
	return hash([selected, scene.call("_clip_key_snapshot", player.get_animation(selected))])
