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
// its own uniforms and its own bright-end policy: the field clamps size and intensity,
// the sun does not (it is HDR and escapes the clamp). farwarp is provided separately
// by _farwarp.gdshaderinc.

// Desaturated B-V -> RGB ramp; peaks at R = 1.0 so intensity alone sets brightness.
vec3 star_color(float bv) {
	bv = clamp(bv, -0.4, 2.0);
	if (bv < 0.0) {
		return mix(vec3(0.61, 0.70, 1.00), vec3(1.0), (bv + 0.4) / 0.4);
	}
	if (bv < 0.4) {
		return mix(vec3(1.0), vec3(1.00, 0.98, 0.90), bv / 0.4);
	}
	if (bv < 0.8) {
		return mix(vec3(1.00, 0.98, 0.90), vec3(1.00, 0.92, 0.75), (bv - 0.4) / 0.4);
	}
	if (bv < 1.5) {
		return mix(vec3(1.00, 0.92, 0.75), vec3(1.00, 0.80, 0.55), (bv - 0.8) / 0.7);
	}
	return mix(vec3(1.00, 0.80, 0.55), vec3(1.00, 0.68, 0.45), (bv - 1.5) / 0.5);
}

// Linear flux ratio for a V magnitude relative to ref_mag (the magnitude that maps to
// flux 1.0). Brighter (smaller) magnitude -> larger flux. The caller applies its own
// dynamic-range compression and clamp (or, for the sun, no clamp). Params avoid the
// callers' uniform names -- Godot rejects a function parameter that shadows a uniform.
float star_flux(float mag, float ref_mag) {
	return pow(10.0, -0.4 * (mag - ref_mag));
}

// 0..1 interpolant placing mag on a size ramp (faint_mag -> 0, bright_mag -> 1).
// Unclamped: the field clamps to [0, 1]; the sun lets it run so a bright sun still
// tracks size instead of pinning to the field's max.
float star_size_ramp(float mag, float faint_mag, float bright_mag) {
	return (faint_mag - mag) / (faint_mag - bright_mag);
}

// Field-of-view brightness compensation: scales by the inverse pixel solid angle so a
// fixed-size sprite field holds constant on-screen luminance across zoom. proj_11 is
// PROJECTION_MATRIX[1][1] (= +-1/tan(fov/2), sign flipped by the Vulkan Y-flip), so it
// is squared before pow() -- pow() of a negative base is undefined in GLSL and would
// collapse every point to zero. amount 0 = off (fixed), 1 = full 1/tan^2(fov/2) law.
// Used by the field to match the surface-brightness-conserving background; a lone
// object (the sun) omits it, tracking distance rather than zoom.
float star_fov_compensation(float proj_11, float ref_tan_half_fov, float amount) {
	float fov_ratio = proj_11 * ref_tan_half_fov;
	return pow(fov_ratio * fov_ratio, amount);
}

// Squared radial distance across a point sprite: 0 at center, 1 at the inscribed
// circle (>1 in the square corners, which the caller discards for a round mask).
float star_point_dist_sq(vec2 point_coord) {
	vec2 offset = point_coord - vec2(0.5);
	return dot(offset, offset) * 4.0;
}
