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

var frame_count: int = 0
var main_node: Node2D

func _init() -> void:
	print("Starting screenshot capture script...")
	var scn: PackedScene = load("res://scenes/main.tscn")
	main_node = scn.instantiate()
	root.add_child(main_node)

func _process(delta: float) -> bool:
	frame_count += 1
	var pb: PlaybackController = main_node.get_node("PlaybackController")
	var rend: NoteRenderer = main_node.get_node("CanvasLayer/NoteRenderer")
	if pb and not pb.is_playing:
		pb.seek(2.5)
		pb.play()

	if frame_count % 30 == 0:
		print("Frame: ", frame_count, ", time: ", pb.current_time, ", visible notes: ", pb.get_visible_notes().size(), ", mm count: ", rend.multimesh.visible_instance_count)

	# Run for 90 frames (~1.5 seconds) with sustained sparkles & smoke
	if frame_count == 90:
		var img: Image = root.get_texture().get_image()
		if img and not img.is_empty():
			img.save_png("preview_glass_render.png")
			img.save_png("media/screenshot.png")
			print("Preview screenshot saved successfully to media/screenshot.png!")
		else:
			print("Viewport image was empty (headless mode without display).")
		quit(0)
		return true

	return false
