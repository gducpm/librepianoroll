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

class_name FFmpegMuxer
extends RefCounted

var ffmpeg_path: String = "C:\\Users\\Ducpm\\scoop\\shims\\ffmpeg.exe"

func _init() -> void:
	# Fallback if path doesn't exist
	if not FileAccess.file_exists(ffmpeg_path):
		var check_path: String = OS.get_environment("PATH")
		for p in check_path.split(";"):
			var candidate := p.path_join("ffmpeg.exe")
			if FileAccess.file_exists(candidate):
				ffmpeg_path = candidate
				break

func is_ffmpeg_available() -> bool:
	return FileAccess.file_exists(ffmpeg_path)

# Render frames sequence into high quality MP4 or ProRes 4444 with Alpha
func encode_video(frames_pattern: String, output_video_path: String, fps: int = 60, is_transparent: bool = false, audio_path: String = "", start_pad: float = 0.0) -> int:
	if not is_ffmpeg_available():
		push_error("FFmpeg not found at: " + ffmpeg_path)
		return -1

	var args: PackedStringArray = [
		"-y",
		"-framerate", str(fps),
		"-i", frames_pattern,
	]
	
	if audio_path != "" and FileAccess.file_exists(audio_path):
		args.append_array(["-i", audio_path])
		if start_pad > 0.0:
			var delay_ms := int(start_pad * 1000.0)
			# Apply delay to all channels (left and right)
			args.append_array(["-af", "adelay=%d|%d" % [delay_ms, delay_ms]])
		
		# Do NOT use -shortest so the end_pad is preserved as silent video!
		args.append_array(["-c:a", "aac", "-b:a", "192k"])
	
	if is_transparent:
		# Lossless Apple ProRes 4444 with Alpha channel for DaVinci / Premiere overlay
		args.append_array([
			"-c:v", "prores_ks",
			"-profile:v", "4444",
			"-pix_fmt", "yuva444p10le",
			"-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
		])
	else:
		# Universal high-compatibility H.264 MP4
		args.append_array([
			"-c:v", "libx264",
			"-preset", "slow",
			"-crf", "17",
			"-pix_fmt", "yuv420p",
			"-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
		])

	args.append(output_video_path)

	print("LibrePianoRoll: Launching FFmpeg with args: ", args)
	var output: Array = []
	var exit_code := OS.execute(ffmpeg_path, args, output, true, false)
	print("LibrePianoRoll: FFmpeg exit code: ", exit_code)
	return exit_code
