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

class_name UIController
extends Control

@export var playback: PlaybackController
@export var note_renderer: NoteRenderer
@export var keyboard: KeyboardController
@export var vfx_manager: VfxManager
@export var synth_engine: SynthEngine

# UI Nodes
var top_bar: PanelContainer
var bottom_timeline: PanelContainer
var left_track_dock: PanelContainer
var right_visuals_dock: PanelContainer
var export_dock: PanelContainer

var play_btn: Button
var reset_btn: Button
var freeplay_btn: Button
var export_btn: Button
var octave_label: Label
var time_label: Label
var scrubber: HSlider
var speed_btn: OptionButton
var preset_btn: OptionButton
var file_dialog: FileDialog
var texture_file_dialog: FileDialog
var track_vbox: VBoxContainer

var export_fps_opt: OptionButton
var export_start_slider: HSlider
var export_end_slider: HSlider

var is_scrubbing: bool = false
var _updating_scrubber: bool = false
var hud_visible: bool = true
var is_freeplay: bool = false
var current_octave: int = 4
var pressed_pc_keys: Dictionary = {} # keycode -> pitch

const KEY_TO_NOTE_OFFSET: Dictionary = {
	KEY_A: 0,   # C
	KEY_W: 1,   # C#
	KEY_S: 2,   # D
	KEY_E: 3,   # D#
	KEY_D: 4,   # E
	KEY_F: 5,   # F
	KEY_T: 6,   # F#
	KEY_G: 7,   # G
	KEY_Y: 8,   # G#
	KEY_H: 9,   # A
	KEY_U: 10,  # A#
	KEY_J: 11,  # B
	KEY_K: 12,  # C (+1)
	KEY_O: 13,  # C# (+1)
	KEY_L: 14,  # D (+1)
	KEY_P: 15,  # D# (+1)
	KEY_SEMICOLON: 16, # E (+1)
	KEY_APOSTROPHE: 17, # F (+1)
}

var video_exporter: VideoExporter
var export_dialog: FileDialog
var export_progress_panel: Window
var export_progress_bar: ProgressBar

func _ready() -> void:
	build_studio_layout()
	connect_signals()

