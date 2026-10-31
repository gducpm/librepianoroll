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

class_name PlaybackController
extends Node

signal time_updated(current_time: float)
signal playback_state_changed(is_playing: bool)
signal note_started(note: NoteData)
signal note_ended(note: NoteData)
signal song_loaded()
signal song_reset()
signal speed_changed(speed: float)
signal color_settings_changed()

enum ColorMode {
	BY_TRACK,
	LEFT_RIGHT_HAND,
	GRADIENT,
}

var color_mode: ColorMode = ColorMode.GRADIENT
var left_hand_color: Color = Color(0.0, 0.75, 1.0, 1.0) # Ice Blue
var right_hand_color: Color = Color(1.0, 0.72, 0.08, 1.0) # Warm Amber Gold
var hand_split_pitch: int = 60 # Middle C (C4)

var current_time: float = 0.0
var is_playing: bool = false
var playback_speed: float = 1.0 # 0.25x - 2.0x
var loop_enabled: bool = false
var loop_start: float = 0.0
var loop_end: float = 0.0
var current_midi_path: String = ""

var parser: MidiParser = MidiParser.new()
var active_notes: Dictionary = {} # NoteData -> bool

# Fall window duration: how many seconds ahead notes appear falling towards the keyboard
var fall_duration: float = 2.5

var active_gradient: Gradient = Gradient.new()
var _pitch_colors: Array[Color] = []
var _cached_visible_notes: Array[NoteData] = []
var _to_remove_notes: Array[NoteData] = []

func _init() -> void:
	# Default gradient: Cyan -> Purple -> Pink -> Orange
	active_gradient.set_color(0, Color(0.0, 1.0, 1.0, 1.0)) # Cyan
	active_gradient.set_offset(0, 0.0)
	
	active_gradient.set_color(1, Color(1.0, 0.6, 0.0, 1.0)) # Orange
	active_gradient.set_offset(1, 1.0)
	
	active_gradient.add_point(0.33, Color(0.6, 0.2, 1.0, 1.0)) # Purple
	active_gradient.add_point(0.66, Color(1.0, 0.2, 0.6, 1.0)) # Pink
	
	_pitch_colors.resize(128)
	_rebuild_pitch_colors()

func _rebuild_pitch_colors() -> void:
	if _pitch_colors.size() < 128:
		_pitch_colors.resize(128)
	if color_mode == ColorMode.GRADIENT:
		for p in range(128):
			var t := clampf(float(p - 21) / 87.0, 0.0, 1.0)
			_pitch_colors[p] = active_gradient.sample(t)
	elif color_mode == ColorMode.LEFT_RIGHT_HAND:
		for p in range(128):
			_pitch_colors[p] = left_hand_color if p < hand_split_pitch else right_hand_color

func get_note_color(note: NoteData) -> Color:
	if color_mode == ColorMode.BY_TRACK:
		if note.track_idx < parser.tracks.size():
			return parser.tracks[note.track_idx].color
		return Color(0.863, 0.208, 0.271, 1.0) # Brand #dc3545
	
	var p := clampi(note.pitch, 0, 127)
	return _pitch_colors[p]

func set_track_color(track_idx: int, color: Color) -> void:
	if track_idx >= 0 and track_idx < parser.tracks.size():
		parser.tracks[track_idx].color = color
		color_settings_changed.emit()

func set_left_hand_color(color: Color) -> void:
	left_hand_color = color
	_rebuild_pitch_colors()
	color_settings_changed.emit()

func set_right_hand_color(color: Color) -> void:
	right_hand_color = color
	_rebuild_pitch_colors()
	color_settings_changed.emit()

func set_color_mode(mode: ColorMode) -> void:
	color_mode = mode
	_rebuild_pitch_colors()
	color_settings_changed.emit()

func set_hand_split_pitch(pitch: int) -> void:
	hand_split_pitch = clampi(pitch, 21, 108)
	_rebuild_pitch_colors()
	color_settings_changed.emit()

func notify_gradient_changed() -> void:
	_rebuild_pitch_colors()
	color_settings_changed.emit()

func _ready() -> void:
	pass

func _end_all_active_notes() -> void:
	var prev := active_notes.duplicate()
	active_notes.clear()
	for n in prev:
		note_ended.emit(n)

func reset() -> void:
	pause()
	_end_all_active_notes()
	current_time = 0.0
	song_reset.emit()
	time_updated.emit(current_time)

