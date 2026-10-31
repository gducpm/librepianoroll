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

class_name VfxManager
extends Node2D

var sim_time: float = 0.0
var playback: PlaybackController
var saber_mode: int = 2 # 0: Off, 1: Straight, 2: Electric Static
var export_override_delta: float = 0.0

class BubbleDroplet:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var radius: float = 4.0
	var life: float = 1.0
	var max_life: float = 1.0
	var wobble_seed: float = 0.0

class FluidMist:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var size: float = 3.0
	var life: float = 0.8
	var max_life: float = 0.8

class SmokeParticle:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var radius: float = 12.0
	var max_radius: float = 48.0
	var life: float = 1.3
	var max_life: float = 1.3
	var wobble_seed: float = 0.0

class SustainedEmitter:
	var pitch: int = 0
	var center: Vector2 = Vector2.ZERO
	var width: float = 24.0
	var color: Color = Color.WHITE
	var droplet_timer: float = 0.0
	var mist_timer: float = 0.0
	var smoke_timer: float = 0.0

var active_droplets: Array[BubbleDroplet] = []
var active_mist: Array[FluidMist] = []
var active_smoke: Array[SmokeParticle] = []
var active_emitters: Dictionary = {} # pitch -> SustainedEmitter
var _droplet_pool: Array[BubbleDroplet] = []
var _mist_pool: Array[FluidMist] = []
var _smoke_pool: Array[SmokeParticle] = []

# Particle caps tuned for high FPS
var max_droplets: int = 220
var max_mist: int = 260
var max_smoke: int = 120

var particle_density: float = 0.5
var smoke_enabled: bool = true
var smoke_density: float = 1.0

# Pre-allocated rail points to eliminate allocations
var rail_seg_count: int = 60
var rail_pts: PackedVector2Array = PackedVector2Array()

# Ambient background shining particles
class AmbientMote:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var alpha: float = 0.5
	var size: float = 2.0
	var twinkle_speed: float = 2.0
	var phase: float = 0.0

var ambient_motes: Array[AmbientMote] = []
var num_ambient_motes: int = 42
var bg_particles_enabled: bool = true
var bg_particle_color: Color = Color(0.863, 0.208, 0.271, 0.9) # Brand #dc3545
var rail_y: float = 870.0
var smoke_texture: ImageTexture = null

var bg_canvas: Node2D

func _ready() -> void:
	z_index = 5
	
	bg_canvas = Node2D.new()
	bg_canvas.z_as_relative = false
	bg_canvas.z_index = -1
	bg_canvas.draw.connect(_draw_bg_particles)
	add_child(bg_canvas)
	
	_create_smoke_texture()

	# Pre-allocate ripple rail geometry once
	rail_pts.resize(rail_seg_count + 1)
	var vp_size := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var step_x := vp_size.x / float(rail_seg_count)
	for i in range(rail_seg_count + 1):
		rail_pts[i] = Vector2(float(i) * step_x, rail_y)

	for i in range(num_ambient_motes):
		var m := AmbientMote.new()
		m.position = Vector2(randf() * get_viewport_rect().size.x, randf() * get_viewport_rect().size.y)
		m.velocity = Vector2((randf() - 0.5) * 16.0, -12.0 - randf() * 26.0)
		m.size = randf_range(1.6, 4.2)
		m.alpha = randf_range(0.35, 0.85)
		m.twinkle_speed = randf_range(1.5, 4.5)
		m.phase = randf() * TAU
		ambient_motes.append(m)

func _create_smoke_texture() -> void:
	var tex_size := 64
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(tex_size) * 0.5, float(tex_size) * 0.5)
	var radius := float(tex_size) * 0.5
	for y in range(tex_size):
		for x in range(tex_size):
			var d := center.distance_to(Vector2(float(x) + 0.5, float(y) + 0.5)) / radius
			if d >= 1.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
			else:
				var a := pow(1.0 - d * d, 2.5)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	smoke_texture = ImageTexture.create_from_image(img)