func build_studio_layout() -> void:
	# Fullscreen container
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	# Top Bar
	top_bar = PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 48)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "  LibrePianoRoll"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.863, 0.208, 0.271, 1.0)) # #dc3545
	top_hbox.add_child(title_lbl)

	var open_btn := Button.new()
	open_btn.text = "Open Performance"
	open_btn.pressed.connect(_on_open_file_pressed)
	top_hbox.add_child(open_btn)

	var demo_btn := Button.new()
	demo_btn.text = "Demonstrative Performance"
	demo_btn.pressed.connect(_on_load_demo_pressed)
	top_hbox.add_child(demo_btn)

	freeplay_btn = Button.new()
	freeplay_btn.text = "Live Performance (with Keyboard, Mouse or MIDI Device)"
	freeplay_btn.toggle_mode = true
	freeplay_btn.toggled.connect(_on_freeplay_toggled)
	top_hbox.add_child(freeplay_btn)

	var oct_down_btn := Button.new()
	oct_down_btn.text = "Oct -"
	oct_down_btn.tooltip_text = "Shift Octave Down (Key: Z)"
	oct_down_btn.pressed.connect(func(): _change_octave(current_octave - 1))
	top_hbox.add_child(oct_down_btn)

	octave_label = Label.new()
	octave_label.text = "C4 [Z/X]"
	octave_label.tooltip_text = "Current base octave for PC keyboard (Keys: A to ')"
	top_hbox.add_child(octave_label)

	var oct_up_btn := Button.new()
	oct_up_btn.text = "Oct +"
	oct_up_btn.tooltip_text = "Shift Octave Up (Key: X)"
	oct_up_btn.pressed.connect(func(): _change_octave(current_octave + 1))
	top_hbox.add_child(oct_up_btn)

	top_hbox.add_child(VSeparator.new())



	var toggle_tracks_btn := Button.new()
	toggle_tracks_btn.text = "Tracks"
	toggle_tracks_btn.pressed.connect(func(): left_track_dock.visible = not left_track_dock.visible)
	top_hbox.add_child(toggle_tracks_btn)

	var toggle_visuals_btn := Button.new()
	toggle_visuals_btn.text = "Visuals"
	toggle_visuals_btn.pressed.connect(func(): right_visuals_dock.visible = not right_visuals_dock.visible)
	top_hbox.add_child(toggle_visuals_btn)
	
	export_btn = Button.new()
	export_btn.text = "Export"
	export_btn.pressed.connect(func(): export_dock.visible = not export_dock.visible)
	top_hbox.add_child(export_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	var fullscreen_btn := Button.new()
	fullscreen_btn.text = "Fullscreen (F11)"
	fullscreen_btn.pressed.connect(_toggle_fullscreen)
	top_hbox.add_child(fullscreen_btn)

	var hud_btn := Button.new()
	hud_btn.text = "Clean View (Tab)"
	hud_btn.pressed.connect(toggle_hud)
	top_hbox.add_child(hud_btn)

	left_track_dock = PanelContainer.new()
	left_track_dock.custom_minimum_size = Vector2(280, 0)
	left_track_dock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_track_dock.offset_left = 16
	left_track_dock.offset_top = 60
	left_track_dock.offset_right = 366
	left_track_dock.offset_bottom = 500
	add_child(left_track_dock)

	var track_scroll := ScrollContainer.new()
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_track_dock.add_child(track_scroll)

	track_vbox = VBoxContainer.new()
	track_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.add_child(track_vbox)

	var track_hdr := Label.new()
	track_hdr.text = "Track & Color Customizer"
	track_hdr.add_theme_font_size_override("font_size", 14)
	track_vbox.add_child(track_hdr)
	track_vbox.add_child(HSeparator.new())

	right_visuals_dock = PanelContainer.new()
	right_visuals_dock.custom_minimum_size = Vector2(240, 0)
	right_visuals_dock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_visuals_dock.offset_top = 60
	right_visuals_dock.offset_left = -256
	right_visuals_dock.offset_right = -16
	right_visuals_dock.offset_bottom = 400
	add_child(right_visuals_dock)

	var vis_vbox := VBoxContainer.new()
	vis_vbox.add_theme_constant_override("separation", 8)
	right_visuals_dock.add_child(vis_vbox)

	var vis_hdr := Label.new()
	vis_hdr.text = "Visual Effects"
	vis_hdr.add_theme_font_size_override("font_size", 14)
	vis_vbox.add_child(vis_hdr)
	vis_vbox.add_child(HSeparator.new())

	# Checkbox removed per user request (always viewport anchored)

	# Glass texture selector
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Glass Texture Style"
	var tex_btn := OptionButton.new()
	tex_btn.add_item("Procedural Voronoi", 0)
	tex_btn.add_item("Water Bubbles", 1)
	tex_btn.add_item("Cracked Ice", 2)
	tex_btn.add_item("Marble Caustics", 3)
	tex_btn.add_item("Load Custom Image...", 4)
	tex_btn.item_selected.connect(_on_texture_selected)
	vis_vbox.add_child(tex_btn)

	# Glow intensity slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Glow Bloom Intensity"
	var glow_slider := HSlider.new()
	glow_slider.min_value = 1.0
	glow_slider.max_value = 6.0
	glow_slider.step = 0.1
	glow_slider.value = 1.2
	glow_slider.value_changed.connect(func(v: float):
		if note_renderer:
			note_renderer.set_glow_intensity(v)
	)
	vis_vbox.add_child(glow_slider)

	# Bubble density slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Glass Bubble Density"
	var bubble_slider := HSlider.new()
	bubble_slider.min_value = 1.0
	bubble_slider.max_value = 10.0
	bubble_slider.step = 0.2
	bubble_slider.value = 2.0
	bubble_slider.value_changed.connect(func(v: float):
		if note_renderer:
			note_renderer.set_bubble_density(v)
	)
	vis_vbox.add_child(bubble_slider)

	# Glass refraction slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Glass Refraction"
	var refr_slider := HSlider.new()
	refr_slider.min_value = 0.0
	refr_slider.max_value = 2.0
	refr_slider.step = 0.05
	refr_slider.value = 1.2
	refr_slider.value_changed.connect(func(v: float):
		if note_renderer:
			note_renderer.set_glass_refraction(v)
	)
	vis_vbox.add_child(refr_slider)

	# Note fall speed slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Fall Speed (px/s)"
	var speed_slider := HSlider.new()
	speed_slider.min_value = 150.0
	speed_slider.max_value = 700.0
	speed_slider.step = 10.0
	speed_slider.value = 680.0
	speed_slider.value_changed.connect(func(v: float):
		if note_renderer:
			note_renderer.pixels_per_second = v
	)
	vis_vbox.add_child(speed_slider)

	# Particle density slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Liquid Splash Particles"
	var part_slider := HSlider.new()
	part_slider.min_value = 0.0
	part_slider.max_value = 2.5
	part_slider.step = 0.1
	part_slider.value = 0.5
	part_slider.value_changed.connect(func(v: float):
		if vfx_manager:
			vfx_manager.particle_density = v
	)
	vis_vbox.add_child(part_slider)

	# Piano Smoke toggle checkbox (can be disabled)
	var smoke_chk := CheckBox.new()
	smoke_chk.text = "Piano Smoke Wisps"
	smoke_chk.button_pressed = true
	smoke_chk.toggled.connect(func(pressed: bool):
		if vfx_manager:
			vfx_manager.set_smoke_enabled(pressed)
	)
	vis_vbox.add_child(smoke_chk)

	# Piano Smoke density slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Smoke Density"
	var smoke_slider := HSlider.new()
	smoke_slider.min_value = 0.0
	smoke_slider.max_value = 2.5
	smoke_slider.step = 0.1
	smoke_slider.value = 1.0
	smoke_slider.value_changed.connect(func(v: float):
		if vfx_manager:
			vfx_manager.set_smoke_density(v)
	)
	vis_vbox.add_child(smoke_slider)

	# Ambient Background Particles toggle checkbox (can be disabled)
	var bg_part_chk := CheckBox.new()
	bg_part_chk.text = "Ambient BG Particles"
	bg_part_chk.button_pressed = true
	bg_part_chk.toggled.connect(func(pressed: bool):
		if vfx_manager:
			vfx_manager.set_bg_particles_enabled(pressed)
	)
	vis_vbox.add_child(bg_part_chk)

	# Ambient BG Particle density slider
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "BG Particle Density"
	var bg_slider := HSlider.new()
	bg_slider.min_value = 0.0
	bg_slider.max_value = 2.0
	bg_slider.step = 0.1
	bg_slider.value = 0.3
	bg_slider.value_changed.connect(func(v: float):
		if vfx_manager:
			vfx_manager.num_ambient_motes = int(140 * v)
			vfx_manager.refresh_bg_particles()
	)
	vis_vbox.add_child(bg_slider)


	
	vis_vbox.add_child(Label.new())
	(vis_vbox.get_child(vis_vbox.get_child_count() - 1) as Label).text = "Saber Animation Mode"
	
	var saber_opt := OptionButton.new()
	saber_opt.add_item("Off", 0)
	saber_opt.add_item("Straight", 1)
	saber_opt.add_item("Electric Static", 2)
	saber_opt.select(2)
	saber_opt.item_selected.connect(func(idx: int):
		if vfx_manager:
			vfx_manager.saber_mode = idx
	)
	vis_vbox.add_child(saber_opt)

	export_dock = PanelContainer.new()
	export_dock.custom_minimum_size = Vector2(240, 0)
	export_dock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	export_dock.offset_top = 60
	export_dock.offset_left = -512
	export_dock.offset_right = -272
	export_dock.offset_bottom = 320
	export_dock.visible = false
	add_child(export_dock)

	var exp_vbox := VBoxContainer.new()
	exp_vbox.add_theme_constant_override("separation", 8)
	export_dock.add_child(exp_vbox)

	var exp_hdr := Label.new()
	exp_hdr.text = "Export Settings"
	exp_hdr.add_theme_font_size_override("font_size", 14)
	exp_vbox.add_child(exp_hdr)
	exp_vbox.add_child(HSeparator.new())

	exp_vbox.add_child(Label.new())
	(exp_vbox.get_child(exp_vbox.get_child_count() - 1) as Label).text = "Export FPS"
	export_fps_opt = OptionButton.new()
	export_fps_opt.add_item("30 FPS", 30)
	export_fps_opt.add_item("60 FPS", 60)
	export_fps_opt.add_item("120 FPS", 120)
	export_fps_opt.select(1)
	exp_vbox.add_child(export_fps_opt)

	exp_vbox.add_child(Label.new())
	(exp_vbox.get_child(exp_vbox.get_child_count() - 1) as Label).text = "Start Pad (s)"
	export_start_slider = HSlider.new()
	export_start_slider.min_value = 0.0
	export_start_slider.max_value = 10.0
	export_start_slider.step = 0.5
	export_start_slider.value = 0.0
	var start_lbl = Label.new()
	start_lbl.text = "0.0 s"
	export_start_slider.value_changed.connect(func(v: float): start_lbl.text = "%.1f s" % v)
	var st_hbox = HBoxContainer.new()
	export_start_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_hbox.add_child(export_start_slider)
	st_hbox.add_child(start_lbl)
	exp_vbox.add_child(st_hbox)

	exp_vbox.add_child(Label.new())
	(exp_vbox.get_child(exp_vbox.get_child_count() - 1) as Label).text = "End Pad (s)"
	export_end_slider = HSlider.new()
	export_end_slider.min_value = 0.0
	export_end_slider.max_value = 10.0
	export_end_slider.step = 0.5
	export_end_slider.value = 3.0
	var end_lbl = Label.new()
	end_lbl.text = "3.0 s"
	export_end_slider.value_changed.connect(func(v: float): end_lbl.text = "%.1f s" % v)
	var end_hbox = HBoxContainer.new()
	export_end_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_hbox.add_child(export_end_slider)
	end_hbox.add_child(end_lbl)
	exp_vbox.add_child(end_hbox)
	
	exp_vbox.add_child(HSeparator.new())
	var do_export_btn := Button.new()
	do_export_btn.text = "Render Performance..."
	do_export_btn.pressed.connect(_on_export_video_pressed)
	exp_vbox.add_child(do_export_btn)

	bottom_timeline = PanelContainer.new()
	bottom_timeline.custom_minimum_size = Vector2(0, 56)
	bottom_timeline.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_timeline.offset_top = -56
	bottom_timeline.offset_bottom = 0
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.06, 0.06, 0.08, 0.92)
	bot_style.border_width_top = 1
	bot_style.border_color = Color(0.25, 0.25, 0.3, 0.7)
	bot_style.content_margin_left = 16
	bot_style.content_margin_right = 16
	bot_style.content_margin_top = 4
	bot_style.content_margin_bottom = 4
	bottom_timeline.add_theme_stylebox_override("panel", bot_style)
	add_child(bottom_timeline)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 12)
	bottom_timeline.add_child(bot_hbox)

	reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(_on_reset_pressed)
	bot_hbox.add_child(reset_btn)

	play_btn = Button.new()
	play_btn.text = "  ▶ Play  "
	play_btn.pressed.connect(_on_play_pressed)
	bot_hbox.add_child(play_btn)

	time_label = Label.new()
	time_label.text = "00:00.0 / 00:00.0"
	time_label.custom_minimum_size = Vector2(130, 0)
	bot_hbox.add_child(time_label)

	scrubber = HSlider.new()
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.min_value = 0.0
	scrubber.max_value = 100.0
	scrubber.step = 0.01
	scrubber.drag_started.connect(func(): is_scrubbing = true)
	scrubber.drag_ended.connect(func(_val: bool):
		is_scrubbing = false
		if playback:
			playback.seek(scrubber.value)
	)
	scrubber.value_changed.connect(func(v: float):
		if not _updating_scrubber and playback:
			playback.seek(v)
	)
	bot_hbox.add_child(scrubber)

	speed_btn = OptionButton.new()
	speed_btn.add_item("0.5x", 5)
	speed_btn.add_item("0.75x", 7)
	speed_btn.add_item("1.0x", 10)
	speed_btn.add_item("1.25x", 12)
	speed_btn.add_item("1.5x", 15)
	speed_btn.add_item("2.0x", 20)
	speed_btn.select(2)
	speed_btn.item_selected.connect(_on_speed_selected)
	bot_hbox.add_child(speed_btn)

	# File Dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.mid, *.midi ; MIDI Files"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	# Texture File Dialog
	texture_file_dialog = FileDialog.new()
	texture_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	texture_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	texture_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files"])
	texture_file_dialog.file_selected.connect(_on_custom_texture_selected)
	add_child(texture_file_dialog)

	# Export Dialog
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.mp4 ; MP4 Video"])
	export_dialog.current_file = "piano_export.mp4"
	export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(export_dialog)
	
	# Export Progress Panel (Separate Window to keep it out of screenshots)
	export_progress_panel = Window.new()
	export_progress_panel.title = "Rendering Performance..."
	export_progress_panel.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	export_progress_panel.size = Vector2i(450, 150)
	export_progress_panel.transient = true
	export_progress_panel.exclusive = true
	export_progress_panel.unresizable = true
	export_progress_panel.visible = false
	export_progress_panel.close_requested.connect(func():
		if video_exporter: video_exporter.cancel_export()
	)
	
	var center_cont := CenterContainer.new()
	export_progress_panel.add_child(center_cont)
	
	var prog_vbox := VBoxContainer.new()
	prog_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prog_vbox.custom_minimum_size = Vector2(400, 100)
	var prog_lbl := Label.new()
	prog_lbl.text = "Rendering Performance... Please wait."
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	export_progress_bar = ProgressBar.new()
	export_progress_bar.max_value = 1.0
	prog_vbox.add_child(prog_lbl)
	prog_vbox.add_child(export_progress_bar)
	
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func():
		if video_exporter: video_exporter.cancel_export()
	)
	prog_vbox.add_child(cancel_btn)
	
	center_cont.add_child(prog_vbox)
	add_child(export_progress_panel)

