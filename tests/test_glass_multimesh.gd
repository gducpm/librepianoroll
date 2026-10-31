# LibrePianoRoll - Next-generation, high-performance libre piano visualizer
# Copyright (C) 2026  gducpm <gducpm@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

extends SceneTree

func _init() -> void:
	print("Testing MultiMeshInstance2D with note_glass.gdshader...")
	var root_node := Node2D.new()
	root.add_child(root_node)

	var mm_inst := MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.5, 0.5, 0.0) # pivot (0,0)
	mm.mesh = quad

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/note_glass.gdshader")
	mm_inst.material = mat
	mm_inst.multimesh = mm

	root_node.add_child(mm_inst)

	mm.instance_count = 5
	for i in range(5):
		var xform := Transform2D(0.0, Vector2(20.0, 100.0), 0.0, Vector2(i * 30.0, 50.0))
		mm.set_instance_transform_2d(i, xform)
		mm.set_instance_color(i, Color(0.863, 0.208, 0.271, 1.0))
		mm.set_instance_custom_data(i, Color(1.0, 0.0, 5.0, 0.0))

	print("MultiMeshInstance2D configured with 5 instances and glass shader!")
	quit(0)
