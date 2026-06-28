# fragment_id_compositor_effect.gd
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
class_name IVFragmentIDCompositorEffect
extends CompositorEffect

## Compute-shader probe attached to the active [Camera3D]'s [Compositor] by
## [IVFragmentIdentifier].
##
## Runs at [code]EFFECT_CALLBACK_TYPE_POST_TRANSPARENT[/code] each frame:[br]
## 1. Iterates a sparse 3-pixel grid around [member _world_mouse], bounded by
##    the fragment range passed in to [method _init].[br]
## 2. Each grid pixel is decoded as [code]ivec3(round(rgb))[/code]; channel
##    values in [code][1, 2048][/code] are valid id-encoded pixels (offset-by-1
##    sentinel; any zero rejects). Without MSAA this reads the resolved HDR color
##    buffer; with MSAA it reads the unresolved multisampled buffer and scans
##    samples, since a resolve would average the exact encoding away.[br]
## 3. Tracks the closest-to-center valid sample and writes it to a small SSBO.[br]
## 4. Issues an asynchronous readback. The callback decodes the id and emits
##    [signal fragment_decoded] on the main thread via [code]call_deferred[/code].[br][br]
##
## WARNING: All [RenderingDevice] work happens on the render thread.
## [signal fragment_decoded] is hopped to the main thread before emit.[br][br]
##
## WARNING: CompositorEffect is currently marked @experimental. It's possilbe
## that API might change, although the capability are unlikely to go away.[br][br]
##
## TODO: When Godot proposal [url]https://github.com/godotengine/godot-proposals/issues/7916[/url]
## is fully implemented, we won't need this class or the probe compute shader.
## The id shader fragment() methods will be able to broadcast id directly via
## CUSTOM_BUFFER0, CUSTOM_BUFFER1, etc. 

const _PROBE_SHADER_PATH := "res://addons/ivoyager_core/shaders/fragment_id_probe.glsl"
const _PROBE_SHADER_MSAA_PATH := "res://addons/ivoyager_core/shaders/fragment_id_probe_msaa.glsl"
const _PUSH_CONSTANT_SIZE := 16 # ivec2 probe_pixel + int fragment_range + int pad
const _PUSH_CONSTANT_MSAA_SIZE := 24 # adds ivec2 buffer_size for the multisample probe
const _SSBO_BYTE_SIZE := 16 # ivec3 best_channels + int best_dist_sq

## Emitted from the main thread with the latest decoded fragment id, or
## [code]-1[/code] when the probe found no valid id.
signal fragment_decoded(id: int)

# Sparse-grid half-extent in pixels (multiple of 3). Owned by IVFragmentIdentifier
# and passed to _init(); not changeable after construction.
var _fragment_range: int

# Read on render thread; written from main thread. A torn read on Vector2 is
# at most one stale frame's mouse position — acceptable.
var _world_mouse := Vector2.ZERO

# Render-thread state.
var _rd: RenderingDevice
var _shader_rid := RID()
var _pipeline_rid := RID()
var _shader_msaa_rid := RID() # texture2DMS probe; used when msaa_3d is enabled
var _pipeline_msaa_rid := RID()
var _ssbo_rid := RID()
var _sampler_rid := RID()


func _init(fragment_range: int) -> void:
	_fragment_range = fragment_range
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = true
	RenderingServer.call_on_render_thread(_init_render_resources)


func _notification(what: int) -> void:
	# Inline RID frees because PREDELETE means `self` is being freed — a
	# Callable bound to a method on `self` can't be deferred to the render
	# thread anymore. RenderingDevice.free_rid() is itself thread-safe and
	# queues the free for the render thread.
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
	if _pipeline_msaa_rid.is_valid():
		_rd.free_rid(_pipeline_msaa_rid)
	if _shader_msaa_rid.is_valid():
		_rd.free_rid(_shader_msaa_rid)
	if _ssbo_rid.is_valid():
		_rd.free_rid(_ssbo_rid)
	if _sampler_rid.is_valid():
		_rd.free_rid(_sampler_rid)


## Main-thread setter for the window-space mouse position used as the probe
## center. Read on the render thread.
func set_world_mouse(pos: Vector2) -> void:
	_world_mouse = pos


# *****************************************************************************
# Render-thread methods.

