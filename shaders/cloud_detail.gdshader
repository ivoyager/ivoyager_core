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


void vertex() {
	model_position = VERTEX; // unit-sphere local position
}


// Dave Hoskins' hash13 ("Hash without Sine"). A hash symmetric in p.x/p.y/p.z (as an
// earlier one here was) correlates the field along the model axes and their diagonals,
// printing faint ridgelines that cross in "X" shapes through the FBM. This form is
// asymmetric and decorrelates cleanly.
float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	// Quintic fade (C2-continuous). The cubic smoothstep f*f*(3-2f) has a discontinuous
	// second derivative at lattice cell boundaries, which FBM amplifies into grid-aligned
	// creases — the bright ridge/"X" artifact. The quintic is C2 and removes them.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
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


// Smooth (B-spline) bicubic texture lookup assembled from four hardware-bilinear taps.
// The albedo map's texels are kilometers wide at orbital range, so plain bilinear
// magnification shows them as square cells with creased edges and diagonal "X" saddles —
// the persistent ridgeline/grid artifact. Cubic reconstruction is C2-continuous, so the
// magnified map reads smooth and the FBM detail below (not texel filtering) supplies the
// fine structure. Relies on the sampler filtering linear (Godot's default for this map).
vec4 cubic_weights(float v) {
	float v2 = v * v;
	float v3 = v2 * v;
	vec4 w;
	w.x = -v3 + 3.0 * v2 - 3.0 * v + 1.0;
	w.y = 3.0 * v3 - 6.0 * v2 + 4.0;
	w.z = -3.0 * v3 + 3.0 * v2 + 3.0 * v + 1.0;
	w.w = v3;
	return w / 6.0;
}


vec4 texture_bicubic(sampler2D tex, vec2 uv) {
	vec2 texsize = vec2(textureSize(tex, 0));
	vec2 inv_texsize = 1.0 / texsize;

	vec2 coord = uv * texsize - 0.5;
	vec2 fxy = fract(coord);
	coord -= fxy;

	vec4 wx = cubic_weights(fxy.x);
	vec4 wy = cubic_weights(fxy.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 offset = c + vec4(wx.yw, wy.yw) / s;
	offset *= inv_texsize.xxyy;

	vec4 sample0 = texture(tex, offset.xz);
	vec4 sample1 = texture(tex, offset.yz);
	vec4 sample2 = texture(tex, offset.xw);
	vec4 sample3 = texture(tex, offset.yw);

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
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
	float detail = fbm(noise_position * clouds_detail_scale) - 0.5;
	float coverage = clamp(base_coverage + detail * clouds_detail_strength * gate, 0.0, 1.0);

	ALBEDO = clouds_color * cloud.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Shape the alpha rolloff at the boundary. The base map's edge is a straight bilinear
	// ramp one (kilometers-wide) texel across, which reads as fake up close; the gamma
	// curve bends it into a softer, more cloud-like falloff. Default 1.0 leaves it linear.
	ALPHA = pow(coverage, clouds_edge_gamma) * clouds_opacity;
}