func connect_signals() -> void:
	if playback:
		playback.time_updated.connect(_on_time_updated)
		playback.playback_state_changed.connect(_on_playback_state_changed)
		playback.song_loaded.connect(_on_song_loaded)

func _on_time_updated(curr_time: float) -> void:
	if is_freeplay:
		time_label.text = "Live Performance Mode"
		return

	if not is_scrubbing:
		_updating_scrubber = true
		scrubber.value = curr_time
		_updating_scrubber = false

	var total_time := 0.0
	if playback:
		total_time = playback.parser.total_duration

	time_label.text = "%s / %s" % [_format_time(curr_time), _format_time(total_time)]

func _format_time(sec: float) -> String:
	var m := int(sec / 60.0)
	var s := fmod(sec, 60.0)
	return "%02d:%04.1f" % [m, s]

func _on_playback_state_changed(is_playing: bool) -> void:
	play_btn.text = "  Pause  " if is_playing else "  Play  "

func _on_play_pressed() -> void:
	if is_freeplay:
		# Exiting freeplay into normal playback
		_on_freeplay_toggled(false)
		freeplay_btn.button_pressed = false
	if playback:
		playback.toggle_play()

func _on_reset_pressed() -> void:
	if playback:
		playback.reset()
	if keyboard:
		keyboard.reset_all_keys()
	if synth_engine:
		synth_engine.all_notes_off()
	if vfx_manager:
		vfx_manager.clear_all()
	if scrubber:
		_updating_scrubber = true
		scrubber.value = 0.0
		_updating_scrubber = false
	if time_label:
		if is_freeplay:
			time_label.text = "Live Performance Mode"
		else:
			var total_time := playback.parser.total_duration if playback else 0.0
			time_label.text = "%s / %s" % [_format_time(0.0), _format_time(total_time)]