func set_bg_particles_enabled(val: bool) -> void:
	bg_particles_enabled = val
	queue_redraw()

func set_bg_particle_color(col: Color) -> void:
	bg_particle_color = col
	queue_redraw()

func set_smoke_enabled(val: bool) -> void:
	smoke_enabled = val
	if not smoke_enabled:
		active_smoke.clear()

func set_smoke_density(val: float) -> void:
	smoke_density = clampf(val, 0.0, 3.0)

func refresh_bg_particles() -> void:
	if num_ambient_motes > ambient_motes.size():
		for i in range(num_ambient_motes - ambient_motes.size()):
			var m := AmbientMote.new()
			m.position = Vector2(randf() * get_viewport_rect().size.x, randf() * get_viewport_rect().size.y)
			m.velocity = Vector2((randf() - 0.5) * 16.0, -12.0 - randf() * 26.0)
			m.size = randf_range(1.6, 4.2)
			m.alpha = randf_range(0.35, 0.85)
			m.twinkle_speed = randf_range(1.5, 4.5)
			m.phase = randf() * TAU
			ambient_motes.append(m)
	elif num_ambient_motes < ambient_motes.size():
		ambient_motes.resize(num_ambient_motes)

func _spawn_droplet(pos: Vector2, col: Color) -> void:
	var d: BubbleDroplet = _droplet_pool.pop_back() if not _droplet_pool.is_empty() else BubbleDroplet.new()
	d.position = pos
	var angle := randf_range(-PI * 0.85, -PI * 0.15)
	var speed := randf_range(150.0, 390.0)
	d.velocity = Vector2(cos(angle), sin(angle)) * speed
	d.color = col
	d.radius = randf_range(2.5, 5.5)
	d.max_life = randf_range(0.32, 0.72)
	d.life = d.max_life
	d.wobble_seed = randf() * 10.0
	active_droplets.append(d)

func _spawn_mist(pos: Vector2, col: Color) -> void:
	var m: FluidMist = _mist_pool.pop_back() if not _mist_pool.is_empty() else FluidMist.new()
	m.position = pos
	var angle := randf_range(-PI * 0.9, -PI * 0.1)
	var speed := randf_range(70.0, 260.0)
	m.velocity = Vector2(cos(angle), sin(angle)) * speed
	m.color = col.lightened(randf_range(0.3, 0.7))
	m.size = randf_range(1.2, 2.6)
	m.max_life = randf_range(0.2, 0.5)
	m.life = m.max_life
	active_mist.append(m)

func _spawn_smoke(pos: Vector2, col: Color) -> void:
	var s: SmokeParticle = _smoke_pool.pop_back() if not _smoke_pool.is_empty() else SmokeParticle.new()
	s.position = pos
	var vx := randf_range(-18.0, 18.0)
	var vy := randf_range(-55.0, -115.0)
	s.velocity = Vector2(vx, vy)
	s.color = col
	s.radius = randf_range(9.0, 14.0)
	s.max_radius = randf_range(34.0, 52.0)
	s.max_life = randf_range(1.1, 1.6)
	s.life = s.max_life
	s.wobble_seed = randf() * 100.0
	active_smoke.append(s)

