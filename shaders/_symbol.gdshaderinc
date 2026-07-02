// _symbol.gdshaderinc
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

// Shared symbol-atlas sampling for the orbiting-points shaders. The atlas
// (resources/symbol_atlas.png) is a 3-column x 4-row grid of 12 white-on-
// transparent shapes; the cell is the IVGlobal.Symbols value, laid out
// row-major (col = symbol_type % 3, row = symbol_type / 3, top-left origin).
// This layout is mirrored in resources/symbol_atlas_generator.py and the
// GDScript AtlasTexture helper -- keep the three in sync.
//
// symbol_type == -1 means "no shape" (a flat point); callers handle that case
// before calling get_symbol_alpha(), which is only valid for symbol_type >= 0.
// No-mipmap linear filtering avoids neighbor-cell bleed under heavy minification.

const int SYMBOL_COLS = 3;
const int SYMBOL_ROWS = 4;

uniform int symbol_type = -1;
uniform sampler2D symbol_atlas : filter_linear, repeat_disable;

float get_symbol_alpha(vec2 coord) {
	int col = symbol_type % SYMBOL_COLS;
	int row = symbol_type / SYMBOL_COLS;
	vec2 cell_uv = (vec2(float(col), float(row)) + coord)
			/ vec2(float(SYMBOL_COLS), float(SYMBOL_ROWS));
	return texture(symbol_atlas, cell_uv).a;
}
