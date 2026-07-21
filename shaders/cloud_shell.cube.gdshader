// cloud_shell.cube.gdshader
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
// See cloud_shell.gdshader for what each mode is for; this variant changes only how the
// cloud map is sampled.
render_mode skip_vertex_transform, ambient_light_disabled;

// Cubemap counterpart of cloud_shell.gdshader: the same lit, translucent deck and the
// same procedural sub-texel detail, but the cloud map is sampled by DIRECTION from a
// Cubemap instead of by UV from an equirect map, which removes the pole starburst and the
// +/-180 seam. IVSpheroidModel routes a shell here automatically when its discovered
// channels are Cubemaps (see spheroid_model.gd _build_shader_material and
// IVAssetPreloader.cube_shader_variants); the tables are unchanged.
//
// The map's coverage lives in ALPHA (its rgb is flat white), so the strip must be baked
// and imported alpha-preserving or the deck renders as a solid white shell — see
// bake_cubemap.py load_equirect() and IVCubeStripSaver.
//
// Every uniform here means what it means in cloud_shell.gdshader, so a body's shells.tsv
// tuning carries over unchanged when its maps are swapped for cubemaps. Keep it that way:
// the two are meant to be the same deck sampled two ways, and the domain warp in
// particular is easy to reimplement into something that measures the same and looks
// different (see fragment).

#include "_detail.gdshaderinc"       // value_noise, fbm, cubic_weights
#include "_detail.cube.gdshaderinc"  // texture_bicubic_cube
#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

uniform samplerCube albedo : source_color; // auto-bound: <prefix>.<file_tag>.albedo.*
uniform vec3 clouds_color : source_color = vec3(1.0); // tint over the map's own rgb
uniform float clouds_opacity = 1.0; // overall coverage multiplier
uniform float clouds_warp_scale = 6.0; // domain-warp frequency; keep scale*strength under ~0.08
uniform float clouds_warp_strength = 0.01; // domain-warp amount, in uv units (see fragment)
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
	vec3 dir = normalize(model_position);

	// Warp the lookup to give cloud edges organic, non-repeating wander. (The bicubic
	// fetch below is what removes the texel squares; this only adds drift.) A vector warp
	// folds the texture onto itself once its Jacobian exceeds 1, printing bright caustic
	// ridgelines that cross in "X" cusps along the edges — so keep it gentle: one smooth
	// (quintic) octave, with clouds_warp_scale * clouds_warp_strength held under ~0.08.
	//
	// The offset is the equirect shader's, applied to lon/colat and rebuilt as a direction
	// rather than added to UV. That is deliberate: warping in some other frame (a tangent
	// nudge, say) displaces by the same arc but in a different direction, which leaves a
	// body looking measurably unlike itself when its maps are swapped for cubemaps —
	// measured at 0.79 correlation, worse than either shader against the raw map. Only the
	// texture lookup needs the cubemap's pole immunity; the warp needs to agree.
	vec2 warp = vec2(value_noise(dir * clouds_warp_scale),
			value_noise(dir * clouds_warp_scale + vec3(19.7))) - vec2(0.5);
	// atan(length(dir.xz), dir.y) rather than acos(dir.y): well conditioned at the poles,
	// where a 1e-7 error in a 32-bit acos becomes a milliradian. Colatitude driven past 0
	// or PI is not clamped — sin() turns negative and carries the direction over the pole
	// to the far side, which is where it belongs.
	float longitude = atan(dir.x, dir.z) + warp.x * clouds_warp_strength * TAU;
	float colatitude = atan(length(dir.xz), dir.y) + warp.y * clouds_warp_strength * PI;
	float sin_colatitude = sin(colatitude);
	vec4 cloud = texture_bicubic_cube(albedo, vec3(sin_colatitude * sin(longitude),
			cos(colatitude), sin_colatitude * cos(longitude)));
	float base_coverage = cloud.a;

	// Gate detail by base coverage so clear sky stays clear and detail concentrates
	// in and at the edges of clouds.
	float gate = smoothstep(0.0, clouds_detail_floor + 0.15, base_coverage);
	float detail = fbm(dir * clouds_detail_scale, OCTAVES) - 0.5;
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
