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

class_name MidiParser
extends RefCounted

class TrackInfo:
	var index: int = 0
	var name: String = "Track"
	var note_count: int = 0
	var min_pitch: int = 127
	var max_pitch: int = 0
	var color: Color = Color(0.86, 0.21, 0.27, 1.0) # #dc3545 default brand color
	var is_muted: bool = false
	var is_solo: bool = false

var notes: Array[NoteData] = []
var tracks: Array[TrackInfo] = []
var tempo_map: TempoMap = TempoMap.new()
var total_duration: float = 0.0
var max_note_duration: float = 4.0
var format: int = 1
var division: int = 480

# Load and parse MIDI file from path
func parse_file(path: String) -> bool:
	notes.clear()
	tracks.clear()
	total_duration = 0.0

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("MidiParser: Failed to open file: " + path)
		return false

	var buffer: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	return parse_buffer(buffer)

func parse_buffer(buffer: PackedByteArray) -> bool:
	if buffer.size() < 14:
		push_error("MidiParser: File too short for MIDI header")
		return false

	# Header chunk must start with 'MThd' (0x4D 0x54 0x68 0x64)
	if buffer[0] != 0x4D or buffer[1] != 0x54 or buffer[2] != 0x68 or buffer[3] != 0x64:
		push_error("MidiParser: Invalid MIDI header magic")
		return false

	var header_length: int = _read_u32(buffer, 4)
	format = _read_u16(buffer, 8)
	var num_tracks: int = _read_u16(buffer, 10)
	var raw_division: int = _read_u16(buffer, 12)

	if (raw_division & 0x8000) != 0:
		# SMTPE timecode (rare), fallback to 480
		division = 480
	else:
		division = raw_division

	tempo_map = TempoMap.new(division)

	var offset: int = 8 + header_length
	var track_buffers: Array[PackedByteArray] = []

	# Scan all chunks
	while offset + 8 <= buffer.size():
		var chunk_id := buffer.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_len := _read_u32(buffer, offset + 4)
		offset += 8

		if offset + chunk_len > buffer.size():
			chunk_len = buffer.size() - offset

		if chunk_id == "MTrk":
			track_buffers.append(buffer.slice(offset, offset + chunk_len))

		offset += chunk_len

	# First pass: parse meta events across all tracks to build full TempoMap
	for track_data in track_buffers:
		_parse_track_tempo_pass(track_data)

	# Second pass: parse notes with exact timing
	for i in range(track_buffers.size()):
		var t_info := TrackInfo.new()
		t_info.index = i
		t_info.name = "Track %d" % (i + 1)
		# Assign default color palette based on track index, anchored around #dc3545
		t_info.color = _get_default_track_color(i)
		tracks.append(t_info)

		_parse_track_notes_pass(track_buffers[i], i, t_info)

	# Calculate total duration and max note duration
	max_note_duration = 0.0
	for n in notes:
		if n.end_time > total_duration:
			total_duration = n.end_time
		var dur := n.end_time - n.start_time
		if dur > max_note_duration:
			max_note_duration = dur
	if max_note_duration <= 0.0:
		max_note_duration = 4.0

	# Sort notes by start_time for optimal rendering / spatial search
	notes.sort_custom(func(a: NoteData, b: NoteData) -> bool:
		return a.start_time < b.start_time
	)

	return true

func _parse_track_tempo_pass(data: PackedByteArray) -> void:
	var pos: int = 0
	var current_tick: int = 0
	var running_status: int = 0

	while pos < data.size():
		var delta_res := _read_vlq(data, pos)
		current_tick += delta_res[0]
		pos = delta_res[1]

		if pos >= data.size():
			break

		var status := data[pos]
		if (status & 0x80) != 0:
			pos += 1
			running_status = status
		else:
			status = running_status

		var event_type := status & 0xF0

		if status == 0xFF: # Meta event
			if pos >= data.size():
				break
			var meta_type := data[pos]
			pos += 1
			var len_res := _read_vlq(data, pos)
			var meta_len: int = len_res[0]
			pos = len_res[1]

			if meta_type == 0x51 and meta_len == 3 and pos + 3 <= data.size(): # Set Tempo
				var micros := (int(data[pos]) << 16) | (int(data[pos + 1]) << 8) | int(data[pos + 2])
				tempo_map.add_tempo_event(current_tick, micros)
			elif meta_type == 0x58 and meta_len >= 2 and pos + 2 <= data.size(): # Time Signature
				var num := int(data[pos])
				var den := 1 << int(data[pos + 1])
				tempo_map.add_time_signature_event(current_tick, num, den)

			pos += meta_len

		elif status == 0xF0 or status == 0xF7: # SysEx
			var len_res := _read_vlq(data, pos)
			pos = len_res[1] + len_res[0]
		else:
			# Channel events
			if event_type == 0xC0 or event_type == 0xD0: # 1 data byte
				pos += 1
			else: # 2 data bytes
				pos += 2

