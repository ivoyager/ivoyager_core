// _clouds.gdshaderinc
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

// What a body's CLOUD DECK does to the shell beneath it. Included by the shaders that draw
// that shell, not by the one that draws the deck.
//
// Requires, in this order before it: _display.gdshaderinc (display_decode) and
// _atmosphere.gdshaderinc (atm_luma).


// Fed by IVShellsModel._propagate_cloud_shadow from the body's own cloud shell. A body with
// no deck leaves the scale at 0 and not a line below is read. Only a deck whose map keeps its
// coverage and its optical thickness apart can cast a shadow: a composited map's alpha is a
// compositing weight and not a transmittance, so `clouds_two_stream_map` gates the propagation
// on the deck's own side.
uniform samplerCube clouds_shadow_map : source_color;
uniform float clouds_shadow_scale = 0.0; // the deck's radius / this shell's; <= 1 disables
uniform vec3 clouds_shadow_range_lo = vec3(0.0);
uniform vec3 clouds_shadow_range_hi = vec3(1.0);
// Where the deck is DRAWN, as (cos, sin) of its spin about +Y. A deck that drifts over the
// surface is a map this shell samples in a frame the deck has turned out of, so the lookup
// below turns back into the deck's own before it reads -- without this the shadow is cast by
// the deck's UNSPUN map and walks away from the cloud it belongs to. Identity for a fixed deck.
uniform vec2 clouds_shadow_spin = vec2(1.0, 0.0);


// The share of the direct beam reaching [param local_direction] on this shell that gets past
// the deck. Geometry is the whole of it: the sun ray leaves this shell and crosses the deck at
// a horizontally DISPLACED place, which is what makes a cloud's shadow something you can see
// BESIDE the cloud rather than a darkening hidden underneath it. The displacement closes as
// the sun goes overhead, so shadows vanish toward the subsolar point with no phase term saying
// they should -- which is what real full-disc imagery shows, and why nothing here needs one.
// Solved against the deck's SPHERE rather than as h tan(zenith), which diverges at a grazing
// sun where the true crossing walks round the limb instead: at Earth's 10.19 km deck the
// displacement is 5.9 km at a 30 deg solar zenith, 17.6 at 60, 56 at 80 and 201 at 88.
//
// This is a REDISTRIBUTION and not a new term. The deck's own alpha carries only its view leg
// (see _cloud_shell.gdshaderinc), so the sunlight removed here is the sunlight that used to be
// removed directly under the cloud; the body's total reflected flux does not move and only
// where the darkening lands does.
//
// Sampled BILINEAR, where the deck's own shader reads the same map bicubically -- deliberately,
// and measured, at both deck resolutions the project has shipped. Matching the filter is the
// obvious tidiness and it is a bad trade: at the shipped face 2048 bicubic on this lookup moves
// 1.88 % of the frame's texels by at most **1 DN** and costs **92 us, 2.8 % of a frame the deck
// fills** (at face 512: 3.74 % and 73 us). The reason it buys so little is that the shadow is
// already smooth twice over -- a coverage-weighted transmittance through a saturating T(mu0) --
// so the interpolant's shape barely reaches the result. Note what this says against the
// deck-size measurement in records/Earth.md: texture RESOLUTION is free (512 to 2048 costs 2 us
// against 3 us of run-to-run drift), extra TAPS are not.
//
// [param local_direction] and [param local_sun] are unit vectors in this shell's own frame,
// where the shell is the unit sphere -- so an oblate body's deck is treated as a scaled copy
// of its surface, the same approximation atm_disc_air() already makes and worth 1 part in 298
// on Earth.
float clouds_sun_transmittance(vec3 local_direction, vec3 local_sun, float mu0) {
	if (clouds_shadow_scale <= 1.0 || mu0 <= 0.0) {
		return 1.0;
	}
	float k = clouds_shadow_scale;
	float t = -mu0 + sqrt(max(k * k - 1.0 + mu0 * mu0, 0.0));
	// The crossing is solved in THIS shell's frame, where local_sun lives; only the texel
	// lookup belongs to the deck's.
	vec3 crossing = normalize(local_direction + local_sun * t);
	crossing = vec3(clouds_shadow_spin.x * crossing.x - clouds_shadow_spin.y * crossing.z,
			crossing.y,
			clouds_shadow_spin.y * crossing.x + clouds_shadow_spin.x * crossing.z);
	vec4 deck = texture(clouds_shadow_map, crossing);
	vec3 reflectance = clouds_shadow_range_lo
			+ (clouds_shadow_range_hi - clouds_shadow_range_lo) * display_decode(deck.rgb);
	float albedo = clamp(atm_luma(reflectance), 0.0, 1.0);
	float tau_star = albedo / max(1.0 - albedo, 1.0e-4);
	// The deck's own conservative two-stream at the SUN's cosine -- the 2 mu0 in the
	// denominator is the slant path, so a low sun closes the covered fraction off. The clear
	// fraction passes everything at any incidence, which is why a broken deck still lights
	// the ground when an overcast one no longer does.
	return mix(1.0, 2.0 * mu0 / (tau_star + 2.0 * mu0), deck.a);
}
