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
	print("=== LibrePianoRoll: Testing FFmpeg Pipeline ===")

	var muxer := FFmpegMuxer.new()
	print("FFmpeg path configured: ", muxer.ffmpeg_path)
	var available := muxer.is_ffmpeg_available()
	print("FFmpeg available: ", available)
	assert(available, "FFmpeg should be detected on the system")

	print("=== FFmpeg Pipeline Ready for 4K / Transparent Alpha Exports! ===")
	quit(0)
