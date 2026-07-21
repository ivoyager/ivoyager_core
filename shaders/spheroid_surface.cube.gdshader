// spheroid_surface.cube.gdshader
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

// Cubemap counterpart of spheroid_surface.gdshader: same lit PBR surface and the
// same ring/eclipse occlusion, but the maps are sampled by DIRECTION
// (normalize(VERTEX)) from a Cubemap instead of by UV from an equirect map. This
// removes the equirect pole starburst and the +/-180 seam outright, and the sliver-
// triangle shading with them, because a direction lookup is exact on the sphere at
// every latitude regardless of tessellation. IVSpheroidModel routes a body here
// automatically when its discovered channels are Cubemaps (see spheroid_model.gd
// _build_shader_material + IVAssetPreloader.cube_shader_variants); the tables are
// unchanged. Bicubic de-pixelation is preserved (texture_bicubic_cube).
//
// NORMAL: the bound "normal" Cubemap is an OBJECT-space (unit-sphere/mesh-space)
// normal, baked by bake_cubemap.py -- a cubemap cannot carry a tangent-space map
// (each face has a different tangent basis, so cross-face filtering would mix
// frames). We transform it to view space with the vertex MODELVIEW_NORMAL_MATRIX
// (which bakes in the oblate inverse-transpose) and write NORMAL directly, skipping
// the mesh TBN that is degenerate at the poles.
//
// It stores the RESIDUAL from each texel's own sphere direction rather than the normal,
// so what a block codec sees is near zero over flat ground instead of the direction's
// full-range sweep. See bake_normal_face() in bake_cubemap.py for why that matters --
// briefly, a specular lobe magnifies the per-block endpoint fitting into a visible 4x4
// grid, which is exactly what a tangent-space map avoids by being stored around a
// constant.

#include "_detail.gdshaderinc"       // cubic_weights (shared with the cube bicubic below)
#include "_detail.cube.gdshaderinc"  // texture_bicubic_cube
#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

// Auto-bound channels (Cubemaps built by IVAssetPreloader). albedo/emission decode
// sRGB; normal/roughness are linear. albedo always exists (fallback guaranteed); the
// other three are optional and gated by their has_* flag below.
uniform samplerCube albedo : source_color;
uniform samplerCube normal;
uniform samplerCube roughness;
uniform samplerCube emission : source_color;

// Present-channel flags, set true by IVAssetPreloader for each discovered channel.
// An object-space normal has no constant "flat" default the way a tangent map does
// (hint_normal), and an unbound samplerCube samples black — so an absent optional
// channel must fall back in-shader, not via a sampler hint.
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform bool has_emission = false;

// Material scalars (per-body tunable via shells.tsv columns of the same name).
// Mirror spheroid_surface.gdshader so an equirect body's override columns still
// validate against this shader when it routes here.
uniform float normal_scale = 1.0;      // bump strength: 0 = smooth sphere, 1 = full baked normal
// Half-range the normal cube's residual was encoded over; MUST match the baker's
// --normal-residual-scale. This is the one uniform here with no counterpart in
// spheroid_surface.gdshader, so it cannot be driven from a shells.tsv column without
// breaking that column for the same body's equirect maps (see _assert_overrides_are_uniforms).
uniform float normal_residual_scale = 1.0;
uniform float roughness_scale = 1.0;   // multiplies sampled roughness, or is the flat value if unbound
uniform float metallic = 0.0;
uniform float metallic_specular = 0.5; // dielectric specular reflectance; 0.5 = StandardMaterial3D default
uniform float emission_energy_multiplier = 1.0;


varying vec3 model_position;   // unit-sphere local position (the cubemap sample direction)
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying mat3 v_normal_matrix;  // mesh -> view for normals; constant per model (no interp effect)


void vertex() {
	model_position = VERTEX; // captured before farwarp overwrites VERTEX
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_matrix = MODELVIEW_NORMAL_MATRIX;
	// Farwarp remaps the position only (a render-depth compression, not a deformation);
	// the smooth normal it sets here is a fallback that fragment overrides per texel.
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {
	vec3 dir = normalize(model_position);

	ALBEDO = texture_bicubic_cube(albedo, dir).rgb;

	if (has_roughness) {
		ROUGHNESS = clamp(texture_bicubic_cube(roughness, dir).r * roughness_scale, 0.0, 1.0);
	} else {
		ROUGHNESS = clamp(roughness_scale, 0.0, 1.0);
	}
	METALLIC = metallic;
	SPECULAR = metallic_specular;

	// Object-space normal -> view space, written directly (no tangent frame). The cube
	// stores relief as a deviation from dir, so normal_scale falls out as a plain
	// multiplier on it and an absent normal cube leaves n_obj = dir (a smooth sphere).
	vec3 n_obj = dir;
	if (has_normal) {
		vec3 relief = (texture_bicubic_cube(normal, dir).xyz * 2.0 - 1.0) * normal_residual_scale;
		n_obj = normalize(dir + relief * normal_scale);
	}
	NORMAL = normalize(v_normal_matrix * n_obj);

	// City lights etc.; black if no emission cube. Rebuilt ambient (engine ambient is
	// disabled; see render_mode) added before the shadow so occlusion removes sunlight,
	// not starlight; see the include.
	if (has_emission) {
		EMISSION = texture_bicubic_cube(emission, dir).rgb * emission_energy_multiplier;
	} else {
		EMISSION = vec3(0.0);
	}
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
