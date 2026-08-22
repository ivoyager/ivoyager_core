// atmosphere_limb.gdshader
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
render_mode blend_add, ambient_light_disabled, shadows_disabled, skip_vertex_transform;

// Additive atmospheric limb (haze ring) for an IVShellsModel overlay shell. Name it
// in the shell's shells.tsv "shader" column on a slightly oversized shell (e.g. scale
// 1.02). Each limb_* column in that row overrides the matching uniform below, because
// IVShellsModel feeds every (non-special) shells.tsv column to set_shader_parameter.
//
// THIN EDGE: a Fresnel rim term is ~0 across the camera-facing disk and rises to 1 at
// the edge-on limb, so the glow shows only as a thin edge. limb_falloff sets how thin.
//
// LIGHTING: lit by the same IVDynamicLight (a DirectionalLight3D pointed source->camera)
// that lights the body surface, via a custom light(). Using the engine light — rather
// than a per-frame sun-position uniform as rings.gd does — means the atmosphere's
// day/night terminator lines up with the surface terminator for free, with no plumbing.
// Under physical light the energy also carries the compensating camera's exposure, so
// the limb rides it exactly like the surface — but the limb_* values are authored
// against nonphysical O(1) energies, and that ride spans ~20+ EV. iv_limb_scale
// (IVExposureManager.limb_physical_scale while physical light is active, 1.0 otherwise)
// rebases the glow so the limb is invisible at day exposures and emerges as arcs and
// rings only when night or backlit exposure opens up.
//
// PHASE ANGLE (the reason this shader exists): like rings.gdshader, the sun/view geometry
// drives the look. dot(LIGHT, VIEW) is +1 at full phase (sun behind the camera) and -1
// when the body is backlit (sun behind it). The forward-scatter term blazes the sunward
// limb on a thin crescent (high phase); the day term is the gentler full-disk haze ring
// seen at low phase. Both terms are gated by local sunlitness (normal vs LIGHT): the
// shell is thin, so a fragment inside the planet's own shadow is exactly one whose sun
// is below the local horizon. Ungated, the phase term painted the whole limb from the
// night side close up (a blown annulus around the dark disc); gated, that dies while
// the far inferior-conjunction ring survives, because its rim fragments sit at grazing
// sunlitness (~0.5) instead of deep shadow (NdotL ~ -R/r -> 0 as r grows).
//
// ADDITIVE (blend_add): an unlit or non-backlit limb fragment contributes ~0 color, so
// there is never a dark halo against space. The rim is baked into the COLOR (not ALPHA)
// because blend_add adds straight rgb (src factor ONE) in the Forward+ renderer — ALPHA
// would be ignored.
//
// The defaults below are generic; Earth, Venus and Titan each set their own limb_* columns.
// All values are first-pass starting points, pending reference-image tuning.

#include "_farwarp.gdshaderinc"

global uniform float iv_limb_scale;

uniform vec4 limb_color : source_color = vec4(0.5, 0.65, 0.95, 1.0); // rgb tint; a unused
uniform float limb_intensity = 1.0; // master brightness
uniform float limb_falloff = 3.0; // Fresnel rim exponent; higher = thinner edge
uniform float limb_day_glow = 1.0; // front-lit (low phase) limb brightness
uniform float limb_forward_scatter = 3.0; // backlit (high phase) forward-scatter brightness
uniform float limb_phase_exponent = 4.0; // forward-scatter sharpness (cf. rings PHASE_EXPONENT)
uniform float limb_twilight = 0.2; // terminator softness; how far day glow wraps past the limb


void vertex() {
	// Farwarp remap (see _farwarp.gdshaderinc). The limb light() reads NORMAL and VIEW; both keep
	// their true orientation under the remap (it scales along the view ray).
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {
	ALBEDO = limb_color.rgb;
	ALPHA = 1.0; // blend_add ignores src alpha for color; the rim is applied in light()
}


void light() {
	vec3 normal = normalize(NORMAL);

	// Fresnel rim: 0 across the camera-facing disk, ->1 at the edge-on limb. Baked into
	// the color (see header) so the thin edge survives blend_add's alpha-less rgb add.
	float rim = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), limb_falloff);

	// Sunlit/twilight gate, aligned to the surface terminator (same light). Gates BOTH
	// terms: a thin-shell fragment with the sun below its local horizon is inside the
	// planet's own shadow, so it cannot scatter (see header). Guard the smoothstep
	// edges against limb_twilight == 0.
	float twilight = max(limb_twilight, 1e-4);
	float sunlit = smoothstep(-twilight, twilight, dot(normal, LIGHT));

	// Forward scatter: brightest where the body is backlit and we look toward the sun
	// through the limb (cf. rings.gdshader phase_mix at low phase_mix).
	float forward = pow(clamp(-dot(LIGHT, VIEW), 0.0, 1.0), limb_phase_exponent);

	float glow = rim * sunlit * (limb_day_glow + limb_forward_scatter * forward)
			* limb_intensity * iv_limb_scale;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * glow;
}
