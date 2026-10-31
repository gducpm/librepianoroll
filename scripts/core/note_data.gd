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

class_name NoteData
extends RefCounted

var pitch: int = 60 # Middle C (C4)
var start_time: float = 0.0 # Start time in seconds
var end_time: float = 1.0 # End time in seconds
var velocity: int = 100 # 0-127
var track_idx: int = 0
var channel: int = 0

const NOTE_NAMES: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const BLACK_KEY_PITCHES: Array[int] = [1, 3, 6, 8, 10] # Pitch modulo 12

func _init(p_pitch: int = 60, p_start: float = 0.0, p_end: float = 1.0, p_vel: int = 100, p_track: int = 0, p_chan: int = 0) -> void:
	pitch = clampi(p_pitch, 0, 127)
	start_time = maxf(0.0, p_start)
	end_time = maxf(start_time + 0.001, p_end)
	velocity = clampi(p_vel, 1, 127)
	track_idx = p_track
	channel = p_chan

func duration() -> float:
	return end_time - start_time

func is_black_key() -> bool:
	return (pitch % 12) in BLACK_KEY_PITCHES

func get_note_name() -> String:
	var name_str: String = NOTE_NAMES[pitch % 12]
	var octave: int = int(pitch / 12.0) - 1
	return "%s%d" % [name_str, octave]

func is_active_at(time: float) -> bool:
	return time >= start_time and time <= end_time
