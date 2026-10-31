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

const MidiParserClass = preload("res://scripts/core/midi_parser.gd")

func _init() -> void:
	print("=== LibrePianoRoll: Running MIDI & Tempo Tests ===")

	var parser = MidiParserClass.new()
	parser.create_demo_song()

	print("Demo song created:")
	print("  Total notes: ", parser.notes.size())
	print("  Tracks: ", parser.tracks.size())
	print("  Duration: ", parser.total_duration, " seconds")

	assert(parser.notes.size() > 50, "Expected at least 50 notes in demo song")
	assert(parser.tracks.size() == 2, "Expected 2 tracks")
	assert(parser.total_duration > 10.0, "Expected duration > 10 seconds")

	# Test tempo map conversions
	var tempo = parser.tempo_map
	var sec_at_0: float = tempo.tick_to_seconds(0)
	assert(is_equal_approx(sec_at_0, 0.0), "Tick 0 should be 0.0 seconds")

	var tick_at_0: int = tempo.seconds_to_tick(0.0)
	assert(tick_at_0 == 0, "Seconds 0 should be tick 0")

	print("=== All Core Tests Passed Successfully! ===")
	quit(0)
