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

class_name SoundFontLoader
extends RefCounted

class VoiceEntry:
	var name: String = ""
	var stream: AudioStream = null
	var root_key: int = 60
	var sample_rate: int = 44100
	var fine_tune: int = 0
	var pan: float = 0.0 # -1.0 (Left) to +1.0 (Right)
	var atten_db: float = 0.0 # Total SF2 attenuation (Preset + Instrument) in dB
	
	# FluidSynth / SoundFont 2.04 ADSR Envelopes in seconds
	var attack: float = 0.001
	var hold: float = 0.0
	var decay: float = 1.0
	var sustain_db: float = 100.0
	var release: float = 0.55
	
	# Velocity range for this layer
	var vel_min: int = 0
	var vel_max: int = 127

class SoundFontData:
	var is_sf3: bool = false
	var key_lookup: Array[Array] = [] # 0..127 -> Array[VoiceEntry]

	func get_voices_for_note(pitch: int, velocity: int = 80) -> Array[VoiceEntry]:
		var p := clampi(pitch, 0, 127)
		if key_lookup.is_empty() or p >= key_lookup.size():
			return []
		var candidates: Array = key_lookup[p]
		if candidates.is_empty():
			return []
		
		# Collect all voices matching this velocity range (typically Left + Right pair)
		var matching: Array[VoiceEntry] = []
		for item in candidates:
			var entry: VoiceEntry = item as VoiceEntry
			if entry and velocity >= entry.vel_min and velocity <= entry.vel_max:
				matching.append(entry)
		
		# Fallback to nearest velocity layer if velocity falls in an unmapped gap
		if matching.is_empty():
			var best_diff := 999
			var fallback_entries: Array[VoiceEntry] = []
			for item in candidates:
				var entry: VoiceEntry = item as VoiceEntry
				if entry:
					var mid_vel := (entry.vel_min + entry.vel_max) / 2
					var diff := absi(velocity - mid_vel)
					if diff < best_diff:
						best_diff = diff
						fallback_entries = [entry]
					elif diff == best_diff:
						fallback_entries.append(entry)
			matching = fallback_entries
				
		return matching

	func get_sample_for_pitch(pitch: int) -> Dictionary:
		var voices := get_voices_for_note(pitch, 80)
		if voices.is_empty():
			return {}
		var entry: VoiceEntry = voices[0]
		var pitch_shift := float(pitch - entry.root_key) + float(entry.fine_tune) / 100.0
		var scale := pow(2.0, pitch_shift / 12.0)
		return {
			"stream": entry.stream,
			"pitch_scale": scale,
			"attack": entry.attack,
			"hold": entry.hold,
			"decay": entry.decay,
			"sustain_db": entry.sustain_db,
			"release": entry.release,
			"pan": entry.pan,
			"atten_db": entry.atten_db
		}

static func _tc_to_sec(tc: int, default_sec: float = 0.0) -> float:
	if tc == -12000:
		return default_sec
	return pow(2.0, float(tc) / 1200.0)

