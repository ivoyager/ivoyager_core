// depixelation.gdshader
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

// Lit surface shader for a solid IVSpheroidModel surface (shell 0) that removes the texel
// "squares" a fixed-resolution map shows when magnified at close (orbital) range. It does
// ONE thing: resample the albedo and normal maps BICUBIC (C2-continuous) so the magnified
// map reads smooth instead of blocky. No synthesized or sharpened detail is added — that was
// explored on the Moon and intentionally dropped (see IMAGE_ENHANCEMENT_EXPLORATION.md in the
// plugin root for what was tried, why it didn't pay off, and the directions that would:
// offline super-resolution of the source maps, and structure-guided shader synthesis).
//
// Set as a spheroid type's default in the spheroids.tsv "shader" column (the default for
// rocky/desert/gas-giant/etc. types), or per-body in a SHELL_<body>_SURFACE shells.tsv shell-0 row.
// Discovered channels auto-bind to the like-named uniforms (albedo, normal, roughness, emission);
// each table override column feeds the uniform of the same name, so the scalars below are tunable.
//
// LIGHTING: no custom light(); writes ALBEDO/NORMAL_MAP/ROUGHNESS/EMISSION and lets the engine's
// default PBR + shadow path light it (a custom light() would break the tuned METER=1e-3 shadows).
//
// CITY LIGHTS: emission defaults to black (hint_default_black), so a body with no emission map
// emits nothing; one that ships a map gets additive emission (night side, washed out by day).

#include "_detail.gdshaderinc"

// Auto-bound channels. Default hints make an unbound map a no-op (see asset_preloader.gd
// texture_channels). normal/roughness stay LINEAR (no source_color); albedo/emission decode sRGB.
uniform sampler2D albedo : source_color;                        // surface color map
uniform sampler2D normal : hint_normal;                         // tangent-space; unbound = flat
uniform sampler2D roughness : hint_default_white;               // unbound = white -> roughness_scale
uniform sampler2D emission : source_color, hint_default_black;  // city lights; unbound = no emission

// Material scalars (per-body tunable via shells.tsv columns of the same name).
uniform float normal_scale = 1.0;      // strength of the bound tangent normal map
uniform float roughness_scale = 1.0;   // multiplies the sampled roughness (white if unbound)
uniform float metallic = 0.0;
uniform float metallic_specular = 0.5; // dielectric specular reflectance; 0.5 = StandardMaterial3D default
uniform float emission_energy_multiplier = 1.0;


void fragment() {
	// Bicubic resample removes the texel squares of the magnified maps (texture_bicubic lives
	// in _detail_common.gdshaderinc); plain texture() for the scalar-fallback roughness.
	ALBEDO = texture_bicubic(albedo, UV).rgb;
	ROUGHNESS = clamp(texture(roughness, UV).r * roughness_scale, 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = metallic_specular;

	vec3 n = texture_bicubic(normal, UV).xyz * 2.0 - 1.0;
	n.xy *= normal_scale;
	n = normalize(n);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	EMISSION = texture_bicubic(emission, UV).rgb * emission_energy_multiplier; // black if no map
}
