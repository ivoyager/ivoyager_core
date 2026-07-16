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

// Far representation of an in-scene star ("sun"): a single point sprite carrying the catalog
// star field's photometry exactly. Every line of the intensity chain below is
// stars.gdshader's, uniform for uniform, and must stay that way -- past the disc handoff the
// sun IS a field star. From the Oort cloud it sits among its neighbors, and a divergence in
// any of flux, gamma, PSF, size, fov or resolution law would single it out of its own sky.
// See stars.gdshader for what each shared uniform does and why. Only the difference is
// documented here, and there is exactly one: the LOD crossfade against the sun_surface disc.
//
// Rendered on a 1-vertex PRIMITIVE_POINTS mesh parented to the star's IVBody; the per-vertex
// farwarp remap (shared with the field) keeps it inside the camera far plane at any distance.
// blend_add + depth_draw_never: opaque bodies occlude it (depth test stays on) but it never
// occludes anything and sums like light.
//
// Driven by IVSpheroidModel sun-mode, which sets apparent_magnitude and angular_radius from
// the true camera distance each frame. Both are viewport-independent; this shader resolves
// them against its own VIEWPORT_SIZE and PROJECTION_MATRIX, so an off-screen capture is sized
// for its own buffer rather than for the main window.
//
// The crossfade scales intensity, so a partly-faded point is photometrically just a fainter
// star -- size and peak stay welded by the size law at every fade level, and no special case
// or size floor is needed (see stars.gdshader for why a floor cannot help a field sized this
// way). At the sun's flux the sqrt(ln) size response compresses the fade: the point holds
// near its full size through most of the ramp and reads as a brightness fade, which is what
// lets the solved handoff match its size to the disc's. angular_radius feeds the LOD ramp
// and nothing else -- it does not size the sprite. That split is what the handoff is for: an
// unresolved star is a PSF whose footprint tracks brightness rather than geometry, since a
// camera cannot render detail it never resolved; once the disc resolves, sun_surface takes
// over and geometry rules again.

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

// The field's photometry, shared value for value. These defaults must track stars.gdshader's
// (and IVStarsVisual's exports, which push them); nothing enforces that, and any drift shows
// up as the sun disagreeing with the stars around it.
uniform float psf_sigma = 0.5;
uniform float intensity_faint_mag = 6.5;
uniform float intensity_gamma = 1.0;
uniform float intensity_scale = 0.5;
uniform float color_saturation = 1.0;
global uniform float iv_reference_viewport_height;
uniform float reference_tan_half_fov = 0.4663;
uniform float fov_compensation = 1.0;

uniform float apparent_magnitude = -20.0; // V magnitude at the current distance (sun-mode sets per frame)
uniform float color_bv = 0.63;            // star B-V -> point color
uniform float angular_radius = 0.0;       // star radius / camera distance; the LOD ramp's input alone
uniform float handoff_low = 1.0;          // px on-screen radius at/below which this point fully replaces the disc
uniform float handoff_high = 2.5;         // px at/above which the disc fully replaces this point

varying flat float v_intensity;
varying flat float v_falloff;

void vertex() {
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	float pixel_radius = sun_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
	float flux = star_flux(apparent_magnitude, intensity_faint_mag);
	float resolution_scale = VIEWPORT_SIZE.y / iv_reference_viewport_height;
	float intensity = intensity_scale * pow(flux, intensity_gamma)
			* star_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov,
			fov_compensation)
			* resolution_scale * resolution_scale
			* (1.0 - sun_disc_weight(pixel_radius, handoff_low, handoff_high));
	v_intensity = intensity;
	POINT_SIZE = star_visible_size(intensity, psf_sigma);
	v_falloff = star_psf_falloff(POINT_SIZE, psf_sigma);
}

void fragment() {
	float dist_sq = star_point_dist_sq(POINT_COORD); // 0 at center, 1 at the inscribed circle
	if (dist_sq > 1.0) {
		discard; // round mask; drops the square point-sprite corners
	}
	// The PSF multiplies in-shader rather than via ALPHA so it sees full precision
	// before the f16 buffer write; see star_point_light. The sun is where this bites:
	// its intensity exceeds f16 max everywhere the camera can reach.
	ALBEDO = star_color(color_bv, color_saturation) * star_point_light(v_intensity, dist_sq, v_falloff);
	ALPHA = 1.0; // blend_add: the add is ALBEDO * ALPHA, already folded above
}