func _on_freeplay_toggled(pressed: bool) -> void:
	is_freeplay = pressed
	if export_btn:
		export_btn.visible = not is_freeplay
	if is_freeplay and export_dock:
		export_dock.visible = false
		
	if is_freeplay:
		if freeplay_btn:
			freeplay_btn.text = "Live Performance (ON)"
		if playback:
			playback.pause()
		if note_renderer:
			note_renderer.visible = false
		if keyboard:
			keyboard.reset_all_keys()
		if synth_engine:
			synth_engine.all_notes_off()
		if vfx_manager:
			vfx_manager.clear_all()
		if time_label:
			time_label.text = "Live Performance Mode"
	else:
		if freeplay_btn:
			freeplay_btn.text = "Live Performance (with Keyboard, Mouse or MIDI Device)"
		if note_renderer:
			note_renderer.visible = true
		var curr := playback.current_time if playback else 0.0
		var total := playback.parser.total_duration if playback else 0.0
		if time_label:
			time_label.text = "%s / %s" % [_format_time(curr), _format_time(total)]

func _change_octave(new_oct: int) -> void:
	new_oct = clampi(new_oct, 1, 7)
	if new_oct == current_octave:
		return
	for keycode in pressed_pc_keys.keys():
		var pitch: int = pressed_pc_keys[keycode]
		if keyboard:
			keyboard.user_note_off.emit(pitch)
	pressed_pc_keys.clear()
	current_octave = new_oct
	_update_octave_ui()

