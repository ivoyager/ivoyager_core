// _display.gdshaderinc
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

// The colour space the running renderer expects, and the only place that decides it.
//
// Forward+ and Mobile keep a linear pipeline: a shader's colour is linear at both ends, a
// source_color texture decoded on sample and the finished frame encoded to sRGB. The
// Compatibility renderer (including every web export) is DISPLAY-REFERRED at both ends: a
// source_color texture arrives still encoded, and what a shader writes is taken as encoded
// too - decoded for the light multiply, re-encoded into the framebuffer. Measured, over an
// 11x range of light_energy: Forward+ renders enc(ALBEDO * energy), Compatibility renders
// enc(dec(ALBEDO) * energy). The two conventions agree for a value that is only sampled and
// multiplied by light - a plain albedo map renders the same under both - and agree for
// nothing else. They do not agree for:
//
//   1. ARITHMETIC ON A SAMPLED COLOUR. A range tag's affine unpack, a disc-photometry
//      factor, a band tint, an albedo scale or ceiling: all state a LINEAR coefficient, and
//      applying one to a display-referred value makes a multiplier m act like m^2.4.
//      Enceladus' range tag of hi = 2.64 blew 89 % of its disc to white, Mimas' 1.79 blew
//      64 %, and Saturn's narrow offset range came out 12 % over-saturated.
//   2. A COMPUTED RADIANCE. Emission in cd/m^2, a star's flux, an atmosphere's path
//      radiance: nothing samples these, so nothing cancels, and they were displayed raw -
//      a veil at I/F 0.05 rendered at 0.05 where it should read 0.25.
//
// So a shader DECODES what it samples, does all of its colour arithmetic in linear, and
// ENCODES what it writes. Every conversion is the identity on a renderer that handles its
// own colour space, so those render bit-identically to before.
//
// WHAT THIS CANNOT REACH: the BLEND, which runs after a shader returns and therefore on
// display-referred values, where a sum is not a sum. That boundary is accepted; what can
// move OUT of the blend has been (the atmosphere's whole disc branch — veil, twilight
// glow, far half — is summed inside the disc shaders' own fragments since 2026-08-30,
// atm_disc_air), and what stands bright AT it is restated: the atmosphere's beyond-limb
// ring, like the rings shell, self-lights and hands the blend its finished value over a
// pedestal that is the provable constant 0 — display_mix() for a mix blend, plain
// display_write() for a premultiplied one, whose colour is its whole term. What is left
// approximate is a translucent overlay's convex mix, which dims its fringes and cannot
// pass the fragment's 1.0 clamp (a bright cloud deck at partial coverage). Correcting a
// blend needs the fragment to know what lies behind it, and only a caller that KNOWS —
// empty sky — may restate. Never feed a restatement an ESTIMATE of another shell's
// rendered output: a cross-shell prediction is wrong wherever the other shell has detail,
// and the restatement converts that error into structured colour casts wherever the
// encode slope is steep.
//
// IVGraphicsManager writes the global once at startup; nothing else touches it.

global uniform float iv_display_encode; // 0.0 = the renderer converts for itself; 1.0 = we do

// sRGB's exact transfer — the FRAMEBUFFER's space, matching Forward+'s own tonemap encode.
// The piecewise form and not the cheap power approximation: that one returns zero below
// 0.003, and a faint limb or a night-side city lives there. This is the function for
// arithmetic ABOUT the framebuffer (an alpha weight, an increment, a mix); what a fragment
// actually WRITES goes through display_write() below instead.
// (internal) The exact transfer itself, unconditionally.
vec3 display_encode_curve(vec3 linear_value) {
	vec3 clamped = max(linear_value, vec3(0.0));
	vec3 curve = 1.055 * pow(clamped, vec3(1.0 / 2.4)) - 0.055;
	return mix(clamped * 12.92, curve, step(vec3(0.0031308), clamped));
}

vec3 display_encode(vec3 linear_value) {
	if (iv_display_encode < 0.5) {
		return linear_value;
	}
	return display_encode_curve(linear_value);
}

