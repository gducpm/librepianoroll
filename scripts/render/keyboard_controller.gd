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

class_name KeyboardController
extends Control

signal key_pressed(pitch: int, key_center: Vector2, color: Color)
signal key_released(pitch: int)
signal user_note_on(pitch: int, velocity: int)
signal user_note_off(pitch: int)

var playback: PlaybackController

class KeyVisual:
	var pitch: int = 0
	var is_black: bool = false
	var rect: Rect2 = Rect2()
	var press_intensity: float = 0.0 # 0.0 to 1.0
	var target_intensity: float = 0.0
	var color: Color = Color(0.863, 0.208, 0.271, 1.0) # Brand #dc3545
	var color_rect: ColorRect = null
	var material: ShaderMaterial = null
	var active_holders: int = 0

var keys: Dictionary = {} # pitch -> KeyVisual
var key_rects: Array[Rect2] = []
var white_keys_count: int = 52
var min_pitch: int = 21 # A0
var max_pitch: int = 108 # C8

var key_material_shader: Shader = preload("res://shaders/key_illumination.gdshader")
var last_built_size: Vector2 = Vector2.ZERO
var is_building: bool = false

var mouse_pressed_pitch: int = -1
var freeplay_color: Color = Color(0.863, 0.208, 0.271, 1.0) # Brand #dc3545

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	build_keyboard()
	resized.connect(_on_resized)

func _on_resized() -> void:
	if size == last_built_size or is_building:
		return
	build_keyboard()

func build_keyboard() -> void:
	if is_building:
		return
	is_building = true

	# Clear existing keys
	for c in get_children():
		c.queue_free()
	keys.clear()
	key_rects.clear()
	key_rects.resize(128)
	for i in range(128):
		key_rects[i] = Rect2()

	var total_w := size.x
	var total_h := size.y
	if total_w <= 10.0:
		total_w = custom_minimum_size.x if custom_minimum_size.x > 10.0 else 1920.0
	if total_h <= 10.0:
		total_h = custom_minimum_size.y if custom_minimum_size.y > 10.0 else 210.0

	last_built_size = Vector2(total_w, total_h)

	var white_w: float = total_w / float(white_keys_count)
	var black_w: float = white_w * 0.60
	var black_h: float = total_h * 0.64

	var white_idx: int = 0

	# First pass: Create white keys
	for pitch in range(min_pitch, max_pitch + 1):
		var note_mod := pitch % 12
		var is_black := note_mod in [1, 3, 6, 8, 10]
		if not is_black:
			var kv := KeyVisual.new()
			kv.pitch = pitch
			kv.is_black = false
			var x_pos := float(white_idx) * white_w
			kv.rect = Rect2(x_pos, 0.0, white_w - 1.0, total_h)

			var cr := ColorRect.new()
			cr.position = kv.rect.position
			cr.size = kv.rect.size
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var mat := ShaderMaterial.new()
			mat.shader = key_material_shader
			mat.set_shader_parameter("is_black_key", false)
			mat.set_shader_parameter("key_size", cr.size)
			mat.set_shader_parameter("corner_radius", 4.0)
			mat.set_shader_parameter("press_intensity", 0.0)
			mat.set_shader_parameter("glow_color", Color(0.863, 0.208, 0.271, 1.0))
			cr.material = mat

			kv.color_rect = cr
			kv.material = mat
			add_child(cr)
			keys[pitch] = kv
			key_rects[pitch] = kv.rect

			white_idx += 1

	# Second pass: Create black keys (placed on top)
	for pitch in range(min_pitch, max_pitch + 1):
		var note_mod := pitch % 12
		var is_black := note_mod in [1, 3, 6, 8, 10]
		if is_black:
			# Find preceding white key
			var prev_pitch := pitch - 1
			if keys.has(prev_pitch):
				var prev_kv: KeyVisual = keys[prev_pitch]
				var kv := KeyVisual.new()
				kv.pitch = pitch
				kv.is_black = true
				var x_pos := prev_kv.rect.end.x - (black_w * 0.5)
				kv.rect = Rect2(x_pos, 0.0, black_w, black_h)

				var cr := ColorRect.new()
				cr.position = kv.rect.position
				cr.size = kv.rect.size
				cr.z_index = 2 # On top of white keys
				cr.mouse_filter = Control.MOUSE_FILTER_IGNORE

				var mat := ShaderMaterial.new()
				mat.shader = key_material_shader
				mat.set_shader_parameter("is_black_key", true)
				mat.set_shader_parameter("key_size", cr.size)
				mat.set_shader_parameter("corner_radius", 4.5)
				mat.set_shader_parameter("press_intensity", 0.0)
				mat.set_shader_parameter("glow_color", Color(0.863, 0.208, 0.271, 1.0))
				cr.material = mat

				kv.color_rect = cr
				kv.material = mat
				add_child(cr)
				keys[pitch] = kv
				key_rects[pitch] = kv.rect

	update_key_colors()
	is_building = false

