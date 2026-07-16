// _star_point.gdshaderinc
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

// Shared star-photometry helpers for the catalog star field (stars.gdshader), the
// far-sun point (sun_point.gdshader), and the sun disc (sun_surface.gdshader). Pure
// functions only -- no uniforms, varyings, or entry points -- so each shader keeps
// its own uniforms. Sizing splits on whether the star is resolved, not on which shader
// draws it: the field and the sun's far point both size from intensity through one
// camera PSF, and only the sun's near disc is geometric (an angular radius the camera
// actually resolves). farwarp is provided separately by _farwarp.gdshaderinc.
//
// The sun's two halves also share their LOD ramp here. Its disc fade-out and its point
// fade-in are opposite ends of one crossfade, so they must come from one expression
// against one pixel radius or they would not sum to a constant through the handoff.

// B-V -> linear sRGB: the blackbody color of the temperature B-V implies, sampled at
// eight knots and interpolated (within 0.02 of the source curve everywhere). Derived
// rather than authored -- Ballesteros' B-V -> T, then Planck through the CIE 1931
// observer onto sRGB primaries -- so "correct color" is a computed answer and
// saturation 1.0 means it, which is what makes the uniform's midpoint worth anything.
//
// The neutral knot lands at B-V 0.45, and that placement is the whole point: a
// monitor's white is D65 (~6500 K), not Vega. Reading the astronomical zero point
// (B-V 0, the A0 anchor conventionally called "white") as display white is the easy
// mistake here, and it costs the blue end everything -- A0 renders pure white when it
// should be visibly blue, and every hotter star loses its color with it. Here B-V 0 is
// blue, the sun (0.63) is faintly warm, and the crossover sits where the display's
// white actually is.
//
// Normalized to peak channel 1.0, not to luminance, so intensity alone sets brightness
// and the size law stays color-blind: two stars of equal intensity saturate equal
// cores whatever their color, as a camera's channels do. saturation lerps white ->
// this color; the peak channel is 1.0 in both, so any value preserves that invariant.
//
// Note these are linear radiances, and the display's sRGB encode compresses ratios
// toward white on the way to 8-bit -- a screenshot's channel numbers therefore read
// far paler than the values here. That is the encode being correct (the monitor decodes
// it back to this light); it is not a loss to pre-compensate for.
vec3 star_color(float bv, float saturation) {
	bv = clamp(bv, -0.4, 2.0);
	vec3 color;
	if (bv < -0.1) {
		color = mix(vec3(0.394, 0.527, 1.000), vec3(0.542, 0.646, 1.000), (bv + 0.4) / 0.3);
	} else if (bv < 0.2) {
		color = mix(vec3(0.542, 0.646, 1.000), vec3(0.748, 0.791, 1.000), (bv + 0.1) / 0.3);
	} else if (bv < 0.45) {
		color = mix(vec3(0.748, 0.791, 1.000), vec3(0.980, 0.935, 1.000), (bv - 0.2) / 0.25);
	} else if (bv < 0.8) {
		color = mix(vec3(0.980, 0.935, 1.000), vec3(1.000, 0.825, 0.699), (bv - 0.45) / 0.35);
	} else if (bv < 1.2) {
		color = mix(vec3(1.000, 0.825, 0.699), vec3(1.000, 0.700, 0.454), (bv - 0.8) / 0.4);
	} else if (bv < 1.6) {
		color = mix(vec3(1.000, 0.700, 0.454), vec3(1.000, 0.596, 0.293), (bv - 1.2) / 0.4);
	} else {
		color = mix(vec3(1.000, 0.596, 0.293), vec3(1.000, 0.510, 0.188), (bv - 1.6) / 0.4);
	}
	// max(): saturation above 1.0 drives the dimmest channel past the true color, and
	// a negative radiance would subtract light under blend_add.
	return max(mix(vec3(1.0), color, saturation), vec3(0.0));
}

// Linear flux ratio for a V magnitude relative to ref_mag (the magnitude that maps to
// flux 1.0). Brighter (smaller) magnitude -> larger flux. The caller applies its own
// dynamic-range compression and clamp (or, for the sun, no clamp). Params avoid the
// callers' uniform names -- Godot rejects a function parameter that shadows a uniform.
float star_flux(float mag, float ref_mag) {
	return pow(10.0, -0.4 * (mag - ref_mag));
}

