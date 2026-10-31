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

uniform vec4 key_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.863, 0.208, 0.271, 1.0); // Brand #dc3545
uniform float press_intensity : hint_range(0.0, 1.0) = 0.0;
uniform bool is_black_key = false;
uniform vec2 key_size = vec2(36.0, 210.0);
uniform float corner_radius : hint_range(0.0, 20.0) = 4.0;

void fragment() {
    vec2 uv = UV;
    vec3 base;

    // Pixel space coordinates centered at key center
    vec2 p = (uv - 0.5) * key_size;
    vec2 b = key_size * 0.5;

    // Rounded corners at the bottom of the key (facing the player)
    // Top of key tucked under fallboard remains square (r = 0.0)
    float r = (p.y > 0.0) ? corner_radius : 0.0;
    r = min(r, min(b.x, b.y));
    vec2 q = abs(p) - b + r;
    float d = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;

    // Smooth boundary discard for rounded corners
    if (d > 0.5) {
        discard;
    }
    float edge_alpha = clamp(0.5 - d, 0.0, 1.0);

    if (press_intensity > 0.01) {
        // Uniform, solid, static illumination across the entire key (no gradient)
        base = glow_color.rgb * 1.5;
    } else {
        if (is_black_key) {
            // Pure jet black key when idle, but with a faint ambient reflection of the glow at the top
            float ambient = smoothstep(0.4, 0.0, uv.y) * 0.45;
            base = mix(vec3(0.0), glow_color.rgb, ambient);
        } else {
            // Glossy ivory white key with subtle bottom shadow bevel when idle
            float shadow = smoothstep(0.88, 1.0, uv.y) * 0.12;
            base = vec3(0.96, 0.96, 0.98) - shadow;
            
            // Faint ambient reflection at the top
            float ambient = smoothstep(0.3, 0.0, uv.y) * 0.35;
            base = mix(base, glow_color.rgb, ambient);
        }
    }

    COLOR = vec4(base, edge_alpha);
}
