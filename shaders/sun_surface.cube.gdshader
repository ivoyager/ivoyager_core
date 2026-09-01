// sun_surface.cube.gdshader
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
// See sun_surface.gdshader for what each mode is for; this variant changes only how the
// surface map is sampled.
render_mode unshaded, skip_vertex_transform, depth_draw_opaque;

// Cubemap counterpart of sun_surface.gdshader: the same procedural photosphere and the
// same disc/point handoff, but the optional modulation map is sampled by DIRECTION from
// a Cubemap instead of by UV from an equirect map, which removes the pole starburst and
// the +/-180 seam. IVShellsModel routes a star here automatically when its discovered
// channels are Cubemaps (see shells_model.gd _build_shader_material and
// IVAssetPreloader.cube_shader_variants); the tables are unchanged. With the Sun's map
// retired no shipped star selects this variant; it is kept, mirrored, for any star that
// ever ships a cube map over the procedural surface.
//
// Sampling stays plain bilinear, as in the equirect original — a star has no relief to
// resolve, and de-pixelating one variant but not the other would make them diverge in a
// second way. Adding texture_bicubic_cube here means adding texture_bicubic there.

#include "_detail.gdshaderinc"          // hash, value_noise (the photosphere's noise)
#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_point_spread_function.gdshaderinc"
#include "_sun_photosphere.gdshaderinc"

// A star's surface map is discovered under the "emission" tag; see the uniform note in
// sun_surface.gdshader. An unbound samplerCube samples black rather than honoring a
// default-white hint, so absence is handled in fragment() instead.
uniform samplerCube emission : source_color;
uniform bool has_emission = false;

uniform float color_bv = 0.63;       // star B-V; tints the disc (esp. with no surface map)
uniform float color_saturation = 1.0; // shared with the field, so B-V reads the same either side
uniform float brightness = 1.0;      // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float angular_radius = 0.0;  // star radius / camera distance (sun-mode sets per frame)
uniform float handoff_low = -2.0;    // px on-screen radius at/below which the quad replaces this disc
uniform float handoff_high = -1.0;   // px at/above which this disc fully replaces the quad core (defaults saturate ON)
global uniform float iv_exposure;    // compensating-camera exposure; 1.0 when off (see stars.gdshader)

// Photosphere parameters; see sun_surface.gdshader (kept identical here).
uniform float granulation_scale = 500.0;
uniform float granulation_contrast = 0.10;
uniform float mottle_scale = 45.0;
uniform float mottle_contrast = 0.015;
uniform float spot_cell_scale = 6.0;
uniform float spot_activity = 0.12;
uniform float spot_belt_center_deg = 15.0;
uniform float spot_belt_width_deg = 9.0;
uniform float umbra_level = 0.15;
uniform float penumbra_level = 0.75;
uniform float facula_contrast = 0.06;
uniform float spot_seed = 0.0;

varying vec3 model_position; // unit-sphere local position (the cubemap sample direction)
varying flat float v_alpha;
varying vec3 v_view_position;  // pre-farwarp view-space position, for the incidence cosine
varying vec3 v_view_normal;
varying flat float v_pixel_radius; // rendered px per radian of surface arc (alias fades)

void vertex() {
	model_position = VERTEX; // captured before farwarp overwrites VERTEX
	vec3 view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view_position = view_position;
	// A unit sphere's normal is its own local position.
	v_view_normal = MODELVIEW_NORMAL_MATRIX * VERTEX;
	VERTEX = farwarp(view_position);
	float pixel_radius = body_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
	v_pixel_radius = pixel_radius;
	v_alpha = body_disc_weight(pixel_radius, handoff_low, handoff_high);
}

void fragment() {
	// Discard rather than draw a fully-faded disc; see sun_surface.gdshader for why this
	// must resolve per viewport rather than through a CPU "visible" flag.
	if (v_alpha <= 0.0) {
		discard;
	}
	// See sun_surface.gdshader for why mu is per-fragment.
	float mu = clamp(dot(normalize(-v_view_position), normalize(v_view_normal)), 0.0, 1.0);
	vec3 dir = normalize(model_position);
	float intensity = photosphere_intensity(dir, mu, granulation_scale, granulation_contrast,
			mottle_scale, mottle_contrast, spot_cell_scale, spot_activity,
			spot_belt_center_deg, spot_belt_width_deg, umbra_level, penumbra_level,
			facula_contrast, spot_seed, v_pixel_radius);
	vec3 surface = photosphere_color(intensity) * photosphere_limb_darkening(mu);
	if (has_emission) {
		surface *= display_decode(texture(emission, dir).rgb);
	}
	// Scalar cap at the shared f16-safe ceiling; see sun_surface.gdshader.
	float disc_light = min(brightness * iv_exposure, PSF_LIGHT_MAX);
	// Nothing sampled this radiance, so no renderer decode cancels against it: it crosses
	// into the renderer's own colour space here (see _display.gdshaderinc).
	ALBEDO = display_write(surface * color_from_b_v(color_bv, color_saturation) * disc_light);
	ALPHA = v_alpha;
}
