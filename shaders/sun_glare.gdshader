// sun_glare.gdshader
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

// An in-scene star's GLARE: the wide r^-2 wings its Gaussian core does not have. The law,
// the defaults and the reasoning are all in _star_point.gdshaderinc (star_glare_*), shared
// with the catalog field, which carries the same wing on its own point sprites -- one camera,
// one law, one IVStarSettings, exactly as the intensity chain already is.
//
// WHY THIS IS A QUAD AND THE FIELD'S IS NOT. Geometry is the only difference between the two,
// and it is forced: a point sprite's footprint is POINT_SIZE, whose driver maximum is 64 in
// the Vulkan spec's floor and as little as 1 in the GLES3 spec's -- and the web export is
// GLES3. A field star's glare reaches 2-6 px and rides its sprite; the sun's runs to hundreds
// and cannot. So this draws a camera-facing quad sized in the vertex shader, positioned by
// the same farwarp remap the point uses, and reading the same radius law. There is one star,
// so the extra draw is one.
//
// It is NOT faded by the disc/point crossfade, and that is deliberate: the crossfade decides
// whether the camera RESOLVES the star, and glare is the imaging system's, not the subject's.
// A resolved sun glares harder, not less. So the glare rides the star's own apparent
// magnitude at every distance and the two halves under it trade places beneath it.
//
// Rendered on a 6-vertex triangle mesh parented to the star's IVBody, driven by IVShellsModel
// sun-mode, which sets apparent_magnitude each frame. blend_add + depth_draw_never with the
// depth test left on, as for sun_point: an opaque body in front of the star cuts the glare
// where it covers it, and the glare never occludes anything.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

// The field's photometry, shared value for value with stars.gdshader and sun_point.gdshader
// through IVStarSettings; these defaults must track theirs.
uniform float psf_sigma = 0.5;
uniform float intensity_faint_mag = 6.5;
uniform float intensity_gamma = 1.0;
uniform float intensity_scale = 0.5;
uniform float color_saturation = 1.0;
uniform float glare_scale = 0.0126;
uniform float glare_gamma = 0.286;
uniform float glare_max_px = 384.0;
global uniform float iv_reference_viewport_height;
uniform float reference_tan_half_fov = 0.4663;
uniform float fov_compensation = 1.0;
global uniform float iv_exposure;

uniform float apparent_magnitude = -20.0; // V magnitude at the current distance (sun-mode sets per frame)
uniform float color_bv = 0.63;            // star B-V -> glare color

varying flat float v_glare;  // wing amplitude at 1 px
varying flat float v_radius; // the quad's half-width in px, i.e. the wing's outer radius
varying vec2 v_offset;       // this vertex's corner, in [-1, 1]


void vertex() {
	// VERTEX.xy carries the corner sign; the mesh is a unit quad and the size is set here.
	v_offset = VERTEX.xy;
	// The star itself sits at the mesh origin. Project THAT, then push the corner out in
	// clip space, so the quad is camera-facing and sized in pixels at any orientation.
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec4 center = PROJECTION_MATRIX * vec4(view_position, 1.0);
	float flux = star_flux(apparent_magnitude, intensity_faint_mag);
	float resolution_scale = VIEWPORT_SIZE.y / iv_reference_viewport_height;
	float intensity = intensity_scale * pow(flux, intensity_gamma)
			* star_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov,
			fov_compensation)
			* resolution_scale * resolution_scale * iv_exposure;
	v_glare = star_glare_amplitude(intensity, glare_scale, glare_gamma,
			glare_max_px * resolution_scale);
	v_radius = star_glare_draw_size(v_glare);
	// One NDC unit is half the viewport, and the corner offset is in clip units, so it
	// scales by w. Behind the camera (w <= 0) that scaling flips the corners and would draw
	// the glare mirrored across the frame instead of not at all -- farwarp keeps the star
	// inside the FAR plane and says nothing about the near one -- so every corner goes
	// outside the guard band and the triangles clip away. Written as a branch on POSITION
	// rather than an early exit: Godot's shader language rejects `return` in vertex().
	vec2 ndc_radius = 2.0 * v_radius / VIEWPORT_SIZE;
	if (center.w > 0.0) {
		POSITION = vec4(center.xy + v_offset * ndc_radius * center.w, center.zw);
	} else {
		POSITION = vec4(2.0, 2.0, 1.0, 1.0);
	}
}


void fragment() {
	float radius_px = length(v_offset) * v_radius;
	if (radius_px > v_radius) {
		discard; // round mask; drops the square quad's corners
	}
	// Nothing sampled this radiance, so no renderer decode cancels against it: it crosses
	// into the renderer's own colour space here (see _display.gdshaderinc). The core is a
	// separate draw (sun_point / sun_surface), so this fragment's whole term is the wing.
	ALBEDO = display_write(star_color(color_bv, color_saturation)
			* star_glare_light(v_glare, radius_px));
	ALPHA = 1.0; // blend_add: the add is ALBEDO * ALPHA, already folded above
}
