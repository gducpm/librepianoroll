// LibrePianoRoll - Next-generation, high-performance libre piano visualizer
// Copyright (C) 2026  gducpm <gducpm@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

shader_type canvas_item;
render_mode blend_add;

uniform bool use_screen_space = true;
uniform vec2 texture_scale = vec2(4.0, 2.25);
uniform vec2 texture_scroll = vec2(0.0, 0.0);
uniform sampler2D custom_glass_texture : filter_linear_mipmap, repeat_enable;
uniform bool use_custom_texture = false;

varying vec4 v_custom;
varying vec4 v_color;

void vertex() {
    v_custom = INSTANCE_CUSTOM;
    v_color = COLOR;
}

void fragment() {
    vec2 sample_uv;
    if (use_screen_space) {
        // Anchored to viewport coordinates (stays in the same position on the screen!)
        sample_uv = SCREEN_UV * texture_scale + TIME * texture_scroll;
    } else {
        sample_uv = UV;
    }

    vec4 tex = texture(custom_glass_texture, sample_uv);
    COLOR = vec4(tex.rgb, 1.0);
}
