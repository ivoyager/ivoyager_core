// _atmosphere.gdshaderinc
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

// A body's atmosphere as single scattering of sunlight, for the limb shader that draws it
// and for the surface and cloud shaders whose direct light passes through it.
//
// THE MODEL. Three layers above an opaque disc: a Rayleigh gas and a Henyey-Greenstein
// haze, each exponential in altitude, and one Gaussian "detached" layer (Mars' water-ice
// haze, Titan's detached haze). Each carries one extinction optical depth per sRGB channel
// at the disc, a single-scattering albedo and an asymmetry. A view ray collects the
// sunlight the layers scatter toward it, attenuated to the observer and along each sun
// path, with the planet's own shadow; what lies behind the ray is attenuated by the same
// column. The unit throughout is I/F, the radiance relative to a white Lambert surface at
// normal incidence, which is what ALBEDO * light_energy renders - so the limb rides the
// sun's light_energy exactly like a surface, exposure included, and meters with it.
//
// THE EVALUATION. No marching: a fixed Gauss-Legendre quadrature along the LIT part of the
// view ray (six nodes per half of a beyond-limb ray, six along a surface-hit ray), every
// node's columns to the observer and to the sun in closed form - the Chapman function in
// its erfcx form for an exponential layer, the Abel transform of a Gaussian (tabulated) and
// its partial columns for the thin layer - and the sun's shadow as the ray's analytic exit
// from the shadow cylinder, a domain boundary rather than a factor at the nodes. A thin
// layer's crossing is sampled at three altitudes, because a grazing sun's transmittance
// changes severalfold across its own thickness.
//
// THE CONTRACT. scripts/limb_model.py in the assets build tree is the reference
// transcription of this file, verified against a numeric single-scatter integral for
// Earth, Venus, Mars and Titan at every phase (within 11 % worst case, usually under 3 %).
// Change nothing here without changing it there and re-running --verify: keep the two
// identical, constant for constant.
//
// TWO FLOAT32 TRAPS, both found as a black curve across Venus' night side. A float literal
// below about 1e-14 compiles to ZERO in the shader language (1.0e-20 reads as 0.0; 1e-12 is
// fine), so every floor here is 1e-12 or larger. And a valid but tiny float (~1e-36) passes
// "> 0.0" yet comes out of the GPU's log() as -inf, so the disc quadrature decides whether
// a ray's lit part is worth integrating in ALTITUDE, before any exp() is taken.
//
// FRAME AND UNITS. Everything is in the SHELL'S local frame, where the shell is the unit
// sphere (an oblate body is a sphere there, so altitude above the disc is exact), in
// kilometres: one local unit is body_radius_km * shell_scale km, the disc (shell 0) has
// radius R = body_radius_km * surface_scale km and is altitude zero - Titan's included,
// whose disc is its haze's optical limb, not its surface. IVShellsModel feeds the three
// geometry uniforms to every shader shell and propagates the atm_* columns of the limb
// row to all of them, so one atmosphere is shared; body_radius_km = 0 (unfed) makes every
// term here a no-op.
//
// TASTE, AND ITS GATE. Physical parameters are the look. With physical light OFF the two
// taste multipliers act: atm_intensity scales the radiance and atm_thickness every
// altitude scale. The runtime global iv_limb_scale gates them - 1.0 lets them act, 0.0
// (set by IVExposureManager while physical light is active) forces both to exactly 1.0 -
// so the same shells.tsv row serves both modes.
//
// EVERY DISC IS FULLY COVERED. The disc branch draws over the whole body, not a rim
// annulus, so a shell beneath an atmosphere must carry SURFACE reflectance and let the
// renderer supply the rest -- a top-of-atmosphere map would count the air twice. That was
// a per-body uniform (atm_veil_extent) until 2026-08-24, when the last body still carrying
// a top-of-atmosphere map was re-referenced and it was retired: the choice belongs to how a map is built, and a knob
// for it only let the convention be broken silently.
//
// A RECEIVING SURFACE OR CLOUD SHADER multiplies its sunlight by
// atm_sun_transmittance(mu0) in its photometry slot, after the disc law: the total
// illumination reaching that shell's own altitude, direct beam plus diffuse sky, which is
// what turns the cloud deck at the limb the colour of sunset and what keeps a surface
// legible through a terminator its direct beam alone does not survive. It also composites
// the air IN FRONT of itself, through atm_disc_air(); the limb shader calls atm_limb(),
// which is the beyond-limb rays alone and discards the rest.
//
// THE COMPOSITING SPLIT. A ray that meets the disc is composited by the DISC'S OWN
// SHADERS, not by the limb shell: atm_disc_air() hands each of them the path radiance in
// front of its fragment and the LUMA of the disc's view transmittance, which the shader
// adds over and multiplies into everything it renders. Alpha is one number and the
// transmittance is three, Rayleigh air letting red through where it stops blue — so the
// luma carries the achromatic half and every shell multiplies in atm_view_tint(mu), the
// per-channel transmittance of the column above ITS OWN altitude over that luma. The
// product is exact, and it is also what keeps a cloud deck 10 km up from being dimmed by
// the air below it. The limb shell used to draw the disc term and remove the luma through
// its blend_premul_alpha — an identity only where the blend runs in linear light, and the
// Compatibility renderer's blend is display-referred and clamped, which is the one
// boundary _display.gdshaderinc cannot reach: a faint veil over a lit disc landed crushed
// there. Summed inside the fragment the composite is exact on every renderer, and in
// linear light it is algebraically the same frame — the path distributes through a deck's
// alpha mix with weight alpha + (1 - alpha) = 1. Beyond the limb nothing stands behind
// the ray but sky and stars, so the shell's premultiplied blend remains correct there —
// and at the very silhouette the two owners hand off over a thin feathered band, because
// no polygonal disc mesh covers its own mathematical silhouette (ATM_RIM_HANDOFF).
//
// THE COLOUR SPACE. Everything here is physical linear radiance and linear transmittance, and
// it stays that way: converting to whatever the running renderer expects is the calling
// shader's boundary, not this file's. See _display.gdshaderinc.

// ---------------------------------------------------------------- the shared uniform interface

// Geometry, fed by IVShellsModel to every shader shell (no-op defaults).
uniform float body_radius_km = 0.0; // mean radius; 0 disables every atmosphere term
uniform float shell_scale = 1.0;    // this shell's radius / mean radius
uniform float surface_scale = 1.0;  // shell 0's radius / mean radius: the disc, altitude zero

// The atmosphere, authored on the body's LIMB row of shells.tsv (the atm_* columns) and
// propagated to every shell of the body. Optical depths are vertical EXTINCTION depths at
// the disc, per sRGB channel; scale heights and altitudes in km above the disc.
uniform vec3 atm_gas_tau = vec3(0.0);             // Rayleigh gas
uniform float atm_gas_scale_height_km = 8.0;
uniform float atm_gas_multiple = 1.0;             // multiple-scattering boost on its radiance, >= 1
uniform vec3 atm_haze_tau = vec3(0.0);            // aerosol / haze, Henyey-Greenstein
uniform float atm_haze_scale_height_km = 2.0;
uniform float atm_haze_top_km = 0.0;              // the haze's top above the disc; 0 = none
uniform float atm_haze_top_scale_height_km = 1.0; // its scale height above that top
uniform vec3 atm_haze_albedo = vec3(1.0);         // single-scattering albedo per channel
uniform float atm_haze_g = 0.7;                   // Henyey-Greenstein asymmetry
uniform float atm_haze_multiple = 1.0;
uniform vec3 atm_layer_tau = vec3(0.0);           // a detached Gaussian layer; 0 = none
uniform float atm_layer_altitude_km = 0.0;        // its centre above the disc
uniform float atm_layer_width_km = 10.0;          // its sigma
uniform vec3 atm_layer_albedo = vec3(1.0);
uniform float atm_layer_g = 0.3;
// The twilight curve: what a shell is lit by once the plane-parallel beam has run out. Fitted
// per body by limb_model.py --fit-skylight against its hemisphere integral; zero disables it.
uniform vec3 atm_sky_flux = vec3(0.0);   // downwelling diffuse at the disc at mu0 = 0, / vacuum
uniform vec3 atm_sky_slope = vec3(0.0);  // d ln(flux) / d mu0 there
uniform vec3 atm_sky_bend = vec3(0.0);   // its curvature; NEGATIVE, which is what kills the
                                         // term at high sun with no clamp
uniform float atm_intensity = 1.0;  // nonphysical taste: radiance multiplier (gated, see header)
uniform float atm_thickness = 1.0;  // nonphysical taste: altitude-scale multiplier (gated)
global uniform float iv_limb_scale; // 1.0 = taste multipliers act; 0.0 = physical, they are 1.0

// ---------------------------------------------------------------------------- constants