func trigger_burst(center: Vector2, color: Color, width: float = 24.0) -> void:
	rail_y = center.y
	var half_w := width * 0.42

	# 1. Spawn spherical glass bubble droplets with caustic glints
	if particle_density > 0.01:
		var droplet_count := int(8.0 * particle_density)
		for i in range(droplet_count):
			if active_droplets.size() >= max_droplets:
				break
			var px := randf_range(center.x - half_w, center.x + half_w)
			_spawn_droplet(Vector2(px, center.y + randf_range(-2.0, 2.0)), color)

		# 2. Spawn fine fluid mist
		var mist_count := int(10.0 * particle_density)
		for i in range(mist_count):
			if active_mist.size() >= max_mist:
				break
			var px := randf_range(center.x - half_w, center.x + half_w)
			_spawn_mist(Vector2(px, center.y + randf_range(-2.0, 2.0)), color)

	# 3. Spawn billowing ethereal piano smoke wisps
	if smoke_enabled and smoke_density > 0.01:
		var smoke_count := int(3.0 * smoke_density)
		for i in range(smoke_count):
			if active_smoke.size() >= max_smoke:
				break
			var px := randf_range(center.x - half_w, center.x + half_w)
			_spawn_smoke(Vector2(px, center.y + randf_range(-3.0, 1.0)), color)

func start_emitter(pitch: int, center: Vector2, width: float, color: Color) -> void:
	rail_y = center.y
	trigger_burst(center, color, width)

	var emitter: SustainedEmitter
	if active_emitters.has(pitch):
		emitter = active_emitters[pitch]
	else:
		emitter = SustainedEmitter.new()
		active_emitters[pitch] = emitter

	emitter.pitch = pitch
	emitter.center = center
	emitter.width = width
	emitter.color = color
	emitter.droplet_timer = randf() * 0.03
	emitter.mist_timer = randf() * 0.02
	emitter.smoke_timer = randf() * 0.06

func stop_emitter(pitch: int) -> void:
	if active_emitters.has(pitch):
		active_emitters.erase(pitch)

func clear_emitters() -> void:
	active_emitters.clear()

func clear_all() -> void:
	active_emitters.clear()
	active_droplets.clear()
	active_mist.clear()
	active_smoke.clear()
	queue_redraw()

func _process(delta: float) -> void:
	if export_override_delta > 0.0:
		delta = export_override_delta
		
	sim_time += delta
	var gravity := Vector2(0.0, 400.0)

	# Continuous generation while falling tiles touch the piano (until gone)
	if not active_emitters.is_empty():
		for emitter in active_emitters.values():
			var col: Color = emitter.color
			var cx: float = emitter.center.x
			var cy: float = emitter.center.y
			var half_w: float = emitter.width * 0.42

			# Continuous bubble droplets and fine mist
			if particle_density > 0.01:
				emitter.droplet_timer += delta
				var droplet_interval := 0.065 / particle_density # ~15 droplets/sec per active key
				while emitter.droplet_timer >= droplet_interval:
					emitter.droplet_timer -= droplet_interval
					if active_droplets.size() < max_droplets:
						_spawn_droplet(Vector2(randf_range(cx - half_w, cx + half_w), cy + randf_range(-2.0, 2.0)), col)

				emitter.mist_timer += delta
				var mist_interval := 0.045 / particle_density # ~22 mist motes/sec per active key
				while emitter.mist_timer >= mist_interval:
					emitter.mist_timer -= mist_interval
					if active_mist.size() < max_mist:
						_spawn_mist(Vector2(randf_range(cx - half_w, cx + half_w), cy + randf_range(-2.0, 2.0)), col)

			# Continuous billowing soft smoke
			if smoke_enabled and smoke_density > 0.01:
				emitter.smoke_timer += delta
				var smoke_interval := 0.17 / smoke_density # ~6 smoke puffs/sec per active key
				while emitter.smoke_timer >= smoke_interval:
					emitter.smoke_timer -= smoke_interval
					if active_smoke.size() < max_smoke:
						_spawn_smoke(Vector2(randf_range(cx - half_w, cx + half_w), cy + randf_range(-3.0, 1.0)), col)

	# Update bubble droplets (O(1) removal, no allocations)
	for i in range(active_droplets.size() - 1, -1, -1):
		var d = active_droplets[i]
		d.life -= delta
		if d.life <= 0.0:
			if _droplet_pool.size() < 300:
				_droplet_pool.append(d)
			active_droplets[i] = active_droplets[active_droplets.size() - 1]
			active_droplets.pop_back()
		else:
			d.velocity += gravity * delta
			d.position += d.velocity * delta

	# Update fluid mist
	for i in range(active_mist.size() - 1, -1, -1):
		var m = active_mist[i]
		m.life -= delta
		if m.life <= 0.0:
			if _mist_pool.size() < 350:
				_mist_pool.append(m)
			active_mist[i] = active_mist[active_mist.size() - 1]
			active_mist.pop_back()
		else:
			m.velocity += (gravity * 0.5) * delta
			m.position += m.velocity * delta

	# Update smoke particles
	for i in range(active_smoke.size() - 1, -1, -1):
		var s = active_smoke[i]
		s.life -= delta
		if s.life <= 0.0:
			if _smoke_pool.size() < 150:
				_smoke_pool.append(s)
			active_smoke[i] = active_smoke[active_smoke.size() - 1]
			active_smoke.pop_back()
		else:
			s.velocity.y *= (1.0 - 0.3 * delta)
			var breeze := sin(s.wobble_seed + s.life * 3.5) * 18.0
			s.position += (s.velocity + Vector2(breeze, 0.0)) * delta

	# Update ambient motes
	for am in ambient_motes:
		am.position += am.velocity * delta
		if am.position.y < -10.0:
			am.position.y = (get_viewport_rect().size.y + 10.0)
			am.position.x = randf() * get_viewport_rect().size.x
		if am.position.x < -10.0:
			am.position.x = (get_viewport_rect().size.x + 10.0)
		elif am.position.x > (get_viewport_rect().size.x + 10.0):
			am.position.x = -10.0
			
	if bg_canvas:
		bg_canvas.queue_redraw()

	queue_redraw()

