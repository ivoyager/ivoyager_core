// _photometry.gdshaderinc
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

// Disc photometry for a solid body: how a body's brightness falls from the subsolar
// point toward the limb and the terminator. Shared by the surface shaders so the law
// cannot drift between the equirect and cubemap paths; see PHOTOMETRIC_MODEL.md.
//
// The problem it solves: the engine's diffuse gives radiance proportional to mu0
// (cos incidence), and an airless regolith body does NOT do that. At full phase such a
// body is nearly FLAT across its disc - the full Moon reads as a disc, not as a lit
// ball - so a cos falloff renders half the projected disc about 1.4x too dark and its
// outer quarter about 2x too dark.
//
// The law is Lunar-Lambert (McEwen 1991; ISIS 'lunarlambert'), a one-parameter blend
// of Lommel-Seeliger and Lambert:
//
//   I = A * [ 2L * mu0 / (mu + mu0) + (1 - L) * mu0 ]
//
// L = 0 is Lambert exactly and L = 1 is Lommel-Seeliger, which is uniform across the
// disc at zero phase. Chosen over Minnaert (mu0^k * mu^(k-1)) because its RADIANCE is
// bounded everywhere - Minnaert's diverges at the limb and needs a clamp that has no
// physical meaning - and because L is the parameter planetary photometry publishes.
//
// Applied as a factor on ALBEDO rather than in a light() override: the engine's diffuse
// already supplies the leading mu0, so dividing it out leaves
//
//   ALBEDO *= 2L / (mu + mu0) + (1 - L)
//
// which keeps the specular lobe, AO / AO_LIGHT_AFFECT and the shadow path intact. It is
// an exact no-op at L = 0 AND at the subsolar-subobserver point (mu = mu0 = 1), so
// metering - which keys that point - is untouched and no shipped map level changes.

// A CLOUD DECK wants the other direction. Venus, Titan and the giants are limb-DARKENED
// relative to Lambert, and the law for that is Minnaert:
//
//   I = A * mu0^k * mu^(k-1)          Lambert = k = 1
//
// which in the same albedo-factor form (the engine again supplying the leading mu0) is
//
//   ALBEDO *= (mu0 * mu)^(k - 1)
//
// For k > 1 the exponent is positive, so the factor is bounded by 1, never negative, and
// still exactly 1.0 at mu = mu0 = 1. Only k < 1 diverges at the limb, and that direction
// is Lunar-Lambert's job, so this clamps k up to 1.0 rather than pretending to serve it.
//
// The two laws are complementary and meet at Lambert (L = 0 is k = 1). A NEGATIVE
// lunar_lambert would look like a way to get here from one parameter and is not: at zero
// phase its radiance is L + (1 - L)*t, which passes through zero at t = |L|/(1 + |L|) and
// puts a hard black ring around the limb - 2.8 % of the disc area at L = -0.2, 11 % at
// L = -0.5 - instead of darkening it.

// Guards the intermediate factor only. The factor diverges at the limb while the
// radiance it produces does not: the engine's own mu0 multiply cancels the divergence,
// leaving a bound of 2L. The clamp keeps ALBEDO finite where the body is already
// sub-pixel, and never binds anywhere the surface is resolved.
const float LUNAR_LAMBERT_FACTOR_MAX = 64.0;


// All three vectors in the SAME space (the shaders pass view space) and unit length.
// Pass the MACROSCOPIC normal, not the normal-mapped one: this is a law about the
// body's disc, and per-texel relief is the normal map's job. Returns 1.0 at el = 0.
float lunar_lambert_albedo_factor(vec3 macro_normal, vec3 sun_dir, vec3 view_dir, float el) {
	if (el <= 0.0) {
		return 1.0;
	}
	float mu0 = max(dot(macro_normal, sun_dir), 0.0);
	float mu = max(dot(macro_normal, view_dir), 0.0);
	float factor = 2.0 * el / max(mu + mu0, 1e-4) + (1.0 - el);
	return min(factor, LUNAR_LAMBERT_FACTOR_MAX);
}


// See the Minnaert block above. Same space and unit-length requirements as
// lunar_lambert_albedo_factor, same macroscopic normal, and returns 1.0 at k = 1.
float minnaert_albedo_factor(vec3 macro_normal, vec3 sun_dir, vec3 view_dir, float k) {
	if (k <= 1.0) {
		return 1.0;
	}
	float mu0 = max(dot(macro_normal, sun_dir), 0.0);
	float mu = max(dot(macro_normal, view_dir), 0.0);
	return pow(mu0 * mu, k - 1.0);
}