// Rendered width in px for a star of linear intensity, imaged by a camera PSF of width
// sigma (px): twice the radius at which the PSF falls to one 8-bit step, sigma*sqrt(2*
// ln(255*I)). Size the sprite to this and the round mask cuts exactly where the star stops
// being representable, so no brightness can produce a hard edge.
//
// This is the whole size law, and it is why nothing here clamps or floors: radius grows as
// sqrt(ln(I)), so the bright end compresses on its own (480x the intensity is ~1.5x the
// radius) while every star keeps a distinct size, and the faint end shrinks to nothing
// exactly where the star drops below one 8-bit step. The max() holds the log's domain
// there; the point vanishing at that size is correct, as there is no light left to draw.
float star_visible_size(float intensity, float sigma) {
	return 2.0 * sigma * sqrt(2.0 * max(log(255.0 * intensity), 0.0));
}

// Exponent for ALPHA = exp(-dist_sq * falloff), giving a Gaussian of width sigma (px)
// across a sprite of point_size (px). Derived from the rendered size so the PSF keeps the
// width the camera has whatever the sprite spans: a fixed falloff would tie the Gaussian to
// the sprite, making a bright star a scaled-up copy of a faint one rather than a brighter one.
float star_psf_falloff(float point_size, float sigma) {
	return (point_size * point_size) / (8.0 * sigma * sigma);
}

// Field-of-view brightness compensation: scales by the inverse pixel solid angle so a
// fixed-size sprite field holds constant on-screen luminance across zoom. proj_11 is
// PROJECTION_MATRIX[1][1] (= +-1/tan(fov/2), sign flipped by the Vulkan Y-flip), so it
// is squared before pow() -- pow() of a negative base is undefined in GLSL and would
// collapse every point to zero. amount 0 = off (fixed), 1 = full 1/tan^2(fov/2) law.
//
// This is the point-source half of one camera model, so every unresolved star takes it --
// the field and the sun's far point alike. At fixed f-number an extended source holds its
// surface brightness across zoom (the per-pixel background panorama gets that for free, and
// the sun's resolved disc correctly has no fov term), while an unresolved point gains flux
// as 1/tan^2(fov/2) into a PSF that stays fixed in pixels. Omitting it for the sun would
// desync it from its own neighbors: zoom in from the Oort cloud and the whole field would
// brighten around a sun that sat still.
float star_fov_compensation(float proj_11, float ref_tan_half_fov, float amount) {
	float fov_ratio = proj_11 * ref_tan_half_fov;
	return pow(fov_ratio * fov_ratio, amount);
}

// On-screen radius in pixels of a sphere whose angular radius is radius/distance, under a
// perspective projection. proj_11 is PROJECTION_MATRIX[1][1] (= +-1/tan(fov/2), sign flipped
// by the Vulkan Y-flip, so it is abs()'d) and viewport_height is VIEWPORT_SIZE.y -- the 3D
// render target rather than the window, so a SubViewport or scaling_3d render sizes the sun
// for the buffer it actually rasterizes into.
float sun_pixel_radius(float angular_radius, float proj_11, float viewport_height) {
	return angular_radius * abs(proj_11) * viewport_height * 0.5;
}

// Sun disc<->point crossfade: 0 at/below handoff_low (the point fully replaces the disc),
// 1 at/above handoff_high (the disc fully replaces the point). The disc uses this as its
// alpha and the point uses 1.0 - this as its fade-in.
float sun_disc_weight(float pixel_radius, float handoff_low, float handoff_high) {
	return smoothstep(handoff_low, handoff_high, pixel_radius);
}

// Squared radial distance across a point sprite: 0 at center, 1 at the inscribed
// circle (>1 in the square corners, which the caller discards for a round mask).
float star_point_dist_sq(vec2 point_coord) {
	vec2 offset = point_coord - vec2(0.5);
	return dot(offset, offset) * 4.0;
}

// A star fragment's additive light: intensity through the PSF at this fragment's
// radius, evaluated in shader float32 and capped below float16 max. The cap is load-
// bearing: the 3D color buffer is RGBA16F and the fragment's color converts to f16
// BEFORE blending applies ALPHA, so a peak above 65504 clamps (or becomes inf) and
// takes the whole PSF skirt with it -- fragments that should still be saturated
// come out dim, pinning every sufficiently bright star at one identical rendered
// size. Multiplying here first keeps each fragment's true value wherever f16 can
// represent it; the cap only touches values tonemapping clips to white anyway, and
// keeps inf out of any downstream pass (e.g. glow).
float star_point_light(float intensity, float dist_sq, float falloff) {
	return min(intensity * exp(-dist_sq * falloff), 32768.0);
}