func _process(delta: float) -> void:
	# Smooth delta-time spring release decay for visual keys
	for pitch in keys:
		var kv: KeyVisual = keys[pitch]
		if kv.press_intensity > 0.0 or kv.target_intensity > 0.0:
			if kv.press_intensity != kv.target_intensity:
				kv.press_intensity = move_toward(kv.press_intensity, kv.target_intensity, delta * 16.0)
				if kv.material:
					kv.material.set_shader_parameter("press_intensity", kv.press_intensity)

func update_key_colors() -> void:
	if not playback:
		return
	for pitch in keys:
		var kv: KeyVisual = keys[pitch]
		var dummy_note := NoteData.new(pitch)
		var col: Color = playback.get_note_color(dummy_note)
		kv.color = col
		if kv.material and kv.target_intensity <= 0.0:
			kv.material.set_shader_parameter("glow_color", col)

func press_key(pitch: int, color: Color = Color(0.863, 0.208, 0.271, 1.0), _velocity: int = 100) -> void:
	if not keys.has(pitch):
		return
	var kv: KeyVisual = keys[pitch]
	kv.active_holders += 1
	kv.press_intensity = 1.0
	kv.target_intensity = 1.0
	kv.color = color
	if kv.material:
		kv.material.set_shader_parameter("press_intensity", 1.0)
		kv.material.set_shader_parameter("glow_color", color)

	var center := Vector2(kv.rect.position.x + kv.rect.size.x * 0.5, global_position.y)
	key_pressed.emit(pitch, center, color)

func release_key(pitch: int) -> void:
	if not keys.has(pitch):
		return
	var kv: KeyVisual = keys[pitch]
	kv.active_holders = maxi(0, kv.active_holders - 1)
	if kv.active_holders == 0:
		kv.target_intensity = 0.0
		if kv.material:
			kv.material.set_shader_parameter("glow_color", kv.color)
		key_released.emit(pitch)

func get_pitch_at_pos(pos: Vector2) -> int:
	# First check black keys (they are drawn on top)
	for pitch in keys:
		var kv: KeyVisual = keys[pitch]
		if kv.is_black and kv.rect.has_point(pos):
			return pitch
	# Then check white keys
	for pitch in keys:
		var kv: KeyVisual = keys[pitch]
		if not kv.is_black and kv.rect.has_point(pos):
			return pitch
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			var p := get_pitch_at_pos(event.position)
			if p != -1:
				mouse_pressed_pitch = p
				user_note_on.emit(p, 110)
		else:
			if mouse_pressed_pitch != -1:
				user_note_off.emit(mouse_pressed_pitch)
				mouse_pressed_pitch = -1
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var p := get_pitch_at_pos(event.position)
		if p != mouse_pressed_pitch:
			if mouse_pressed_pitch != -1:
				user_note_off.emit(mouse_pressed_pitch)
			mouse_pressed_pitch = p
			if p != -1:
				user_note_on.emit(p, 110)

func reset_all_keys() -> void:
	if mouse_pressed_pitch != -1:
		mouse_pressed_pitch = -1
	for pitch in keys:
		var kv: KeyVisual = keys[pitch]
		kv.active_holders = 0
		kv.press_intensity = 0.0
		kv.target_intensity = 0.0
		if kv.material:
			kv.material.set_shader_parameter("press_intensity", 0.0)
		key_released.emit(pitch)

func get_key_rect(pitch: int) -> Rect2:
	if pitch >= 0 and pitch < key_rects.size():
		return key_rects[pitch]
	return Rect2()

func get_key_center_x(pitch: int) -> float:
	if pitch >= 0 and pitch < key_rects.size():
		var r := key_rects[pitch]
		return r.position.x + r.size.x * 0.5
	return 0.0
