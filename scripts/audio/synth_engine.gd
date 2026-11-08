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

class_name SynthEngine
extends Node

## High-performance FluidSynth SoundFont synthesis engine streamed natively into Godot's audio bus.
@export var volume_linear: float = 1.0

var fs = null
var soundfont_loaded: bool = false
var sf_id: int = -1

var player: AudioStreamPlayer = null
var generator: AudioStreamGenerator = null
var playback: AudioStreamGeneratorPlayback = null

func _ready() -> void:
	_init_godot_stream()
	_init_fluidsynth()

func _init_godot_stream() -> void:
	generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.15 # 150ms buffer provides rock-solid underrun protection while preserving responsive live preview

	player = AudioStreamPlayer.new()
	player.stream = generator
	player.bus = "Master"
	add_child(player)
	player.play()

	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

func _init_fluidsynth() -> void:
	if not ClassDB.class_exists("FluidSynthEngine"):
		printerr("SynthEngine: FluidSynthEngine native extension is not available in ClassDB.")
		return

	fs = ClassDB.instantiate("FluidSynthEngine")
	if not fs:
		printerr("SynthEngine: Failed to instantiate FluidSynthEngine.")
		return

	# Initialize FluidSynth with MuseScore base gain (1.0 = full dynamic range) and dynamic sample loading (fast load, zero OOM)
	var initial_gain: float = clampf(volume_linear, 0.05, 2.0)
	var ok: bool = fs.init_synth(initial_gain)
	if ok:
		print("SynthEngine: Native FluidSynth DSP initialized successfully.")
	else:
		printerr("SynthEngine: Failed to initialize FluidSynth DSP.")

	# Auto-load SoundFont (MS Basic Grand Piano)
	var sf_path: String = ""
	if FileAccess.file_exists("res://default.sf3"):
		sf_path = ProjectSettings.globalize_path("res://default.sf3")
	elif FileAccess.file_exists("res://default.sf2"):
		sf_path = ProjectSettings.globalize_path("res://default.sf2")

	if sf_path != "":
		load_soundfont(sf_path)

func _process(_delta: float) -> void:
	if playback and fs and soundfont_loaded:
		var frames: int = playback.get_frames_available()
		if frames > 0:
			var buffer: PackedVector2Array = fs.render_frames(frames)
			playback.push_buffer(buffer)

func load_soundfont(path: String) -> bool:
	if not fs:
		return false
	var abs_path: String = path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)

	sf_id = fs.load_soundfont(abs_path)
	if sf_id > 0:
		soundfont_loaded = true
		print("SynthEngine: FluidSynth loaded SoundFont: ", abs_path, " [SFID: ", sf_id, "]")
		return true
	else:
		printerr("SynthEngine: Failed to load SoundFont: ", abs_path)
		return false

func note_on(pitch: int, velocity: int = 100) -> void:
	if fs and soundfont_loaded:
		fs.note_on(0, clampi(pitch, 0, 127), clampi(velocity, 0, 127))

func note_off(pitch: int) -> void:
	if fs and soundfont_loaded:
		fs.note_off(0, clampi(pitch, 0, 127))

func note_preview(pitch: int, velocity: int = 100, duration: float = 0.18) -> void:
	note_on(pitch, velocity)
	if is_inside_tree():
		var timer := get_tree().create_timer(duration)
		timer.timeout.connect(func(): note_off(pitch))

func all_notes_off() -> void:
	if fs:
		fs.all_notes_off(-1)

func set_volume(vol: float) -> void:
	volume_linear = clampf(vol, 0.0, 2.0)
	if fs:
		fs.set_gain(clampf(volume_linear, 0.0, 2.0))

func pitch_bend(value: int) -> void:
	if fs:
		fs.pitch_bend(0, clampi(value, 0, 16383))

func control_change(controller: int, value: int) -> void:
	if fs:
		fs.control_change(0, clampi(controller, 0, 127), clampi(value, 0, 127))

func _exit_tree() -> void:
	if fs:
		fs.close()
		fs = null
