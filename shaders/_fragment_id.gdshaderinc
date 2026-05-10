// _fragment_id.gdshaderinc
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

// Helpers for "id" shaders that broadcast a fragment id to IVFragmentIdentifier
// via its compute-shader probe. Each id-bearing shader writes its (already
// encoded) fragment id into ALBEDO at the sparse 3-pixel grid pattern around
// the mouse. ALBEDO (not EMISSION) is the right channel here because Godot 4
// `render_mode unshaded` outputs ALBEDO directly and skips the EMISSION add.
//
// Globals are set by IVFragmentIdentifier each frame:
//   iv_mouse_fragcoord  - mouse position + (0.5, 0.5) in internal-buffer pixels
//   iv_fragment_id_range - sparse-grid half-extent; <= 0 disables broadcasting
//
// Fragment id components arrive in [1, 2048] per channel (offset-by-1 sentinel
// applied by IVFragmentIdentifier.encode_vec3). Half-float (RGBA16F) carries
// these integers exactly.

global uniform vec2 iv_mouse_fragcoord;
global uniform float iv_fragment_id_range;


bool is_id_fragment(vec2 fragcoord_xy) {
	// Sparse 3-pixel grid (every 3rd pixel) inside a square bounded by
	// iv_fragment_id_range. The compute shader iterates the same grid.
	if (iv_fragment_id_range <= 0.0) {
		return false;
	}
	vec2 d = abs(fragcoord_xy - iv_mouse_fragcoord);
	if (d.x > iv_fragment_id_range || d.y > iv_fragment_id_range) {
		return false;
	}
	vec2 m = mod(d, 3.0);
	return m.x < 0.5 && m.y < 0.5;
}
