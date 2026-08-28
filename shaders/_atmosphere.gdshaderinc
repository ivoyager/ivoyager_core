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
// A RECEIVING SURFACE OR CLOUD SHADER multiplies its direct light by
// atm_sun_transmittance(mu0) in its photometry slot, after the disc law: the column
// above that shell's own altitude along the sun ray, which is what turns the cloud deck
// at the limb the colour of sunset. The limb shader calls atm_limb().
//
// THE COMPOSITING SPLIT. The limb shell composites with blend_premul_alpha: its colour is
// the path radiance and its alpha is one minus the transmittance of what lies behind - but
// alpha is one number and the transmittance is three, Rayleigh air letting red through
// where it stops blue. So the limb's alpha carries the LUMA of the disc's transmittance,
// and every shell beneath it multiplies in atm_view_tint(mu): the per-channel
// transmittance of the column above ITS OWN altitude over that luma. The product is exact,
// and it is also what keeps a cloud deck 10 km up from being dimmed by the air below it.
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
uniform float atm_intensity = 1.0;  // nonphysical taste: radiance multiplier (gated, see header)
uniform float atm_thickness = 1.0;  // nonphysical taste: altitude-scale multiplier (gated)
global uniform float iv_limb_scale; // 1.0 = taste multipliers act; 0.0 = physical, they are 1.0

// ---------------------------------------------------------------------------- constants

const float ATM_PI = 3.14159265358979;
// Scale heights over which the ring fades out at the shell's own edge; see atm_limb().
const float ATM_EDGE_FADE = 3.0;
const float ATM_FAR_GATE_TAU = 30.0;  // chord extinction at which a ray's far half is dropped
// Sigmas above a Gaussian layer's centre at which its column is treated as the exact zero it
// rounds to (e^-32 of its tau): the early-out this feeds is what spares the layer machinery
// over the large part of a shell that stands above its own layer.
const float ATM_LAYER_REACH = 8.0;
const float ATM_PENUMBRA_FLOOR_KM = 1.0;  // the planet's shadow edge is never sharper than this
const float ATM_INF = 1.0e30;
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

// Surface-hit ray at a point with view cosine mu and sun cosine mu0 (sz = dot(e, s) as for the
// ring): path radiance above it and the view transmittance through the whole column.
void atm_disc(AtmLayers L, float R, float mu, float mu0, float sz, float sun_ang,
		float far_floor, out vec3 path, out vec3 transmittance) {
	float b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	float h_v = b_ray - R; // the view ray's own tangent altitude, below the surface
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
}

// --------------------------------------------------------------------- the entry points

// The limb shell's fragment: camera and fragment positions and the sun direction in the
// shell's LOCAL frame (unit sphere = this shell), sun_ang the sun's angular radius, and
// far_floor the vertex stage's atm_far_floor(). Returns the path radiance (I/F, taste
// applied) and the transmittance of whatever lies behind.
void atm_limb(vec3 camera_local, vec3 fragment_local, vec3 sun_local, float sun_ang,
		float far_floor, out vec3 path, out vec3 transmittance) {
	path = vec3(0.0);
	transmittance = vec3(1.0);
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
	AtmLayers L = atm_layers(-sz);               // cos(theta) = dot(s, d)
	float tc = -dot(c, d);
	vec3 q = c + tc * d;                          // closest approach to the centre
	float b = length(q);
	if (b >= R) {
		float h = b - R;
		float qs = dot(q / b, sun_local);
		atm_ring(L, R, h, qs, sz, sun_ang, path, transmittance);
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
	} else {
		// The hit point on the near side of the disc.
		float half_chord = sqrt(max(R * R - b * b, 0.0));
		vec3 hit = q - half_chord * d;
		vec3 n = hit / R;
		float mu = dot(n, e);
		float mu0 = dot(n, sun_local);
		atm_disc(L, R, mu, mu0, sz, sun_ang, far_floor, path, transmittance);
	}
	path *= mix(1.0, atm_intensity, iv_limb_scale);
}

// Transmittance of the column above altitude z along a view ray that meets the DISC at view
// cosine mu (so the ray's tangent altitude is the disc's, below the surface).
vec3 atm_view_transmittance(AtmLayers L, float R, float z, float mu) {
	float b_ray = R * sqrt(max(1.0 - mu * mu, 0.0));
	float h_v = b_ray - R;
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

// What a surface or cloud shell multiplies its direct light by: the transmittance of the
// column above this shell's own altitude along the sun ray, windowed like the disc branch.
// mu0 and mu are the fragment's sun and view cosines on the macroscopic normal. A sun below
// the horizon needs no branch: the engine's own N.L has already removed its light.
vec3 atm_sun_transmittance(float mu0) {
	if (body_radius_km <= 0.0) {
		return vec3(1.0);
	}
	AtmLayers L = atm_layers(0.0);
	float R = body_radius_km * surface_scale;
	float z = max((shell_scale - surface_scale) * body_radius_km, 0.0);
	float up = max(mu0, 0.0);
	vec3 column = atm_exp_column_beneath(L, R, z, up);
	if (L.has_layer) {
		column += atm_shell_ray_column(L, R, z, up) * L.delta_l;
	}
	return exp(-column);
}

// The chromatic half of the view-path extinction, for a surface or cloud shell beneath the
// limb (see THE COMPOSITING SPLIT): the windowed transmittance of the column above this
// shell's own altitude over the luma of the disc's, which is what the limb's alpha removes.
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
