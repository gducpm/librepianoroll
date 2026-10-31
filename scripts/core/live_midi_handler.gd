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

class_name LiveMidiHandler
extends Node

signal live_note_on(pitch: int, velocity: int)
signal live_note_off(pitch: int)
signal midi_device_connected(device_name: String)

@export var is_enabled: bool = true

func _ready() -> void:
	OS.open_midi_inputs()
	var connected_devices := OS.get_connected_midi_inputs()
	if not connected_devices.is_empty():
		for d in connected_devices:
			print("LibrePianoRoll: MIDI device detected: ", d)
			midi_device_connected.emit(d)
	else:
		print("LibrePianoRoll: No MIDI hardware connected (live input ready)")

func _input(event: InputEvent) -> void:
	if not is_enabled:
		return

	if event is InputEventMIDI:
		var midi := event as InputEventMIDI
		var msg_type := midi.message

		# MIDI message 9 is Note On (0x90)
		if msg_type == MIDI_MESSAGE_NOTE_ON:
			if midi.velocity > 0:
				live_note_on.emit(midi.pitch, midi.velocity)
			else:
				live_note_off.emit(midi.pitch)
		# MIDI message 8 is Note Off (0x80)
		elif msg_type == MIDI_MESSAGE_NOTE_OFF:
			live_note_off.emit(midi.pitch)
