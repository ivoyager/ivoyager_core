// _detail.gdshaderinc
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

// Shared helpers for "detail" surface shaders (e.g., cloud_shell,
// spheroid_surface): model-space value-noise FBM plus a C2-continuous bicubic
// texture lookup. A fixed-resolution map at close (orbital) range has
// texels kilometers wide; bicubic resampling removes the texel squares and FBM
// supplies the sub-texel structure the base map lacks. Pure functions only —
// the including shader owns its uniforms, varyings and blending.


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


// Octave count is a parameter (not a file-global const) so each includer passes its own:
// a textual #include can't see a const the caller declares afterward.
float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < octaves; octave++) {
		sum += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return sum; // ~[0, 1), midpoint ~0.5
}


// Smooth (B-spline) bicubic texture lookup assembled from four hardware-bilinear taps.
// A map's texels are kilometers wide at orbital range, so plain bilinear magnification
// shows them as square cells with creased edges and diagonal "X" saddles — the persistent
// ridgeline/grid artifact. Cubic reconstruction is C2-continuous, so the magnified map
// reads smooth and the FBM detail (not texel filtering) supplies the fine structure.
// Relies on the sampler filtering linear (Godot's default for these maps).
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