func _update_octave_ui() -> void:
	if octave_label:
		octave_label.text = "C%d [Z/X]" % current_octave

func _on_speed_selected(idx: int) -> void:
	var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
	if playback and idx < speeds.size():
		playback.set_speed(speeds[idx])



func _on_texture_selected(idx: int) -> void:
	if not note_renderer:
		return
	if idx == 0:
		note_renderer.set_custom_texture(null) # Procedural Voronoi
	elif idx == 1:
		note_renderer.set_custom_texture(load("res://resources/textures/bubbles_cellular.tres"))
	elif idx == 2:
		note_renderer.set_custom_texture(load("res://resources/textures/cracked_ice.tres"))
	elif idx == 3:
		note_renderer.set_custom_texture(load("res://resources/textures/marble_caustic.tres"))
	elif idx == 4:
		texture_file_dialog.popup_centered_ratio(0.7)

func _on_custom_texture_selected(path: String) -> void:
	if note_renderer:
		note_renderer.load_texture_from_file(path)

func _on_open_file_pressed() -> void:
	file_dialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	if is_freeplay:
		is_freeplay = false
		freeplay_btn.button_pressed = false
		freeplay_btn.text = "Live Performance (with Keyboard, Mouse or MIDI Device)"
		if note_renderer:
			note_renderer.visible = true
	if playback:
		playback.load_midi_file(path)

func _on_load_demo_pressed() -> void:
	if is_freeplay:
		is_freeplay = false
		freeplay_btn.button_pressed = false
		freeplay_btn.text = "Live Performance (with Keyboard, Mouse or MIDI Device)"
		if note_renderer:
			note_renderer.visible = true
	if playback:
		playback.load_demo()

func _on_export_video_pressed() -> void:
	if export_dialog:
		export_dialog.popup_centered_ratio(0.7)

func _on_export_file_selected(path: String) -> void:
	if video_exporter:
		export_progress_panel.visible = true
		export_progress_bar.value = 0.0
		
		# Ensure signals are connected exactly once
		if not video_exporter.export_progress.is_connected(_on_export_progress):
			video_exporter.export_progress.connect(_on_export_progress)
			video_exporter.export_finished.connect(_on_export_finished)
			
		var vp := get_viewport()
		var fps := 60.0
		if export_fps_opt.selected == 0: fps = 30.0
		elif export_fps_opt.selected == 1: fps = 60.0
		elif export_fps_opt.selected == 2: fps = 120.0
		
		AudioServer.set_bus_mute(0, true)
		if synth_engine:
			synth_engine.all_notes_off()
			
		# Hide UI
		top_bar.visible = false
		bottom_timeline.visible = false
		left_track_dock.visible = false
		right_visuals_dock.visible = false
		if export_dock: export_dock.visible = false
			
		video_exporter.start_export(playback, vfx_manager, note_renderer, vp, path, fps, export_start_slider.value, export_end_slider.value)

func _on_export_progress(pct: float) -> void:
	export_progress_bar.value = pct
	if video_exporter and video_exporter.is_audio_pass:
		export_progress_panel.title = "Pass 1/2: Synthesizing Audio (Real-time)..."
	else:
		export_progress_panel.title = "Pass 2/2: Rendering Video..."

