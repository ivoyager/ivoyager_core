// fragment_id_probe_msaa.glsl
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

// MSAA variant of fragment_id_probe.glsl, used by IVFragmentIDCompositorEffect
// when msaa_3d is enabled. Resolving an MSAA buffer averages samples, which
// destroys the exact id encoding written by the id-shaders. So we read the
// UNRESOLVED multisampled color buffer (sampler2DMS) and scan samples per pixel,
// taking the first sample that decodes to a valid id (channels in [1, 1024]
// after the broadcast band is lifted; offset-by-1 sentinel). Writes the closest
// valid sample to the SSBO; (0, 0, 0) means no valid id was found.
//
// The band constants invert id_broadcast() in _fragment_id.gdshaderinc and must
// track it and the non-MSAA probe; nothing shares them across the pipelines.

#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2DMS color_tex;

layout(set = 1, binding = 0, std430) restrict buffer Result {
	ivec3 best_channels;
	int best_dist_sq;
} result;

layout(push_constant, std430) uniform PushConstants {
	ivec2 probe_pixel;
	int fragment_range;
	int num_samples;
	ivec2 buffer_size;
} pc;

void main() {
	ivec2 size = pc.buffer_size;
	int best_dist = 0x7fffffff;
	ivec3 best = ivec3(0);

	for (int dy = -pc.fragment_range; dy <= pc.fragment_range; dy += 3) {
		for (int dx = -pc.fragment_range; dx <= pc.fragment_range; dx += 3) {
			ivec2 px = pc.probe_pixel + ivec2(dx, dy);
			if (any(lessThan(px, ivec2(0))) || any(greaterThanEqual(px, size))) {
				continue;
			}
			ivec3 v = ivec3(0);
			bool found = false;
			for (int s = 0; s < pc.num_samples; s++) {
				vec4 c = texelFetch(color_tex, px, s);
				// Tested before the int conversion so a NaN or a huge scene radiance
				// rejects here instead of reaching ivec3().
				vec3 channels = c.rgb * 2048.0 - 1024.0;
				if (all(greaterThanEqual(channels, vec3(0.5)))
						&& all(lessThanEqual(channels, vec3(1024.5)))) {
					v = ivec3(round(channels));
					found = true;
					break;
				}
			}
			if (!found) {
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
