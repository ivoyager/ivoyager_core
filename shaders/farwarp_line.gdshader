// farwarp_line.gdshader
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
render_mode unshaded, cull_disabled, skip_vertex_transform;

// Visible base pass for line visuals (IVPathVisual, IVSBGOrbitsVisual):
// unshaded color with the per-vertex farwarp remap, replacing what was a
// StandardMaterial3D (which can't remap, so distant line vertices would be
// culled by the camera far plane). COLOR is white unless the mesh/multimesh
// supplies vertex or instance colors, so 'color' alone tints the simple case.
// Any id overlay on the same visual applies the same remap, keeping overlay
// and base on identical pixels.

uniform vec4 color : source_color = vec4(1.0);

#include "_farwarp.gdshaderinc"


void vertex() {
	VERTEX = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}


void fragment() {
	ALBEDO = color.rgb * COLOR.rgb;
}