func _on_export_finished(success: bool, final_path: String) -> void:
	export_progress_panel.visible = false
	AudioServer.set_bus_mute(0, false)
		
	# Restore UI
	if hud_visible:
		top_bar.visible = true
		bottom_timeline.visible = true
		left_track_dock.visible = true
		right_visuals_dock.visible = true
		
	if success:
		print("Export finished successfully to ", final_path)
	else:
		push_error("Export failed.")

func _on_song_loaded() -> void:
	if playback:
		_updating_scrubber = true
		scrubber.max_value = playback.parser.total_duration
		scrubber.value = 0.0
		_updating_scrubber = false
		_refresh_track_list()
		var total_time := playback.parser.total_duration
		time_label.text = "%s / %s" % [_format_time(0.0), _format_time(total_time)]

const QUICK_PALETTE: Array[Color] = [
	Color(0.863, 0.208, 0.271, 1.0), # Crimson #dc3545
	Color(1.0, 0.72, 0.08, 1.0),    # Amber Gold
	Color(0.0, 0.75, 1.0, 1.0),     # Ice Blue
	Color(1.0, 0.45, 0.65, 1.0),    # Neon Pink
	Color(0.02, 0.84, 0.63, 1.0),   # Emerald Mint
	Color(0.62, 0.31, 0.93, 1.0),   # Royal Violet
	Color(1.0, 1.0, 1.0, 1.0),       # Pure White
]

