// sun_point.gdshader
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2019-2026 Charlie Whitfield
// I, Voyager is a registered trademark of Charlie Whitfield in the US
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// *****************************************************************************
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, blend_add, depth_draw_never;

// Far representation of an in-scene star ("sun"): a single point sprite, drawn with the
// same photometry as the catalog star field (stars.gdshader) but UNCLAMPED, so it stays
// on the same magnitude scale as the background stars and dims with distance instead of
// pinning to white. Rendered on a 1-vertex PRIMITIVE_POINTS mesh parented to the star's
// IVBody; the per-vertex farwarp remap (shared with the field) keeps it inside the camera
// far plane at any distance. blend_add + depth_draw_never: opaque bodies occlude it (depth
// test stays on) but it never occludes anything and sums like light.
//
// Driven by IVSpheroidModel sun-mode, which owns the disc<->point crossfade: it sets
// point_size (the star's true on-screen size, floored so a receding sun doesn't
// scintillate below a pixel) and apparent_magnitude (recomputed each frame from the true
// camera distance). Unlike the field it omits fov-compensation -- a lone object should
// track distance, not zoom.
//
// intensity is HDR (>1) and intentionally unclamped: with no glow pass it clips to white
// in the framebuffer (as the field's brightest stars do), but a future glow pass will
// bloom it in proportion to the star's true brightness. See _star_point.gdshaderinc for
// the shared helpers and stars.gdshader for the clamped field counterpart.

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

uniform float apparent_magnitude = -20.0; // V magnitude at the current distance (sun-mode sets per frame)
uniform float color_bv = 0.63;            // star B-V -> point color
uniform float point_size = 4.0;           // px; sun-mode sets from true angular size, floored
uniform float intensity_fade = 1.0;       // 0..1 LOD crossfade-in (sun-mode ramps it against the disc)
uniform float reference_mag = 6.5;        // magnitude mapping to flux 1.0 (matches the field's intensity_faint_mag)
uniform float intensity_scale = 0.5;      // linear intensity at reference_mag
uniform float intensity_gamma = 0.35;     // dynamic-range compression of flux

void vertex() {
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	POINT_SIZE = point_size;
}

void fragment() {
	float dist_sq = star_point_dist_sq(POINT_COORD);
	if (dist_sq > 1.0) {
		discard; // round mask; drops the square point-sprite corners
	}
	float flux = star_flux(apparent_magnitude, reference_mag);
	float intensity = intensity_scale * pow(flux, intensity_gamma) * intensity_fade; // unclamped HDR; glow will bloom it
	ALBEDO = star_color(color_bv) * intensity;
	ALPHA = exp(-4.0 * dist_sq); // soft Gaussian core; blend_add scales the add by ALPHA
}
