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

class_name TempoMap
extends RefCounted

class TempoPoint:
	var tick: int = 0
	var micros_per_quarter: int = 500000 # Default 120 BPM
	var time_seconds: float = 0.0

	func _init(p_tick: int, p_micros: int, p_time: float) -> void:
		tick = p_tick
		micros_per_quarter = p_micros
		time_seconds = p_time

	func bpm() -> float:
		return 60000000.0 / float(micros_per_quarter)

class TimeSignaturePoint:
	var tick: int = 0
	var numerator: int = 4
	var denominator: int = 4

	func _init(p_tick: int, p_num: int, p_den: int) -> void:
		tick = p_tick
		numerator = p_num
		denominator = p_den

var ticks_per_quarter: int = 480
var tempo_points: Array[TempoPoint] = []
var time_sig_points: Array[TimeSignaturePoint] = []

func _init(p_tpq: int = 480) -> void:
	ticks_per_quarter = p_tpq
	clear()

func clear() -> void:
	tempo_points.clear()
	time_sig_points.clear()
	# Always have default initial tempo: 120 BPM at tick 0
	tempo_points.append(TempoPoint.new(0, 500000, 0.0))
	time_sig_points.append(TimeSignaturePoint.new(0, 4, 4))

func add_tempo_event(tick: int, micros_per_quarter: int) -> void:
	if tempo_points.is_empty():
		tempo_points.append(TempoPoint.new(0, micros_per_quarter, 0.0))
		return

	# Sort insertion
	var insert_idx: int = tempo_points.size()
	for i in range(tempo_points.size()):
		if tempo_points[i].tick == tick:
			tempo_points[i].micros_per_quarter = micros_per_quarter
			_rebuild_times()
			return
		elif tempo_points[i].tick > tick:
			insert_idx = i
			break

	var new_pt := TempoPoint.new(tick, micros_per_quarter, 0.0)
	tempo_points.insert(insert_idx, new_pt)
	_rebuild_times()

func add_time_signature_event(tick: int, numerator: int, denominator: int) -> void:
	for i in range(time_sig_points.size()):
		if time_sig_points[i].tick == tick:
			time_sig_points[i].numerator = numerator
			time_sig_points[i].denominator = denominator
			return
		elif time_sig_points[i].tick > tick:
			time_sig_points.insert(i, TimeSignaturePoint.new(tick, numerator, denominator))
			return
	time_sig_points.append(TimeSignaturePoint.new(tick, numerator, denominator))

func _rebuild_times() -> void:
	if tempo_points.is_empty():
		return
	tempo_points[0].time_seconds = 0.0

	for i in range(1, tempo_points.size()):
		var prev: TempoPoint = tempo_points[i - 1]
		var curr: TempoPoint = tempo_points[i]
		var delta_ticks: int = curr.tick - prev.tick
		var seconds_per_tick: float = float(prev.micros_per_quarter) / (1000000.0 * float(ticks_per_quarter))
		curr.time_seconds = prev.time_seconds + (float(delta_ticks) * seconds_per_tick)

func tick_to_seconds(tick: int) -> float:
	if tempo_points.is_empty():
		return 0.0
	if tick <= 0:
		return 0.0

	# Binary search to find the latest tempo point <= tick
	var low: int = 0
	var high: int = tempo_points.size() - 1
	var best_idx: int = 0

	while low <= high:
		var mid: int = (low + high) / 2
		if tempo_points[mid].tick <= tick:
			best_idx = mid
			low = mid + 1
		else:
			high = mid - 1

	var pt: TempoPoint = tempo_points[best_idx]
	var delta_ticks: int = tick - pt.tick
	var seconds_per_tick: float = float(pt.micros_per_quarter) / (1000000.0 * float(ticks_per_quarter))
	return pt.time_seconds + (float(delta_ticks) * seconds_per_tick)

func seconds_to_tick(seconds: float) -> int:
	if tempo_points.is_empty() or seconds <= 0.0:
		return 0

	var low: int = 0
	var high: int = tempo_points.size() - 1
	var best_idx: int = 0

	while low <= high:
		var mid: int = (low + high) / 2
		if tempo_points[mid].time_seconds <= seconds:
			best_idx = mid
			low = mid + 1
		else:
			high = mid - 1

	var pt: TempoPoint = tempo_points[best_idx]
	var delta_time: float = seconds - pt.time_seconds
	var seconds_per_tick: float = float(pt.micros_per_quarter) / (1000000.0 * float(ticks_per_quarter))
	if seconds_per_tick <= 0.0:
		return pt.tick
	return pt.tick + int(delta_time / seconds_per_tick)

func get_bpm_at_time(seconds: float) -> float:
	var tick: int = seconds_to_tick(seconds)
	for i in range(tempo_points.size() - 1, -1, -1):
		if tempo_points[i].tick <= tick:
			return tempo_points[i].bpm()
	return 120.0
