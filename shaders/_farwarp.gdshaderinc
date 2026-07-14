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


// Farwarp for a LIT surface/shell, used under 'render_mode skip_vertex_transform' (which turns
// off the engine's built-in vertex transform; see the local coordinates block in
// scene_forward_*.glsl). These reproduce that transform exactly - VERTEX to view space, the
// normal frame via modelview_normal - and add the farwarp remap on the position only. Pass
// MODELVIEW_MATRIX and MODELVIEW_NORMAL_MATRIX; the latter already bakes in the oblate
// (non-uniform) inverse-transpose, so the normal frame stays correct without a per-vertex
// inverse. The normal keeps its TRUE (un-remapped) view orientation - farwarp is a render-depth
// remap, not a deformation - so PBR shading and the day/night terminator are unchanged. Use the
// _tbn variant on a shell that samples a normal map (needs TANGENT/BINORMAL); the plain one
// otherwise.

void farwarp_lit_vertex(mat4 modelview, mat3 modelview_normal, inout vec3 vertex,
		inout vec3 normal) {
	vertex = farwarp((modelview * vec4(vertex, 1.0)).xyz);
	normal = modelview_normal * normal;
}

void farwarp_lit_vertex_tbn(mat4 modelview, mat3 modelview_normal, inout vec3 vertex,
		inout vec3 normal, inout vec3 tangent, inout vec3 binormal) {
	vertex = farwarp((modelview * vec4(vertex, 1.0)).xyz);
	normal = modelview_normal * normal;
	tangent = modelview_normal * tangent;
	binormal = modelview_normal * binormal;
}
