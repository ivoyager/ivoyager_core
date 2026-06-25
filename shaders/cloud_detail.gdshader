// cloud_detail.gdshader
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

uniform sampler2D albedo : source_color; // auto-bound: <prefix>.<file_tag>.albedo.*
uniform vec3 clouds_color : source_color = vec3(1.0); // tint over the map's own rgb
uniform float clouds_opacity = 1.0; // overall coverage multiplier
uniform float clouds_warp_scale = 24.0; // domain-warp frequency
uniform float clouds_warp_strength = 0.006; // domain-warp amount, in uv units
uniform float clouds_detail_scale = 90.0; // sub-texel detail frequency
uniform float clouds_detail_strength = 0.35; // how hard detail erodes/extends coverage
uniform float clouds_detail_floor = 0.04; // coverage below which sky stays clear

const int OCTAVES = 5;

// Noise rides model space (not uv or screen space) so detail spins with the deck
// — the shell rotates via its _rotate process — and a sphere has no seam or pole
// pinch here that a uv- or lat/long-based field would show.
varying vec3 model_position;


void vertex() {
	model_position = VERTEX; // unit-sphere local position
}


float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f); // smooth lattice interpolation
	return mix(mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}


float fbm(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < OCTAVES; octave++) {
		sum += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return sum; // ~[0, 1), midpoint ~0.5
}


void fragment() {
	vec3 noise_position = normalize(model_position);

	// Warp the lookup so the magnified texel grid reads as organic edges, not
	// bilinear diamonds.
	vec2 warp = vec2(fbm(noise_position * clouds_warp_scale),
			fbm(noise_position * clouds_warp_scale + vec3(19.7))) - vec2(0.5);
	vec4 cloud = texture(albedo, UV + warp * clouds_warp_strength);
	float base_coverage = cloud.a;

	// Gate detail by base coverage so clear sky stays clear and detail concentrates
	// in and at the edges of clouds.
	float gate = smoothstep(0.0, clouds_detail_floor + 0.15, base_coverage);
	float detail = fbm(noise_position * clouds_detail_scale) - 0.5;
	float coverage = clamp(base_coverage + detail * clouds_detail_strength * gate, 0.0, 1.0);

	ALBEDO = clouds_color * cloud.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = coverage * clouds_opacity;
}
