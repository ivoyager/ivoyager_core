// body_psf.gdshader
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

// The camera's point-spread response to one body's flux: the Gaussian PSF core plus the
// r^-2 glare wing, on a camera-facing quad. Driven by IVBodyPSF, which sets the apparent
// magnitude and angular radius from true (un-farwarped) geometry each frame -- for an
// in-scene star from its own luminosity, for a sunlit body from its albedo, phase and the
// two distances. The law is the catalog star field's, shared function for function through
// _point_spread_function.gdshaderinc, which is what welds an in-scene source to the sky
// behind it: this fragment should read as stars.gdshader's sibling, because it is one.
//
// THE TWO REGIMES. Unresolved, this quad IS the body: the core takes the disc handoff
// (angular_radius -> pixel radius -> the crossfade the surface shader fades out on), so a
// body that shrinks past its disc becomes a photometric point rather than vanishing at a
// distance cull. Resolved, the WING persists -- glare belongs to the camera and not to the
// subject, so it takes no crossfade -- and that persisting wing is the crescent glow.
//
// WHY ONE ITEM RATHER THAN TWO. This merges what were sun_point.gdshader (a point sprite)
// and sun_glare.gdshader (a quad). Two draws are two adds in the blend, and on the
// display-referred renderer a blend runs on ENCODED values, where a sum is not a sum. Core
// and wing are therefore summed in linear here and cross into the renderer's colour space
// through one display_write(), exactly as the field's own fragment does. One item is also
// one farwarped position, one uniform set, and one place for what used to be a discipline
// note ("must track stars.gdshader uniform for uniform").
//
// WHY A QUAD. POINT_SIZE's driver maximum is 64 in the Vulkan spec's floor and as little as
// 1 in the GLES3 spec's -- and the web export is GLES3 -- while the glare law runs to ~700 px
// for the sun seen from Earth. A quad has no cap. (The field keeps sprites and accepts the
// clamp as a stated risk: it can only truncate a wing's faint outer part.)
//
// Rendered on a 6-vertex unit quad parented to the body's IVBody, so it sits at the true
// position and rides the origin shift; the per-vertex farwarp remap (shared with the field)
// keeps it inside the camera far plane at any distance. blend_add + depth_draw_never with the
// depth test left on: an opaque body in front cuts it where it covers it, it never occludes
// anything, and it sums like light.
//
// KNOWN ARTIFACT, and why the final write stays in one place. Over a bright background -- the
// Milky Way's bulge -- blend_add on the display-referred renderer lands enc(g) where the
// linear sum wants enc(bg + g) - enc(bg), several-fold at the wing's faint end, so the halo
// reads ~2-3x wider there than over dark sky. (Forward+ adds in linear.) The exact fix is a
// screen-texture increment -- sample hint_screen_texture, write enc(dec(S) + g) - S under the
// same blend_add -- at the cost of one backbuffer copy per frame while a quad is visible.
// Not implemented; the fragment's one final write is kept in one place so it can slot in.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_point_spread_function.gdshaderinc"

// The field's photometry, shared value for value with stars.gdshader through IVStarSettings,
// which owns the uniform names. These defaults must track that shader's; nothing enforces it,
// and any drift shows up as an in-scene source disagreeing with the stars around it.
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
global uniform float iv_exposure; // a global, so this cannot drift from the field

// Per-body, set each frame by IVBodyPSF. Both are viewport-independent: this shader
// resolves them against its own VIEWPORT_SIZE and PROJECTION_MATRIX, so an off-screen
// capture is sized for its own buffer rather than for the main window.
uniform float apparent_magnitude = -20.0; // V magnitude at the current distance and phase
uniform float color_bv = 0.63;            // B-V -> source color, through the field's ramp
uniform float angular_radius = 0.0;       // body radius / camera distance; the LOD ramp's input
uniform float handoff_low = 1.0;          // px radius at/below which this fully replaces the disc
uniform float handoff_high = 2.5;         // px at/above which the disc fully replaces this core

varying flat float v_intensity; // core intensity, crossfade already folded in
varying flat float v_glare;     // wing amplitude at 1 px
varying flat float v_radius;    // the quad's half-width in px
varying vec2 v_offset;          // this vertex's corner, in [-1, 1]


void vertex() {
	// VERTEX.xy carries the corner sign; the mesh is a unit quad and the size is set here.
	v_offset = VERTEX.xy;
	// The body itself sits at the mesh origin. Project THAT, then push the corner out in
	// clip space, so the quad is camera-facing and sized in pixels at any orientation.
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec4 center = PROJECTION_MATRIX * vec4(view_position, 1.0);
	// Unclamped, and both compensations belong here rather than in the fragment: a source
	// brightened by a zoom or a taller render must saturate a correspondingly wider core --
	// that is what a longer exposure does, not a post-hoc gain on the pixels.
	float flux = flux_from_magnitude(apparent_magnitude, intensity_faint_mag);
	float resolution_scale = VIEWPORT_SIZE.y / iv_reference_viewport_height;
	float intensity = intensity_scale * pow(flux, intensity_gamma)
			* point_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov,
			fov_compensation)
			* resolution_scale * resolution_scale * iv_exposure;
	// The crossfade scales the core's intensity, so a partly-faded core is photometrically
	// just a fainter source -- size and peak stay welded by the size law at every fade level,
	// and no special case or size floor is needed. The WING takes the full intensity: it does
	// not fade, because the crossfade decides whether the camera RESOLVES the body and glare
	// is the imaging system's, not the subject's. A resolved body glares harder, not less.
	float pixel_radius = body_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1],
			VIEWPORT_SIZE.y);
	v_intensity = intensity * (1.0 - body_disc_weight(pixel_radius, handoff_low,
			handoff_high));
	v_glare = psf_glare_amplitude(intensity, glare_scale, glare_gamma,
			glare_max_px * resolution_scale);
	// The quad must span whichever component reaches further. psf_visible_size returns a
	// DIAMETER and psf_glare_draw_size a RADIUS, so the core halves and the wing does not.
	v_radius = max(0.5 * psf_visible_size(v_intensity, psf_sigma),
			psf_glare_draw_size(v_glare));
	// One NDC unit is half the viewport, and the corner offset is in clip units, so it
	// scales by w. Behind the camera (w <= 0) that scaling flips the corners and would draw
	// the quad mirrored across the frame instead of not at all -- farwarp keeps the body
	// inside the FAR plane and says nothing about the near one -- so every corner goes
	// outside the guard band and the triangles clip away. Written as a branch on POSITION
	// rather than an early exit: Godot's shader language rejects a return in vertex().
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
	// Core plus wing, summed in linear before the one conversion, so the pair crosses into
	// the renderer's colour space as one value rather than as two adds in the blend (see
	// header). Both multiply here rather than via ALPHA so they see full precision before the
	// f16 buffer write; see psf_core_light_sprite. Nothing sampled this radiance, so no renderer
	// decode cancels against it: it crosses over here (see _display.gdshaderinc).
	float light = psf_core_light(v_intensity, radius_px, psf_sigma)
			+ psf_glare_light(v_glare, radius_px);
	ALBEDO = display_write(color_from_b_v(color_bv, color_saturation) * light);
	ALPHA = 1.0; // blend_add: the add is ALBEDO * ALPHA, already folded above
}
