class_name VideoExporter
extends Node

signal export_progress(percent: float)
signal export_finished(success: bool, path: String)

var playback: PlaybackController
var viewport: Viewport
var is_exporting: bool = false
var frame_idx: int = 0
var total_frames: int = 0
var fps: float = 60.0
var output_path: String = ""
var export_dir: String = "user://export_frames"
var start_pad: float = 0.0
var end_pad: float = 3.0

var is_audio_pass: bool = false
var audio_effect: AudioEffectRecord
var record_bus_idx: int = -1
var audio_warmup_frames: int = 0

var vfx_manager: VfxManager
var note_renderer: NoteRenderer

func start_export(pb: PlaybackController, vfx: VfxManager, nr: NoteRenderer, vp: Viewport, out_path: String, p_fps: float = 60.0, p_start: float = 0.0, p_end: float = 3.0) -> void:
	if is_exporting: return
	playback = pb
	vfx_manager = vfx
	note_renderer = nr
	viewport = vp
	output_path = out_path
	fps = p_fps
	start_pad = p_start
	end_pad = p_end
	
	var dir := DirAccess.open("user://")
	if dir.dir_exists("export_frames"):
		var d := DirAccess.open(export_dir)
		for f in d.get_files():
			d.remove(f)
	else:
		dir.make_dir("export_frames")
		
	is_exporting = true
	frame_idx = 0
	
	# Determine if we should do an audio pass
	var audio_path := ""
	if playback.current_midi_path != "":
		var base: String = playback.current_midi_path.get_basename()
		for ext in [".wav", ".mp3", ".ogg", ".flac"]:
			if FileAccess.file_exists(base + ext):
				audio_path = base + ext
				break
	
	total_frames = int((start_pad + playback.parser.total_duration + end_pad) * fps)
	
	if audio_path == "":
		# No external audio found. DO A REAL-TIME AUDIO PASS!
		is_audio_pass = true
		record_bus_idx = AudioServer.get_bus_index("Master")
		
		# Setup the recorder
		audio_effect = AudioEffectRecord.new()
		audio_effect.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(record_bus_idx, audio_effect)
		
		# Give the engine a few frames to stabilize UI-hide lag spikes before recording
		audio_warmup_frames = 5
		set_process(true)
	else:
		# Audio file exists, skip audio pass
		_start_video_pass()

func _start_video_pass() -> void:
	is_audio_pass = false
	frame_idx = 0
	if vfx_manager:
		vfx_manager.export_override_delta = 1.0 / fps
	if note_renderer:
		note_renderer.export_override_delta = 1.0 / fps
	playback.pause()
	playback.seek(-start_pad)
	set_process(true)

func cancel_export() -> void:
	if is_exporting:
		is_exporting = false
		set_process(false)
		if is_audio_pass and record_bus_idx != -1 and audio_effect:
			audio_effect.set_recording_active(false)
			AudioServer.remove_bus_effect(record_bus_idx, AudioServer.get_bus_effect_count(record_bus_idx) - 1)
		if vfx_manager:
			vfx_manager.export_override_delta = 0.0
		if note_renderer:
			note_renderer.export_override_delta = 0.0
		export_finished.emit(false, "Cancelled by user")

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	if not is_exporting:
		set_process(false)
		return
		
	if is_audio_pass:
		if audio_warmup_frames > 0:
			audio_warmup_frames -= 1
			if audio_warmup_frames == 0:
				audio_effect.set_recording_active(true)
				playback.seek(0.0)
				playback.set_speed(1.0)
				playback.play()
			return
			
		export_progress.emit(playback.current_time / playback.parser.total_duration)
		if not playback.is_playing:
			audio_effect.set_recording_active(false)
			var recording := audio_effect.get_recording()
			if recording and recording.data.size() > 0:
				# Compensate AudioStreamGenerator ring-buffer (150ms) + AudioServer mix latency
				var buffer_latency: float = 0.15
				var total_latency: float = buffer_latency + AudioServer.get_output_latency()
				var bytes_per_frame: int = 4 # 16-bit stereo = 2 channels * 2 bytes
				var trim_frames: int = int(total_latency * float(recording.mix_rate))
				var trim_bytes: int = trim_frames * bytes_per_frame
				if recording.data.size() > trim_bytes:
					recording.data = recording.data.slice(trim_bytes)
				recording.save_to_wav("user://temp_audio.wav")
			AudioServer.remove_bus_effect(record_bus_idx, AudioServer.get_bus_effect_count(record_bus_idx) - 1)
			_start_video_pass()
		return
		
	# Capture the PREVIOUS frame that was just drawn
	if frame_idx > 0:
		var img := viewport.get_texture().get_image()
		var path := ProjectSettings.globalize_path(export_dir).path_join("frame_%05d.png" % (frame_idx - 1)).replace("\\", "/")
		img.save_png(path)
		export_progress.emit(float(frame_idx) / float(total_frames))
		
	if frame_idx >= total_frames:
		_finish_export()
		return
		
	# Advance time for the CURRENT frame
	playback.manual_step(1.0 / fps)
	
	frame_idx += 1

func _finish_export() -> void:
	is_exporting = false
	set_process(false)
	var muxer := FFmpegMuxer.new()
	var pattern := ProjectSettings.globalize_path(export_dir).path_join("frame_%05d.png").replace("\\", "/")
	var real_out := ProjectSettings.globalize_path(output_path).replace("\\", "/")
	
	# Attempt to find matching audio file (mp3, wav, ogg) next to the MIDI file
	var audio_path := ""
	if playback.current_midi_path != "":
		var base: String = playback.current_midi_path.get_basename()
		for ext in [".wav", ".mp3", ".ogg", ".flac"]:
			if FileAccess.file_exists(base + ext):
				audio_path = ProjectSettings.globalize_path(base + ext)
				break
				
	# Fallback to the real-time recorded audio if no external file was provided
	if audio_path == "" and FileAccess.file_exists("user://temp_audio.wav"):
		audio_path = ProjectSettings.globalize_path("user://temp_audio.wav")
	
	# Run FFmpeg blocking
	var code := muxer.encode_video(pattern, real_out, int(fps), false, audio_path, start_pad)
	if vfx_manager:
		vfx_manager.export_override_delta = 0.0
	if note_renderer:
		note_renderer.export_override_delta = 0.0
	export_finished.emit(code == 0, real_out)
