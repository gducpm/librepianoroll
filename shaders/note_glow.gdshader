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

uniform vec4 base_color : source_color = vec4(0.863, 0.208, 0.271, 1.0); // Brand #dc3545
uniform vec4 head_glow_color : source_color = vec4(1.0, 0.65, 0.75, 1.0);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.25;
uniform float hdr_intensity : hint_range(1.0, 5.0) = 2.4;
uniform float border_glow : hint_range(0.0, 1.0) = 0.45;

// Signed Distance Field for rounded rectangle
float sd_rounded_box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
    vec2 uv = UV;
    // Map UV from [0, 1] to centered [-1, 1]
    vec2 p = (uv - vec2(0.5)) * 2.0;

    // Aspect ratio compensation
    vec2 half_size = vec2(0.88, 0.94);
    float d = sd_rounded_box(p, half_size, corner_radius * 2.0);

    // Smooth antialiased border
    float alpha = 1.0 - smoothstep(-0.04, 0.02, d);
    if (alpha <= 0.001) {
        discard;
    }

    // Vertical gradient: Note head (bottom, y near 1.0) glows hottest
    float head_factor = smoothstep(0.0, 1.0, uv.y);
    vec3 col = mix(base_color.rgb, head_glow_color.rgb, pow(head_factor, 1.6));

    // Outer neon edge halo
    float edge_factor = smoothstep(-0.15, -0.01, d);
    col += head_glow_color.rgb * edge_factor * border_glow * 1.5;

    // Hot center core
    float center_x = 1.0 - abs(p.x);
    col += vec3(0.3, 0.2, 0.25) * pow(center_x, 2.5) * head_factor;

    // HDR Emission: multiply by hdr_intensity (> 1.0) to activate Godot WorldEnvironment Bloom
    COLOR = vec4(col * hdr_intensity, alpha * base_color.a);
}
