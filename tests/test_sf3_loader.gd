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
	print("--- Testing SF3 Sample Extraction ---")
	var f := FileAccess.open("res://default.sf3", FileAccess.READ)
	if not f:
		push_error("Could not open default.sf3")
		quit(1)
		return
	
	f.seek(448 + 8 + 0) # Sample 0 starts at 0
	var buf := f.get_buffer(11524)
	var stream := AudioStreamOggVorbis.load_from_buffer(buf)
	if stream:
		print("SUCCESS: Loaded AudioStreamOggVorbis! Duration: ", stream.get_length(), "s")
		quit(0)
	else:
		push_error("FAILED to load stream from buffer")
		quit(1)
