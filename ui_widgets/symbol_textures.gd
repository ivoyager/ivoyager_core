# symbol_textures.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVSymbolTextures
extends Object

## Shared [AtlasTexture]s for the [enum IVGlobal.Symbols] cells of the symbol
## atlas ([code]resources/symbol_atlas.png[/code]).
##
## Used by [IVBodyPositionVisual] (3D symbol) and [IVSymbolPickerButton] /
## [IVSymbolPicker] (2D icons). The 3-column x 4-row layout matches the enum
## order and [code]shaders/_symbol.gdshaderinc[/code]. Textures are built once
## (lazily, after [member IVGlobal.resources] is populated) and shared.

const COLS := 3
const ROWS := 4

static var _textures: Array[AtlasTexture] = []
static var _point_texture: ImageTexture


## Returns the shared [AtlasTexture] for [param symbol_type] (an
## [enum IVGlobal.Symbols] value 0..11). Not valid for -1 ("point").
static func get_atlas_texture(symbol_type: int) -> AtlasTexture:
	if _textures.is_empty():
		_build()
	return _textures[symbol_type]


static func _build() -> void:
	var atlas: Texture2D = IVGlobal.resources[&"symbol_atlas"]
	var cell_w := atlas.get_width() / float(COLS)
	var cell_h := atlas.get_height() / float(ROWS)
	_textures.resize(COLS * ROWS)
	for i in COLS * ROWS:
		var col := i % COLS
		@warning_ignore("integer_division")
		var row := i / COLS
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = atlas
		atlas_texture.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
		_textures[i] = atlas_texture


## Returns a shared small-dot texture for the "point" (symbol_type -1) indicator,
## so a picker button's icon (and thus height) stays consistent with the shapes.
static func get_point_texture() -> Texture2D:
	if !_point_texture:
		_point_texture = _make_point_texture()
	return _point_texture


static func _make_point_texture() -> ImageTexture:
	const SIZE := 64
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center := SIZE / 2.0
	var radius := SIZE * 0.18
	for y in SIZE:
		for x in SIZE:
			var dist := Vector2(x + 0.5 - center, y + 0.5 - center).length()
			var alpha := clampf(radius - dist + 0.75, 0.0, 1.0) # ~1px edge AA
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
