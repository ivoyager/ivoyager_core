// rings_shadow_caster.gdshader
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2017-2025 Charlie Whitfield
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

// Maintained sun-facing by parent IVRings node.
//
// There are banding/aliasing artifacts that are hard to remove. Here are the
// factors to tweek:
//
// 1. Max out directional shadow resolution in ProjectSettings. The higher the
//    better.
// 2. shadow_blur in dynamic_lights.tsv. Higher blur (>1.0) doesn't hide any
//    of the artifacts here (it just makes the artifacts appear blurry).
// 3. shadow_lod in rings.tsv. Higher removes banding pattern but starts to
//    cause "chunky" aliasing.
// 4. Increase radial_noise_multiplier by adjusting shadow_radial_noise_a, _b
//    and _c in rings.tsv (a quadratic function of distance). This applies
//    noise to  radial mapping. Higher disrupts banding pattern but leaves a
//    jagged pattern.
// 5. const alpha_noise_multiplier (here). Softens jaggedness from above but
//    causes noise grain.
// 6. Widening the alpha sample in fragment() below. This reduces banding
//    patterns without the downsides of #3 and #4. But it adds overhead.

const float alpha_noise_multiplier = 0.1;

// set once
uniform sampler2D texture_r8;
uniform float texture_width;
uniform float texture_start; // from center
uniform float inner_margin; // from center, includes padding (> texture_start)
uniform float outer_margin; // from center, includes padding (< 1.0)
uniform float low_alpha; // exclusive
uniform float max_alpha; // inclusive
uniform sampler2D blue_noise_1024;

// set by rings.gd/RingsShadowCaster each frame
uniform float alpha_exponent; // 1.0 (sun above) -> 0.001 min (sun edge-on)
uniform float radial_noise_multiplier; // adjusted with distance



void fragment() {

	float r = length(UV * 2.0 - vec2(1.0));

	if (r < inner_margin || r > outer_margin) {
		discard; // out of rings area

	} else {

		ivec2 noise_texel = ivec2(FRAGCOORD.xy) % 1024;
		vec2 noise = texelFetch(blue_noise_1024, noise_texel, 0).rg;
		r += (noise.r - 0.5) * radial_noise_multiplier;

		float texture_fraction = (r - texture_start) / (1.0 - texture_start);
		float texel_position = texture_fraction * texture_width;
		int texel = int(texel_position);
		float texel_fraction = fract(texel_position);
		float alpha = texelFetch(texture_r8, ivec2(texel - 6, 0), 0).r * (1.0 - texel_fraction);
		alpha += texelFetch(texture_r8, ivec2(texel - 5, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel - 4, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel - 3, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel - 2, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel - 1, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 1, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 2, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 3, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 4, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 5, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 6, 0), 0).r;
		alpha += texelFetch(texture_r8, ivec2(texel + 7, 0), 0).r * texel_fraction;
		alpha /= 13.0;

		alpha = pow(alpha, alpha_exponent); // sun angle effect
		alpha += (noise.g - 0.5) * alpha_noise_multiplier;
		if (alpha <= low_alpha || alpha > max_alpha) {
			discard;
		}
	}
}
