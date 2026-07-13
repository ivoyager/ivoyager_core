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
// Driven by IVSpheroidModel sun-mode, which owns the disc<->point crossfade: "alpha"
// ramps the disc out as the star shrinks toward a pixel (the sun_point takes over), and
// "brightness" is the star's HDR surface brightness (distance-invariant -- a resolved
// disc's surface brightness does not change with distance; only the point carries the
// distance gradient). No lighting, occlusion, or ring-shadow term -- the sun casts light,
// it does not receive it.

#include "_farwarp.gdshaderinc"
#include "_star_point.gdshaderinc"

uniform sampler2D albedo : source_color, hint_default_white; // surface map; unbound = white
uniform float color_bv = 0.63;    // star B-V; tints the disc (esp. with no albedo map)
uniform float brightness = 1.0;   // HDR-capable surface-brightness multiplier (sun-mode sets)
uniform float alpha = 1.0;        // LOD crossfade (sun-mode ramps 0..1); 1 = fully shown

void vertex() {
	VERTEX = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	ALBEDO = texture(albedo, UV).rgb * star_color(color_bv) * brightness;
	ALPHA = alpha;
}
