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

// Cubemap counterpart of sun_surface.gdshader: the same emissive disc and the same
// disc/point handoff, but the surface map is sampled by DIRECTION from a Cubemap
// instead of by UV from an equirect map, which removes the pole starburst and the
// +/-180 seam. IVSpheroidModel routes a star here automatically when its discovered
// channels are Cubemaps (see spheroid_model.gd _build_shader_material and
// IVAssetPreloader.cube_shader_variants); the tables are unchanged.
//
// Sampling stays plain bilinear, as in the equirect original — a star has no relief to
// resolve, and de-pixelating one variant but not the other would make them diverge in a
// second way. Adding texture_bicubic_cube here means adding texture_bicubic there.

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

// A star's surface map is discovered under the "emission" tag; see the uniform note in
// sun_surface.gdshader. An unbound samplerCube samples black rather than honoring a
// default-white hint, so absence is handled in fragment() instead.
uniform samplerCube emission : source_color;
uniform bool has_emission = false;

uniform float color_bv = 0.63;       // star B-V; tints the disc (esp. with no surface map)
uniform float color_saturation = 1.0; // shared with the field, so B-V reads the same either side
uniform float brightness = 1.0;      // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float angular_radius = 0.0;  // star radius / camera distance (sun-mode sets per frame)
uniform float handoff_low = 1.0;     // px on-screen radius at/below which the point fully replaces this disc
uniform float handoff_high = 2.5;    // px at/above which this disc fully replaces the point

varying vec3 model_position; // unit-sphere local position (the cubemap sample direction)
varying flat float v_alpha;

void vertex() {
	model_position = VERTEX; // captured before farwarp overwrites VERTEX
	VERTEX = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pixel_radius = sun_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
	v_alpha = sun_disc_weight(pixel_radius, handoff_low, handoff_high);
}

void fragment() {
	// Discard rather than draw a fully-faded disc; see sun_surface.gdshader for why this
	// must resolve per viewport rather than through a CPU "visible" flag.
	if (v_alpha <= 0.0) {
		discard;
	}
	vec3 surface = vec3(1.0);
	if (has_emission) {
		surface = texture(emission, normalize(model_position)).rgb;
	}
	ALBEDO = surface * star_color(color_bv, color_saturation) * brightness;
	ALPHA = v_alpha;
}
