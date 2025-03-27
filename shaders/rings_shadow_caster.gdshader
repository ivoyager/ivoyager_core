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
// Applying noise to r breaks up banding patterns; applying to alpha doesn't.
//
// The iv_vec2_randf offset shifts noise sampling each frame, which causes a
// temporal speckling effect that may be annoying. This seems to be fully fixed
// by setting ProjectSetting/Renderer/Anti Aliasing/Use TAA == true.

// set once
uniform sampler2D texture_r8;
uniform float texture_width;
uniform float texture_start; // from center
uniform float inner_margin; // from center, includes padding (> texture_start)
uniform float outer_margin; // from center, includes padding (< 1.0)
uniform float low_alpha; // exclusive
uniform float max_alpha; // inclusive
uniform sampler2D blue_noise_1024;

// set by rings.gd/ShadowCaster each frame
uniform float alpha_exponent; // 1.0 (sun above) -> 0.001 min (sun edge-on)
uniform float noise_strength; // 0.005 is good close but needs boost when distant

// global
global uniform vec2 iv_vec2_randf; // updated each frame



void fragment() {
	
	float r = length(UV * 2.0 - vec2(1.0));
	
	if (r < inner_margin || r > outer_margin) {
		discard; // out of rings area
	
	} else {
		
		// noise here works best
		ivec2 noise_position = ivec2(FRAGCOORD.xy + iv_vec2_randf * 1024.0) % 1024;
		float noise = texelFetch(blue_noise_1024, noise_position, 0).r;
		r += (noise - 0.5) * noise_strength;
		
		float texture_fraction = (r - texture_start) / (1.0 - texture_start);
		float texel_position = texture_fraction * texture_width;
		int texel = int(texel_position);
		float texel_fraction = fract(texel_position);
		float alpha = texelFetch(texture_r8, ivec2(texel, 0), 0).r * (1.0 - texel_fraction);
		alpha += texelFetch(texture_r8, ivec2(texel, 0), 0).r * texel_fraction;
		alpha = pow(alpha, alpha_exponent);
		
		if (alpha <= low_alpha || alpha > max_alpha) {
			discard;
		}
	}
}
