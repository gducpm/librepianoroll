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
	print("--- Testing Piano SF3 Extraction ---")
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open("res://default.sf3", FileAccess.READ)
	if not f:
		push_error("Could not open res://default.sf3")
		quit(1)
		return

	var file_len := f.get_length()
	print("File size: ", file_len, " bytes")

	# Find sdta and pdta
	f.seek(12)
	var smpl_offset := 0
	var shdr_offset := 0
	var shdr_size := 0
	var is_sf3 := false

	while f.get_position() < file_len - 8:
		var chunk_id := f.get_buffer(4).get_string_from_ascii()
		var chunk_size := f.get_32()
		var next_pos := f.get_position() + chunk_size
		if chunk_size % 2 == 1:
			next_pos += 1

		if chunk_id == "LIST":
			var list_type := f.get_buffer(4).get_string_from_ascii()
			if list_type == "sdta":
				var sub_id := f.get_buffer(4).get_string_from_ascii()
				var sub_sz := f.get_32()
				if sub_id == "smpl":
					smpl_offset = f.get_position()
					# Check if Ogg Vorbis
					var magic := f.get_buffer(4).get_string_from_ascii()
					is_sf3 = (magic == "OggS")
					print("Found smpl at ", smpl_offset, " size=", sub_sz, " is_sf3=", is_sf3)
			elif list_type == "pdta":
				while f.get_position() < next_pos - 8:
					var p_id := f.get_buffer(4).get_string_from_ascii()
					var p_sz := f.get_32()
					var p_next := f.get_position() + p_sz
					if p_sz % 2 == 1:
						p_next += 1
					if p_id == "shdr":
						shdr_offset = f.get_position()
						shdr_size = p_sz
						print("Found shdr at ", shdr_offset, " size=", shdr_size)
					f.seek(p_next)
		f.seek(next_pos)

	assert(smpl_offset > 0, "smpl chunk not found")
	assert(shdr_offset > 0, "shdr chunk not found")

	var sample_count := int(shdr_size / 46)
	print("Total samples in SoundFont: ", sample_count)

	var piano_samples: Dictionary = {} # root_key -> AudioStream
	f.seek(shdr_offset)

	for i in range(sample_count):
		f.seek(shdr_offset + i * 46)
		var name_bytes := f.get_buffer(20)
		var s_name := name_bytes.get_string_from_ascii().strip_edges()
		var dw_start := f.get_32()
		var dw_end := f.get_32()
		f.get_32() # start loop
		f.get_32() # end loop
		var s_rate := f.get_32()
		var orig_key := f.get_8()
		var corr := f.get_8()

		if s_name.begins_with("Piano MF") and s_name.ends_with("(L)"):
			var sz := dw_end - dw_start
			f.seek(smpl_offset + dw_start)
			var buf := f.get_buffer(sz)
			var stream = AudioStreamOggVorbis.load_from_buffer(buf)
			if stream:
				piano_samples[orig_key] = stream

	var t1 := Time.get_ticks_msec()
	print("Loaded ", piano_samples.size(), " acoustic piano root samples in ", (t1 - t0), " ms!")
	assert(piano_samples.size() > 20, "Expected at least 20 piano samples")
	print("All SF3 Piano sample tests passed!")
	quit(0)
