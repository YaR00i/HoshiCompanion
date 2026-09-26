@tool
extends PanelContainer
## Opens the built-in AnimationPlayer timeline when the workshop scene is edited.

func _ready() -> void:
	if Engine.is_editor_hint():
		_focus_timeline.call_deferred()

func _focus_timeline() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var player: AnimationPlayer = get_parent().get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(player)
