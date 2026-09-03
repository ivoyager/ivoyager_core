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


// THE SAME TWO LAWS' RESPONSE TO ISOTROPIC ILLUMINATION, which is a different integral and
// emphatically not the same factor. A BRDF's beam factor answers "how bright at THIS
// incidence angle"; skylight, and the diffuse half of a two-stream, have no single incidence
// angle, so what they get is the BRDF integrated over the whole incident hemisphere. Using
// the beam factor for diffuse light applies mu0^(k-1) to light that has no mu0, which on a
// limb-darkened body collapses the diffuse term toward the terminator exactly where it is
// supposed to be taking over -- rendered, that put a flat shelf a couple of degrees wide in
// Venus's terminator gradient, bracketed by steep gradients, which is a Mach band.
//
// Both are FULL responses, not albedo factors: the emission path they feed has no engine
// N.L to supply a leading mu0. Both reduce to exactly 1.0 at Lambert.
//
// Minnaert, f_r proportional to mu0^(k-1) mu^(k-1):
//     int over the hemisphere of mu0^k dw  =>  2/(k+1) mu^(k-1)
float minnaert_isotropic_response(vec3 macro_normal, vec3 view_dir, float k) {
	if (k <= 1.0) {
		return 1.0;
	}
	float mu = max(dot(macro_normal, view_dir), 1.0e-4);
	return 2.0 / (k + 1.0) * pow(mu, k - 1.0);
}


// Lunar-Lambert, f_r proportional to 2L/(mu + mu0) + (1 - L):
//     int_0^1 mu0/(mu + mu0) dmu0 = 1 - mu ln(1 + 1/mu)   =>  4L(1 - mu ln(1 + 1/mu)) + (1 - L)
// Bounded without a clamp, unlike the beam factor: it runs from 1 + 0.227 L at the
// sub-observer point to 1 + 3L at the limb, where the beam factor diverges.
float lunar_lambert_isotropic_response(vec3 macro_normal, vec3 view_dir, float el) {
	if (el <= 0.0) {
		return 1.0;
	}
	float mu = max(dot(macro_normal, view_dir), 1.0e-4);
	return 4.0 * el * (1.0 - mu * log(1.0 + 1.0 / mu)) + (1.0 - el);
}


