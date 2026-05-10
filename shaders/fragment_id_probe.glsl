// fragment_id_probe.glsl
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

// Compute shader paired with IVFragmentIDCompositorEffect.
// Iterates a sparse 3-pixel grid around probe_pixel in the resolved scene HDR
// color buffer (RGBA16F linear, pre-tonemap). For each sample, decodes the
// rounded RGB to ivec3. Channels in [1, 2048] are valid encoded ids
// (offset-by-1 sentinel); any zero rejects the sample. Writes the closest
// valid sample to the SSBO; (0, 0, 0) means no valid id was found.

#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D color_tex;

layout(set = 1, binding = 0, std430) restrict buffer Result {
	ivec3 best_channels;
	int best_dist_sq;
} result;

layout(push_constant, std430) uniform PushConstants {
	ivec2 probe_pixel;
	int fragment_range;
	int _pad;
} pc;

void main() {
	ivec2 size = textureSize(color_tex, 0);
	int best_dist = 0x7fffffff;
	ivec3 best = ivec3(0);

	for (int dy = -pc.fragment_range; dy <= pc.fragment_range; dy += 3) {
		for (int dx = -pc.fragment_range; dx <= pc.fragment_range; dx += 3) {
			ivec2 px = pc.probe_pixel + ivec2(dx, dy);
			if (any(lessThan(px, ivec2(0))) || any(greaterThanEqual(px, size))) {
				continue;
			}
			vec4 c = texelFetch(color_tex, px, 0);
			ivec3 v = ivec3(round(c.rgb));
			if (any(lessThan(v, ivec3(1))) || any(greaterThan(v, ivec3(2048)))) {
				continue;
			}
			int d = dx * dx + dy * dy;
			if (d < best_dist) {
				best_dist = d;
				best = v;
			}
		}
	}

	result.best_channels = best;
	result.best_dist_sq = best_dist;
}
