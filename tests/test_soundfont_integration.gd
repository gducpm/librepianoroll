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
	print("--- Testing SoundFontLoader Integration ---")
	var sf := SoundFontLoader.load_file("res://default.sf3")
	assert(sf != null, "Failed to load default.sf3")
	assert(sf.samples_by_key.size() > 10, "Expected at least 10 acoustic sample keys")
	
	for test_pitch in [21, 36, 60, 72, 88, 108]:
		var res := sf.get_sample_for_pitch(test_pitch)
		assert(res.has("stream") and res.stream != null, "Failed stream lookup for pitch " + str(test_pitch))
		print("Pitch ", test_pitch, " -> mapped scale: ", res.pitch_scale)

	print("=== All SoundFont Tests Passed Successfully! ===")
	quit(0)
