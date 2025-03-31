// rings.gdshader
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
render_mode cull_disabled;

// Source data and color/phase-angle tips: https://bjj.mmedia.is/data/s_rings.
// See https://github.com/ivoyager/ivbinary_maker for conversion of source data
// to the 3 png files. The 3 images have the same alpha channel.
//
// Adjusted to match https://bjj.mmedia.is/3dtest/saturn/saturn_montage.jpg
// on the lit side. Those are rendered (not real) so we still need ground truth
// comparisons to Cassini images (lit and unlit sides).
//
// The png files must be imported as Texture2D without compression and all
// options off or disabled. Mipmaps are broken as of Godot 4.3 for our "1D"
// textures, so we code LOD levels explicitely. (In 4.2.x and earlier, we had
// n x 2 textures that were mipmapped to n/2 x 1, n/4 x 1, n/8 x 1, etc.)
//
// ALBEDO is set with color values >> 1.0. It's necessary to get proper
// brightness given the 'thinness' (i.e., transparency) of our material with
// black space as background.
//
// As of v0.0.24, IVRings flips to always keep the front face on the sun-
// facing side. This is so the child ShadowCaster is correctly oriented.
// (Because we can't have SHADOW_CASTING_SETTING_SHADOWS_ONLY and
// SHADOW_CASTING_SETTING_DOUBLE_SIDED at the same time!)
//
// WARNING! FRONT_FACING is not reliable as of Godot 4.2.2. It's sometimes
// wrong on my laptop (NVIDIA GeForce GTX 1650 Ti).
//
// TODO: For ring shadow on Saturn, we need a dithering shader:
// https://github.com/godotengine/godot-proposals/issues/3276#issuecomment-917516630

// set by rings.gd once
uniform float texture_width;
uniform float texture_start; // from center
uniform float inner_margin; // from center, includes padding (> texture_start)
uniform float outer_margin; // from center, includes padding (< 1.0)
uniform int sun_index; // must be 0, 1 or 2
uniform sampler2DArray textures0 : source_color; // backscatter/forwardscatter/unlitside for LOD 0
uniform sampler2DArray textures1 : source_color;
uniform sampler2DArray textures2 : source_color;
uniform sampler2DArray textures3 : source_color;
uniform sampler2DArray textures4 : source_color;
uniform sampler2DArray textures5 : source_color;
uniform sampler2DArray textures6 : source_color;
uniform sampler2DArray textures7 : source_color;
uniform sampler2DArray textures8 : source_color;

// visual settings
uniform float dfdr_multiplier = 1.0; // for LOD calculation; smaller for more detail & aliasing
uniform float phase_exponent = 6.0; // larger narrows the low phase-angle effect
uniform float forwardscatter_redshift = 1.05;
uniform float unlitside_boost = 3.0; // general brightening
uniform float litside_phase_boost = 6.0; // low phase-angle brightening
uniform float unlitside_phase_boost = 4.0;

// globals
global uniform mat3 iv_sun_global_positions;

// varyings
varying vec3 sun_direction;
varying flat float camera_y; // >0.0 for lit side


void vertex() {
	vec3 sun_position = iv_sun_global_positions[sun_index];
	vec3 sun_vector = (VIEW_MATRIX * vec4(sun_position, 1.0)).xyz;
	sun_direction = normalize(sun_vector);
	camera_y = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).y;
}


vec4 sample_color(int texel, float texel_fraction, int index, int lod) {
	// index: [0] backscatter, [1] forwardscatter, [2] unlitside.
	// Mipmaps are broken as of Godot 4.3 for our "1D" textures, so we code
	// LOD levels explicitely.

	switch (lod) {
		case 0:
			vec4 sample = texelFetch(textures0, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures0, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 1:
			vec4 sample = texelFetch(textures1, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures1, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 2:
			vec4 sample = texelFetch(textures2, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures2, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 3:
			vec4 sample = texelFetch(textures3, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures3, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 4:
			vec4 sample = texelFetch(textures4, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures4, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 5:
			vec4 sample = texelFetch(textures5, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures5, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 6:
			vec4 sample = texelFetch(textures6, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures6, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 7:
			vec4 sample = texelFetch(textures7, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures7, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
		case 8:
			vec4 sample = texelFetch(textures8, ivec3(texel, 0, index), 0) * (1.0 - texel_fraction);
			sample += texelFetch(textures8, ivec3(texel + 1, 0, index), 0) * texel_fraction;
			return sample;
	}
}


void fragment() {

	float r = length(UV * 2.0 - vec2(1.0));

	// dFdx() & dFdy() must be before the 'if' fork to avoid edge artifacts!
	float texture_fraction = (r - texture_start) / (1.0 - texture_start);
	float texel_position = texture_fraction * texture_width;
	float dfdx = dFdx(texel_position); // texels per horizontal screen pixel
	float dfdy = dFdy(texel_position); // texels per vertical screen pixel

	if (r < inner_margin || r > outer_margin) {
		discard; // out of rings area

	} else {

		// LOD for anti-aliasing
		float dfdr = length(vec2(dfdx, dfdy));
		float lod_map = log2(dfdr * dfdr_multiplier);
		lod_map = clamp(round(lod_map), 0.0, 8.0);
		int lod = int(lod_map);

		// debug mipmaps
		//lod = 4;

		// position in the LOD texture
		texel_position /= float(1 << lod);
		int texel = int(texel_position);
		float texel_fraction = fract(texel_position);

		// phase effects (phase_mix = 1.0 corresponds to phase angle = 0.0)
		float phase_mix = dot(sun_direction, VIEW) / 2.0 + 0.5;
		phase_mix = pow(phase_mix, phase_exponent);

		vec4 color;
		vec3 albedo;

		if (camera_y > 0.0) {
			// lit side
			vec4 backscatter = sample_color(texel, texel_fraction, 0, lod);
			vec4 forwardscatter = sample_color(texel, texel_fraction, 1, lod);
			forwardscatter.r *= forwardscatter_redshift;
			color = mix(forwardscatter, backscatter, phase_mix);
			albedo = color.rgb * (litside_phase_boost * phase_mix + 1.0);
		} else {
			// unlit side
			color = sample_color(texel, texel_fraction, 2, lod);
			albedo = color.rgb * unlitside_boost;
			albedo *= (unlitside_phase_boost * phase_mix + 1.0);
		}

		// debug lod mapping
		//albedo = vec3(lod_map / 8.0, lod_map / 8.0, 1.0 - lod_map / 8.0);

		ALBEDO = albedo;
		ALPHA = color.a;

	}
}