func _parse_track_notes_pass(data: PackedByteArray, track_idx: int, t_info: TrackInfo) -> void:
	var pos: int = 0
	var current_tick: int = 0
	var running_status: int = 0

	# Active notes being held: key is (channel << 8) | pitch, value is [start_tick, velocity]
	var active_notes: Dictionary = {}

	while pos < data.size():
		var delta_res := _read_vlq(data, pos)
		current_tick += delta_res[0]
		pos = delta_res[1]

		if pos >= data.size():
			break

		var status := data[pos]
		if (status & 0x80) != 0:
			pos += 1
			running_status = status
		else:
			status = running_status

		var channel := status & 0x0F
		var event_type := status & 0xF0

		if status == 0xFF: # Meta event
			if pos >= data.size():
				break
			var meta_type := data[pos]
			pos += 1
			var len_res := _read_vlq(data, pos)
			var meta_len: int = len_res[0]
			pos = len_res[1]

			if meta_type == 0x03 and meta_len > 0 and pos + meta_len <= data.size():
				t_info.name = data.slice(pos, pos + meta_len).get_string_from_utf8()

			pos += meta_len

		elif status == 0xF0 or status == 0xF7:
			var len_res := _read_vlq(data, pos)
			pos = len_res[1] + len_res[0]

		elif event_type == 0x90: # Note On
			if pos + 1 < data.size():
				var pitch := int(data[pos])
				var vel := int(data[pos + 1])
				pos += 2

				var key := (channel << 8) | pitch
				if vel > 0:
					# If already active, close previous note
					if active_notes.has(key):
						var prev = active_notes[key]
						_add_note(track_idx, channel, pitch, prev[0], current_tick, prev[1], t_info)
					active_notes[key] = [current_tick, vel]
				else:
					# Note on with velocity 0 is Note Off
					if active_notes.has(key):
						var prev = active_notes[key]
						active_notes.erase(key)
						_add_note(track_idx, channel, pitch, prev[0], current_tick, prev[1], t_info)

		elif event_type == 0x80: # Note Off
			if pos + 1 < data.size():
				var pitch := int(data[pos])
				pos += 2
				var key := (channel << 8) | pitch
				if active_notes.has(key):
					var prev = active_notes[key]
					active_notes.erase(key)
					_add_note(track_idx, channel, pitch, prev[0], current_tick, prev[1], t_info)

		elif event_type == 0xC0 or event_type == 0xD0:
			pos += 1
		else:
			pos += 2

	# Close any unclosed notes at end of track
	for key in active_notes:
		var prev = active_notes[key]
		var pitch: int = key & 0xFF
		var channel: int = (key >> 8) & 0x0F
		_add_note(track_idx, channel, pitch, prev[0], current_tick + division, prev[1], t_info)

func _add_note(track_idx: int, channel: int, pitch: int, start_tick: int, end_tick: int, vel: int, t_info: TrackInfo) -> void:
	var start_sec := tempo_map.tick_to_seconds(start_tick)
	var end_sec := tempo_map.tick_to_seconds(maxi(end_tick, start_tick + 10))
	var note := NoteData.new(pitch, start_sec, end_sec, vel, track_idx, channel)
	notes.append(note)

	t_info.note_count += 1
	if pitch < t_info.min_pitch:
		t_info.min_pitch = pitch
	if pitch > t_info.max_pitch:
		t_info.max_pitch = pitch

func _read_u16(buffer: PackedByteArray, offset: int) -> int:
	return (int(buffer[offset]) << 8) | int(buffer[offset + 1])

func _read_u32(buffer: PackedByteArray, offset: int) -> int:
	return (int(buffer[offset]) << 24) | (int(buffer[offset + 1]) << 16) | (int(buffer[offset + 2]) << 8) | int(buffer[offset + 3])

func _read_vlq(buffer: PackedByteArray, offset: int) -> Array[int]:
	var value: int = 0
	var pos: int = offset

	for i in range(4):
		if pos >= buffer.size():
			break
		var byte := int(buffer[pos])
		pos += 1
		value = (value << 7) | (byte & 0x7F)
		if (byte & 0x80) == 0:
			break

	return [value, pos]

func _get_default_track_color(idx: int) -> Color:
	# Primary brand color #dc3545 (Bootstrap Crimson Danger) as anchor
	var palette: Array[Color] = [
		Color(0.863, 0.208, 0.271, 1.0), # #dc3545 Crimson Red
		Color(1.0, 0.419, 0.592, 1.0),   # Neon Rose / Coral Pink
		Color(0.992, 0.435, 0.278, 1.0), # Tangerine Ember
		Color(0.851, 0.353, 0.949, 1.0), # Electric Violet
		Color(0.247, 0.702, 0.996, 1.0), # Cyan Laser
		Color(0.196, 0.843, 0.604, 1.0), # Emerald Neon
		Color(1.0, 0.835, 0.309, 1.0),   # Solar Amber
		Color(0.553, 0.451, 0.996, 1.0), # Royal Indigo
	]
	return palette[idx % palette.size()]