const float ATM_PI = 3.14159265358979;
// Scale heights over which the ring fades out at the shell's own edge; see atm_limb().
const float ATM_EDGE_FADE = 3.0;
// The disc-air handoff band, as a fraction of the disc radius inside the silhouette. The
// disc's air is composited by the disc's own shaders (atm_disc_air) — except at the very
// silhouette, where no disc fragment is guaranteed to exist: every mesh is a polyhedron
// whose silhouette sits up to its facet sagitta INSIDE the true sphere (7.5e-5 R at the
// stock 256 segments), and the surface, deck and limb meshes each interpolate their own
// copy of the ray, so a hard partition at b = R leaves a dotted arc of pixels that no
// branch owns (measured: ~270 per view, up to 77 codes dark). Over this band the veil
// hands from the disc shaders to the limb shell by complementary smoothstep weights, so
// the sum is exact wherever both draw and the shell alone covers the sliver the disc
// meshes miss; the seam error is bounded by sagitta / band, ~1.5 % of the veil at stock
// segments and still ~12 % for a project at 64.
const float ATM_RIM_HANDOFF = 0.01;
const float ATM_FAR_GATE_TAU = 30.0;  // chord extinction at which a ray's far half is dropped
// Sigmas above a Gaussian layer's centre at which its column is treated as the exact zero it
// rounds to (e^-32 of its tau): the early-out this feeds is what spares the layer machinery
// over the large part of a shell that stands above its own layer.
const float ATM_LAYER_REACH = 8.0;
const float ATM_PENUMBRA_FLOOR_KM = 1.0;  // the planet's shadow edge is never sharper than this
const float ATM_INF = 1.0e30;
// The conservative two-stream coefficient, 3/4, in T = 1 / (1 + k tau_scattered): the total
// downward flux through a scattering column, direct plus diffuse, where exp(-tau) is the
// direct beam alone. See atm_sun_transmittance().
const float ATM_TWO_STREAM_K = 0.75;
// Gauss-Legendre nodes and weights on (0, 1): six along a ray, three across a thin layer.
const float ATM_GL6_T[6] = {0.0337652, 0.1693953, 0.3806904, 0.6193096, 0.8306047, 0.9662348};
const float ATM_GL6_W[6] = {0.0856622, 0.1803808, 0.2339570, 0.2339570, 0.1803808, 0.0856622};
const float ATM_SHELL_P[3] = {0.1127017, 0.5, 0.8872983};
const float ATM_SHELL_W[3] = {0.2777778, 0.4444444, 0.2777778};
// F(delta) = int_0^inf u^-1/2 exp(-(u + delta)^2 / 2) du / sqrt(2 pi), the Abel transform of a
// unit Gaussian, on delta = -6 .. 3 by 0.25 (a parabolic cylinder function; no closed form).
// A ray tangent delta sigma above a Gaussian layer's centre carries tau sqrt(2 r_c / sigma) F.
const float ATM_ABEL_MIN = -6.0;
const float ATM_ABEL_STEP = 0.25;
const float ATM_ABEL[37] = {
	0.41280, 0.42212, 0.43214, 0.44294, 0.45464, 0.46740,
	0.48138, 0.49683, 0.51408, 0.53354, 0.55581, 0.58163,
	0.61196, 0.64787, 0.69034, 0.73989, 0.79602, 0.85651,
	0.91687, 0.97025, 1.00799, 1.02108, 1.00223, 0.94796,
	0.86004, 0.74559, 0.61574, 0.48322, 0.35964, 0.25346,
	0.16892, 0.10636, 0.06322, 0.03544, 0.01873, 0.00933,
	0.00438};

// Whether this shell HAS an atmosphere: the geometry is fed and some layer carries optical
// depth. IVShellsModel feeds body_radius_km to every shader shell, airless bodies included,
// so the radius alone does not answer this; the taus do. The callers that must be a true
// no-op on an airless body — atm_disc_air() and the per-vertex atm_far_floor() — gate on
// it; the sampled-transmittance functions stay numerical no-ops as before.
bool atm_present() {
	return body_radius_km > 0.0
			&& dot(atm_gas_tau + atm_haze_tau + atm_layer_tau, vec3(1.0)) > 0.0;
}

// ------------------------------------------------------------------- special functions

// exp(a^2) erfc(a) for a >= 0: Numerical Recipes' rational form (relative error < 1.2e-7),
// with no exp(-a^2) to underflow.
float atm_erfcx(float a) {
	float t = 1.0 / (1.0 + 0.5 * a);
	return t * exp(-1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418
			+ t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587
			+ t * (-0.82215223 + t * 0.17087277)))))))));
}

float atm_erf(float x) { // x >= 0
	return 1.0 - atm_erfcx(x) * exp(-x * x);
}

float atm_gauss_tail(float x) { // Q(x), the unit Gaussian's upper tail
	float ax = abs(x);
	float tail = 0.5 * atm_erfcx(ax * 0.70710678) * exp(-0.5 * ax * ax);
	return x >= 0.0 ? tail : 1.0 - tail;
}

float atm_gauss_density(float x) {
	return exp(-0.5 * x * x) * 0.39894228;
}

// Giles' single-precision erfinv (GPU Computing Gems, 2010); the argument is clamped to the
// last float below 1, where the fit ends (v 3.8).
float atm_erfinv(float x) {
	x = clamp(x, -0.99999994, 0.99999994);
	float w = -log((1.0 - x) * (1.0 + x));
	float p;
	if (w < 5.0) {
		w = w - 2.5;
		p = 2.81022636e-08;
		p = 3.43273939e-07 + p * w;
		p = -3.5233877e-06 + p * w;
		p = -4.39150654e-06 + p * w;
		p = 0.00021858087 + p * w;
		p = -0.00125372503 + p * w;
		p = -0.00417768164 + p * w;
		p = 0.246640727 + p * w;
		p = 1.50140941 + p * w;
	} else {
		w = sqrt(w) - 3.0;
		p = -0.000200214257;
		p = 0.000100950558 + p * w;
		p = 0.00134934322 + p * w;
		p = -0.00367342844 + p * w;
		p = 0.00573950773 + p * w;
		p = -0.0076224613 + p * w;
		p = 0.00943887047 + p * w;
		p = 1.00167406 + p * w;
		p = 2.83297682 + p * w;
	}
	return p * x;
}

// The Chapman function: the slant column above altitude h relative to the vertical one,
// for a ray leaving at zenith cosine mu - sqrt(pi x / 2) erfcx(sqrt(x / 2) mu), x = (R + h) / H,
// the large-x form (0.1 % for x > 300, 2 % at Titan's 47). Below the horizon the ray first
// descends to its own tangent altitude; the chi > 90 identity folds that into two upward
// halves. Schueler's rational form is NOT used: it reads 8-15 % low at grazing incidence,
// which in the exponent of a column of 30 is the difference between a terminator and a wall.
float atm_chapman(float R, float h, float H, float mu) {
	float x = (R + h) / H;
	float c = sqrt(0.5 * ATM_PI * x);
	float up = c * atm_erfcx(sqrt(0.5 * x) * abs(mu));
	if (mu >= 0.0) {
		return up;
	}
	float h_t = (R + h) * sqrt(max(1.0 - mu * mu, 0.0)) - R;
	float c_t = sqrt(0.5 * ATM_PI * (R + max(h_t, 0.0)) / H);
	return 2.0 * c_t * exp(min((h - h_t) / H, 60.0)) - up;
}

// 1 where the sun ray from altitude h at zenith cosine mu clears the disc, 0 where it hits,
// with a penumbra the sun's angular size wide in between.
float atm_sun_shadow(float R, float h, float mu, float sun_ang_radius) {
	if (mu >= 0.0) {
		return 1.0;
	}
	float h_t = (R + h) * sqrt(max(1.0 - mu * mu, 0.0)) - R;
	float half_width = max((R + h) * abs(mu) * sun_ang_radius, ATM_PENUMBRA_FLOOR_KM);
	return smoothstep(-half_width, half_width, h_t);
}

// Half-chord of a ray of tangent altitude h_t at altitude z: sqrt((R + z)^2 - (R + h_t)^2) in
// the factored form, because the difference of two squares of ~R cancels in float32 for a
// node metres above the tangent point.
float atm_chord(float R, float z, float h_t) {
	return sqrt(max((z - h_t) * (2.0 * R + z + h_t), 0.0));
}

// F(delta) from the table, with the asymptotic tails beyond it.
float atm_gauss_abel(float delta) {
	if (delta < ATM_ABEL_MIN) {
		float d2 = delta * delta;
		return (1.0 + 3.0 / (8.0 * d2)) / sqrt(-delta);
	}
	float top = ATM_ABEL_MIN + ATM_ABEL_STEP * 36.0;
	if (delta > top) {
		float d2 = delta * delta;
		return exp(-0.5 * d2) / sqrt(2.0 * delta) * (1.0 - 3.0 / (8.0 * d2));
	}
	float f = (delta - ATM_ABEL_MIN) / ATM_ABEL_STEP;
	int i = min(int(f), 35);
	f -= float(i);
	return ATM_ABEL[i] * (1.0 - f) + ATM_ABEL[i + 1] * f;
}

