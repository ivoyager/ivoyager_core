# map_converter.gd
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
@tool
class_name IVMapConverter
extends Node

## Editor-only reprojector that turns an equirectangular body map into a 3x2 cube-face
## strip [Image], on the GPU.
##
## This is the in-editor counterpart of [code]bake_cubemap.py[/code] in the tools
## submodule, for projects that do not have its Python toolchain. The two are held to
## producing the same bytes: measured over nine shipped maps in both modes, 99.3-99.99%
## of channel values match exactly and the rest differ by one count, which is the 32-bit
## floor against the script's 64-bit arithmetic (see equirect_to_cube.gdshader).
##
## Add as a child of the dialog driving it and [method Node.queue_free] it when done —
## the [SubViewport] must be gone before anything is imported (see [IVCubeStripSaver]).
##
## A source with a non-opaque alpha channel (a shell overlay such as
## [code]Earth.clouds.albedo[/code], whose coverage lives entirely in alpha) reprojects
## alpha too, and returns an [constant Image.FORMAT_RGBA8] strip.

## Per-output-texel taps, area-averaged; the [code]--supersample[/code] default. Matters
## most on the two pole faces, where the equirect is wildly oversampled in longitude.
const DEFAULT_SUPERSAMPLE := 4

## Half-range the normal cube's residual is encoded over. Must match
## [code]bake_cubemap.py --normal-residual-scale[/code] AND
## [code]spheroid_surface.cube.gdshader[/code]'s uniform of the same name — the shader
## multiplies the decoded value by it, so a mismatch scales every body's relief wrong.
## 1.0 clips no shipped map; smaller resolves gentle relief finer.
const NORMAL_RESIDUAL_SCALE := 1.0

const _SHADER: Shader = preload("equirect_to_cube.gdshader")
const _MAX_DIMENSION_FALLBACK := 16384 # Compatibility has no RenderingDevice to ask

var _sub_viewport: SubViewport
var _color_rect: ColorRect
var _material: ShaderMaterial



## Cube face edge for an equirect [param source_width]: the smallest power of two at or
## above a quarter of it. A quarter puts the face's average angular density at the
## source's density at the equator; the power of two is what the importer stores, and it
## upscales any face that is not one — so a 450 face would cost a 512 face's VRAM while
## carrying 450 texels of detail through a second resample. Port of
## [code]face_size_for()[/code] in [code]bake_cubemap.py[/code].
static func face_size_for(source_width: int) -> int:
	@warning_ignore("integer_division")
	var quarter := source_width / 4
	return nearest_po2(maxi(4, quarter))


## Largest face this GPU can render, since the strip is 3 faces wide — as a power of two,
## being the only size the importer stores without upscaling (see [method face_size_for]).
static func max_face_size() -> int:
	var limit := _MAX_DIMENSION_FALLBACK
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device:
		limit = rendering_device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D)
	@warning_ignore("integer_division")
	var face := nearest_po2(limit / 3)
	if face * 3 > limit: # nearest_po2 rounds UP, so it can overshoot the limit
		face >>= 1
	return maxi(4, face)


## Reprojects one channel of one body. [param source_path] is a [code]res://[/code] map;
## [param is_normal] bakes an object-space normal instead of color; [param face_size] 0
## takes it from the source width. Must be awaited. Returns null on failure. The caller
## can recover the face size as the returned strip's width / 3.
func convert(source_path: String, is_normal: bool, face_size := 0,
		supersample := DEFAULT_SUPERSAMPLE) -> Image:
	# Read the original jpg/png, NOT the imported .ctex: that is already VRAM compressed
	# (and for a normal map, RGTC, which has thrown the blue channel away), so resampling
	# it would compress twice. Globalized because Image.load_from_file warns on any res://
	# path the ResourceLoader recognizes.
	var source_image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if !source_image:
		push_error("Map Convert: could not read '%s'" % source_path)
		return null
	if face_size <= 0:
		face_size = face_size_for(source_image.get_width())
	if face_size > max_face_size():
		push_error("Map Convert: face %d exceeds this GPU's limit %d" % [face_size,
				max_face_size()])
		return null

	_ensure_nodes()
	_material.set_shader_parameter(&"source", ImageTexture.create_from_image(source_image))
	_material.set_shader_parameter(&"source_size",
			Vector2(source_image.get_width(), source_image.get_height()))
	_material.set_shader_parameter(&"face_size", float(face_size))
	_material.set_shader_parameter(&"supersample", supersample)
	_material.set_shader_parameter(&"object_space_normal", is_normal)
	_material.set_shader_parameter(&"normal_residual_scale", NORMAL_RESIDUAL_SCALE)
	var strip_size := Vector2i(face_size * 3, face_size * 2)
	_sub_viewport.size = strip_size
	_color_rect.size = Vector2(strip_size)

	var strip := await _render_once()
	if !strip or strip.is_empty():
		strip = await _render_once() # an empty first read is normal, not an error
	_material.set_shader_parameter(&"source", null) # drop the source before the next body
	if !strip or strip.is_empty():
		push_error("Map Convert: render produced no image for '%s'" % source_path)
		return null
	# Keep alpha only where it carries something: an all-opaque alpha channel would still
	# cost the imported cubemap BC7's 8 bpp where rgb alone compresses to BC1's 4 bpp.
	# Matches load_equirect() in bake_cubemap.py, whose test is the same one.
	var format := Image.FORMAT_RGB8
	if !is_normal and source_image.detect_alpha() != Image.ALPHA_NONE:
		format = Image.FORMAT_RGBA8
	if strip.get_format() != format:
		strip.convert(format)
	return strip


func _ensure_nodes() -> void:
	if _sub_viewport:
		return
	_sub_viewport = SubViewport.new()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Not about the clear color — the ColorRect covers the whole target, and blend_disabled
	# means every texel is written outright. Left false, the readback comes back opaque and
	# a shell overlay's coverage (which lives entirely in alpha) is silently replaced by 255.
	_sub_viewport.transparent_bg = true
	# use_hdr_2d would make the readback RGBA16F and cost a count per channel; disable_3d
	# keeps Forward+ from allocating a full 3D buffer set for what is a 2D blit (hundreds
	# of MB at a 6144x4096 strip).
	_sub_viewport.use_hdr_2d = false
	_sub_viewport.disable_3d = true
	add_child(_sub_viewport)
	_material = ShaderMaterial.new()
	_material.shader = _SHADER
	_color_rect = ColorRect.new()
	_color_rect.material = _material
	_color_rect.position = Vector2.ZERO
	_sub_viewport.add_child(_color_rect)


# UPDATE_ONCE clears itself to UPDATE_DISABLED once it has drawn, so a retry has to re-arm
# it. Two frame_post_draw awaits: the first can return within the frame the viewport was
# armed in, the second only after it has actually drawn. We must NOT call
# RenderingServer.force_draw() from a tool script — forcing a re-entrant draw inside the
# editor's own frame corrupts the shared RenderingServer, which then breaks thumbnail
# generation and crashes manual Reimport later in the session.
func _render_once() -> Image:
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _sub_viewport.get_texture().get_image()
