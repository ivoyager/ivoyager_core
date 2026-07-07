// _farwarp.gdshaderinc
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

// Farwarp compression for vertex shaders: beyond iv_farwarp_start, a
// view-space position is pulled inward along its view ray to the compressed
// distance T * (1 + ln(d / T)), preserving screen direction and angular size
// exactly, so content beyond the camera far plane stays renderable. Monotonic,
// so occlusion order is preserved. Keep the curve in exact sync with the
// GDScript source of truth in IVFarwarpManager, which also sets the global
// each frame (<= 0.0 disables).

global uniform float iv_farwarp_start;


vec3 farwarp(vec3 position) {
	if (iv_farwarp_start <= 0.0) {
		return position;
	}
	float dist = length(position);
	if (dist <= iv_farwarp_start) {
		return position;
	}
	float compressed = iv_farwarp_start * (1.0 + log(dist / iv_farwarp_start));
	return position * (compressed / dist);
}
