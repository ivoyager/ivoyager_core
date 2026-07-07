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

// Shared symbol-atlas sampling for the orbiting-points shaders. The atlas is a
// grid of white-on-transparent shapes; the cell is the point's symbol_type, laid
// out row-major (col = symbol_type % symbol_cols, row = symbol_type / symbol_cols,
// top-left origin). The atlas texture and its symbol_cols/symbol_rows come from
// IVCoreSettings via IVAssetPreloader and are pushed by IVSBGPositionsVisual.
//
// symbol_type == -1 means "no shape" (a flat point); callers handle that case
// before calling get_symbol_alpha(), which is only valid for symbol_type >= 0.
// No-mipmap linear filtering avoids neighbor-cell bleed under heavy minification.

uniform int symbol_cols = 3;
uniform int symbol_rows = 4;

uniform int symbol_type = -1;
uniform sampler2D symbol_atlas : filter_linear, repeat_disable;

float get_symbol_alpha(vec2 coord) {
	int col = symbol_type % symbol_cols;
	int row = symbol_type / symbol_cols;
	vec2 cell_uv = (vec2(float(col), float(row)) + coord)
			/ vec2(float(symbol_cols), float(symbol_rows));
	return texture(symbol_atlas, cell_uv).a;
}