func _refresh_track_list() -> void:
	# Clear previous track widgets (keep header and separator)
	while track_vbox.get_child_count() > 2:
		var c := track_vbox.get_child(2)
		track_vbox.remove_child(c)
		c.queue_free()

	if not playback:
		return
		
	if keyboard:
		keyboard.update_key_colors()
	
	# Loop playback UI
	var loop_chkbox := CheckBox.new()
	loop_chkbox.text = "Loop Performance"
	loop_chkbox.button_pressed = playback.loop_enabled
	loop_chkbox.toggled.connect(func(pressed: bool):
		playback.loop_enabled = pressed
	)
	track_vbox.add_child(loop_chkbox)
	track_vbox.add_child(HSeparator.new())

	# 1. Color Mode Selector (By Track vs Left / Right Hand)
	var mode_hbox := HBoxContainer.new()
	var mode_lbl := Label.new()
	mode_lbl.text = "Color Mode:"
	mode_hbox.add_child(mode_lbl)

	var mode_opt := OptionButton.new()
	mode_opt.add_item("By Track", 0)
	mode_opt.add_item("Left / Right Hand (Split C4)", 1)
	mode_opt.add_item("Gradient", 2)
	
	var sel_idx := 0
	if playback.color_mode == PlaybackController.ColorMode.LEFT_RIGHT_HAND:
		sel_idx = 1
	elif playback.color_mode == PlaybackController.ColorMode.GRADIENT:
		sel_idx = 2
	mode_opt.select(sel_idx)

	mode_opt.item_selected.connect(func(idx: int):
		var new_mode = PlaybackController.ColorMode.BY_TRACK
		if idx == 1:
			new_mode = PlaybackController.ColorMode.LEFT_RIGHT_HAND
		elif idx == 2:
			new_mode = PlaybackController.ColorMode.GRADIENT
		playback.set_color_mode(new_mode)
		_refresh_track_list()
	)
	mode_hbox.add_child(mode_opt)
	track_vbox.add_child(mode_hbox)
	track_vbox.add_child(HSeparator.new())

	if playback.color_mode == PlaybackController.ColorMode.BY_TRACK:
		# --- By Track Customizer ---
		for i in range(playback.parser.tracks.size()):
			var t: MidiParser.TrackInfo = playback.parser.tracks[i]
			var track_box := VBoxContainer.new()
			track_box.add_theme_constant_override("separation", 3)

			# Header: Visibility check + Track name + Color picker
			var row := HBoxContainer.new()
			var vis_chk := CheckBox.new()
			vis_chk.button_pressed = not t.is_muted
			vis_chk.tooltip_text = "Toggle Track Visibility"
			var track_ref: MidiParser.TrackInfo = t
			vis_chk.toggled.connect(func(pressed: bool):
				track_ref.is_muted = not pressed
			)
			row.add_child(vis_chk)

			var lbl := Label.new()
			lbl.text = "%s (%d)" % [t.name, t.note_count]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)

			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(36, 22)
			cp.color = t.color
			cp.color_changed.connect(func(col: Color):
				playback.set_track_color(i, col)
			)
			row.add_child(cp)
			track_box.add_child(row)

			# Quick Palette chips under each track
			var palette_row := HBoxContainer.new()
			palette_row.add_theme_constant_override("separation", 4)
			var p_lbl := Label.new()
			p_lbl.text = " Quick:"
			p_lbl.add_theme_font_size_override("font_size", 11)
			p_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			palette_row.add_child(p_lbl)

			for pal_col in QUICK_PALETTE:
				var btn := Button.new()
				btn.custom_minimum_size = Vector2(16, 16)
				btn.tooltip_text = "Set color to " + pal_col.to_html()
				var target_col: Color = pal_col
				var target_idx: int = i
				var btn_style := StyleBoxFlat.new()
				btn_style.bg_color = target_col
				btn_style.set_corner_radius_all(3)
				btn.add_theme_stylebox_override("normal", btn_style)
				btn.add_theme_stylebox_override("hover", btn_style)
				btn.add_theme_stylebox_override("pressed", btn_style)
				btn.pressed.connect(func():
					cp.color = target_col
					playback.set_track_color(target_idx, target_col)
				)
				palette_row.add_child(btn)

			track_box.add_child(palette_row)
			track_box.add_child(HSeparator.new())
			track_vbox.add_child(track_box)
	elif playback.color_mode == PlaybackController.ColorMode.GRADIENT:
		# --- Gradient Customizer ---
		var grad_vbox := VBoxContainer.new()
		grad_vbox.add_theme_constant_override("separation", 6)
		
		# Points list
		var grad: Gradient = playback.active_gradient
		for i in range(grad.get_point_count()):
			var pt_hbox := HBoxContainer.new()
			var idx_lbl := Label.new()
			idx_lbl.text = "Pt %d:" % i
			pt_hbox.add_child(idx_lbl)
			
			var offset_slider := HSlider.new()
			offset_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			offset_slider.max_value = 1.0
			offset_slider.step = 0.01
			offset_slider.value = grad.get_offset(i)
			
			var val_lbl := Label.new()
			val_lbl.text = "%d%%" % int(grad.get_offset(i) * 100)
			
			offset_slider.value_changed.connect(func(v: float):
				grad.set_offset(i, v)
				val_lbl.text = "%d%%" % int(v * 100)
				playback.notify_gradient_changed()
				if keyboard: keyboard.update_key_colors()
			)
			pt_hbox.add_child(offset_slider)
			pt_hbox.add_child(val_lbl)
			
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(32, 24)
			cp.color = grad.get_color(i)
			cp.color_changed.connect(func(c: Color):
				grad.set_color(i, c)
				playback.notify_gradient_changed()
				if keyboard: keyboard.update_key_colors()
			)
			pt_hbox.add_child(cp)
			
			var rm_btn := Button.new()
			rm_btn.text = "X"
			rm_btn.disabled = (grad.get_point_count() <= 2)
			rm_btn.pressed.connect(func():
				grad.remove_point(i)
				playback.notify_gradient_changed()
				_refresh_track_list()
				if keyboard: keyboard.update_key_colors()
			)
			pt_hbox.add_child(rm_btn)
			
			grad_vbox.add_child(pt_hbox)
			
		var actions_row := HBoxContainer.new()
		actions_row.add_theme_constant_override("separation", 6)

		var add_btn := Button.new()
		add_btn.text = "+ Add Point"
		add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_btn.pressed.connect(func():
			grad.add_point(0.5, Color.WHITE)
			playback.notify_gradient_changed()
			_refresh_track_list()
			if keyboard: keyboard.update_key_colors()
		)
		actions_row.add_child(add_btn)

		var apply_btn := Button.new()
		apply_btn.text = "Apply Gradient"
		apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_btn.pressed.connect(func():
			playback.notify_gradient_changed()
			if keyboard: keyboard.update_key_colors()
		)
		actions_row.add_child(apply_btn)

		grad_vbox.add_child(actions_row)
		
		track_vbox.add_child(grad_vbox)
	else:
		# --- Hand Splitting Mode (Left Hand Bass vs Right Hand Treble) ---
		var hand_vbox := VBoxContainer.new()
		hand_vbox.add_theme_constant_override("separation", 6)

		# Left Hand (Bass)
		var lh_row := HBoxContainer.new()
		var lh_lbl := Label.new()
		lh_lbl.text = "Left Hand (Bass)"
		lh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lh_row.add_child(lh_lbl)

		var lh_cp := ColorPickerButton.new()
		lh_cp.custom_minimum_size = Vector2(36, 22)
		lh_cp.color = playback.left_hand_color
		lh_cp.color_changed.connect(func(col: Color):
			playback.set_left_hand_color(col)
		)
		lh_row.add_child(lh_cp)
		hand_vbox.add_child(lh_row)

		# Left Hand Quick Palette
		var lh_pal := HBoxContainer.new()
		lh_pal.add_theme_constant_override("separation", 4)
		for pal_col in QUICK_PALETTE:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(16, 16)
			var target_col: Color = pal_col
			var btn_style := StyleBoxFlat.new()
			btn_style.bg_color = target_col
			btn_style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", btn_style)
			btn.add_theme_stylebox_override("hover", btn_style)
			btn.add_theme_stylebox_override("pressed", btn_style)
			btn.pressed.connect(func():
				lh_cp.color = target_col
				playback.set_left_hand_color(target_col)
			)
			lh_pal.add_child(btn)
		hand_vbox.add_child(lh_pal)
		hand_vbox.add_child(HSeparator.new())

		# Right Hand (Treble)
		var rh_row := HBoxContainer.new()
		var rh_lbl := Label.new()
		rh_lbl.text = "Right Hand (Treble)"
		rh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh_row.add_child(rh_lbl)

		var rh_cp := ColorPickerButton.new()
		rh_cp.custom_minimum_size = Vector2(36, 22)
		rh_cp.color = playback.right_hand_color
		rh_cp.color_changed.connect(func(col: Color):
			playback.set_right_hand_color(col)
		)
		rh_row.add_child(rh_cp)
		hand_vbox.add_child(rh_row)

		# Right Hand Quick Palette
		var rh_pal := HBoxContainer.new()
		rh_pal.add_theme_constant_override("separation", 4)
		for pal_col in QUICK_PALETTE:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(16, 16)
			var target_col: Color = pal_col
			var btn_style := StyleBoxFlat.new()
			btn_style.bg_color = target_col
			btn_style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", btn_style)
			btn.add_theme_stylebox_override("hover", btn_style)
			btn.add_theme_stylebox_override("pressed", btn_style)
			btn.pressed.connect(func():
				rh_cp.color = target_col
				playback.set_right_hand_color(target_col)
			)
			rh_pal.add_child(btn)
		hand_vbox.add_child(rh_pal)
		hand_vbox.add_child(HSeparator.new())

		# Split Pitch Slider
		var split_lbl := Label.new()
		split_lbl.text = "Split Pitch: C4 (MIDI %d)" % playback.hand_split_pitch
		hand_vbox.add_child(split_lbl)

		var split_slider := HSlider.new()
		split_slider.min_value = 21.0
		split_slider.max_value = 108.0
		split_slider.step = 1.0
		split_slider.value = float(playback.hand_split_pitch)
		split_slider.value_changed.connect(func(v: float):
			var p := int(v)
			playback.set_hand_split_pitch(p)
			split_lbl.text = "Split Pitch: %s (MIDI %d)" % [NoteData.new(p).get_note_name(), p]
		)
		hand_vbox.add_child(split_slider)
		track_vbox.add_child(hand_vbox)