// THE LIMB IS A SAMPLING EDGE, and one shading sample per pixel cannot resolve it. Each
// pixel along a body's silhouette holds a sliver of surface at grazing incidence, and the
// shader answers for that whole sliver from ONE point, whose interpolated (and normal-mapped)
// normal extrapolates past where the geometry actually turns away -- so a fragment that
// should be edge-on can report a lit mu0, at full physical-light radiance. What that renders
// is speckle: isolated full-brightness pixels scattered along a backlit rim, reshuffling as
// the camera moves, and dashes running off the tips of a crescent once its width drops below
// a pixel. With the sun within a radius or so of the limb the whole lit crescent is such a
// sliver -- at 175 deg phase it is 0.55 px on a Jupiter 145 px across -- and the rim renders as
// a dotted chain. It is the SHADING rate that is short, not coverage, so MSAA cannot touch it:
// MSAA resolves coverage and shades a fragment once.
//
// WHAT A CAMERA DOES WITH THE SAME SLIVER is the standard this has to meet, and it is the star
// field's standard: a source narrower than the PSF is imaged AS the PSF, at the source's flux.
// The rim is such a source in one dimension. So limb_mean_incidence images each pixel's stretch
// of rim through the camera's Gaussian -- iv_psf_sigma, the one that images every star -- and
// answers the two questions the one shading sample cannot: how much of this pixel the body
// COVERS, and what the sun angle is, on average, over the covered part. A rim far above
// saturation then comes out as a line whose WIDTH the size law sets, exactly as a bright star's
// disc does, rather than as one pixel that is either lit or not; and a rim that is only faintly
// lit trails off through intermediate values instead of breaking up.
//
// COVERAGE is what a shell multiplies its whole contribution by: the fraction of the pixel's
// PSF footprint that lands on the body -- 1.0 everywhere but the last few pixels of the
// silhouette, one half at the silhouette itself. That is the camera's own edge, so a body
// filling the screen gets an edge softening finer than any by-eye ramp, and a normal that
// extrapolates past the silhouette lands ON it rather than off it. An OPAQUE shell applies
// coverage to radiance (specular takes the fade below instead). It cannot use ALPHA, which
// would move it to the transparent pass and stop it writing depth. Its
// light is therefore removed rather than replaced by what stands behind: right against sky,
// where every one of these artifacts lives, and a ~1 px dark fringe in the rarer case of a lit
// body transiting a brighter one. A TRANSLUCENT shell has no such constraint and applies it to
// ALPHA, where partial coverage is what alpha already means.
//
// THE MEAN SUN ANGLE is what closes the speckle. The engine's diffuse carries albedo * N.L from
// the one interpolated normal; rescaling ALBEDO (and SPECULAR) by mean / N.L replaces that
// sample with the pixel's true mean -- zero on a night side however the normal extrapolated,
// the sliver's exact light where the sample missed it. Where N.L is zero no factor can reach
// the diffuse, and the caller hands the remainder to emission.
//
// SPECULAR KEEPS A FIXED-WIDTH FADE AT THE SILHOUETTE on top of that, LIMB_FADE_PX wide, and
// not the coverage above. The lobe is a point sample of the sliver as the diffuse was, but the
// rescale by N.L does not average it: at grazing incidence the microfacet visibility term makes
// it a function of N.V as much as N.L, and N.V runs to zero across the sliver, where the term is
// the model's grazing sheen -- a default dielectric lobe no body has tuned -- rather than any
// sunlight the camera resolves. Measured on the Jupiter rim with specular on coverage alone, the
// sheen turned the line's fading end pixels from intermediate to clipped and brightened a ~20 px
// band along the whole rim by 15-30 codes through the glow pass. Whether a limb should glint is
// a question for the disc photometry laws, not for sampling, so the fade that held the sheen in
// check before coverage existed stays, for specular alone. Applied as the square root, F0
// scaling as SPECULAR^2.
//
// HAZARD: screen derivatives, so call this under UNIFORM control flow -- the rule the ring
// shadow's fwidth() carries (see _sun_occlusion.gdshaderinc). Form it where mu is formed,
// never inside a branch that some lanes of a 2x2 quad skip.
//
// WHY THE OBVIOUS CHEAP VERSION IS WRONG, recorded because it shipped once and had to come back
// out. Estimating the pixel's mean from mu0 and its screen gradient assumes mu0 ramps LINEARLY
// across the pixel. Near a limb it does not -- it goes as the square root of the distance inside
// the silhouette -- and the error is worst exactly where the fix is needed. At 180 deg phase the
// gradient is large all along the rim, so a linear estimate reports a lit fraction on a night
// side that has no sunlight at all, and reports a different one per pixel: the original speckle,
// straight back.
//
// WHY POINT SAMPLES ARE WRONG TOO, recorded for the same reason. Eight samples across one pixel
// in surface angle still miss a sliver thinner than their spacing, or catch it with one sample
// at eight times its weight. Against the exact integral the rim's mean came out 1.9x high on
// average and anywhere from zero to several times that from one pixel to the next -- and that
// noise IS the dashes that survived: it sits exactly where the line is faint enough for noise
// to show.
//
// WHAT THIS DOES INSTEAD. A spheroid's visible surface has an exact parameterization along the
// screen-radial direction: at surface angle t from the sub-observer point the normal is
// cos(t) * view + sin(t) * radial, so mu0 is exactly A cos(t) + B sin(t) for two dot products
// fixed per fragment, and the sunlight on any stretch of that line integrates in closed form.
// The kernel is cut into cells of screen pixels, each cell's light is that integral -- so a
// sliver of any width is counted exactly, in whichever cell it falls -- and the cells are
// weighted by the camera's Gaussian at the pixel's own depth. Past the limb is sky: it counts
// toward coverage as the zero it is, and not toward the mean. At 180 deg phase every cell
// integrates to exactly zero, so the speckle cannot come back; where the crescent is resolved
// the mean equals the centre sample and this is a no-op. Modelled before it was written,
// against a brute-force render of the sliver through the same PSF: at 179 deg phase the point
// samples left 86 of 144 lit degrees of arc dark, and this leaves none.
//
// The pixel's depth inside the limb and the limb's pixel radius both come from mu's own screen
// gradient: for a sphere mu = sqrt(2x/R) at x px inside a limb of pixel radius R, so
// |grad mu| is tan(t) / R per pixel -- the LOCAL curvature, right on an oblate body at any
// latitude, and needing no CPU feed. What that cannot serve is the pixel whose interpolated
// normal has already turned past the silhouette: mu is zero or negative there, the ratio is
// meaningless, and the pixel is nonetheless a surface fragment sitting right on the limb. The
// caller supplies the body's pixel radius from its own geometry for that case, and it bounds
// the gradient's answer everywhere else against interpolation error at the limb.
//
// COST is confined to the rim by the kernel's reach, and there is no texture work in it --
// per rim fragment, one asin and a few trig calls per cell.
const int LIMB_KERNEL_CELLS = 16;
// Half-width of the kernel in px. Three sigma would be 1.5 px; this is set by the size law
// instead, as a star's sprite is: the rim at the camera's dark-adapted rest exposure stands
// four to five decades above saturation, and its Gaussian is still above one 8-bit step at
// 2.7 px. A cell is 3/8 px, fine enough that the Gaussian is nearly flat across it.
const float LIMB_KERNEL_REACH_PX = 3.0;
// Width in px of the silhouette fade that SPECULAR alone keeps (see above).
const float LIMB_FADE_PX = 1.5;
const float LIMB_HALF_PI = 1.5707963;
// How far the ALBEDO rescale may carry the mean above the centre sample before the rest is
// handed to emission. A cap is needed because the ratio diverges as the centre sample goes to
// zero, which is precisely the pixel whose sliver the centre missed.
const float LIMB_INCIDENCE_ALBEDO_MAX = 4.0;
// The camera's PSF width in px, IVPSFSettings.psf_sigma -- a global so this cannot drift from
// the star field and the body quads it images alongside.
global uniform float iv_psf_sigma;