// G(a, b) = int_a^inf phi(x) (x - b)^-1/2 dx, a >= b: the part of F(b) above a. Within half a
// sigma of the tangent, F(b) less a three-point estimate of 2 int_0^sqrt(a-b) phi(b + v^2) dv;
// beyond that the weight is smooth over the remaining mass: Q(a) (m - b)^-1/2 with the
// second-order term in the truncated variance, m the truncated mean phi(a) / Q(a).
float atm_gauss_abel_partial(float a, float b) {
	float d = max(a - b, 0.0);
	float s = sqrt(d);
	float near = atm_gauss_abel(b);
	for (int i = 0; i < 3; i++) {
		float p = ATM_SHELL_P[i];
		near -= 2.0 * s * ATM_SHELL_W[i] * atm_gauss_density(b + d * p * p);
	}
	near = max(near, 0.0);
	// The far form needs the true Mills ratio, so it is dropped outright where the tail is
	// below 1e-12 (a > 7 sigma): a floor on Q would hand it a false mean and blow it up.
	float tail = atm_gauss_tail(a);
	float far = 0.0;
	if (tail > 1.0e-12) {
		float m = atm_gauss_density(a) / tail;
		float variance = max(1.0 + a * m - m * m, 0.0);
		float gap = max(m - b, 1.0e-6);
		far = tail / sqrt(gap) * (1.0 + 3.0 * variance / (8.0 * gap * gap));
	}
	return mix(near, far, smoothstep(0.3, 0.8, d));
}

// ------------------------------------------------------------------------ the layers

// Altitude scales after the (gated) thickness taste; computed once per fragment.
struct AtmLayers {
	float H_g;      // gas scale height, km
	float H_h;      // haze scale height
	float H_ref;    // the taller of the two: the quadrature's measure
	float z_k;      // the haze's top: above it the scale height is H_t; 0 = no top
	float H_t;
	vec3 tau_t;     // the region above the top as an exponential in its own right
	float z_c;      // thin layer centre
	float sigma;    // thin layer sigma
	bool has_layer;
	vec3 scatter_g; // gas radiance coefficient omega m piP tau: times the density, per km of path
	vec3 scatter_h; // haze: omega m piP only - it multiplies a density that carries the tau
	vec3 scatter_l; // thin layer: omega piP only -- it multiplies a column that carries the tau
	vec3 delta_h;   // haze extinction scale for what lies BENEATH: 1 - omega g
	vec3 delta_l;   // the same for the thin layer
};

float atm_phase_rayleigh(float cos_theta) {
	return 0.1875 * (1.0 + cos_theta * cos_theta);
}