func _draw() -> void:
	var time := sim_time * 3.0

	# 1. Draw billowing piano smoke plumes with soft Gaussian blur
	if smoke_enabled:
		for s in active_smoke:
			var prog := s.life / s.max_life
			var cur_r := lerpf(s.max_radius, s.radius, prog)
			var alpha_factor := sin(prog * PI) * smoke_density
			var base_smoke_col := s.color

			if smoke_texture:
				# Soft blurred outer cloud
				var outer_col := base_smoke_col
				outer_col.a = clampf(alpha_factor * 0.16, 0.0, 1.0)
				var rect_outer := Rect2(s.position.x - cur_r, s.position.y - cur_r, cur_r * 2.0, cur_r * 2.0)
				draw_texture_rect(smoke_texture, rect_outer, false, outer_col)

				# Soft blurred inner core
				var core_col := base_smoke_col.lightened(0.30)
				core_col.a = clampf(alpha_factor * 0.28 * prog, 0.0, 1.0)
				var core_r := cur_r * 0.55
				var rect_core := Rect2(s.position.x - core_r, s.position.y - core_r, core_r * 2.0, core_r * 2.0)
				draw_texture_rect(smoke_texture, rect_core, false, core_col)
			else:
				var outer_col := base_smoke_col
				outer_col.a = clampf(alpha_factor * 0.09, 0.0, 1.0)
				draw_circle(s.position, cur_r, outer_col)

	# 2. Update and draw Saber / Glow line
	if saber_mode > 0:
		var step_x := get_viewport_rect().size.x / float(rail_seg_count)
		var thickness_base := 2.5

		for i in range(rail_seg_count + 1):
			var px := float(i) * step_x
			var py := rail_y - 2.0
			
			if saber_mode == 2: # Electric Static (Average of old Electric and Light Static)
				# Old electric: sin(px * 0.04 + time * 3.0) * 4.0 + cos(px * 0.1 - time * 5.0) * 2.0
				# Old static: sin(px * 0.08 - time * 2.5) * 1.5
				# Average them loosely:
				py += sin(px * 0.06 + time * 2.0) * 2.5 + cos(px * 0.09 - time * 3.5) * 1.25
				
			rail_pts[i] = Vector2(px, py)
		
		# Draw the saber line in segments to apply gradient colors
		if playback and playback.color_mode == PlaybackController.ColorMode.GRADIENT:
			for i in range(rail_seg_count):
				var p1 = rail_pts[i]
				var p2 = rail_pts[i+1]
				var t = (float(i) / float(rail_seg_count))
				# Map to keyboard width (roughly 21 to 108 pitch equivalent)
				var c1 = playback.active_gradient.sample(t)
				var c2 = playback.active_gradient.sample(float(i+1) / float(rail_seg_count))
				
				# Base line
				draw_line(p1, p2, c1, thickness_base, true)
				# Outer glow
				var glow_col = c1
				glow_col.a = 0.3
				draw_line(p1, p2, glow_col, thickness_base * 4.0, true)
				# Inner bright core
				var core_col = c1.lightened(0.6)
				core_col.a = 0.9
				draw_line(p1, p2, core_col, thickness_base * 0.4, true)
		else:
			# Single color mode
			var col := Color(0.863, 0.208, 0.271, 1.0)
			if playback and playback.color_mode == PlaybackController.ColorMode.LEFT_RIGHT_HAND:
				col = playback.left_hand_color # simplified for hand mode
			elif playback and playback.parser.tracks.size() > 0:
				col = playback.parser.tracks[0].color

			draw_polyline(rail_pts, col, thickness_base, true)
			var glow_col = col
			glow_col.a = 0.3
			draw_polyline(rail_pts, glow_col, thickness_base * 4.0, true)
			var core_col = col.lightened(0.6)
			core_col.a = 0.9
			draw_polyline(rail_pts, core_col, thickness_base * 0.4, true)

	# 4. Draw fine fluid mist motes
	for m in active_mist:
		var prog := m.life / m.max_life
		var mist_col := m.color
		mist_col.a = clampf(prog * 1.2, 0.0, 1.0)
		draw_circle(m.position, m.size * prog, mist_col)

	# 5. Draw glass bubble droplets with fast caustic circles & glints
	for d in active_droplets:
		var prog := d.life / d.max_life
		var cur_r := d.radius * (0.4 + 0.6 * prog)
		var bubble_col := d.color
		bubble_col.a = clampf(prog * 1.4, 0.0, 1.0)

		# Outer glowing rim
		draw_circle(d.position, cur_r, bubble_col.lightened(0.35))
		# Inner translucent core
		var inner_col := bubble_col
		inner_col.a *= 0.3
		draw_circle(d.position, cur_r * 0.72, inner_col)

		# Specular glint
		var glint_pos := d.position + Vector2(-cur_r * 0.35, -cur_r * 0.35)
		draw_circle(glint_pos, cur_r * 0.25, Color(1.0, 1.0, 1.0, bubble_col.a))

func _draw_bg_particles() -> void:
	if not bg_particles_enabled:
		return
	
	var time := sim_time * 3.0
	for am in ambient_motes:
		var pulse := 0.65 + 0.35 * sin(time * am.twinkle_speed + am.phase)
		var p_alpha := am.alpha * pulse

		var base_col := bg_particle_color
		if playback and playback.color_mode == PlaybackController.ColorMode.GRADIENT:
			var t := clampf(am.position.x / get_viewport_rect().size.x, 0.0, 1.0)
			base_col = playback.active_gradient.sample(t)

		var halo_col := base_col
		halo_col.a = clampf(p_alpha * 0.8, 0.0, 1.0)
		bg_canvas.draw_circle(am.position, am.size * 3.5, halo_col)

		var core_col := base_col.lightened(0.7)
		core_col.a = clampf(p_alpha * 1.5, 0.0, 1.0)
		bg_canvas.draw_circle(am.position, am.size * 1.5, core_col)

		bg_canvas.draw_circle(am.position, am.size * 0.6, Color(1.0, 1.0, 1.0, p_alpha))
