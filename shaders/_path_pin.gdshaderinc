// _path_pin.gdshaderinc
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

// Render-frame pin for IVPathVisual lines: a drawn path misses its body by the
// local approximation error (Hermite bow between state-path knots; any error
// in the path data itself), which is absolute — so it can dominate the view at
// close zoom no matter how dense the base path is. Each frame the visual sends
// the f64-computed body-minus-curve residual (pin_offset) and the body's
// object-space position (pin_center); vertices within pin_inner of the body
// shift by the full residual, tapering to zero at pin_outer, so the line
// passes exactly through the body. The visual sizes the window to the local
// knot chord — the scale the residual field itself varies over — so the
// shifted neighborhood IS the true local curve and the taper bend stays
// sub-pixel at any zoom. The base pass and the id overlay must both apply the
// pin (like farwarp) to keep their pixels identical. pin_outer <= 0.0 disables.

uniform vec3 pin_offset = vec3(0.0);
uniform vec3 pin_center = vec3(0.0);
uniform float pin_inner = 0.0;
uniform float pin_outer = 0.0;


vec3 path_pin(vec3 vertex) {
	if (pin_outer <= 0.0) {
		return vertex;
	}
	return vertex + pin_offset * (1.0 - smoothstep(pin_inner, pin_outer, distance(vertex, pin_center)));
}