float atm_phase_hg(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

AtmLayers atm_layers(float cos_theta) {
	float thick = mix(1.0, atm_thickness, iv_limb_scale);
	AtmLayers L;
	L.H_g = atm_gas_scale_height_km * thick;
	L.H_h = atm_haze_scale_height_km * thick;
	L.H_ref = max(L.H_g, L.H_h);
	L.z_k = atm_haze_top_km * thick;
	L.H_t = max(atm_haze_top_scale_height_km * thick, 0.01);
	L.tau_t = atm_haze_tau * ((L.H_t / L.H_h) * exp(L.z_k / L.H_t - L.z_k / L.H_h));
	L.z_c = atm_layer_altitude_km * thick;
	L.sigma = max(atm_layer_width_km * thick, 0.01);
	L.has_layer = dot(atm_layer_tau, vec3(1.0)) > 0.0;
	L.scatter_g = atm_gas_multiple * atm_phase_rayleigh(cos_theta) * atm_gas_tau;
	L.scatter_h = atm_haze_albedo * atm_haze_multiple * atm_phase_hg(cos_theta, atm_haze_g);
	L.scatter_l = atm_layer_albedo * atm_phase_hg(cos_theta, atm_layer_g);
	// Delta-scaling, for what lies BENEATH the atmosphere only. Single scattering counts
	// every interaction as removal, but a forward-scattering aerosol returns most of what it
	// takes to the beam's own direction: tau* = tau (1 - omega g) is that truncation's
	// similarity-scaled depth. It is a stand-in for the multiple scattering this model does
	// not carry, so it is deliberately not energy-conserving -- the light it stops removing
	// is not re-deposited anywhere. Rayleigh air is g = 0 and so unscaled, which is right:
	// its removal from the direct beam is real and is what reddens a low sun. The partner
	// relation g* = g/(1+g) belongs to the same transformation and never appears here,
	// because g enters only the phase function and no source term is scaled -- the ring and
	// the disc's own path radiance keep the full extinction and are bit-identical.
	L.delta_h = 1.0 - atm_haze_albedo * atm_haze_g;
	L.delta_l = 1.0 - atm_layer_albedo * atm_layer_g;
	return L;
}

// Slant column above altitude z of a unit-tau exponential, at zenith cosine mu.
vec3 atm_exp_slant(float R, float z, float H, float mu, vec3 tau) {
	return tau * (exp(-z / H) * atm_chapman(R, z, H, mu));
}

// The haze's slant column above z along an UPWARD ray (mu >= 0). Below a top, the ray crosses
// it at its own zenith cosine there and the two regions are two exponentials joined at that
// crossing; above it, only the upper one is left.
vec3 atm_haze_up(AtmLayers L, float R, float z, float mu) {
	if (z > L.z_k) {
		return atm_exp_slant(R, z, L.H_t, mu, L.tau_t);
	}
	float b = (R + z) * sqrt(max(1.0 - mu * mu, 0.0));
	float mu_k = sqrt(max(1.0 - (b / (R + L.z_k)) * (b / (R + L.z_k)), 0.0));
	return atm_exp_slant(R, z, L.H_h, mu, atm_haze_tau)
			- atm_exp_slant(R, L.z_k, L.H_h, mu_k, atm_haze_tau)
			+ atm_exp_slant(R, L.z_k, L.H_t, mu_k, L.tau_t);
}

// The haze's slant column above z at any zenith cosine. A ray below the horizon descends to
// its tangent altitude and comes back: two upward halves less the part above its start, the
// identity atm_chapman() applies internally to a single exponential.
vec3 atm_haze_column(AtmLayers L, float R, float z, float mu) {
	if (L.z_k <= 0.0) {
		return atm_exp_slant(R, z, L.H_h, mu, atm_haze_tau);
	}
	if (mu >= 0.0) {
		return atm_haze_up(L, R, z, mu);
	}
	float h_t = (R + z) * sqrt(max(1.0 - mu * mu, 0.0)) - R;
	return 2.0 * atm_haze_up(L, R, max(h_t, 0.0), 0.0) - atm_haze_up(L, R, z, -mu);
}

// Extinction of the two exponential layers along a ray from altitude z at zenith cosine mu.
vec3 atm_exp_column(AtmLayers L, float R, float z, float mu) {
	return atm_exp_slant(R, z, L.H_g, mu, atm_gas_tau) + atm_haze_column(L, R, z, mu);
}

// Radiance coefficient of the exponential layers at altitude z (per km of path).
// atm_exp_column for a ray that ends on something BENEATH the atmosphere. The haze column
// is linear in atm_haze_tau (L.tau_t is proportional to it too), so scaling the column is
// identical to scaling the depth, and no separate column math is needed.
vec3 atm_exp_column_beneath(AtmLayers L, float R, float z, float mu) {
	return atm_exp_slant(R, z, L.H_g, mu, atm_gas_tau) + atm_haze_column(L, R, z, mu) * L.delta_h;
}

// The same column split into what is ABSORBED and what is SCATTERED, for the sun leg. The
// split is exact and introduces no parameter, because 1 - omega g = (1 - omega) + omega (1 - g)
// -- so the two pieces sum to the delta-scaled depth above, term for term. Rayleigh gas is
// conservative (no albedo cell, omega = 1) and so is entirely the scattered half.
void atm_exp_column_split(AtmLayers L, float R, float z, float mu, out vec3 absorbed,
		out vec3 scattered) {
	vec3 haze = atm_haze_column(L, R, z, mu);
	absorbed = haze * (1.0 - atm_haze_albedo);
	scattered = atm_exp_slant(R, z, L.H_g, mu, atm_gas_tau)
			+ haze * (atm_haze_albedo * (1.0 - atm_haze_g));
}
vec3 atm_exp_scatter(AtmLayers L, float z) {
	vec3 haze = L.z_k > 0.0 && z > L.z_k
			? L.tau_t * (exp(-z / L.H_t) / L.H_t)
			: atm_haze_tau * (exp(-z / L.H_h) / L.H_h);
	return L.scatter_g * (exp(-z / L.H_g) / L.H_g) + L.scatter_h * haze;
}

// Whole tangent columns of the exponential layers for a ray tangent at altitude h.
vec3 atm_exp_tangent_column(AtmLayers L, float R, float h) {
	return atm_gas_tau * (exp(-h / L.H_g) * sqrt(2.0 * ATM_PI * (R + h) / L.H_g))
			+ 2.0 * atm_haze_column(L, R, h, 0.0);
}

// The altitude floor below the disc at which a ray's far half is dropped (see atm_disc): where
// the sub-disc chord's extinction reaches ATM_FAR_GATE_TAU on the channel with the THINNEST
// chord, which is the one that reaches deepest. The gate is set on the chord's own extinction
// and not on a count of scale heights, because those are the same thing only for a body whose
// disc tangent tau is already of order the threshold: a fixed two scale heights cut Titan at
// e^-7.5 of the unattenuated half -- four orders of magnitude over its own night side -- and
// drew a hard circle 90 km inside the disc that read as a second surface behind the glow.
// Decided in ALTITUDE before any exp(), for the reason atm_disc's 46 H_ref window gives; the
// epsilon is a domain guard bounding the floor at 17 H_ref, well inside R. Uniform-only, so
// the limb shader evaluates it once per VERTEX (v_far_floor) -- the chord costs several
// Chapman functions per call.
float atm_far_floor() {
	if (!atm_present()) {
		return 0.0; // no atmosphere: spare the airless bodies the tangent columns per vertex
	}
	AtmLayers L = atm_layers(0.0);
	float R = body_radius_km * surface_scale;
	vec3 disc_chord = atm_exp_tangent_column(L, R, 0.0);
	float thinnest_chord = min(min(disc_chord.r, disc_chord.g), disc_chord.b);
	return min(-L.H_ref * log(ATM_FAR_GATE_TAU / max(thinnest_chord, 1.0e-6)), 0.0);
}

// Extinction of the thin layer above altitude z along one side of a ray of tangent altitude
// h_t <= z. Exactly zero beyond ATM_LAYER_REACH, which is what lets every caller keep its
// layer terms unconditional.
vec3 atm_shell_partial(AtmLayers L, float R, float z, float h_t) {
	if (z - L.z_c > ATM_LAYER_REACH * L.sigma) {
		return vec3(0.0);
	}
	float scale = sqrt((R + L.z_c) / (2.0 * L.sigma));
	return atm_layer_tau * (scale * atm_gauss_abel_partial((z - L.z_c) / L.sigma, (h_t - L.z_c) / L.sigma));
}

// Extinction of the thin layer along a ray from altitude z at zenith cosine mu: an upward ray
// takes what lies above it; one below the horizon descends to its tangent altitude and comes
// back, so it takes that side twice less the part above its start.
vec3 atm_shell_ray_column(AtmLayers L, float R, float z, float mu) {
	float h_t = min((R + z) * sqrt(max(1.0 - mu * mu, 0.0)) - R, z);
	vec3 up = atm_shell_partial(L, R, z, h_t);
	if (mu >= 0.0) {
		return up;
	}
	return 2.0 * atm_shell_partial(L, R, h_t, h_t) - up;
}

// The part of a half-ray p0 + u e (u >= 0) that the sun lights, as (u_lo, u_hi), u_hi = ATM_INF
// when open. |p_perp|^2 = p0_perp2 + 2 u cross + u^2 e_perp2 is the squared distance from the
// shadow axis; the shadow is the cylinder |p_perp| < R on the night side of the terminator
// plane (a + u b < 0). The line meets the cylinder in one interval, the night side is a
// half-line, and a ray above the surface cannot cross the terminator plane inside the
// cylinder, so the lit set is one interval at each end; within an atmosphere's extent only
// the one the ray starts in, or starts after, matters.
vec2 atm_lit_interval(float R, float p0_perp2, float a, float b, float cross, float e_perp2) {
	float disc = cross * cross - e_perp2 * (p0_perp2 - R * R);
	if (disc <= 0.0) {
		return vec2(0.0, ATM_INF);
	}
	float root = sqrt(disc);
	float u_a = (-cross - root) / e_perp2;
	float u_b = (-cross + root) / e_perp2;
	float s_lo;
	float s_hi;
	if (b > 0.0) {
		s_lo = u_a;
		s_hi = min(u_b, -a / b);
	} else if (b < 0.0) {
		s_lo = max(u_a, -a / b);
		s_hi = u_b;
	} else {
		s_lo = u_a;
		s_hi = a < 0.0 ? u_b : u_a;
	}
	if (s_hi <= max(s_lo, 0.0)) {
		return vec2(0.0, ATM_INF);
	}
	if (s_lo < 0.0) {
		return vec2(s_hi, ATM_INF);
	}
	return vec2(0.0, s_lo);
}

// --------------------------------------------------------------------- the two branches

// One half of a ray of tangent altitude h, integrated outward from z_floor: the radiance it
// delivers to the camera, attenuated over its whole route. sign_s +1 is the half on the
// camera's side of the tangent point, -1 the half beyond it, whose light crosses the near half
// too -- which is why exp_total and shell_total are the WHOLE tangent columns and the far
// half's view extinction is `total - own`. a is the sun's component along the tangent-point
// radius (r_t * dot(q_hat, s)) and sz its component along the ray toward the camera.
//
// h may lie BELOW the disc, which is the far half of a ray that meets a disc placed inside its
// own atmosphere. Then z_floor is the disc rather than the tangent point, so the half starts
// where the ray leaves the body -- and `total - own` picks up the sub-disc chord with no new
// term.
vec3 atm_ray_half(AtmLayers L, float R, float h, float z_floor, float a, float p0_perp2,
		float sz, float sun_ang, float sign_s, vec3 exp_total, vec3 shell_total) {
	float r_t = R + h;
	vec3 path = vec3(0.0);
	float b = sign_s * sz;
	vec2 lit = atm_lit_interval(R, p0_perp2, a, b, -a * b, max(1.0 - b * b, 1.0e-12));
	float u_lo = lit.x;
	float u_hi = lit.y;
	bool open = u_hi >= ATM_INF;
	// altitude along the ray, as h + u^2 / (sqrt(r_t^2 + u^2) + r_t) to keep float32 precision
	float z_lo = max(h + u_lo * u_lo / (sqrt(r_t * r_t + u_lo * u_lo) + r_t), z_floor);
	float u_hi_c = min(u_hi, 1.0e9);
	float z_hi = open ? ATM_INF : h + u_hi_c * u_hi_c / (sqrt(r_t * r_t + u_hi_c * u_hi_c) + r_t);
	z_hi = max(z_hi, z_lo);   // the lit part can end below a floored start
	float v_lo = sqrt(max(z_lo - h, 0.0) / L.H_ref);
	float v_hi = sqrt(max(min(z_hi, 1.0e9) - h, 0.0) / L.H_ref);
	float tau_lo = atm_erf(v_lo);
	float tau_hi = open ? 1.0 : atm_erf(min(v_hi, 6.0));
	float span = tau_hi - tau_lo;
	if (span > 0.0) {
		for (int k = 0; k < 6; k++) {
			float v = atm_erfinv(tau_lo + span * ATM_GL6_T[k]);
			float z = h + L.H_ref * v * v;
			float u = atm_chord(R, z, h);
			float du_dv = u > 0.0 ? 2.0 * L.H_ref * v * (R + z) / u : sqrt(2.0 * r_t * L.H_ref);
			float weight = 0.88622693 * ATM_GL6_W[k] * span * exp(v * v) * du_dv;
			float mu_v = u / (R + z);
			vec3 near_exp = atm_exp_column(L, R, z, mu_v);
			vec3 view = sign_s > 0.0 ? near_exp : exp_total - near_exp;
			float mu_s = (a + sign_s * u * sz) / (R + z);
			vec3 sun = atm_exp_column(L, R, z, mu_s);
			if (L.has_layer) {
				vec3 above = atm_shell_partial(L, R, z, h);
				view += sign_s > 0.0 ? above : shell_total - above;
				sun += atm_shell_ray_column(L, R, z, mu_s);
			}
			float shadow = atm_sun_shadow(R, z, mu_s, sun_ang);
			path += weight * atm_exp_scatter(L, z) * exp(-view - sun) * shadow;
		}
	}
	// The reach gate is exact, not approximate: past it the column this block scales is the
	// zero atm_shell_partial returns, so skipping the block changes nothing but the cost.
	if (L.has_layer && z_lo - L.z_c < ATM_LAYER_REACH * L.sigma) {
		// The thin layer's crossing on this side: its lit column, spread over three
		// altitude nodes at the quantiles of the profile between the lit altitudes,
		// weighted by the path length each takes.
		vec3 column = atm_shell_partial(L, R, z_lo, h);
		if (!open) {
			column -= atm_shell_partial(L, R, min(z_hi, 1.0e9), h);
		}
		float lower = 1.0 - atm_gauss_tail((z_lo - L.z_c) / L.sigma);
		float upper = open ? 1.0 : 1.0 - atm_gauss_tail((min(z_hi, 1.0e9) - L.z_c) / L.sigma);
		float zs[3];
		float gs[3];
		float g_total = 0.0;
		for (int i = 0; i < 3; i++) {
			float q = lower + ATM_SHELL_P[i] * (upper - lower);
			float z = L.z_c + L.sigma * 1.41421356 * atm_erfinv(2.0 * q - 1.0);
			z = clamp(z, z_lo, z_hi);
			zs[i] = z;
			gs[i] = ATM_SHELL_W[i] * (R + z) / max(atm_chord(R, z, h), 1.0e-3);
			g_total += gs[i];
		}
		for (int i = 0; i < 3; i++) {
			float z = zs[i];
			float share = gs[i] / g_total;
			float u = atm_chord(R, z, h);
			float mu_v = u / (R + z);
			vec3 near_exp = atm_exp_column(L, R, z, mu_v);
			vec3 above = atm_shell_partial(L, R, z, h);
			vec3 view = sign_s > 0.0 ? near_exp + above : exp_total - near_exp + shell_total - above;
			float mu_s = (a + sign_s * u * sz) / (R + z);
			vec3 sun = atm_exp_column(L, R, z, mu_s) + atm_shell_ray_column(L, R, z, mu_s);
			float shadow = atm_sun_shadow(R, z, mu_s, sun_ang);
			path += share * L.scatter_l * column * exp(-view - sun) * shadow;
		}
	}
	return path;
}

// Beyond-limb ray tangent at altitude h: path radiance and view transmittance. qs is the sun's
// cosine at the tangent point (dot(q_hat, s)), sz its component along the ray toward the
// camera (dot(e, s)).
void atm_ring(AtmLayers L, float R, float h, float qs, float sz, float sun_ang,
		out vec3 path, out vec3 transmittance) {
	float r_t = R + h;
	float a = r_t * qs;
	float p0_perp2 = r_t * r_t * (1.0 - qs * qs);
	vec3 exp_total = atm_exp_tangent_column(L, R, h);
	vec3 shell_total = L.has_layer ? 2.0 * atm_shell_partial(L, R, h, h) : vec3(0.0);
	path = atm_ray_half(L, R, h, h, a, p0_perp2, sz, sun_ang, 1.0, exp_total, shell_total)
			+ atm_ray_half(L, R, h, h, a, p0_perp2, sz, sun_ang, -1.0, exp_total, shell_total);
	transmittance = exp(-exp_total - shell_total);
}


// ONE PIXEL OF THE RING RATHER THAN ONE POINT OF IT, which is the difference between a thin
// continuous band and a dotted arc of saturated single pixels.
//
// THE PROBLEM. The ring's bright band is a few scale heights — some 25 km on a 6371 km Earth —
// so it is thinner than a pixel unless the disc spans a couple of hundred px of radius. Below
// that, which is nearly all of the time, one sample per pixel decides the whole band: the
// screen grid meets the limb circle at a different sub-pixel offset at every azimuth, so the
// pixel nearest the limb lands on the band at one angle and above it at the next, and the ring
// renders as a dotted arc that glow then amplifies. What the pixel stands for is the ring's
// MEAN over the altitude band it covers, and that is what this returns.
//
// WHY IT IS SAMPLED RATHER THAN SOLVED, which is worth recording because the closed forms are
// tempting and both are wrong here. The ring's radiance is NOT a decaying exponential in
// tangent altitude: it peaks where the slant path reaches unit optical depth and is reddened
// and dim BELOW that, the limb's own sunset. So an estimator anchored at the bottom of the
// window — H (I(h_lo) - I(h_hi)) / footprint, exact for A exp(-h/H) — reads the reddened foot
// of the profile and misses the peak entirely; measured, it drained the blue out of Earth's
// ring (arc RGB 136,140,149 -> 144,142,138) without touching the dashing. Compressing the
// altitude axis to widen the band fails the same way and worse, since it puts the dense, red
// low atmosphere across the whole annulus: the arc went orange (146,129,102) and its crest
// fell from 188 to 103. A plain box average over the window has no shape assumption to be
// wrong about, and samples at TRUE altitudes, so the colour comes out right.
//
// Dividing by the FULL footprint while integrating only from h_lo = max(h - footprint/2, 0)
// is deliberate: the part of a pixel below the disc's silhouette carries no ring, its air
// being the disc shaders' own term (atm_disc_air). The result is therefore coverage-weighted,
// and the ring fades across the last pixel at the silhouette instead of ending on a step.
//
// A RENDERING BOUNDARY CONDITION, like the shell-edge fade in atm_limb() and not part of the
// model: limb_model.py's closed_form does not carry it, and it is an exact no-op wherever the
// camera resolves the profile. Its cost is ATM_RING_TAPS ring quadratures on the fragments of
// a thin annulus, paid only where the ring is unresolved. HAZARD: the caller must measure
// `footprint` with screen derivatives under UNIFORM control flow (see atm_limb).
// One sample per scale height across the window, capped. The count is what keeps the cost
// where the need is, and the two move opposite ways: a close camera spreads the annulus over
// many fragments but resolves the profile, so it takes one or two samples each; a distant one
// needs the full set but has a rim of a few hundred fragments to pay it on.
const int ATM_RING_MAX_TAPS = 8;
// The reconstruction filter's width in pixels. A box one pixel wide is the pixel's own MEAN,
// which is correct and still leaves the arc a one-pixel line — and a one-pixel line following a
// shallow curve is a staircase, in runs as long as the curve stays within a row. Reconstructing
// over rather more than a pixel is what gives the arc a soft cross-section, so consecutive rows
// overlap and the steps blur into each other. It is the same width as the camera's own PSF --
// the same camera [code]limb_mean_incidence()[/code] measures a silhouette's coverage through.
const float ATM_RING_FILTER_PX = 2.5;

// Altitude above which the ring carries nothing worth sampling, so the taps can be spent on the
// part of the window that has structure: 8 scale heights is e^-8 of the peak, and the haze top
// and a detached layer each push it up if they stand higher.
float atm_ring_reach(AtmLayers L) {
	float reach = 8.0 * L.H_ref;
	if (L.z_k > 0.0) {
		reach = max(reach, L.z_k + 8.0 * L.H_t);
	}
	if (L.has_layer) {
		reach = max(reach, L.z_c + 4.0 * L.sigma);
	}
	return reach;
}

bool atm_ring_pixel(AtmLayers L, float R, float h, float footprint, float qs, float sz,
		float sun_ang, out vec3 path, out vec3 transmittance) {
	path = vec3(0.0);
	transmittance = vec3(1.0);
	// The filter spans this much altitude, and the samples are taken over the part of it that
	// both exists (above the silhouette) and carries signal (below the reach). Normalizing by
	// the FULL width rather than by the sampled part is what makes the clipping mean something:
	// a fragment whose filter hangs half over the silhouette gets half the ring, which is how
	// the band fades out at the limb instead of ending on a step.
	float half_width = 0.5 * ATM_RING_FILTER_PX * footprint;
	float lo = max(h - half_width, 0.0);
	float hi = min(h + half_width, atm_ring_reach(L));
	if (hi <= lo) {
		return false; // no beyond-limb ray with anything on it reaches this pixel
	}
	float span = hi - lo;
	// One tap per scale height, and never coarser than one per pixel: close in, where the
	// annulus spreads over many fragments, the profile is resolved and a couple of taps carry
	// the filter; far out it takes the full set, on a rim of a few hundred fragments.
	int taps = int(clamp(ceil(span / min(L.H_ref, footprint)), 1.0, float(ATM_RING_MAX_TAPS)));
	float step = span / float(taps);
	vec3 transmittance_sum = vec3(0.0);
	float weight_sum = 0.0;
	// Constant trip bound with a break, so no target has to support a dynamic loop count (the
	// same caution the small-body Kepler solver carries).
	for (int i = 0; i < ATM_RING_MAX_TAPS; i++) {
		if (i >= taps) {
			break;
		}
		float tap_h = lo + (float(i) + 0.5) * step;
		// Tent, normalized so its integral over the full width is exactly 1.
		float weight = max(1.0 - abs(tap_h - h) / half_width, 0.0) * step / half_width;
		vec3 tap_path;
		vec3 tap_transmittance;
		atm_ring(L, R, tap_h, qs, sz, sun_ang, tap_path, tap_transmittance);
		path += tap_path * weight;
		transmittance_sum += tap_transmittance * weight;
		weight_sum += weight;
	}
	if (weight_sum <= 0.0) {
		return false;
	}
	transmittance = mix(vec3(1.0), transmittance_sum / weight_sum, min(weight_sum, 1.0));
	return true;
}

// Surface-hit ray at a point with view cosine mu and sun cosine mu0 (sz = dot(e, s) as for the
// ring): path radiance above it and the view transmittance through the whole column.
void atm_disc(AtmLayers L, float R, float mu, float mu0, float sz, float sun_ang,
		float far_floor, out vec3 path, out vec3 transmittance) {
	float b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	// The view ray's own tangent altitude, below the surface -- as -R mu^2 / (1 + sqrt(1 - mu^2))
	// and NEVER as b_ray - R, which is the difference of two planetary radii: in float32 that
	// quantizes to ~0.5 m at Earth's and collapses to EXACTLY zero for a grazing ray. A zero
	// tangent depth puts the last quadrature node on the ray's own tangent point, where
	// atm_chord returns 0, the Jacobian (R + z) / chord is +inf, and inf times an extinction
	// that has underflowed to zero is a NaN -- which reaches the HDR buffer and is not a local
	// defect there, since the glow pass smears it into a bright blob with a black core. That
	// is what flashed at a rotating body's lit-side silhouette, where the disc shaders sample
	// mu from the MESH (a facet at the silhouette presents mu at or below zero) rather than
	// from a ray-sphere intersection, which cannot. Same rule atm_chord itself follows, for
	// the same reason: never difference two squares of order R.
	float h_v = -R * mu * mu / (1.0 + sqrt(max(1.0 - mu * mu, 0.0)));
	vec2 lit = atm_lit_interval(R, R * R * (1.0 - mu0 * mu0), R * mu0, sz, R * (mu - mu0 * sz),
			max(1.0 - sz * sz, 1.0e-12));
	float u_lo = lit.x;
	float u_hi = lit.y;
	bool open = u_hi >= ATM_INF;
	float z_lit = sqrt(R * R + 2.0 * R * mu * u_lo + u_lo * u_lo) - R;
	float u_hi_c = min(u_hi, 1.0e9);
	float z_cap = open ? ATM_INF : sqrt(R * R + 2.0 * R * mu * u_hi_c + u_hi_c * u_hi_c) - R;
	path = vec3(0.0);
	// The lit part of the ray is skipped outright when it starts more than 46 scale heights
	// up (e^-46 of nothing), decided in ALTITUDE before any exp(): where the shadow exit sat
	// ~90 scale heights up, t_lo was a valid but tiny float32 (~1e-36) that the GPU's log()
	// turned into -inf, and the node altitude into NaN - a curve of black across the night
	// side, found on Venus. Inside the window every transcendental stays in range.
	if (z_lit < 46.0 * L.H_ref && z_cap > z_lit) {
		float t_lo = exp(-z_lit / L.H_ref);
		float t_hi = open ? 0.0 : exp(-z_cap / L.H_ref);
		float span = t_lo - t_hi;
		for (int k = 0; k < 6; k++) {
			float t = t_hi + span * ATM_GL6_T[k];
			float z = -L.H_ref * log(t);
			float chord = atm_chord(R, z, h_v);
			float u = chord - R * mu;
			float weight = ATM_GL6_W[k] * span * (L.H_ref / t) * (R + z) / chord;
			float mu_v = (R * mu + u) / (R + z);
			float mu_s = (R * mu0 + u * sz) / (R + z);
			vec3 view = atm_exp_column(L, R, z, mu_v);
			vec3 sun = atm_exp_column(L, R, z, mu_s);
			if (L.has_layer) {
				view += atm_shell_partial(L, R, z, h_v);
				sun += atm_shell_ray_column(L, R, z, mu_s);
			}
			float shadow = atm_sun_shadow(R, z, mu_s, sun_ang);
			path += weight * atm_exp_scatter(L, z) * exp(-view - sun) * shadow;
		}
	}
	// The disc is not always a surface. Where it is the body's own optical limb -- Titan's is,
	// at tangent optical depth 1.0 -- the ray does not stop there: the half beyond it reaches
	// the camera through the sub-disc chord and the near half. At the rim that half is worth
	// exp(-tau/2) of the one we keep, 0.60 on Titan and 0.07 on Venus, and nothing at all on a
	// body whose disc IS the ground, where the profile's extrapolation below it extinguishes
	// the half within a scale height. far_floor is where the sub-disc chord ends it:
	// atm_far_floor(), evaluated in the vertex stage.
	if (h_v > far_floor) {
		float qs_far = clamp(R * (mu0 - mu * sz) / max(b_ray, 1.0e-3), -1.0, 1.0);
		vec3 far_exp = atm_exp_tangent_column(L, R, h_v);
		vec3 far_shell = L.has_layer ? 2.0 * atm_shell_partial(L, R, h_v, h_v) : vec3(0.0);
		path += atm_ray_half(L, R, h_v, 0.0, b_ray * qs_far,
				b_ray * b_ray * (1.0 - qs_far * qs_far), sz, sun_ang, -1.0, far_exp, far_shell);
	}
	// Not part of the path integral: this is what the disc BENEATH keeps, so it is
	// delta-scaled. The quadrature above attenuates its own scattered light by the full
	// extinction and is untouched.
	vec3 view_total = atm_exp_column_beneath(L, R, 0.0, mu);
	if (L.has_layer) {
		view_total += atm_shell_partial(L, R, 0.0, h_v) * L.delta_l;
	}
	// Gated like the ring's crossing: past the reach the column is the exact zero.
	if (L.has_layer && z_lit - L.z_c < ATM_LAYER_REACH * L.sigma) {
		vec3 column = atm_shell_partial(L, R, z_lit, h_v);
		float lower = 1.0 - atm_gauss_tail((z_lit - L.z_c) / L.sigma);
		float zs[3];
		float gs[3];
		float g_total = 0.0;
		for (int i = 0; i < 3; i++) {
			float q = lower + ATM_SHELL_P[i] * (1.0 - lower);
			float z = max(L.z_c + L.sigma * 1.41421356 * atm_erfinv(2.0 * q - 1.0), z_lit);
			zs[i] = z;
			gs[i] = ATM_SHELL_W[i] * (R + z) / max(atm_chord(R, z, h_v), 1.0e-3);
			g_total += gs[i];
		}
		for (int i = 0; i < 3; i++) {
			float z = zs[i];
			float share = gs[i] / g_total;
			float u = atm_chord(R, z, h_v) - R * mu;
			float mu_v = (R * mu + u) / (R + z);
			float mu_s = (R * mu0 + u * sz) / (R + z);
			vec3 view = atm_exp_column(L, R, z, mu_v) + atm_shell_partial(L, R, z, h_v);
			vec3 sun = atm_exp_column(L, R, z, mu_s) + atm_shell_ray_column(L, R, z, mu_s);
			float shadow = atm_sun_shadow(R, z, mu_s, sun_ang);
			path += share * L.scatter_l * column * exp(-view - sun) * shadow;
		}
	}
	transmittance = exp(-view_total);
	// A FINITE GUARD, and the shipped answer to a defect that could not be cornered any
	// closer than this. At grazing incidence this quadrature's intermediates span tens of
	// orders of magnitude -- a Chapman column that clamps at e^60 against an extinction
	// that underflows to exactly zero -- and their product is a NaN, measured reaching the
	// frame from here at about one fragment per two dozen views, always at the silhouette
	// and on the lit side. It cannot be attributed to a term, because it is SENSITIVE TO
	// THE SURROUNDING COMPILATION: with isnan() reads on t, z, chord, weight, view, sun
	// and shadow inside the loop it stops happening altogether, while this guard, reading
	// the same values one scope out, catches it without suppressing it (both builds
	// compile; the difference is reproducible on the same two poses). That is the same
	// driver behaviour atm_present() was added for, one defect earlier, and what reaches
	// the frame must not depend on it. A fragment falling back to no air in front of it is
	// invisible in a field this smooth; a single NaN in the HDR buffer is not local at all,
	// because the glow pass smears it into a bright blob with a black core -- which is what
	// the four atmosphere bodies flashed at their lit-side silhouettes as they turned,
	// under Forward+ ONLY, the display-referred path's own max(value, 0.0) having scrubbed
	// it before it could bloom.
	if (any(isnan(path)) || any(isinf(path))) {
		path = vec3(0.0);
	}
	if (any(isnan(transmittance)) || any(isinf(transmittance))) {
		transmittance = vec3(1.0);
	}
}

// --------------------------------------------------------------------- the entry points

// The limb shell's fragment: camera and fragment positions and the sun direction in the
// shell's LOCAL frame (unit sphere = this shell), sun_ang the sun's angular radius, and
// far_floor the vertex stage's atm_far_floor(). Returns the path radiance (I/F, taste
// applied) and the transmittance of whatever lies behind — for the beyond-limb rays that
// are this shell's whole job, plus the shell's share of the disc-air handoff band
// (ATM_RIM_HANDOFF, drawn as a pure add: the luma dimming is the disc shaders', in full).
// A ray that meets the disc below the band sets disc_hit and returns nothing instead: its
// air belongs to the disc's own shaders (atm_disc_air, and THE COMPOSITING SPLIT above),
// so the caller discards rather than paying for a quadrature another fragment already ran.
void atm_limb(vec3 camera_local, vec3 fragment_local, vec3 sun_local, float sun_ang,
		float far_floor, out vec3 path, out vec3 transmittance, out bool disc_hit) {
	path = vec3(0.0);
	transmittance = vec3(1.0);
	disc_hit = false;
	if (body_radius_km <= 0.0) {
		return;
	}
	float k = body_radius_km * shell_scale;       // km per local unit
	float R = body_radius_km * surface_scale;     // the disc, km
	float h_top = (shell_scale - surface_scale) * body_radius_km; // this shell, km above the disc
	vec3 c = camera_local * k;
	vec3 p = fragment_local * k;
	vec3 d = normalize(p - c);                    // the view ray, camera -> fragment
	vec3 e = -d;
	float sz = dot(e, sun_local);
	float tc = -dot(c, d);
	vec3 q = c + tc * d;                          // closest approach to the centre
	float b = length(q);
	// The pixel's own radial footprint, in km of tangent altitude, for atm_ring_pixel() below.
	// Taken HERE because screen derivatives require uniform control flow and the disc branch
	// under it is not uniform — which is also why this function must be called unconditionally
	// (it is, from atmosphere_limb.gdshader's fragment; see also the ring shadow's fwidth in
	// _sun_occlusion.gdshaderinc, which carries the same rule).
	float b_footprint = length(vec2(dFdx(b), dFdy(b)));
	AtmLayers L = atm_layers(-sz);               // cos(theta) = dot(s, d)
	float h = b - R;
	float qs = dot(q / b, sun_local);
	// THE RING'S SHARE OF THIS PIXEL, computed for a pixel on EITHER side of the silhouette.
	// That is what closes the dashing, and the reason is a footprint that straddles the limb:
	// the ring's bright band is a fraction of a pixel, and where the screen grid falls so that
	// the innermost pixel with b > R already sits above the band, the band lands in the pixel
	// below it — a DISC pixel, which used to draw no beyond-limb ray at all. So at those
	// azimuths the ring's flux was not misplaced but lost, and the arc broke into dashes.
	// Letting a straddling pixel carry the part of its footprint that lies above the limb
	// makes the flux drawn per azimuth constant; the split between the two pixels still moves
	// with the sub-pixel offset, which now reads as a band of shifting thickness rather than
	// one that comes and goes.
	vec3 ring_path;
	vec3 ring_transmittance;
	bool has_ring = atm_ring_pixel(L, R, h, b_footprint, qs, sz, sun_ang, ring_path,
			ring_transmittance);
	if (b < R) {
		float w_shell = smoothstep(R * (1.0 - ATM_RIM_HANDOFF), R, b);
		if (w_shell <= 0.0 && !has_ring) {
			disc_hit = true;
			return;
		}
		if (w_shell > 0.0) {
			// The shell's share of the handoff band (see ATM_RIM_HANDOFF): the sliver at the
			// silhouette that the polygonal disc meshes fail to cover gets its air from here.
			float half_chord = sqrt(max(R * R - b * b, 0.0));
			vec3 hit = q - half_chord * d;
			vec3 n = hit / R;
			float mu = dot(n, e);
			float mu0 = dot(n, sun_local);
			vec3 disc_transmittance;
			atm_disc(L, R, mu, mu0, sz, sun_ang, far_floor, path, disc_transmittance);
			path *= w_shell;
		}
		// Added, and the transmittance left at 1: this side of the silhouette is a pure add,
		// the luma dimming being the disc shaders' in full (see the header).
		path = (path + ring_path) * mix(1.0, atm_intensity, iv_limb_scale);
		return;
	}
	path = ring_path;
	transmittance = ring_transmittance;
	// The shell is where the MODEL stops, not where the atmosphere does - a ray tangent
	// above it gets no fragment at all. Its scale is chosen (see tables/README.md) so
	// that what is left up there is under half a display code, which makes this a no-op;
	// but the camera can sit 20 EV over the limb while dark-adapted against a crescent,
	// and then the shell's own silhouette is a hard white edge against the sky. Taking
	// the last few scale heights smoothly to nothing makes the boundary a ramp at every
	// exposure, at the cost of some of the faintest real signal. It is a rendering
	// boundary condition and not part of the model, so limb_model.py's closed_form does
	// not carry it (its --verify compares the physics).
	float fade = smoothstep(0.0, ATM_EDGE_FADE * L.H_ref, h_top - h);
	path *= fade;
	transmittance = mix(vec3(1.0), transmittance, fade);
	path *= mix(1.0, atm_intensity, iv_limb_scale);
}

// Transmittance of the column above altitude z along a view ray that meets the DISC at view
// cosine mu (so the ray's tangent altitude is the disc's, below the surface).
vec3 atm_view_transmittance(AtmLayers L, float R, float z, float mu) {
	float b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	float h_v = -R * mu * mu / (1.0 + sqrt(max(1.0 - mu * mu, 0.0))); // see atm_disc: never b_ray - R
	// the ray's zenith cosine at altitude z, from its impact parameter
	float mu_z = sqrt(max(1.0 - b_ray * b_ray / ((R + z) * (R + z)), 0.0));
	vec3 column = atm_exp_column_beneath(L, R, z, mu_z);
	if (L.has_layer) {
		column += atm_shell_partial(L, R, z, h_v) * L.delta_l;
	}
	return exp(-column);
}

float atm_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// The disc branch, for the shells that ARE the disc's stack (see THE COMPOSITING SPLIT):
// the air in front of a surface, band or cloud fragment, composited by that fragment
// itself. Returns the path radiance of the ray from the camera to the disc (I/F, taste
// applied — the veil over the lit disc, the twilight glow past the terminator, and the
// far half of a ray whose disc is an optical limb) and the LUMA of the disc's view
// transmittance. The caller ADDS the path over everything it renders and MULTIPLIES the
// luma into all of it — lit albedo, every emission term, and the specular lobe as its
// square root — with atm_view_tint() still carrying the chromatic complement.
//
// Inputs are in the calling shell's LOCAL frame, as for atm_limb(), and far_floor is the
// vertex stage's atm_far_floor(). A shell above the disc (a cloud deck) traces its
// fragment's ray down to the disc; where that ray misses the disc entirely — a deck
// fragment past the disc's silhouette — this returns the no-op and the limb shell's ring
// branch covers the ray as it always did. The path fades out over the last
// ATM_RIM_HANDOFF of the disc's radius, where the limb shell draws the complement — see
// the constant for why a hard partition cannot work there. The luma is NOT feathered:
// it dims this fragment's own content, which needs no second owner.
void atm_disc_air(vec3 camera_local, vec3 fragment_local, vec3 sun_local, float sun_ang,
		float far_floor, out vec3 path, out float behind_luma) {
	path = vec3(0.0);
	behind_luma = 1.0;
	// Gated on the atmosphere EXISTING (atm_present), not only on the geometry being fed:
	// an airless body's "no-op" was otherwise merely numerical — a full six-node quadrature
	// per fragment multiplying everything by a tau of zero. That is a cost with no output
	// on every airless body, and driver arithmetic on its extreme zero-tau intermediates
	// was observed emitting garbage (bright glow-bloomed beads along Saturn's silhouette in
	// the rings view, sensitive to the surrounding compilation). No evaluation, no beads.
	if (!atm_present()) {
		return;
	}
	float k = body_radius_km * shell_scale;       // km per local unit
	float R = body_radius_km * surface_scale;     // the disc, km
	vec3 c = camera_local * k;
	vec3 p = fragment_local * k;
	vec3 d = normalize(p - c);                    // the view ray, camera -> fragment
	vec3 e = -d;
	float sz = dot(e, sun_local);
	vec3 n;
	float b_ray;
	if (shell_scale > surface_scale) {
		// A shell above the disc: continue the ray to the disc's near side, or miss.
		float tc = -dot(c, d);
		vec3 q = c + tc * d;
		b_ray = length(q);
		if (b_ray >= R) {
			return;
		}
		n = (q - sqrt(max(R * R - b_ray * b_ray, 0.0)) * d) / R;
	} else {
		// This fragment IS the disc: its own direction is the hit normal, better
		// conditioned at the silhouette than re-intersecting its ray with the sphere.
		n = normalize(fragment_local);
	}
	float mu = dot(n, e);
	float mu0 = dot(n, sun_local);
	if (shell_scale <= surface_scale) {
		b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	}
	// The handoff fade, decided BEFORE the quadrature runs. Where it is zero the shell owns
	// the air outright and this fragment's own answer is multiplied away -- so evaluating it
	// is pure cost, and worse than free: that is exactly the tangent ray (mu -> 0, b_ray -> R),
	// whose h_v = b_ray - R is the cancellation-limited difference of two planetary radii,
	// quantized in float32 to ~5e-4 km at Earth's. A NaN out of that degenerate evaluation
	// survives `NaN * 0.0` and reaches the frame, and an HDR NaN is not a local defect: the
	// glow pass smears it into a bright blob with a black core, which is what a rotating body
	// flashed at its lit-side silhouette. Skipping is exact for every finite path -- the
	// factor really is zero -- and removes the degenerate ray entirely.
	float rim_fade = 1.0 - smoothstep(R * (1.0 - ATM_RIM_HANDOFF), R, b_ray);
	if (rim_fade <= 0.0) {
		return;
	}
	AtmLayers L = atm_layers(-sz);                // cos(theta) = dot(s, d)
	vec3 transmittance;
	atm_disc(L, R, mu, mu0, sz, sun_ang, far_floor, path, transmittance);
	path *= rim_fade * mix(1.0, atm_intensity, iv_limb_scale);
	behind_luma = atm_luma(transmittance);
}

// What a surface or cloud shell multiplies its sunlight by: the TOTAL illumination reaching
// this shell's own altitude relative to vacuum, direct beam plus diffuse sky. mu0 is the
// fragment's sun cosine on the macroscopic normal. A sun below the horizon needs no branch:
// the engine's own N.L has already removed its light.
//
// NOT exp(-column). Absorbed light is gone and takes the exponential; SCATTERED light is not
// -- roughly a quarter of it arrives anyway, off the sky, and is what lets you see the ground
// at sunset. exp() throws all of it away, and the error is unbounded as the column grows: at
// Earth's terminator the direct beam alone is 7.4e-4 of vacuum in green, which is why the
// surface and the cloud deck both vanished there and left the atmosphere's own glow standing
// in a band with nothing in it, while thin-aired Mars stayed legible to the last code.
// 1 / (1 + k tau) is the conservative two-stream result for the total downward flux, exact in
// the diffusion limit and a standard interpolation elsewhere; against real sky-plus-sun
// illuminance it is right to a few percent from noon down to a solar zenith of 87 degrees.
// It is the same kind of stand-in as the delta-scaling above and deliberately shares its
// depth: what the two-stream returns is precisely the half of `1 - omega g` that is scattered.
//
// The VIEW leg keeps exp() and must -- see atm_view_transmittance. Light scattered out of a
// view ray is not lost from the model, it is the path radiance, and that is added separately.
// Nothing adds the light scattered out of the SUN leg, so this is where it belongs.
vec3 atm_sun_transmittance_at(AtmLayers L, float R, float z, float mu0) {
	float up = max(mu0, 0.0);
	vec3 absorbed;
	vec3 scattered;
	atm_exp_column_split(L, R, z, up, absorbed, scattered);
	if (L.has_layer) {
		vec3 layer = atm_shell_ray_column(L, R, z, up);
		absorbed += layer * (1.0 - atm_layer_albedo);
		scattered += layer * (atm_layer_albedo * (1.0 - atm_layer_g));
	}
	return exp(-absorbed) / (1.0 + ATM_TWO_STREAM_K * scattered);
}

vec3 atm_sun_transmittance(float mu0) {
	if (body_radius_km <= 0.0) {
		return vec3(1.0);
	}
	float R = body_radius_km * surface_scale;
	float z = max((shell_scale - surface_scale) * body_radius_km, 0.0);
	return atm_sun_transmittance_at(atm_layers(0.0), R, z, mu0);
}

// The twilight a shell must ADD to what the engine already gives it, as emission.
//
// Everything above is plane-parallel on the sun leg: flux entering the column goes as mu0, so
// illumination is pinned to zero at the geometric terminator, with a CORNER. On a sphere it is
// not. The air above a point at mu0 = 0 is still fully lit -- the terminator at altitude z
// stands sunward of the one on the ground -- and it shines down. Nothing here or in the engine
// puts that light anywhere, so a surface and a cloud deck both stop dead at the same line while
// the atmosphere's own glow renders on past it, which is the band with nothing in it. Measured
// against the hemisphere integral, real ground at the terminator gets 0.7 % of full sun, and
// the decay past it has no feature at mu0 = 0 at all: the sky does not know where the ground's
// terminator is.
//
// The engine hands a shell albedo x max(mu0, 0) x atm_sun_transmittance and nothing below the
// horizon. The target is direct + max(plane-parallel diffuse, twilight), so what is missing is
// max(twilight - plane-parallel diffuse, 0) and nothing else: the beam and the day-side diffuse
// cancel term for term, which is why the DAY SIDE CANNOT MOVE. The subtraction is not a fudge
// -- atm_sun_transmittance is a TOTAL, direct plus diffuse, so adding a twilight curve on top
// of it would count the diffuse twice.
//
// Evaluated at the DISC for every shell, not at the shell's own altitude. A deck a few km up
// really does see a little more (Earth's measures 1.19x at the terminator, and stays lit 3.2 deg
// longer), but one illumination for all of them is what makes surface and cloud fade TOGETHER;
// give the deck its own and the two part company at the very place the wall was. What the deck
// legitimately keeps beyond this is its direct beam, which is a separate term and not this one.
// The twilight curve alone, from the atm_sky_* cells, HELD at its own vertex. The reference
// is monotone in mu0 -- the sky only brightens as the sun rises -- and a downward parabola is
// not, so past its vertex the raw fit falls where the truth climbs. The cells are fitted so
// that vertex lies beyond the crossover, so nothing is clamped where the term acts; what the
// hold buys is the day side, released because the plane-parallel diffuse overtakes a CONSTANT
// and stays past it rather than because the parabola decayed fast enough.
vec3 atm_sky_illumination(float mu0) {
	if (body_radius_km <= 0.0 || atm_sky_flux == vec3(0.0)) {
		return vec3(0.0);
	}
	vec3 held = min(vec3(mu0), atm_sky_slope / (-2.0 * atm_sky_bend));
	return atm_sky_flux * exp(held * (atm_sky_slope + held * atm_sky_bend));
}

// The DIFFUSE half of what the disc already receives from the plane-parallel two-stream: the
// total less the beam. Absorbed light is gone and takes the exponential; scattered light
// largely is not -- roughly a quarter of it arrives anyway, off the sky, and is what lets you
// see the ground at sunset. Evaluated at the disc for every shell, as the twilight is.
vec3 atm_plane_diffuse(float mu0) {
	if (body_radius_km <= 0.0) {
		return vec3(0.0);
	}
	AtmLayers L = atm_layers(0.0);
	float R = body_radius_km * surface_scale;
	float up = max(mu0, 0.0);
	vec3 beam = atm_exp_column(L, R, 0.0, up);
	if (L.has_layer) {
		beam += atm_shell_ray_column(L, R, 0.0, up);
	}
	return up * max(atm_sun_transmittance_at(L, R, 0.0, up) - exp(-beam), vec3(0.0));
}

// What a shell adds as EMISSION over what the engine already gives it. The engine hands it
// `beam_response * (direct + plane_diffuse)`, so the plane-parallel diffuse has ALREADY been
// delivered -- through the BEAM factor, which is the wrong response for it but is what was
// applied. Subtract what was actually delivered, `beam_response * plane_diffuse`, not the
// unfactored quantity.
//
// SUBTRACTING THE UNFACTORED ONE LEAVES A NOTCH THAT CLOSES AT THE TERMINATOR, AND THE
// PROFILE SPRINGS BACK UP AS IT DOES. Expanded, that mistake renders
// `beam*direct + iso*sky - plane*(iso - beam)`, whose last term is a spurious dip that
// vanishes as beam -> iso*0 at mu0 = 0: on Venus it put a local MAXIMUM in the last 1.2 deg
// before the terminator -- a narrow lighter band, carrying the surface's own chromaticity
// because that is exactly what it is. With the delivered quantity subtracted the sum is
// `beam*direct + iso*sky` wherever the term acts, both terms monotone in mu0, and the profile
// cannot bump. Note the engagement locus is independent of the view angle: iso and the beam
// factor share the same mu^(k-1), which cancels, so it runs parallel to the terminator.
vec3 atm_sky_excess(float mu0, float sky_response, float beam_response) {
	return max(sky_response * atm_sky_illumination(mu0)
			- beam_response * atm_plane_diffuse(mu0), vec3(0.0));
}

// The chromatic half of the view-path extinction, for a surface or cloud shell beneath the
// limb (see THE COMPOSITING SPLIT): the windowed transmittance of the column above this
// shell's own altitude over the luma of the disc's, which is what atm_disc_air() removes.
vec3 atm_view_tint(float mu) {
	if (body_radius_km <= 0.0) {
		return vec3(1.0);
	}
	AtmLayers L = atm_layers(0.0);
	float R = body_radius_km * surface_scale;
	float z = max((shell_scale - surface_scale) * body_radius_km, 0.0);
	vec3 disc = atm_view_transmittance(L, R, 0.0, mu);
	// A shell AT the disc -- every surface and band shell -- has the disc's own column, so
	// the second evaluation exists only for a shell above it (a cloud deck).
	vec3 own = z > 0.0 ? atm_view_transmittance(L, R, z, mu) : disc;
	return own / max(atm_luma(disc), 1.0e-6);
}