static func load_file(path: String) -> SoundFontData:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_warning("SoundFontLoader: Could not open file: " + path)
		return null

	var file_len := f.get_length()
	if file_len < 32:
		push_warning("SoundFontLoader: File too small: " + path)
		return null

	# Validate RIFF header
	var riff_id := f.get_buffer(4).get_string_from_ascii()
	if riff_id != "RIFF":
		push_warning("SoundFontLoader: Invalid RIFF header in " + path)
		return null

	f.get_32() # skip RIFF chunk size
	var riff_type := f.get_buffer(4).get_string_from_ascii()
	if riff_type != "sfbk":
		push_warning("SoundFontLoader: Not a SoundFont bank: " + path)
		return null

	var smpl_offset := 0
	var is_sf3 := false
	var shdr_offset := 0
	var shdr_size := 0
	var inst_offset := 0
	var inst_size := 0
	var ibag_offset := 0
	var ibag_size := 0
	var igen_offset := 0
	var igen_size := 0
	var phdr_offset := 0
	var phdr_size := 0
	var pbag_offset := 0
	var pbag_size := 0
	var pgen_offset := 0
	var pgen_size := 0

	# Scan top-level LIST chunks
	while f.get_position() < file_len - 8:
		var chunk_id := f.get_buffer(4).get_string_from_ascii()
		var chunk_sz := f.get_32()
		var chunk_end := f.get_position() + chunk_sz
		if chunk_sz % 2 == 1:
			chunk_end += 1

		if chunk_id == "LIST":
			var list_type := f.get_buffer(4).get_string_from_ascii()
			if list_type == "sdta":
				while f.get_position() < chunk_end - 8:
					var sub_id := f.get_buffer(4).get_string_from_ascii()
					var sub_sz := f.get_32()
					var sub_end := f.get_position() + sub_sz
					if sub_sz % 2 == 1:
						sub_end += 1
					if sub_id == "smpl":
						smpl_offset = f.get_position()
						var magic := f.get_buffer(4).get_string_from_ascii()
						is_sf3 = (magic == "OggS")
					f.seek(sub_end)
			elif list_type == "pdta":
				while f.get_position() < chunk_end - 8:
					var sub_id := f.get_buffer(4).get_string_from_ascii()
					var sub_sz := f.get_32()
					var sub_end := f.get_position() + sub_sz
					if sub_sz % 2 == 1:
						sub_end += 1
					if sub_id == "shdr":
						shdr_offset = f.get_position()
						shdr_size = sub_sz
					elif sub_id == "inst":
						inst_offset = f.get_position()
						inst_size = sub_sz
					elif sub_id == "ibag":
						ibag_offset = f.get_position()
						ibag_size = sub_sz
					elif sub_id == "igen":
						igen_offset = f.get_position()
						igen_size = sub_sz
					elif sub_id == "phdr":
						phdr_offset = f.get_position()
						phdr_size = sub_sz
					elif sub_id == "pbag":
						pbag_offset = f.get_position()
						pbag_size = sub_sz
					elif sub_id == "pgen":
						pgen_offset = f.get_position()
						pgen_size = sub_sz
					f.seek(sub_end)

		f.seek(chunk_end)

	if smpl_offset <= 0 or shdr_offset <= 0 or inst_offset <= 0 or phdr_offset <= 0:
		push_warning("SoundFontLoader: Incomplete SoundFont chunks in " + path)
		return null

	var sf_data := SoundFontData.new()
	sf_data.is_sf3 = is_sf3

	# Pass 1: Find Acoustic Grand Piano preset (Preset 252 or General MIDI Program 0, Bank 0)
	var preset_count := int(phdr_size / 38)
	var grand_piano_preset_idx := -1
	for i in range(preset_count):
		f.seek(phdr_offset + i * 38)
		var p_name := f.get_buffer(20).get_string_from_ascii().strip_edges()
		var preset_id := f.get_16()
		var bank_id := f.get_16()
		if preset_id == 0 and bank_id == 0 and not p_name.is_empty():
			grand_piano_preset_idx = i
			break
			
	if grand_piano_preset_idx == -1:
		for i in range(preset_count):
			f.seek(phdr_offset + i * 38)
			var p_name := f.get_buffer(20).get_string_from_ascii().strip_edges()
			if p_name.containsn("grand"):
				grand_piano_preset_idx = i
				break
				
	if grand_piano_preset_idx == -1 and preset_count > 0:
		grand_piano_preset_idx = 0

	# Pre-scan: Identify exact sample IDs required by the Grand Piano (prevents OOM)
	var needed_sample_ids := {}
	var pbag_ndx := 0
	var next_pbag_ndx := 0
	if grand_piano_preset_idx != -1:
		f.seek(phdr_offset + grand_piano_preset_idx * 38 + 24)
		pbag_ndx = f.get_16()
		if grand_piano_preset_idx < preset_count - 1:
			f.seek(phdr_offset + (grand_piano_preset_idx + 1) * 38 + 24)
			next_pbag_ndx = f.get_16()
		else:
			next_pbag_ndx = int(pbag_size / 4)
			
		for j in range(pbag_ndx, next_pbag_ndx):
			f.seek(pbag_offset + j * 4)
			var pgen_ndx := f.get_16()
			var next_pgen_ndx := 0
			if j < int(pbag_size / 4) - 1:
				f.seek(pbag_offset + (j + 1) * 4)
				next_pgen_ndx = f.get_16()
			else:
				next_pgen_ndx = int(pgen_size / 4)
				
			var inst_id := -1
			for k in range(pgen_ndx, next_pgen_ndx):
				f.seek(pgen_offset + k * 4)
				var gid := f.get_16()
				var gval := f.get_16()
				if gid == 41:
					inst_id = gval
					break
					
			if inst_id >= 0 and inst_id < int(inst_size / 22):
				f.seek(inst_offset + inst_id * 22 + 20)
				var ibag_ndx := f.get_16()
				var next_ibag_ndx := 0
				if inst_id < int(inst_size / 22) - 1:
					f.seek(inst_offset + (inst_id + 1) * 22 + 20)
					next_ibag_ndx = f.get_16()
				else:
					next_ibag_ndx = int(ibag_size / 4)
					
				for iz in range(ibag_ndx, next_ibag_ndx):
					f.seek(ibag_offset + iz * 4)
					var igen_ndx := f.get_16()
					var next_igen_ndx := 0
					if iz < int(ibag_size / 4) - 1:
						f.seek(ibag_offset + (iz + 1) * 4)
						next_igen_ndx = f.get_16()
					else:
						next_igen_ndx = int(igen_size / 4)
						
					for ig in range(igen_ndx, next_igen_ndx):
						f.seek(igen_offset + ig * 4)
						var gid := f.get_16()
						var gval := f.get_16()
						if gid == 53: # sampleID
							needed_sample_ids[gval] = true

	# Pass 2: Extract only needed sample streams (Left & Right channels)
	var sample_streams: Dictionary = {}
	var shdr_count := int(shdr_size / 46)
	for i in range(shdr_count):
		if not needed_sample_ids.is_empty() and not needed_sample_ids.has(i):
			continue
		f.seek(shdr_offset + i * 46)
		var s_name := f.get_buffer(20).get_string_from_ascii().strip_edges()
		var dw_start := f.get_32()
		var dw_end := f.get_32()
		var start_loop := f.get_32()
		var end_loop := f.get_32()
		var s_rate := f.get_32()
		var orig_key := f.get_8()
		var fine_tune := f.get_8()
		f.get_16() # link
		var _s_type := f.get_16()
		
		var stream: AudioStream = null
		if is_sf3:
			var sz := dw_end - dw_start
			if sz > 100:
				f.seek(smpl_offset + dw_start)
				var ogg = AudioStreamOggVorbis.load_from_buffer(f.get_buffer(sz))
				if ogg:
					ogg.loop = (end_loop > start_loop + 8)
					stream = ogg
		else:
			var num_words := dw_end - dw_start
			if num_words > 100:
				f.seek(smpl_offset + dw_start * 2)
				var wav := AudioStreamWAV.new()
				wav.format = AudioStreamWAV.FORMAT_16_BITS
				wav.mix_rate = s_rate
				wav.stereo = false
				wav.data = f.get_buffer(num_words * 2)
				if end_loop > start_loop + 8:
					wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
					wav.loop_begin = start_loop - dw_start
					wav.loop_end = end_loop - dw_start
				stream = wav
				
		if stream:
			sample_streams[i] = {
				"stream": stream,
				"rate": s_rate,
				"orig_key": orig_key,
				"fine_tune": fine_tune,
				"name": s_name
			}

	# Pass 3: Parse Instruments and Instrument Zones
	var inst_count := int(inst_size / 22)
	var instruments: Array = []
	for i in range(inst_count):
		f.seek(inst_offset + i * 22)
		f.get_buffer(20)
		var i_bag_idx := f.get_16()
		var next_i_bag := 0
		if i < inst_count - 1:
			f.seek(inst_offset + (i + 1) * 22 + 20)
			next_i_bag = f.get_16()
		else:
			next_i_bag = int(ibag_size / 4)
			
		var zones: Array = []
		for j in range(i_bag_idx, next_i_bag):
			f.seek(ibag_offset + j * 4)
			var i_gen_idx := f.get_16()
			var next_i_gen := 0
			if j < int(ibag_size / 4) - 1:
				f.seek(ibag_offset + (j + 1) * 4)
				next_i_gen = f.get_16()
			else:
				next_i_gen = int(igen_size / 4)
				
			var gens: Dictionary = {}
			for k in range(i_gen_idx, next_i_gen):
				f.seek(igen_offset + k * 4)
				var gen_id := f.get_16()
				var gen_val := f.get_16()
				var signed_val: int = gen_val if gen_val < 32768 else gen_val - 65536
				if gen_id == 43 or gen_id == 44:
					gens[gen_id] = [gen_val & 0xFF, (gen_val >> 8) & 0xFF]
				else:
					gens[gen_id] = signed_val
			zones.append(gens)
		instruments.append(zones)

	# Pass 4: Resolve SoundFont 2.04 Generator Hierarchy into Keyboard Lookup Table
	sf_data.key_lookup.resize(128)
	for i in range(128):
		sf_data.key_lookup[i] = []

	if grand_piano_preset_idx != -1:
		var p_global_gens := {}
		for j in range(pbag_ndx, next_pbag_ndx):
			f.seek(pbag_offset + j * 4)
			var pgen_ndx := f.get_16()
			var next_pgen_ndx := 0
			if j < int(pbag_size / 4) - 1:
				f.seek(pbag_offset + (j + 1) * 4)
				next_pgen_ndx = f.get_16()
			else:
				next_pgen_ndx = int(pgen_size / 4)
				
			var p_gens := {}
			for k in range(pgen_ndx, next_pgen_ndx):
				f.seek(pgen_offset + k * 4)
				var gen_id := f.get_16()
				var gen_val := f.get_16()
				var signed_val: int = gen_val if gen_val < 32768 else gen_val - 65536
				if gen_id == 43 or gen_id == 44:
					p_gens[gen_id] = [gen_val & 0xFF, (gen_val >> 8) & 0xFF]
				else:
					p_gens[gen_id] = signed_val
					
			# Global preset zone has no instrument ID (generator 41)
			if not p_gens.has(41):
				p_global_gens = p_gens
				continue
				
			var inst_id: int = p_gens[41]
			if inst_id < 0 or inst_id >= instruments.size():
				continue

			# Filter out slow-swelling sympathetic string pad layers (attackVolEnv > 0)
			var atk_tc: int = p_gens[34] if p_gens.has(34) else (p_global_gens[34] if p_global_gens.has(34) else -12000)
			if atk_tc > 0:
				continue

			var pk_min: int = p_gens[43][0] if p_gens.has(43) else 0
			var pk_max: int = p_gens[43][1] if p_gens.has(43) else 127
			var pv_min: int = p_gens[44][0] if p_gens.has(44) else 0
			var pv_max: int = p_gens[44][1] if p_gens.has(44) else 127

			var inst_zones: Array = instruments[inst_id]
			var i_global_gens := {}
			for iz in inst_zones:
				if not iz.has(53): # Instrument global zone has no sampleID (gen 53)
					i_global_gens = iz
					continue
					
				var ik_min: int = iz[43][0] if iz.has(43) else 0
				var ik_max: int = iz[43][1] if iz.has(43) else 127
				var iv_min: int = iz[44][0] if iz.has(44) else 0
				var iv_max: int = iz[44][1] if iz.has(44) else 127
				
				# Effective key and velocity ranges (Zone intersection)
				var eff_k_min: int = maxi(pk_min, ik_min)
				var eff_k_max: int = mini(pk_max, ik_max)
				var eff_v_min: int = maxi(pv_min, iv_min)
				var eff_v_max: int = mini(pv_max, iv_max)
				if eff_k_min > eff_k_max or eff_v_min > eff_v_max:
					continue

				var sample_id: int = iz[53]
				if not sample_streams.has(sample_id):
					continue
					
				var sdata: Dictionary = sample_streams[sample_id]
				
				# SF2 Specification Precedence:
				# Local zone replaces Global zone within level.
				# Preset generator then adds to Instrument generator.
				var get_sf2_val = func(gid: int, def_inst: int, def_preset: int = 0) -> int:
					var i_v: int = iz[gid] if iz.has(gid) else (i_global_gens[gid] if i_global_gens.has(gid) else def_inst)
					var p_v: int = p_gens[gid] if p_gens.has(gid) else (p_global_gens[gid] if p_global_gens.has(gid) else def_preset)
					return i_v + p_v

				var pan_val: int = get_sf2_val.call(17, 0, 0) # gen 17: pan (-500 to +500)
				var atten_cb: int = get_sf2_val.call(48, 0, 0) # gen 48: initialAttenuation in centibels
				var attack_val: int = get_sf2_val.call(34, -12000, 0)
				var hold_val: int = get_sf2_val.call(35, -12000, 0)
				var decay_val: int = get_sf2_val.call(36, -12000, 0)
				var sustain_val: int = get_sf2_val.call(37, 0, 0)
				var release_val: int = get_sf2_val.call(38, -1200, 0)
				
				# Overriding root key and fine tune
				var r_key: int = sdata["orig_key"]
				if iz.has(58): r_key = iz[58]
				elif i_global_gens.has(58): r_key = i_global_gens[58]
				elif p_gens.has(58): r_key = p_gens[58]
				elif p_global_gens.has(58): r_key = p_global_gens[58]

				var f_tune: int = sdata["fine_tune"]
				if iz.has(52): f_tune = iz[52]
				elif i_global_gens.has(52): f_tune = i_global_gens[52]
				elif p_gens.has(52): f_tune = p_gens[52]
				elif p_global_gens.has(52): f_tune = p_global_gens[52]

				var voice := VoiceEntry.new()
				voice.name = sdata["name"]
				voice.stream = sdata["stream"]
				voice.root_key = r_key
				voice.sample_rate = sdata["rate"]
				voice.fine_tune = f_tune
				voice.pan = clampf(float(pan_val) / 500.0, -1.0, 1.0)
				voice.atten_db = float(atten_cb) / 10.0
				voice.attack = _tc_to_sec(attack_val, 0.001)
				voice.hold = _tc_to_sec(hold_val, 0.0)
				voice.decay = _tc_to_sec(decay_val, 1.0)
				voice.sustain_db = float(sustain_val) / 10.0
				voice.release = _tc_to_sec(release_val, 0.55)
				voice.vel_min = eff_v_min
				voice.vel_max = eff_v_max

				for k in range(eff_k_min, eff_k_max + 1):
					if k >= 0 and k < 128:
						sf_data.key_lookup[k].append(voice)

	# Ensure complete 0..127 coverage via nearest-neighbor fallback
	for k in range(128):
		if sf_data.key_lookup[k].is_empty():
			var best_k := -1
			var min_dist := 999
			for other_k in range(128):
				if not sf_data.key_lookup[other_k].is_empty():
					var d := absi(k - other_k)
					if d < min_dist:
						min_dist = d
						best_k = other_k
			if best_k != -1:
				sf_data.key_lookup[k] = sf_data.key_lookup[best_k]

	print("SoundFontLoader: Successfully loaded MS Basic Grand Piano (SF2 spec compliant) from ", path)
	return sf_data