// Antiderivative of (a cos t + b sin t) cos t.
float limb_chord_antiderivative(float a, float b, float t) {
	float sin_t = sin(t);
	return a * (0.5 * t + 0.25 * sin(2.0 * t)) + 0.5 * b * sin_t * sin_t;
}

// Integral over [t_lo, t_hi] of max(a cos t + b sin t, 0) cos t dt: the sunlight on the
// stretch of screen-radial surface line between two surface angles, per unit radius. The
// clamp is exact -- mu0 is a single sinusoid in t, so its positive part is one interval.
float limb_lit_chord(float a, float b, float t_lo, float t_hi) {
	float t_peak = atan(b, a);
	float lo = max(t_lo, t_peak - LIMB_HALF_PI);
	float hi = min(t_hi, t_peak + LIMB_HALF_PI);
	if (hi <= lo) {
		return 0.0;
	}
	// max(): where the lit stretch is a hair wide the difference can cancel to a hair below
	// zero, and a negative mean reaches the specular path as sqrt() of a negative ratio -- a
	// NaN the glow pass then blooms into a blob many times the size of the sun's.
	return max(limb_chord_antiderivative(a, b, hi) - limb_chord_antiderivative(a, b, lo), 0.0);
}

// Sunlight (the integral of max(mu0, 0), in px) on the surface between screen depths x1 < x2,
// measured inward from the near limb along the screen-radial line, on a sphere of radius_px;
// covered receives the length of [x1, x2] that is surface at all. Sky beyond either limb
// contributes to neither; past the centre the line runs on to the far limb with the radial
// reversed, which only matters for a body a few px across.
float limb_cell_light(float a, float b, float x1, float x2, float radius_px, out float covered) {
	float far_limb = 2.0 * radius_px;
	x1 = max(x1, 0.0);
	x2 = min(x2, far_limb);
	covered = max(x2 - x1, 0.0);
	if (covered <= 0.0) {
		return 0.0;
	}
	float light = 0.0;
	if (x1 < radius_px) { // near side: x = R (1 - sin t)
		float x_hi = min(x2, radius_px);
		light += limb_lit_chord(a, b, asin(1.0 - x_hi / radius_px), asin(1.0 - x1 / radius_px));
	}
	if (x2 > radius_px) { // far side: x = R (1 + sin t)
		float x_lo = max(x1, radius_px);
		light += limb_lit_chord(a, -b, asin(x_lo / radius_px - 1.0), asin(x2 / radius_px - 1.0));
	}
	return light * radius_px;
}

