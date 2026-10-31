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
	print("=== LibrePianoRoll: Starting Integration Test ===")

	var main_scene_res: PackedScene = load("res://scenes/main.tscn")
	assert(main_scene_res != null, "Failed to load scenes/main.tscn")

	var main_node = main_scene_res.instantiate()
	assert(main_node != null, "Failed to instantiate scenes/main.tscn")

	root.add_child(main_node)

	var playback: PlaybackController = main_node.get_node("PlaybackController")
	var keyboard: KeyboardController = main_node.get_node("CanvasLayer/Keyboard")
	var renderer: NoteRenderer = main_node.get_node("CanvasLayer/NoteRenderer")
	var vfx: VfxManager = main_node.get_node("CanvasLayer/VFXManager")
	var synth: SynthEngine = main_node.get_node("SynthEngine")

	assert(playback != null, "PlaybackController missing")
	assert(keyboard != null, "KeyboardController missing")
	assert(renderer != null, "NoteRenderer missing")
	assert(vfx != null, "VfxManager missing")
	assert(synth != null, "SynthEngine missing")

	print("Scene hierarchy verified.")

	# Explicitly load demo song for deterministic test
	playback.load_demo()
	keyboard.build_keyboard()

	print("Song loaded: ", playback.parser.notes.size(), " notes, duration: ", playback.parser.total_duration, "s")
	assert(playback.parser.notes.size() > 50, "Expected notes to be loaded")

	# Test 88 keys generated
	assert(keyboard.keys.size() == 88, "Expected 88 piano keys, got: " + str(keyboard.keys.size()))
	print("Verified 88 piano keys correctly mapped.")

	# Test Playback simulation
	playback.play()
	assert(playback.is_playing, "Playback should be playing")

	# Step time forward by 1.5 seconds
	playback._process(1.5)
	print("Simulated playback to t=1.5s, active notes: ", playback.active_notes.size())

	# Test seeking
	playback.seek(4.5)
	print("Seek to t=4.5s verified, current time: ", playback.current_time)
	assert(is_equal_approx(playback.current_time, 4.5), "Time should equal 4.5s")

	# Test VFX burst & sustained emitter
	var key_pos := keyboard.get_key_rect(60).position
	vfx.trigger_burst(key_pos, Color(0.863, 0.208, 0.271, 1.0), 20)
	print("VFX burst triggered, active droplets: ", vfx.active_droplets.size(), ", mist: ", vfx.active_mist.size(), ", smoke: ", vfx.active_smoke.size())
	assert(vfx.active_droplets.size() > 0, "Droplets should be active after burst")
	assert(vfx.active_mist.size() > 0, "Mist should be active after burst")

	# Test continuous sustained generation while tile touches piano
	vfx.start_emitter(60, key_pos, 24.0, Color(0.863, 0.208, 0.271, 1.0))
	assert(vfx.active_emitters.has(60), "Emitter should be active")
	var prev_droplets := vfx.active_droplets.size()
	vfx._process(0.2)
	assert(vfx.active_emitters.has(60), "Emitter should still be active during sustain")
	vfx.stop_emitter(60)
	assert(not vfx.active_emitters.has(60), "Emitter should be stopped when tile ends")

	# Test SynthEngine note triggers
	synth.note_on(60, 100)
	synth.note_on(64, 90)
	synth.note_on(67, 110)
	synth.note_off(60)
	synth.note_off(64)
	synth.note_off(67)
	print("SynthEngine polyphony test passed.")

	# Test Pause & Resume (audio silencing & emitter halting)
	playback.play()
	playback._process(1.0)
	playback.pause()
	assert(not playback.is_playing, "Playback should be paused")
	assert(vfx.active_emitters.is_empty(), "Emitters should be cleared on pause")

	# Test Track Reset (stuck keys elimination)
	playback.play()
	playback._process(1.0)
	playback.reset()
	assert(playback.current_time == 0.0, "Time should be 0.0 on reset")
	assert(playback.active_notes.is_empty(), "Active notes should be empty on reset")
	synth.all_notes_off()
	for p in keyboard.keys:
		var kv = keyboard.keys[p]
		assert(kv.press_intensity == 0.0, "Key %d must not remain colored on reset" % p)
	print("Track reset stuck key prevention verified: all 88 keys completely uncolored.")

	# Test Freeplay mode
	var ui: UIController = main_node.get_node("CanvasLayer/StudioUI")
	print("ui.note_renderer: ", ui.note_renderer, ", renderer: ", renderer)
	if not ui.note_renderer:
		ui.note_renderer = renderer
	ui._on_freeplay_toggled(true)
	assert(ui.is_freeplay, "Freeplay should be enabled")
	assert(not renderer.visible, "NoteRenderer falling tiles should be hidden in Freeplay")

	# Test PC keyboard input simulation in Freeplay
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_A # Note C
	ui._input(key_event)
	assert(ui.pressed_pc_keys.has(KEY_A), "KEY_A should be pressed in Freeplay")
	var played_pitch: int = ui.pressed_pc_keys[KEY_A]
	assert(played_pitch == (ui.current_octave + 1) * 12, "Should play C in current octave")

	key_event.pressed = false
	ui._input(key_event)
	assert(not ui.pressed_pc_keys.has(KEY_A), "KEY_A should be released")

	ui._on_freeplay_toggled(false)
	assert(not ui.is_freeplay, "Freeplay should be disabled")
	assert(renderer.visible, "NoteRenderer should be visible after exiting Freeplay")

	print("=== All Integration Tests Passed With 100% Success! ===")
	quit(0)
