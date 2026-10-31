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

class_name NoteRenderer
extends Control

@export var playback: PlaybackController
@export var keyboard: KeyboardController

# Visual parameters
var pixels_per_second: float = 680.0
var hdr_glow_intensity: float = 1.2
var bubble_density: float = 2.0
var glass_refraction: float = 1.2

var brand_crimson: Color = Color(0.863, 0.208, 0.271, 1.0) # #dc3545
var brand_pink: Color = Color(1.0, 0.45, 0.65, 1.0) # Neon Pink Accent

var mm_instance: MultiMeshInstance2D
var multimesh: MultiMesh
var glass_material: ShaderMaterial
var glass_shader: Shader = preload("res://shaders/note_glass.gdshader")

var export_override_delta: float = 0.0
var global_time: float = 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_init_multimesh()

const MAX_NOTE_INSTANCES: int = 1500

func _init_multimesh() -> void:
	mm_instance = MultiMeshInstance2D.new()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true

	# Unit quad with top-left pivot (0,0) to (1,1)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.5, 0.5, 0.0)
	multimesh.mesh = quad

	# Pre-allocate fixed instance buffer to eliminate GPU reallocation spikes
	multimesh.instance_count = MAX_NOTE_INSTANCES
	multimesh.visible_instance_count = 0

	glass_material = ShaderMaterial.new()
	glass_material.shader = glass_shader
	glass_material.set_shader_parameter("hdr_intensity", hdr_glow_intensity)
	glass_material.set_shader_parameter("bubble_density", bubble_density)
	glass_material.set_shader_parameter("glass_refraction", glass_refraction)

	# Preload default seamless bubbles texture for 1-cycle GPU hardware sampling
	var default_tex: Texture2D = load("res://resources/textures/bubbles_cellular.tres")
	if default_tex:
		glass_material.set_shader_parameter("custom_texture", default_tex)
		glass_material.set_shader_parameter("use_custom_texture", true)

	mm_instance.material = glass_material
	mm_instance.multimesh = multimesh
	add_child(mm_instance)

func set_glow_intensity(val: float) -> void:
	hdr_glow_intensity = val
	if glass_material:
		glass_material.set_shader_parameter("hdr_intensity", val)

func set_bubble_density(val: float) -> void:
	bubble_density = val
	if glass_material:
		glass_material.set_shader_parameter("bubble_density", val)

func set_glass_refraction(val: float) -> void:
	glass_refraction = val
	if glass_material:
		glass_material.set_shader_parameter("glass_refraction", val)

func set_screen_space_locked(is_locked: bool) -> void:
	if glass_material:
		glass_material.set_shader_parameter("use_screen_space", is_locked)

func set_custom_texture(tex: Texture2D) -> void:
	if glass_material:
		if tex != null:
			glass_material.set_shader_parameter("custom_texture", tex)
			glass_material.set_shader_parameter("use_custom_texture", true)
		else:
			# Fallback to default seamless texture
			var default_tex: Texture2D = load("res://resources/textures/bubbles_cellular.tres")
			glass_material.set_shader_parameter("custom_texture", default_tex)
			glass_material.set_shader_parameter("use_custom_texture", true)

func load_texture_from_file(path: String) -> bool:
	var img := Image.load_from_file(path)
	if not img or img.is_empty():
		push_error("Failed to load image from: " + path)
		return false
	var tex := ImageTexture.create_from_image(img)
	set_custom_texture(tex)
	print("Loaded custom glass texture: ", path)
	return true

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not visible:
		if multimesh:
			multimesh.visible_instance_count = 0
		return
	if not playback or not keyboard or not multimesh:
		return

	var view_h := size.y
	if view_h <= 10.0:
		view_h = 870.0 # Standard fallback above keyboard

	# Dynamically sync the playback controller's lookahead window so notes perfectly spawn exactly at the top edge of the NoteRenderer
	playback.fall_duration = view_h / maxf(pixels_per_second, 10.0)

	var current_time := playback.current_time
	var visible_notes := playback.get_visible_notes()

	var count: int = mini(visible_notes.size(), MAX_NOTE_INSTANCES)
	multimesh.visible_instance_count = count
	if count == 0:
		return
		
	var step_delta := export_override_delta if export_override_delta > 0.0 else _delta
	global_time += step_delta

	if glass_material:
		glass_material.set_shader_parameter("strike_y", view_h)
		glass_material.set_shader_parameter("custom_time", current_time)
		glass_material.set_shader_parameter("global_time", global_time)

	var fall_speed := pixels_per_second
	var tracks := playback.parser.tracks
	var track_count: int = tracks.size()
	const VEL_FACTOR: float = 0.35

	for i in range(count):
		var note: NoteData = visible_notes[i]
		var tidx: int = note.track_idx
		if tidx < track_count and tracks[tidx].is_muted:
			continue

		var key_rect := keyboard.get_key_rect(note.pitch)
		if key_rect.size.x <= 0.0:
			continue

		var note_h: float = maxf(12.0, (note.end_time - note.start_time) * fall_speed)
		var note_y: float = view_h - (note.end_time - current_time) * fall_speed
		var is_active: float = 1.0 if (current_time >= note.start_time and current_time <= note.end_time) else 0.0

		var x_pos := key_rect.position.x
		var note_w := key_rect.size.x
		var aspect := note_h / maxf(note_w, 1.0)

		var note_color: Color = playback.get_note_color(note)
		var xform := Transform2D(0.0, Vector2(note_w, note_h), 0.0, Vector2(x_pos, note_y))
		multimesh.set_instance_transform_2d(i, xform)
		multimesh.set_instance_color(i, note_color)
		multimesh.set_instance_custom_data(i, Color(VEL_FACTOR, is_active, aspect, 0.0))