// Square root of 2*PI, for the Gaussian's own normalization.
const float LIMB_SQRT_TWO_PI = 2.5066283;

// The SKY SIDE of the convolution limb_mean_incidence() does inside the silhouette: the
// PSF-weighted sun angle reaching a pixel distance_px BEYOND the limb, which is light the
// body's own surface has no fragment to carry -- its rim ends at the rasterized edge, and
// half of a rim pixel's point spread belongs outside it. Returned in the same units the
// inside kernel returns (a mean incidence, the Gaussian normalized to one), so the two are
// the two halves of one integral and neither double-counts the other. IVBodyPSF's quad
// draws it, being the one item that covers the sky beside a body's limb.
//
// The coefficients are the caller's own: a = dot(view, sun) and b = dot(radial, sun), where
// radial is the outward screen direction at this pixel's azimuth -- the same pair
// limb_mean_incidence() builds from a surface normal it has and a quad does not. They must be
// the LIMB POINT's for the camera where it is (body_psf.gdshader's limb_sun_angles()), not the
// body centre's phase: the two differ by the body's angular radius.
//
// CELLS ARE SPACED UNIFORMLY IN sqrt(x), not in x, and that is not tidiness. Seen from the
// sky side the whole lit sliver sits AT the limb, x ~ 0, while the Gaussian's weight falls
// by exp(-d/sigma^2) per pixel of depth: a uniform grid puts its first sample half a cell
// past the sliver and so weights it as if it were that much deeper, which at 3 px out reads
// 40% low and at 5 px 80% low -- exactly the faint outer part whose reach the size law sets.
// The sqrt spacing puts the first cell inside the first hundredth of a pixel; measured
// against a high-accuracy integral, 16 cells then hold to 1% at the limb and 4% at 3 px.
float limb_sky_side_incidence(float a, float b, float distance_px, float radius_px,
		float sigma) {
	float scale = LIMB_KERNEL_REACH_PX / float(LIMB_KERNEL_CELLS * LIMB_KERNEL_CELLS);
	float light = 0.0;
	for (int i = 0; i < LIMB_KERNEL_CELLS; i++) {
		float x1 = scale * float(i * i);
		float x2 = scale * float((i + 1) * (i + 1));
		float centre = 0.5 * (x1 + x2) + distance_px;
		float weight = exp(-centre * centre / (2.0 * sigma * sigma));
		float covered;
		light += weight * limb_cell_light(a, b, x1, x2, radius_px, covered);
	}
	return light / (sigma * LIMB_SQRT_TWO_PI);
}