# Built-in generator for rich demo song (Moonlight Sonata arpeggios + melody)
func create_demo_song() -> void:
	notes.clear()
	tracks.clear()
	total_duration = 0.0

	division = 480
	tempo_map = TempoMap.new(division)
	tempo_map.add_tempo_event(0, 857142) # ~70 BPM Adagio sostenuto

	var t1 := TrackInfo.new()
	t1.index = 0
	t1.name = "Right Hand (Melody & Arpeggios)"
	t1.color = Color(0.863, 0.208, 0.271, 1.0) # #dc3545 Brand Crimson
	tracks.append(t1)

	var t2 := TrackInfo.new()
	t2.index = 1
	t2.name = "Left Hand (Bass Octaves)"
	t2.color = Color(1.0, 0.45, 0.65, 1.0) # Neon Pink Accent
	tracks.append(t2)

	# Generate Moonlight Sonata style arpeggios
	# Triplet arpeggios: C#3, G#3, C#4, E4 etc.
	var pattern_chords = [
		# Bar 1: C# minor
		[49, 56, 61, 64], # C#3, G#3, C#4, E4
		[49, 56, 61, 64],
		[49, 56, 61, 64],
		[49, 56, 61, 64],
		# Bar 2: B / C# minor
		[47, 56, 59, 64], # B2, G#3, B3, E4
		[47, 56, 59, 64],
		[45, 57, 61, 64], # A2, A3, C#4, E4
		[45, 57, 61, 64],
		# Bar 3: F# minor
		[42, 54, 61, 66], # F#2, F#3, C#4, F#4
		[42, 54, 61, 66],
		[44, 56, 62, 68], # G#2, G#3, D4, G#4
		[44, 56, 62, 68],
		# Bar 4: Melody entrance
		[49, 56, 61, 64],
		[49, 56, 61, 64],
		[49, 56, 61, 64],
		[49, 56, 61, 64],
	]

	var beat_duration: float = 60.0 / 70.0 # ~0.857s per beat
	var triplet_duration: float = beat_duration / 3.0

	var time_cursor: float = 0.5
	var bar_idx: int = 0

	for chord in pattern_chords:
		# Play 3 triplet notes per beat: chord[1], chord[2], chord[3]
		for step in range(3):
			var pitch: int = chord[1 + (step % 3)]
			var n := NoteData.new(pitch, time_cursor, time_cursor + triplet_duration * 1.8, 75, 0, 0)
			notes.append(n)
			t1.note_count += 1
			time_cursor += triplet_duration

		# Bass notes on beats
		if bar_idx % 4 == 0:
			var bass_pitch: int = chord[0]
			var n_bass1 := NoteData.new(bass_pitch, time_cursor - beat_duration, time_cursor - beat_duration + beat_duration * 3.8, 90, 1, 1)
			var n_bass2 := NoteData.new(bass_pitch - 12, time_cursor - beat_duration, time_cursor - beat_duration + beat_duration * 3.8, 85, 1, 1)
			notes.append(n_bass1)
			notes.append(n_bass2)
			t2.note_count += 2

		bar_idx += 1

	# Add the iconic dotted melody: G#4 ... G#4 ... G#4 ...
	var melody_notes = [
		[68, 4.0 * beat_duration + 0.5, 1.5 * beat_duration, 105], # G#4
		[68, 5.5 * beat_duration + 0.5, 0.5 * beat_duration, 100],
		[68, 6.0 * beat_duration + 0.5, 2.0 * beat_duration, 110],
		[69, 8.0 * beat_duration + 0.5, 1.5 * beat_duration, 105], # A4
		[68, 9.5 * beat_duration + 0.5, 0.5 * beat_duration, 100],
		[67, 10.0 * beat_duration + 0.5, 1.0 * beat_duration, 100], # G4
		[68, 11.0 * beat_duration + 0.5, 2.0 * beat_duration, 110], # G#4
	]

	for m in melody_notes:
		var n_mel := NoteData.new(m[0], m[1], m[1] + m[2], m[3], 0, 0)
		notes.append(n_mel)
		t1.note_count += 1

	total_duration = time_cursor + 2.0
	max_note_duration = 0.0
	for n in notes:
		var dur := n.end_time - n.start_time
		if dur > max_note_duration:
			max_note_duration = dur
	if max_note_duration <= 0.0:
		max_note_duration = 4.0

	notes.sort_custom(func(a: NoteData, b: NoteData) -> bool:
		return a.start_time < b.start_time
	)
