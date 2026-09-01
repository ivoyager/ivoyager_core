// instance_id.gdshader
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

// Pure fragment-id overlay for a MultiMesh of lines (e.g. IVSBGOrbitsVisual). Attach as
// material_overlay over the visible material; it stamps the per-instance encoded id at the
// sparse probe grid near the mouse and discards elsewhere. Each id arrives via
// INSTANCE_CUSTOM (requires multimesh.use_custom_data = true).
// The vertex farwarp remap must match the base material's, so the id overlay
// covers the same pixels as the visible lines.

varying flat vec3 fragment_id;

#include "_fragment_id.gdshaderinc"
#include "_farwarp.gdshaderinc"


void vertex() {
	fragment_id = INSTANCE_CUSTOM.xyz;
	VERTEX = farwarp((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}


void fragment() {
	if (is_id_fragment(FRAGCOORD.xy)) {
		ALBEDO = id_broadcast(fragment_id);
	} else {
		discard;
	}
}
