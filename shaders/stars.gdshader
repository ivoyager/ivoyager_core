// stars.gdshader
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

// Point-sprite star field for IVStarsVisual. Each vertex is a star at its true
// ecliptic position (internal units); CUSTOM0 carries raw (V magnitude, B-V).
// The per-vertex farwarp remap (shared with the small-body points and orbit
// lines) pulls distant stars inside the camera far plane while preserving screen
// direction, so stars render behind everything at any zoom. depth_draw_never +
// blend_add means opaque bodies occlude stars (depth test stays on) but stars
// never occlude each other and sum like real light.
//
// No glow pipeline exists, so >1.0 intensity would clamp flat white; the top of
// the brightness range is carried by POINT_SIZE (brighter = larger) with a
// gamma-compressed intensity underneath. Size and color convert from raw
// magnitude/B-V here (not baked), keeping the door open for a future physical-
// light pass. Tune the uniforms by eye; the structure is the durable part.
//
// A point only a pixel or two across puts its whole luminous core inside a single
// pixel, so under camera motion a faint star blinks on and off as its center
// crosses the pixel grid (point sampling below the Nyquist limit). point_size_floor
// raises the rendered size so every footprint spans several pixels; the area added
// by that clamp is divided back out of each star's flux, so apparent magnitude is
// preserved and only stars below the floor (the faint majority) change -- rendering
// a touch softer and larger.
//
// The background panorama holds constant on-screen brightness across fov -- it is
// surface-brightness-conserving, sampled per pixel. Fixed-size star sprites do not:
// as fov narrows the field thins (fewer stars, each unchanged), so stars fade
// against a magnified nebula when zooming in and swamp it when zooming out.
// reference_tan_half_fov / fov_compensation scale each star by the inverse pixel
// solid angle (1/tan^2(fov/2)), holding the field's total luminance fov-invariant to
// match the background. PROJECTION_MATRIX supplies the live fov, so it tracks zoom.

uniform float size_bright_mag = -1.5; // magnitude mapped to point_size_max
uniform float size_faint_mag = 6.5; // magnitude mapped to point_size_min
uniform float point_size_min = 1.3; // px; faint end of the size->flux ramp (rendered size is raised to point_size_floor)
uniform float point_size_max = 8.0; // px; large sizes clamp to the GPU's ALIASED_POINT_SIZE_RANGE (SBG points use 20 on web)
uniform float point_size_floor = 3.0; // px; smallest rendered size, so drifting stars don't scintillate (flux-compensated)
uniform float intensity_faint_mag = 6.5; // magnitude at the intensity floor
uniform float intensity_gamma = 0.35; // dynamic-range compression of flux
uniform float intensity_scale = 0.5; // linear intensity at intensity_faint_mag
uniform float intensity_max = 6.0; // clamp so the brightest few clip to white

// Field-of-view brightness compensation (see header): keeps the field's on-screen
// luminance constant across zoom so stars track the background.
uniform float reference_tan_half_fov = 0.4862; // tan(fov/2) where compensation is 1.0 (the ~24mm start fov)
uniform float fov_compensation = 1.0; // 0 = off (fixed brightness); 1 = full 1/tan^2(fov/2) law

varying flat float v_mag;
varying flat float v_bv;
varying flat float v_flux_comp;
varying flat float v_fov_comp;

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"


void vertex() {
	v_mag = CUSTOM0.x;
	v_bv = CUSTOM0.y;
	vec3 view_position = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POSITION = PROJECTION_MATRIX * vec4(view_position, 1.0);
	float t = clamp(star_size_ramp(v_mag, size_faint_mag, size_bright_mag), 0.0, 1.0);
	// Enlarge sub-floor stars to point_size_floor so they don't scintillate under
	// motion; divide flux by the area gained to hold apparent magnitude fixed.
	float ramp_size = mix(point_size_min, point_size_max, t);
	float render_size = max(ramp_size, point_size_floor);
	POINT_SIZE = render_size;
	v_flux_comp = (ramp_size * ramp_size) / (render_size * render_size);
	// Hold the field's total luminance constant across zoom (see star_fov_compensation).
	v_fov_comp = star_fov_compensation(PROJECTION_MATRIX[1][1], reference_tan_half_fov, fov_compensation);
}


void fragment() {
	float dist_sq = star_point_dist_sq(POINT_COORD); // 0 at center, 1 at the inscribed circle
	if (dist_sq > 1.0) {
		discard; // round mask; drops the square point-sprite corners
	}
	float flux = star_flux(v_mag, intensity_faint_mag);
	float intensity = min(intensity_scale * pow(flux, intensity_gamma), intensity_max);
	ALBEDO = star_color(v_bv) * intensity * v_flux_comp * v_fov_comp;
	ALPHA = exp(-4.0 * dist_sq); // soft Gaussian core; blend_add scales the add by ALPHA
}
