class_name LevelBase
extends Node2D

func prepare_for_server() -> void:
	for node in get_tree().get_nodes_in_group("visual_only"):
		node.queue_free()
	_strip_static_objects(self)

func _strip_static_objects(node: Node) -> void:
	for child in node.get_children():
		if child is StaticObjectBase:
			child.strip_for_server()
		else:
			_strip_static_objects(child)
