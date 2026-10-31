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

class_name MainCoordinator
extends Node2D

@onready var playback: PlaybackController = $PlaybackController
@onready var note_renderer: NoteRenderer = $CanvasLayer/NoteRenderer
@onready var keyboard: KeyboardController = $CanvasLayer/Keyboard
@onready var vfx_manager: VfxManager = $CanvasLayer/VFXManager
@onready var synth_engine: SynthEngine = $SynthEngine
@onready var live_midi: LiveMidiHandler = $LiveMidiHandler
@onready var studio_ui: UIController = $CanvasLayer/StudioUI
@onready var world_env: WorldEnvironment = $WorldEnvironment
var video_exporter: VideoExporter

func _ready() -> void:
	video_exporter = VideoExporter.new()
	add_child(video_exporter)
	studio_ui.video_exporter = video_exporter
	
	_setup_world_environment()
	_connect_subsystems()

	# Load demo song on launch so user immediately experiences glowing visualizer & audio
	if FileAccess.file_exists("res://default.mid"):
		playback.load_midi_file("res://default.mid")
	else:
		playback.load_demo()

func _setup_world_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06, 1.0)
	
	# Push the built-in solid background backwards so Z-index -1 particles can render over it
	var bg_rect: ColorRect = get_node_or_null("CanvasLayer/Background")
	if bg_rect:
		bg_rect.z_index = -10

	# Forward+ Real-Time HDR Glow / Bloom
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_strength = 1.15
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 1.8

	# Tone mapping for rich filmic contrast
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05

	world_env.environment = env

func _connect_subsystems() -> void:
	if playback.note_started.is_connected(_on_playback_note_started):
		return
	
	vfx_manager.playback = playback
	keyboard.playback = playback
	
	# Connect Playback events to Visuals and Audio
	playback.note_started.connect(_on_playback_note_started)
	playback.note_ended.connect(_on_playback_note_ended)
	playback.playback_state_changed.connect(_on_playback_state_changed)
	playback.song_loaded.connect(_on_song_loaded)
	playback.song_reset.connect(_on_song_reset)
	playback.color_settings_changed.connect(keyboard.update_key_colors)

	# Connect Keyboard physical strikes to VFX spark showers
	keyboard.key_pressed.connect(_on_key_pressed)
	keyboard.key_released.connect(_on_key_released)
	keyboard.user_note_on.connect(_on_user_note_on)
	keyboard.user_note_off.connect(_on_user_note_off)

	# Connect Live MIDI inputs to Visuals and Audio
	if live_midi:
		live_midi.live_note_on.connect(_on_live_note_on)
		live_midi.live_note_off.connect(_on_live_note_off)

func _on_playback_note_started(note: NoteData) -> void:
	if note.track_idx < playback.parser.tracks.size() and playback.parser.tracks[note.track_idx].is_muted:
		return

	var note_color: Color = playback.get_note_color(note)
	keyboard.press_key(note.pitch, note_color, note.velocity)
	if playback.is_playing:
		synth_engine.note_on(note.pitch, note.velocity)
	else:
		synth_engine.note_preview(note.pitch, note.velocity, 0.16)

func _on_playback_note_ended(note: NoteData) -> void:
	keyboard.release_key(note.pitch)
	synth_engine.note_off(note.pitch)

func _on_key_pressed(pitch: int, key_center: Vector2, color: Color) -> void:
	var key_rect := keyboard.get_key_rect(pitch)
	var key_w: float = key_rect.size.x if key_rect.size.x > 0.0 else 24.0
	vfx_manager.start_emitter(pitch, key_center, key_w, color)

func _on_key_released(pitch: int) -> void:
	vfx_manager.stop_emitter(pitch)

func _on_user_note_on(pitch: int, velocity: int) -> void:
	var dummy := NoteData.new(pitch)
	var col: Color = playback.get_note_color(dummy)
	keyboard.press_key(pitch, col, velocity)
	synth_engine.note_on(pitch, velocity)

func _on_user_note_off(pitch: int) -> void:
	keyboard.release_key(pitch)
	synth_engine.note_off(pitch)

func _on_playback_state_changed(is_playing: bool) -> void:
	if not is_playing:
		synth_engine.all_notes_off()
		vfx_manager.clear_emitters()
	else:
		# Restart emitters for notes active at current time
		for n in playback.active_notes:
			if n.track_idx < playback.parser.tracks.size() and playback.parser.tracks[n.track_idx].is_muted:
				continue
			var note_color: Color = playback.get_note_color(n)
			var key_rect := keyboard.get_key_rect(n.pitch)
			var key_w: float = key_rect.size.x if key_rect.size.x > 0.0 else 24.0
			var center := Vector2(key_rect.position.x + key_rect.size.x * 0.5, keyboard.global_position.y)
			vfx_manager.start_emitter(n.pitch, center, key_w, note_color)

func _on_song_loaded() -> void:
	_on_song_reset()

func _on_song_reset() -> void:
	keyboard.reset_all_keys()
	synth_engine.all_notes_off()
	vfx_manager.clear_all()

func _on_live_note_on(pitch: int, velocity: int) -> void:
	# Live play from hardware USB/MIDI keyboard
	var dummy := NoteData.new(pitch)
	var col: Color = playback.get_note_color(dummy)
	keyboard.press_key(pitch, col, velocity)
	synth_engine.note_on(pitch, velocity)

func _on_live_note_off(pitch: int) -> void:
	keyboard.release_key(pitch)
	synth_engine.note_off(pitch)
