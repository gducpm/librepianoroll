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
	print("Generating built-in seamless glass textures...")
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("resources/textures"):
		dir.make_dir_recursive("resources/textures")

	# 1. Water Bubbles (Cellular Distance2)
	var noise_bubbles := FastNoiseLite.new()
	noise_bubbles.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_bubbles.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2
	noise_bubbles.cellular_jitter = 0.85
	noise_bubbles.frequency = 0.015

	var tex_bubbles := NoiseTexture2D.new()
	tex_bubbles.width = 512
	tex_bubbles.height = 512
	tex_bubbles.seamless = true
	tex_bubbles.noise = noise_bubbles
	ResourceSaver.save(tex_bubbles, "res://resources/textures/bubbles_cellular.tres")

	# 2. Cracked Ice (Cellular Distance2-Sub)
	var noise_ice := FastNoiseLite.new()
	noise_ice.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_ice.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	noise_ice.cellular_jitter = 0.95
	noise_ice.frequency = 0.02

	var tex_ice := NoiseTexture2D.new()
	tex_ice.width = 512
	tex_ice.height = 512
	tex_ice.seamless = true
	tex_ice.noise = noise_ice
	ResourceSaver.save(tex_ice, "res://resources/textures/cracked_ice.tres")

	# 3. Marble Caustics (Perlin + Cellular blend)
	var noise_caustic := FastNoiseLite.new()
	noise_caustic.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_caustic.fractal_octaves = 4
	noise_caustic.frequency = 0.018

	var tex_caustic := NoiseTexture2D.new()
	tex_caustic.width = 512
	tex_caustic.height = 512
	tex_caustic.seamless = true
	tex_caustic.noise = noise_caustic
	ResourceSaver.save(tex_caustic, "res://resources/textures/marble_caustic.tres")

	print("Successfully generated and saved seamless glass textures!")
	quit(0)
