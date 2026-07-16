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
// spheroid_surface shader). skip_vertex_transform: for the farwarp vertex remap (see
// _farwarp.gdshaderinc). depth_draw_opaque: write depth even though ALPHA is declared, so
// the disc occludes bodies behind it at close range while still alpha-fading in the handoff.
render_mode unshaded, skip_vertex_transform, depth_draw_opaque;

// Near representation of an in-scene star ("sun"): the solid IVSpheroidModel surface
// (shell 0), rendered emissive. Set as the G_STAR spheroid type's "shader" column. Any
// discovered surface map auto-binds to "albedo"; otherwise the disc is a uniform
// star-colored (from B-V) emissive sphere. Farwarp keeps its depth consistent with the
// warped orbit lines around it, exactly as the lit surface shader does.
//
// Driven by IVSpheroidModel sun-mode, which sets "angular_radius" (the star's true angular
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
// spheroid_model.gd for what that costs.

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

uniform sampler2D albedo : source_color, hint_default_white; // surface map; unbound = white
uniform float color_bv = 0.63;       // star B-V; tints the disc (esp. with no albedo map)
uniform float color_saturation = 1.0; // shared with the field, so B-V reads the same either side
uniform float brightness = 1.0;      // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float angular_radius = 0.0;  // star radius / camera distance (sun-mode sets per frame)
uniform float handoff_low = 1.0;     // px on-screen radius at/below which the point fully replaces this disc
uniform float handoff_high = 2.5;    // px at/above which this disc fully replaces the point

varying flat float v_alpha;

void vertex() {
	VERTEX = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pixel_radius = sun_pixel_radius(angular_radius, PROJECTION_MATRIX[1][1], VIEWPORT_SIZE.y);
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
	ALBEDO = texture(albedo, UV).rgb * star_color(color_bv, color_saturation) * brightness;
	ALPHA = v_alpha;
}