func _init_render_resources() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var shader_resource := load(_PROBE_SHADER_PATH)
	if not shader_resource is RDShaderFile:
		push_error("Fragment id probe shader missing or wrong type at %s" % _PROBE_SHADER_PATH)
		return
	var shader_file: RDShaderFile = shader_resource
	_shader_rid = _rd.shader_create_from_spirv(shader_file.get_spirv())
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)

	# Optional MSAA pipeline. If it fails to load, _render_callback falls back to
	# the resolved path (degraded id reads under MSAA, but no crash).
	var msaa_resource := load(_PROBE_SHADER_MSAA_PATH)
	if msaa_resource is RDShaderFile:
		var msaa_shader_file: RDShaderFile = msaa_resource
		_shader_msaa_rid = _rd.shader_create_from_spirv(msaa_shader_file.get_spirv())
		_pipeline_msaa_rid = _rd.compute_pipeline_create(_shader_msaa_rid)
	else:
		push_error("Fragment id MSAA probe shader missing or wrong type at %s"
				% _PROBE_SHADER_MSAA_PATH)

	var initial_bytes := PackedByteArray()
	initial_bytes.resize(_SSBO_BYTE_SIZE)
	_ssbo_rid = _rd.storage_buffer_create(_SSBO_BYTE_SIZE, initial_bytes)

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler_rid = _rd.sampler_create(sampler_state)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if !enabled or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	if _rd == null or !_pipeline_rid.is_valid():
		return
	var scene_buffers := render_data.get_render_scene_buffers()
	if not scene_buffers is RenderSceneBuffersRD:
		return
	var rd_scene_buffers: RenderSceneBuffersRD = scene_buffers
	var internal_size := rd_scene_buffers.get_internal_size()
	if internal_size.x <= 0 or internal_size.y <= 0:
		return
	# MSAA averages the resolved buffer, destroying the exact per-fragment id
	# encoding. When MSAA is on we read the UNRESOLVED multisampled buffer and
	# scan samples (see fragment_id_probe_msaa.glsl). num_samples maps the
	# TextureSamples enum (SAMPLES_2 -> 2, SAMPLES_4 -> 4, ...) to a sample count.
	var num_samples := 1 << rd_scene_buffers.get_texture_samples()
	var use_msaa := num_samples > 1 and _pipeline_msaa_rid.is_valid()
	var shader_rid := _shader_msaa_rid if use_msaa else _shader_rid
	var pipeline_rid := _pipeline_msaa_rid if use_msaa else _pipeline_rid

	var color_uniform := RDUniform.new()
	color_uniform.binding = 0
	if use_msaa:
		var color_tex := rd_scene_buffers.get_color_layer(0, true) # unresolved MSAA buffer
		if !color_tex.is_valid():
			return
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		color_uniform.add_id(_sampler_rid)
		color_uniform.add_id(color_tex)
	else:
		var color_tex := rd_scene_buffers.get_color_layer(0)
		if !color_tex.is_valid():
			return
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		color_uniform.add_id(_sampler_rid)
		color_uniform.add_id(color_tex)
	# Uniform-set caches must be keyed to the shader owning the bound pipeline.
	var color_uniform_set := UniformSetCacheRD.get_cache(shader_rid, 0, [color_uniform])

	var ssbo_uniform := RDUniform.new()
	ssbo_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ssbo_uniform.binding = 0
	ssbo_uniform.add_id(_ssbo_rid)
	var ssbo_uniform_set := UniformSetCacheRD.get_cache(shader_rid, 1, [ssbo_uniform])

	var probe_pixel := Vector2i(_world_mouse)

	var push_size := _PUSH_CONSTANT_MSAA_SIZE if use_msaa else _PUSH_CONSTANT_SIZE
	var push_constant := PackedByteArray()
	push_constant.resize(push_size)
	push_constant.encode_s32(0, probe_pixel.x)
	push_constant.encode_s32(4, probe_pixel.y)
	push_constant.encode_s32(8, _fragment_range)
	push_constant.encode_s32(12, num_samples if use_msaa else 0)
	if use_msaa:
		# The multisample probe takes the buffer size via push constant.
		push_constant.encode_s32(16, internal_size.x)
		push_constant.encode_s32(20, internal_size.y)

	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, color_uniform_set, 0)
	_rd.compute_list_bind_uniform_set(compute_list, ssbo_uniform_set, 1)
	_rd.compute_list_set_push_constant(compute_list, push_constant, push_size)
	_rd.compute_list_dispatch(compute_list, 1, 1, 1)
	_rd.compute_list_end()

	_rd.buffer_get_data_async(_ssbo_rid, _on_ssbo_ready)


func _on_ssbo_ready(bytes: PackedByteArray) -> void:
	# Render thread. Decode and emit deferred for main thread.
	var c0 := bytes.decode_s32(0)
	var c1 := bytes.decode_s32(4)
	var c2 := bytes.decode_s32(8)
	var id := -1
	if c0 > 0 and c1 > 0 and c2 > 0:
		id = IVFragmentIdentifier.decode_channels(c0, c1, c2)

	fragment_decoded.emit.call_deferred(id)