func load_midi_file(path: String) -> bool:
	reset()
	var success := parser.parse_file(path)
	if success:
		current_midi_path = path
		_on_song_loaded()
	else:
		current_midi_path = ""
	return success

func load_demo() -> void:
	reset()
	if FileAccess.file_exists("res://default.mid"):
		var success := parser.parse_file("res://default.mid")
		if success:
			current_midi_path = "res://default.mid"
			_on_song_loaded()
			return
	parser.create_demo_song()
	_on_song_loaded()

func _on_song_loaded() -> void:
	_end_all_active_notes()
	current_time = 0.0
	loop_start = 0.0
	loop_end = parser.total_duration
	song_loaded.emit()
	time_updated.emit(current_time)

func play() -> void:
	if not is_playing:
		if current_time >= parser.total_duration:
			seek(0.0)
		is_playing = true
		playback_state_changed.emit(true)

func pause() -> void:
	if is_playing:
		is_playing = false
		playback_state_changed.emit(false)

func toggle_play() -> void:
	if is_playing:
		pause()
	else:
		play()

func _find_first_note_after_or_at(time_threshold: float) -> int:
	var notes := parser.notes
	var count := notes.size()
	if count == 0:
		return 0
	var low := 0
	var high := count - 1
	var result := count

	while low <= high:
		var mid := (low + high) >> 1
		if notes[mid].start_time >= time_threshold:
			result = mid
			high = mid - 1
		else:
			low = mid + 1
	return result

func seek(target_time: float) -> void:
	var prev_active := active_notes.duplicate()
	current_time = target_time
	active_notes.clear()

	# End all previously active notes first
	for prev_n in prev_active:
		note_ended.emit(prev_n)

	# Find and trigger notes active at the new target time
	var notes := parser.notes
	var count := notes.size()
	if count > 0:
		var search_start_time := current_time - parser.max_note_duration
		var start_idx := _find_first_note_after_or_at(search_start_time)
		for i in range(start_idx, count):
			var n: NoteData = notes[i]
			if n.start_time > current_time:
				break
			if n.is_active_at(current_time):
				active_notes[n] = true
				note_started.emit(n)

	time_updated.emit(current_time)

func manual_step(delta: float) -> void:
	current_time += delta
	_update_note_events()
	time_updated.emit(current_time)

func set_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.1, 4.0)
	speed_changed.emit(playback_speed)

func _process(delta: float) -> void:
	if not is_playing:
		return

	var step := delta * playback_speed
	var new_time := current_time + step

	if loop_enabled and loop_end > loop_start and new_time >= loop_end:
		seek(loop_start)
		return
	elif new_time >= parser.total_duration + 1.0:
		new_time = parser.total_duration + 1.0
		pause()

	current_time = new_time
	_update_note_events()
	time_updated.emit(current_time)

func _update_note_events() -> void:
	# End finished notes (reusing array to eliminate per-frame allocations)
	_to_remove_notes.clear()
	for n in active_notes:
		if current_time > n.end_time or current_time < n.start_time:
			_to_remove_notes.append(n)
			note_ended.emit(n)
	for n in _to_remove_notes:
		active_notes.erase(n)

	# Trigger started notes using binary search to avoid scanning past notes
	var notes := parser.notes
	var count := notes.size()
	if count == 0:
		return

	var search_start_time := current_time - parser.max_note_duration
	var start_idx := _find_first_note_after_or_at(search_start_time)
	for i in range(start_idx, count):
		var n: NoteData = notes[i]
		if n.start_time > current_time:
			break
		if current_time >= n.start_time and current_time <= n.end_time:
			if not active_notes.has(n):
				active_notes[n] = true
				note_started.emit(n)

# Get notes currently visible in the waterfall window: [current_time, current_time + fall_duration]
func get_visible_notes() -> Array[NoteData]:
	_cached_visible_notes.clear()
	var notes := parser.notes
	var count := notes.size()
	if count == 0:
		return _cached_visible_notes

	var window_start := current_time
	var window_end := current_time + fall_duration
	var search_start_time := window_start - parser.max_note_duration

	var start_idx := _find_first_note_after_or_at(search_start_time)
	for i in range(start_idx, count):
		var n: NoteData = notes[i]
		if n.start_time > window_end:
			break
		if n.end_time < window_start:
			continue
		_cached_visible_notes.append(n)

	return _cached_visible_notes