// (internal) The value to WRITE so that the display value `display` is what lands. A written
// colour does not reach the framebuffer as written: the display-referred renderer's fragment
// tail decodes it with a polynomial and re-encodes it with a power curve that has no linear
// segment (Godot's tonemap_inc.glsl approximations), a bracket that is nearly the identity
// above ~0.3 and crushes below it — a written 0.05 lands at 0.030, and everything under
// ~0.0008 linear lands at exactly zero, which is where a faint ring, the dim sky and every
// terminator live. So invert the bracket: the power curve's inverse names the linear value
// the final encode must see, and Newton steps on the cubic name the value whose decode is
// that (the cubic is convex, so three steps land within 5e-4 everywhere; the seed is the
// target itself, which the polynomial tracks closely). Below one output code the bracket is
// not injective — everything sufficiently small lands at zero — and the inversion returns a
// small positive value that still lands there, so no branch is needed.
// (internal) The value whose polynomial decode is exactly [param linear]: three Newton steps
// on the convex cubic, seeded by the exact encode, which the polynomial closely inverts.
// Zero maps to zero exactly — the seed and every iterate stay 0 — which display_write_albedo
// depends on.
vec3 display_decode_inverse(vec3 linear) {
	vec3 y = max(linear, vec3(0.0));
	vec3 c = display_encode_curve(y);
	for (int i = 0; i < 3; i++) {
		vec3 p = c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
		vec3 dp = c * (c * 0.915918033 + 1.364342222) + 0.012522878;
		c = c - (p - y) / max(dp, vec3(1e-6));
	}
	// No upper clamp: an over-unity value is legitimate and must survive — a range-tagged
	// albedo or a limb-flattened one exceeds 1.0 BEFORE the engine's light multiply, and
	// capping it here is what a 1.0 ceiling was measured to cost (Ganymede's bright end
	// darkened 13–23 codes). The inversion is exact above 1 (the curve and its inverse are
	// the same branch), merely slow to converge at star-point magnitudes, where everything
	// lands blown white regardless.
	return max(c, vec3(0.0));
}

vec3 display_compensate(vec3 display) {
	return display_decode_inverse(pow((max(display, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)));
}

// What a fragment WRITES: display_encode() pre-inverted through the renderer's own
// conversion bracket, so the value that LANDS in the framebuffer is the exact-sRGB one
// Forward+ would land. The identity on a renderer that handles its own colour space.
vec3 display_write(vec3 linear_value) {
	if (iv_display_encode < 0.5) {
		return linear_value;
	}
	return display_compensate(display_encode(linear_value));
}

// What a fragment writes to a slot the renderer DECODES AND THEN MULTIPLIES — ALBEDO, whose
// light multiply runs between the bracket's halves. Only the decode can be inverted here:
// the final encode acts on the LIT result, out of reach. Critically, display_write()'s dark
// boost must NOT leak onto such a slot: a boost that is sub-code after the final encode is
// anything but sub-code before a light multiply — an eclipsed albedo of exactly 0 written
// through display_write() landed at 8e-4 linear, and a dark-adapted light energy of 1e3+
// rendered that floor as a solid white disc (Mimas in Saturn's shadow). Here zero writes
// zero, exactly.
vec3 display_write_albedo(vec3 linear_value) {
	if (iv_display_encode < 0.5) {
		return linear_value;
	}
	return display_decode_inverse(linear_value);
}

// A blend_mix fragment's (colour, alpha) pair, stated in the framebuffer's own space: value
// is the fragment's own LIT linear radiance, alpha_in its coverage, pedestal what lies
// behind. The identity on a linear renderer. On a display-referred one the hardware forms
// alpha * colour + (1 - alpha) * enc(behind), and the colour saturates at 1.0 before that
// mix runs - so where the linear mix calls for more than colour 1.0 can deliver, ALPHA
// RISES to cover the rest (raise the alpha, never clip the colour). The pedestal must be a
// value the caller KNOWS - the rings pass 0.0, standing over empty sky - never an estimate
// of another shell's rendered output; see the header. A caller must SELF-LIGHT on the
// display-referred branch (an engine-lit ALBEDO is one stage too late to restate), so it
// branches on iv_display_encode itself and the identity arm here is a formality.
void display_mix(vec3 value, float alpha_in, vec3 pedestal, out vec3 color, out float alpha) {
	if (iv_display_encode < 0.5) {
		color = value;
		alpha = alpha_in;
		return;
	}
	vec3 target = min(display_encode(alpha_in * value + (1.0 - alpha_in) * pedestal), vec3(1.0));
	vec3 enc_ped = display_encode(pedestal);
	vec3 need = (target - enc_ped) / max(vec3(1.0) - enc_ped, vec3(1e-4));
	alpha = clamp(max(alpha_in, max(need.r, max(need.g, need.b))), 0.0, 1.0);
	color = clamp((target - (1.0 - alpha) * enc_ped) / max(alpha, 1e-4), vec3(0.0), vec3(1.0));
	color = display_compensate(color);
}

// The inverse, for a sampled texture or an authored Color that the renderer handed over
// still encoded. An alpha channel is a coverage and never passes through here.
vec3 display_decode(vec3 display_value) {
	if (iv_display_encode < 0.5) {
		return display_value;
	}
	vec3 clamped = max(display_value, vec3(0.0));
	vec3 curve = pow((clamped + 0.055) / 1.055, vec3(2.4));
	return mix(clamped / 12.92, curve, step(vec3(0.04045), clamped));
}