func _toggle_fullscreen() -> void:
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func toggle_hud() -> void:
	hud_visible = not hud_visible
	top_bar.visible = hud_visible
	bottom_timeline.visible = hud_visible
	if not hud_visible:
		left_track_dock.visible = false
		right_visuals_dock.visible = false
		if export_dock: export_dock.visible = false
	else:
		left_track_dock.visible = true
		right_visuals_dock.visible = true

func _input(event: InputEvent) -> void:
	if video_exporter and video_exporter.is_exporting:
		return
	if (file_dialog and file_dialog.visible) or (texture_file_dialog and texture_file_dialog.visible):
		return
	var vp := get_viewport()
	if vp:
		var focused := vp.gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return

	if not (event is InputEventKey):
		return

	var key_ev: InputEventKey = event as InputEventKey

	# Handle key release for held PC keyboard piano notes
	if not key_ev.is_pressed():
		if pressed_pc_keys.has(key_ev.keycode):
			var pitch: int = pressed_pc_keys[key_ev.keycode]
			pressed_pc_keys.erase(key_ev.keycode)
			if keyboard:
				keyboard.user_note_off.emit(pitch)
			if vp:
				vp.set_input_as_handled()
		return

	# From here on, key is pressed
	if key_ev.is_echo():
		return

	# 1. Studio Shortcuts (HUD, Fullscreen, Transport)
	if key_ev.keycode == KEY_TAB or key_ev.keycode == KEY_QUOTELEFT or (key_ev.ctrl_pressed and key_ev.keycode == KEY_H):
		toggle_hud()
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_F11:
		_toggle_fullscreen()
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_SPACE:
		_on_play_pressed()
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_HOME:
		_on_reset_pressed()
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_LEFT:
		if playback:
			playback.seek(playback.current_time - 5.0)
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_RIGHT:
		if playback:
			playback.seek(playback.current_time + 5.0)
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_Z:
		_change_octave(current_octave - 1)
		if vp:
			vp.set_input_as_handled()
		return
	elif key_ev.keycode == KEY_X:
		_change_octave(current_octave + 1)
		if vp:
			vp.set_input_as_handled()
		return

	# 2. QWERTY PC Keyboard Piano Integration
	if KEY_TO_NOTE_OFFSET.has(key_ev.keycode):
		if not pressed_pc_keys.has(key_ev.keycode):
			var offset: int = KEY_TO_NOTE_OFFSET[key_ev.keycode]
			var pitch: int = (current_octave + 1) * 12 + offset
			if pitch >= 21 and pitch <= 108:
				pressed_pc_keys[key_ev.keycode] = pitch
				if keyboard:
					keyboard.user_note_on.emit(pitch, 110)
			if vp:
				vp.set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for keycode in pressed_pc_keys.keys():
			var pitch: int = pressed_pc_keys[keycode]
			if keyboard:
				keyboard.user_note_off.emit(pitch)
		pressed_pc_keys.clear()