// The body's silhouette radius in px from its own geometry, for limb_mean_incidence: this
// fragment's TRUE world position (the shells' v_world_position, not the farwarped VERTEX),
// the body's world centre (MODEL_MATRIX[3]), the camera, and the projection. The fragment's
// own distance from the centre is the radius, whatever mesh and frame the shell draws with
// -- the shared unit sphere or a packed model in kilometres -- and world space is the one
// frame every shell fills in unconditionally (the local-frame varyings are skipped on an
// airless body). Small-angle, as body_pixel_radius is; the value bounds a local estimate
// and stands in for it only at the silhouette, so a few percent on a body filling the
// screen is nothing.
float limb_radius_px(vec3 world_position, vec3 centre_world, vec3 camera_world,
		float proj_11, float viewport_height) {
	float radius = length(world_position - centre_world);
	float distance = max(length(camera_world - centre_world), radius);
	return abs(proj_11) * viewport_height * 0.5 * radius / distance;
}

// Returns the mean of max(mu0, 0) over the part of this fragment's PSF footprint that lands
// on the body; in coverage the fraction of the footprint that does; and in silhouette_fade
// the fixed-width fade that specular alone applies (see above for what each is for). Pass the
// MACROSCOPIC normal and mu = dot(macro_normal, view_dir), all in one space, and the
// silhouette radius from limb_radius_px.
float limb_mean_incidence(vec3 macro_normal, vec3 view_dir, vec3 sun_dir, float mu,
		float radius_px_hint, out float coverage, out float silhouette_fade) {
	coverage = 1.0;
	silhouette_fade = 1.0;
	float centre = max(dot(macro_normal, sun_dir), 0.0);
	float gradient = length(vec2(dFdx(mu), dFdy(mu)));
	float sin_t = sqrt(max(1.0 - mu * mu, 0.0));
	if (gradient <= 0.0 || sin_t < 1.0e-4) {
		return centre; // degenerate at the sub-observer point, where mu is flat
	}
	// R = tan(t) / |grad mu|, bounded by the geometric radius (see above), and the depth is
	// R (1 - sin t), written with 1 - sin t = mu^2 / (1 + sin t) so it survives float32 at
	// the limb, where sin t -> 1. A normal interpolated past the silhouette sits ON it.
	float radius_px = radius_px_hint;
	float depth_px = 0.0;
	if (mu > 0.0) {
		radius_px = clamp(sin_t / (mu * gradient), 0.5 * radius_px_hint, 2.0 * radius_px_hint);
		depth_px = radius_px * mu * mu / (1.0 + sin_t);
	}
	silhouette_fade = smoothstep(0.0, LIMB_FADE_PX, depth_px);
	if (depth_px > LIMB_KERNEL_REACH_PX + 0.5) {
		return centre; // resolved: the kernel never reaches the silhouette
	}
	vec3 radial = normalize(macro_normal - mu * view_dir); // outward, in the (normal, view) plane
	float along_view = dot(view_dir, sun_dir);
	float along_radial = dot(radial, sun_dir);
	float sigma = max(iv_psf_sigma, 0.1);
	float cell = 2.0 * LIMB_KERNEL_REACH_PX / float(LIMB_KERNEL_CELLS);
	float light = 0.0;
	float covered_weight = 0.0;
	float weight_sum = 0.0;
	for (int i = 0; i < LIMB_KERNEL_CELLS; i++) {
		float offset = (float(i) + 0.5) * cell - LIMB_KERNEL_REACH_PX;
		float weight = exp(-offset * offset / (2.0 * sigma * sigma));
		weight_sum += weight * cell;
		float x = depth_px + offset;
		float covered;
		light += weight * limb_cell_light(along_view, along_radial, x - 0.5 * cell,
				x + 0.5 * cell, radius_px, covered);
		covered_weight += weight * covered;
	}
	coverage = covered_weight / weight_sum;
	return covered_weight > 0.0 ? light / covered_weight : centre;
}
