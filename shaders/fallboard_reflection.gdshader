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

uniform vec4 wood_base : source_color = vec4(0.04, 0.04, 0.05, 1.0);
uniform vec4 rim_color : source_color = vec4(0.863, 0.208, 0.271, 0.3); // Brand #dc3545 accent
uniform float glossiness : hint_range(0.0, 1.0) = 0.85;

void fragment() {
    vec2 uv = UV;
    // Glossy gradient: darker at top, subtle ambient mirror reflection near keyboard
    float mirror_falloff = smoothstep(0.0, 1.0, uv.y);
    vec3 col = mix(wood_base.rgb * 0.6, wood_base.rgb * 1.4, mirror_falloff);

    // Subtle brushed specular reflection line
    float spec = exp(-pow((uv.y - 0.92) / 0.06, 2.0)) * 0.15;
    col += vec3(spec);

    // Subtle brand accent trim line at bottom
    float rim = smoothstep(0.96, 1.0, uv.y) * 0.4;
    col += rim_color.rgb * rim;

    COLOR = vec4(col, 1.0);
}
