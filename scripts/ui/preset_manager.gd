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

class_name PresetManager
extends RefCounted

class ThemePreset:
	var name: String = "Crimson Neon"
	var primary_color: Color = Color(0.863, 0.208, 0.271, 1.0) # #dc3545 Brand
	var secondary_color: Color = Color(1.0, 0.45, 0.65, 1.0)   # Neon Pink
	var accent_color: Color = Color(1.0, 0.75, 0.85, 1.0)      # White-pink hot core
	var background_color: Color = Color(0.04, 0.04, 0.06, 1.0)
	var glow_intensity: float = 2.4
	var fall_speed: float = 380.0
	var particle_density: float = 1.0

	func _init(p_name: String, p_prim: Color, p_sec: Color, p_acc: Color, p_glow: float = 2.4) -> void:
		name = p_name
		primary_color = p_prim
		secondary_color = p_sec
		accent_color = p_acc
		glow_intensity = p_glow

static func get_all_presets() -> Array[ThemePreset]:
	return [
		ThemePreset.new(
			"Crimson Neon (#dc3545)",
			Color(0.863, 0.208, 0.271, 1.0),
			Color(1.0, 0.45, 0.65, 1.0),
			Color(1.0, 0.8, 0.9, 1.0),
			3.2
		),
		ThemePreset.new(
			"Rousseau Glass (Gold & Ice Blue)",
			Color(1.0, 0.72, 0.08, 1.0), # Warm Amber Gold (left hand)
			Color(0.0, 0.75, 1.0, 1.0),  # Luminous Ice Blue (right hand)
			Color(1.0, 0.95, 0.8, 1.0),
			3.4
		),
		ThemePreset.new(
			"Cyberpunk Neon",
			Color(0.0, 0.94, 1.0, 1.0),
			Color(1.0, 0.0, 0.5, 1.0),
			Color(0.6, 0.3, 1.0, 1.0),
			3.0
		),
		ThemePreset.new(
			"Golden Classic",
			Color(1.0, 0.76, 0.03, 1.0),
			Color(1.0, 0.6, 0.0, 1.0),
			Color(1.0, 0.95, 0.8, 1.0),
			2.0
		),
		ThemePreset.new(
			"Synthwave Sunset",
			Color(1.0, 0.34, 0.13, 1.0),
			Color(0.91, 0.12, 0.39, 1.0),
			Color(0.25, 0.32, 0.71, 1.0),
			2.3
		),
		ThemePreset.new(
			"Emerald Laser",
			Color(0.0, 0.9, 0.45, 1.0),
			Color(0.0, 0.7, 0.85, 1.0),
			Color(0.8, 1.0, 0.9, 1.0),
			2.2
		),
	]
