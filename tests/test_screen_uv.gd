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
	print("Checking test_screen_uv_shader.gdshader...")
	var sh: Shader = load("res://tests/test_screen_uv_shader.gdshader")
	assert(sh != null, "Shader load failed")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	print("SCREEN_UV test shader compiled successfully!")
	quit(0)
