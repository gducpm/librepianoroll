extends SceneTree

func _init() -> void:
	var scn: PackedScene = load("res://scenes/main.tscn")
	var main_node = scn.instantiate()
	root.add_child(main_node)
	_print_tree(main_node, "")
	quit(0)

func _print_tree(node: Node, indent: String) -> void:
	var info := node.name + " (" + node.get_class() + ")"
	if node is CanvasItem:
		info += " z_index=" + str(node.z_index) + " z_rel=" + str(node.z_as_relative)
		if node is ColorRect:
			info += " color=" + str(node.color)
	print(indent + info)
	for c in node.get_children():
		_print_tree(c, indent + "  ")
