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

uniform float hdr_intensity : hint_range(1.0, 8.0) = 2.6;
uniform float bubble_density : hint_range(0.5, 8.0) = 2.0;
uniform float glass_refraction : hint_range(0.0, 2.5) = 1.2;
uniform float time_speed : hint_range(0.0, 2.0) = 0.2;
uniform float custom_time = 0.0;
uniform float global_time = 0.0;
uniform float strike_y = 870.0; // Piano strike rail boundary

// Screen-space / Viewport locking
uniform bool use_screen_space = true;
uniform vec2 texture_scale = vec2(3.5, 2.0);
uniform vec2 texture_scroll_speed = vec2(0.0, 0.0);

// Hardware texture sampler (ultra-fast 1-cycle lookup)
uniform bool use_custom_texture = true;
uniform sampler2D custom_texture : filter_linear_mipmap, repeat_enable;

varying vec4 v_custom;
varying vec4 v_color;
varying float v_world_y;

void vertex() {
    v_custom = INSTANCE_CUSTOM;
    v_color = COLOR;
    v_world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

// Fast 2D Hash
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Single-pass fast Voronoi cellular
vec2 fast_voronoi(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float md = 8.0;
    float md2 = 8.0;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash2(n + g) * 0.7 + 0.15;
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md2 = md;
                md = d;
            } else if (d < md2) {
                md2 = d;
            }
        }
    }
    return vec2(sqrt(md), sqrt(md2));
}

void fragment() {
    // Occlude falling tiles behind the piano strike rail (falls straight through behind)
    if (v_world_y > strike_y) {
        discard;
    }

    vec2 uv = UV;
    vec4 base_color = v_color;
    if (base_color.a <= 0.01) {
        base_color = vec4(0.863, 0.208, 0.271, 1.0); // fallback brand #dc3545
    }

    // Aspect ratio: height / width
    float aspect = max(v_custom.z, 0.2);
    float vel = clamp(v_custom.x, 0.35, 1.4);

    // 2D Sleek Rounded Rectangle Tile with distinct borders
    // p: local coordinates centered at (0, 0)
    vec2 p = vec2(uv.x - 0.5, (uv.y - 0.5) * aspect);
    vec2 b = vec2(0.47, 0.5 * aspect); // half-extents

    // Generous rounded rectangle corners
    float r = min(0.34, b.y * 0.45);
    r = min(r, b.x);

    vec2 q = abs(p) - b + r;
    float d = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;

    // Fast discard outside tile boundary
    if (d > 0.01) {
        discard;
    }
    float alpha = 1.0 - smoothstep(-0.02, 0.01, d);

    // Glass edge bevel and well-defined, thicker colored border stroke
    float edge_dist = -d;
    float border_width = 0.09;
    float border_stroke = smoothstep(0.0, 0.018, edge_dist) * (1.0 - smoothstep(border_width - 0.02, border_width, edge_dist));
    float rim_glow = 1.0 - smoothstep(0.0, 0.13, edge_dist);
    float inner_bevel = smoothstep(0.0, 0.22, edge_dist);
    float fresnel = exp(-edge_dist * 5.0);

    // Screen-space vs local UV coordinates
    // User requested to just anchor to viewport and animate slowly
    vec2 sample_uv = SCREEN_UV * texture_scale * bubble_density + vec2(0.0, -0.15) * global_time;

    float glass_pattern = 0.0;
    float bubble_glint = 0.0;

    if (use_custom_texture) {
        // Ultra-fast 1-cycle GPU hardware texture sample
        vec4 tex_sample = texture(custom_texture, sample_uv);
        float lum = tex_sample.r * 0.5 + tex_sample.g * 0.4 + tex_sample.b * 0.1;
        glass_pattern = lum * 1.2 * glass_refraction;
        bubble_glint = pow(clamp(lum, 0.0, 1.0), 3.0) * 0.8;
    } else {
        // Fast procedural fallback
        vec2 v = fast_voronoi(sample_uv);
        float bubble_ring = exp(-pow((v.x - 0.28) / 0.12, 2.0)) * 1.2;
        float cell_wall = smoothstep(0.03, 0.18, v.y - v.x) * 0.8;
        glass_pattern = (bubble_ring + cell_wall * 0.7) * glass_refraction;
        bubble_glint = exp(-pow(v.x / 0.10, 2.0)) * 1.0;
    }

    // Cylindrical glass reflection along the left flank
    float spec_x = 1.0 - abs(uv.x - 0.28) * 3.4;
    float glass_spec = pow(clamp(spec_x, 0.0, 1.0), 3.5) * 0.3 * inner_bevel;

    // Translucent dark colored glass body with luminous bubbles/texture
    vec3 col = base_color.rgb * (1.0 + glass_pattern * 1.5) * vel;

    // Specular highlight: tinted with base_color with white core
    vec3 spec_tint = mix(base_color.rgb, vec3(1.0), 0.5);
    col += spec_tint * (glass_spec * 0.3 + bubble_glint * 0.3);

    // HDR Emission: multiply by hdr_intensity for Forward+ Vulkan bloom
    COLOR = vec4(col * hdr_intensity * 0.9, alpha * base_color.a);
}
