// cloud_shell.gdshader
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
// skip_vertex_transform: for the farwarp vertex remap; see _farwarp.gdshaderinc.
// ambient_light_disabled: ambient is rebuilt as emission; see _sun_occlusion.gdshaderinc.
render_mode skip_vertex_transform, ambient_light_disabled;
//render_mode depth_prepass_alpha; // See note below

// Lit, translucent cloud overlay for an IVSpheroidModel shell. Name it in the
// shell's shells.tsv "shader" column; the shell's discovered "albedo" channel
// (<prefix>.<file_tag>.albedo.*) auto-binds to the uniform below. Default lit
// (no unshaded) so the sun still casts the day/night terminator across the deck.
//
// Purpose: a cloud albedo map at a fixed resolution looks soft and coarse when
// magnified at close (orbital) range — the texels are kilometers wide. This adds
// procedural fractal (FBM) detail at sub-texel scale so the deck keeps believable
// structure at any zoom, without a larger texture. The base map still owns the
// real, large-scale cloud shape.
//
// The clouds_* uniforms below are defaults; override any per body by adding a
// shells.tsv column of the same name to the shell's row (IVSpheroidModel feeds
// each such column to set_shader_parameter).
//
// "render_mode depth_prepass_alpha;" above in conjuction with default `cast_shadow`
// ON in shells.tsv ought to provide shadows, which ought to provide a nice depth
// effect when viewed from ISS. But I can't see it after carefull viewing, so
// it's currently disabled at both ends now.

#include "_detail.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

uniform sampler2D albedo : source_color; // auto-bound: <prefix>.<file_tag>.albedo.*
uniform vec3 clouds_color : source_color = vec3(1.0); // tint over the map's own rgb
uniform float clouds_opacity = 1.0; // overall coverage multiplier
uniform float clouds_warp_scale = 6.0; // domain-warp frequency; keep scale*strength under ~0.08
uniform float clouds_warp_strength = 0.01; // domain-warp amount, in uv units
uniform float clouds_detail_scale = 90.0; // sub-texel detail frequency
uniform float clouds_detail_strength = 0.45; // how hard detail erodes/extends coverage
uniform float clouds_detail_floor = 0.04; // coverage below which sky stays clear
uniform float clouds_edge_gamma = 1.0; // alpha-falloff shaping: >1 softens/thins the fringe, <1 hardens it

const int OCTAVES = 5;

// Noise rides model space (not uv or screen space) so detail spins with the deck
// — the shell rotates via its _rotate process — and a sphere has no seam or pole
// pinch here that a uv- or lat/long-based field would show.
varying vec3 model_position;
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped


void vertex() {
	model_position = VERTEX; // unit-sphere local position (captured before farwarp overwrites VERTEX)
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {
	vec3 noise_position = normalize(model_position);

	// Warp the lookup to give cloud edges organic, non-repeating wander. (The bicubic
	// fetch below is what removes the texel squares; this only adds drift.) A vector warp
	// folds the texture onto itself once its Jacobian exceeds 1, printing bright caustic
	// ridgelines that cross in "X" cusps along the edges — so keep it gentle: one smooth
	// (quintic) octave, with clouds_warp_scale * clouds_warp_strength held under ~0.08.
	vec2 warp = vec2(value_noise(noise_position * clouds_warp_scale),
			value_noise(noise_position * clouds_warp_scale + vec3(19.7))) - vec2(0.5);
	vec4 cloud = texture_bicubic(albedo, UV + warp * clouds_warp_strength);
	float base_coverage = cloud.a;

	// Gate detail by base coverage so clear sky stays clear and detail concentrates
	// in and at the edges of clouds.
	float gate = smoothstep(0.0, clouds_detail_floor + 0.15, base_coverage);
	float detail = fbm(noise_position * clouds_detail_scale, OCTAVES) - 0.5;
	float coverage = clamp(base_coverage + detail * clouds_detail_strength * gate, 0.0, 1.0);

	ALBEDO = clouds_color * cloud.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Shape the alpha rolloff at the boundary. The base map's edge is a straight bilinear
	// ramp one (kilometers-wide) texel across, which reads as fake up close; the gamma
	// curve bends it into a softer, more cloud-like falloff. Default 1.0 leaves it linear.
	ALPHA = pow(coverage, clouds_edge_gamma) * clouds_opacity;

	// Rebuilt ambient (engine ambient is disabled; see render_mode). Added before
	// the shadow so occlusion removes sunlight, not starlight; see the include.
	EMISSION += ALBEDO * ambient_light;

	if (ring_texture_outer > 0.0 || occluder_count > 0) {
		float sun_visible = sun_occlusion_visible_fraction(v_world_position);
		if (compat_albedo_shadow) {
			ALBEDO *= sun_visible;
		} else {
			AO = sun_visible;
			AO_LIGHT_AFFECT = 1.0; // attenuates direct light, not just ambient
		}
	}
}
