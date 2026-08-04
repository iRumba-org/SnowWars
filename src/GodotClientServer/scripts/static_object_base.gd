class_name StaticObjectBase
extends Node2D

func strip_for_server() -> void:
	var visual := get_node_or_null("Visual")
	if visual:
		visual.queue_free()
