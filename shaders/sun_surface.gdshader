// sun_surface.gdshader
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
// unshaded: a star emits its own light and is never lit or self-shadowed (unlike the lit
// surface shader). skip_vertex_transform: for the farwarp vertex remap (see
// _farwarp.gdshaderinc). depth_draw_opaque: write depth even though ALPHA is declared, so
// the disc occludes bodies behind it at close range while still alpha-fading in the handoff.
render_mode unshaded, skip_vertex_transform, depth_draw_opaque;

// Near representation of an in-scene star ("sun"): the solid IVShellsModel surface
// (shell 0), rendered emissive. Set as the G_STAR surface class's "shader" column. The
// white-light photosphere -- limb darkening, granulation, sunspot groups, and the
// intensity->color physics -- is PROCEDURAL (_sun_photosphere.gdshaderinc), the same
// textureless approach band_pattern.gdshader takes for the featureless banded bodies:
// the Sun ships no surface map (the 2006 artist's texture is retired; see the assets
// build tree, records/Sun.md). Every modulation is mean-neutral, so sun-mode's derived
// surface brightness and the B-V tint keep sole custody of level and absolute color.
// A star's surface map is still discovered under the "emission" tag (Sun.emission.*)
// and MODULATES the procedural surface if one is ever shipped; unbound it samples
// white. It drives ALBEDO rather than EMISSION because "unshaded" outputs ALBEDO
// directly and ignores EMISSION. Farwarp keeps the disc's depth consistent with the
// warped orbit lines around it, exactly as the lit surface shader does.
//
// Driven by IVShellsModel sun-mode, which sets "angular_radius" (the star's true angular
// size, radius/distance) each frame; this shader ramps the disc out against its own
// VIEWPORT_SIZE as the star shrinks toward a pixel and the sun_point takes over, so an
// off-screen capture fades at its own buffer's scale rather than the main window's.
// "brightness" is the star's HDR surface brightness (distance-invariant -- a resolved disc's
// surface brightness does not change with distance; only the point carries the distance
// gradient). No lighting, occlusion, or ring-shadow term -- the sun casts light, it does not
// receive it.
//
// Note the model's own "visible" is still culled against the main viewport by sun-mode: it is
// a node property and cannot resolve per viewport. See the sun-mode section of
// shells_model.gd for what that costs.

#include "_detail.gdshaderinc"          // hash, value_noise (the photosphere's noise)
#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"
#include "_sun_photosphere.gdshaderinc"

uniform sampler2D emission : source_color, hint_default_white; // optional modulation map; unbound = white
uniform float color_bv = 0.63;       // star B-V; tints the disc (esp. with no surface map)
uniform float color_saturation = 1.0; // shared with the field, so B-V reads the same either side
uniform float brightness = 1.0;      // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float angular_radius = 0.0;  // star radius / camera distance (sun-mode sets per frame)
uniform float handoff_low = 1.0;     // px on-screen radius at/below which the point fully replaces this disc
uniform float handoff_high = 2.5;    // px at/above which this disc fully replaces the point
global uniform float iv_exposure;    // compensating-camera exposure; 1.0 when off (see stars.gdshader)

// Photosphere parameters (see _sun_photosphere.gdshaderinc for the physics and units;
// scales are cells per radian of surface arc). Defaults are the Sun; shells.tsv columns
// of the same names can override per star if ever needed.
uniform float granulation_scale = 500.0;    // ~1400 km granules
uniform float granulation_contrast = 0.10;
uniform float mottle_scale = 45.0;          // supergranular mottling, ~30 Mm
uniform float mottle_contrast = 0.015;
uniform float spot_cell_scale = 6.0;        // spot-group spacing (cells per radian)
uniform float spot_activity = 0.12;         // in-belt spawn probability; 0 = spotless
uniform float spot_belt_center_deg = 15.0;  // butterfly-belt center latitude
uniform float spot_belt_width_deg = 9.0;
uniform float umbra_level = 0.15;           // continuum intensity in umbra / penumbra
uniform float penumbra_level = 0.75;
uniform float facula_contrast = 0.06;       // limb-side plage brightening around groups
uniform float spot_seed = 0.0;              // re-rolls the whole spot field

varying flat float v_alpha;
varying vec3 model_position;   // unit-sphere local position (captured before farwarp)
varying vec3 v_view_position;  // pre-farwarp view-space position, for the incidence cosine
varying vec3 v_view_normal;
varying flat float v_pixel_radius; // rendered px per radian of surface arc (alias fades)

void vertex() {
	model_position = VERTEX;
	vec3 view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view_position = view_position;
	// A unit sphere's normal is its own local position.
	v_view_normal = MODELVIEW_NORMAL_MATRIX * VERTEX;
	VERTEX = farwarp(view_position);
	float pixel_radius = sun_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
	v_pixel_radius = pixel_radius;
	v_alpha = sun_disc_weight(pixel_radius, handoff_low, handoff_high);
}

void fragment() {
	// Discard rather than draw a fully-faded disc. depth_draw_opaque means an alpha-0 disc
	// would still write depth and punch out the sun_point sitting at the body's center behind
	// it, so something has to drop it -- and doing that here resolves per viewport, where a
	// CPU "visible" flag could only ever answer for the viewport its node lives in.
	if (v_alpha <= 0.0) {
		discard;
	}
	// mu is computed per fragment, not per vertex: the limb-darkening curve is steepest
	// exactly where mu -> 0, and per-vertex interpolation would band the limb on the
	// shared sphere mesh's tessellation.
	float mu = clamp(dot(normalize(-v_view_position), normalize(v_view_normal)), 0.0, 1.0);
	vec3 dir = normalize(model_position);
	float intensity = photosphere_intensity(dir, mu, granulation_scale, granulation_contrast,
			mottle_scale, mottle_contrast, spot_cell_scale, spot_activity,
			spot_belt_center_deg, spot_belt_width_deg, umbra_level, penumbra_level,
			facula_contrast, spot_seed, v_pixel_radius);
	vec3 surface = photosphere_color(intensity) * photosphere_limb_darkening(mu);
	surface *= texture(emission, UV).rgb;
	// The photometric scalar caps at the point's shared f16-safe ceiling: under physical
	// light, brightness carries the star's true surface brightness (~1e11 in rendered
	// units), which nothing meters down while the star is a minor part of the frame, and
	// an inf in the f16 buffer would poison downstream passes. Capping the scalar (not
	// the channels) keeps surface contrast and B-V hue wherever f16 can represent
	// the value, exactly as star_point_light does for the far point.
	float disc_light = min(brightness * iv_exposure, STAR_LIGHT_MAX);
	ALBEDO = surface * star_color(color_bv, color_saturation) * disc_light;
	ALPHA = v_alpha;
}
