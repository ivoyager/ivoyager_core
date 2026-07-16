# screenshot_manager.gd
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
class_name IVScreenshotManager
extends Node

## Saves a PNG of the current view, rendered off-screen at an exact output size.
##
## Added by [IVCoreInitializer]. Composing a shot in a small window is awkward, but composing
## large and downsizing afterwards destroys the star field -- no resampler can recover point
## sources that were never rendered at that scale. Rendering the shot at its final size
## instead skips resampling altogether. Star and sun sizes are picture-space and resolve
## against the render target (see stars.gdshader), so a capture is the same picture as the
## screen, sampled at its own resolution.[br][br]
##
## Driven by settings [code]screenshot_width[/code], [code]screenshot_aspect[/code] (an index
## into [member aspects]) and [code]screenshot_file_dialog[/code]; triggered by the
## [member user_action] hotkey or by calling [method take_screenshot]. With the file dialog
## off, saves to the last-used directory (cached) or [member fallback_directory].[br][br]
##
## Every non-preserved aspect is a crop of what was on screen: the off-screen render always
## uses the source viewport's aspect, so a narrower target loses its sides and a wider one
## loses top and bottom. Neither reveals sky the user was not composing with.[br][br]
##
## [method take_screenshot] acknowledges a quiet save by briefly dimming the world (see
## [member dim_brightness]) -- the world alone, which is also all a screenshot holds. A capture
## that opens the file dialog gets no dim, having announced itself already.[br][br]
##
## The off-screen viewport is built per capture and freed after, so an unused screenshot
## system costs nothing.


## Aspect choices backing the [code]screenshot_aspect[/code] dropdown in [IVOptionsPopup].
## [IVOptionsPopup] uses the setting value as the dropdown item index, so insertion order must
## equal value order, and [member aspect_ratios] must stay index-aligned with this.
var aspects: Dictionary[StringName, int] = {
	ASPECT_PRESERVE = 0,
	ASPECT_2_35_1 = 1,
	ASPECT_16_9 = 2,
	ASPECT_3_2 = 3,
	ASPECT_4_3 = 4,
	ASPECT_5_4 = 5,
	ASPECT_1_1 = 6,
	ASPECT_9_16 = 7,
	ASPECT_10_16 = 8,
}
## Width/height for each of [member aspects], index-aligned. 0.0 preserves the source
## viewport's aspect (no crop).
var aspect_ratios: Array[float] = [
	0.0,
	2.35,
	16.0 / 9.0,
	3.0 / 2.0,
	4.0 / 3.0,
	5.0 / 4.0,
	1.0,
	9.0 / 16.0,
	10.0 / 16.0,
]
## InputMap action that triggers a capture. Set to [code]&""[/code] to disable the hotkey.
var user_action := &"take_screenshot"
## Destination until the user picks another one. Globalized before use, so it reaches
## [IVScreenshotDialog] (and [DirAccess]) as a native path.
var fallback_directory := "user://screenshots"
## Generic name for a quiet save. Takes the first unused index.
var file_name_format := "screenshot %s.png"
var cache_file_name := "screenshots.ivbinary"
## A new value obsoletes existing cache files.
var cache_file_version := "0.0.1"
## How far [method take_screenshot] dims the world to acknowledge a quiet save, as a fraction
## of the environment's normal brightness; 1.0 or above drops the acknowledgement. Needs
## [member Environment.adjustment_enabled], which [IVWorldEnvironment] sets for every renderer
## but Compatibility (see there) -- so a web build gets no dim.
var dim_brightness := 0.25
## Seconds to fall to [member dim_brightness]. 0.0 (default) snaps: the capture hitches the
## frame anyway, which supplies the shutter's pause on its own. Raise it for a slower ramp.
var dim_in_time := 0.0
## Seconds to recover from [member dim_brightness].
var dim_out_time := 0.3

var _cache_handler: IVCacheHandler
var _cache_defaults: Dictionary[StringName, Variant] = {
	&"directory": "", # empty until the user picks one; then the last used
}
var _cache_current: Dictionary[StringName, Variant] = {}
var _pending_image: Image # captured and held until the dialog reports a path
var _is_capturing: bool
var _dim_tween: Tween
var _dim_environment: Environment # set with _dim_tween; the resource _end_dim() puts back
var _dim_restore_brightness := 1.0


## Emitted by [method take_screenshot] when setting [code]screenshot_file_dialog[/code] is
## true and an image is waiting for a destination. [IVScreenshotDialog] opens at
## [param suggested_path] and calls [method save_pending] with the user's choice.
signal dialog_requested(suggested_path: String)
## Emitted after an image is written to [param path].
signal screenshot_saved(path: String)


# *****************************************************************************


func _init() -> void:
	assert(aspects.size() == aspect_ratios.size(), "aspects and aspect_ratios must stay aligned")
	process_mode = PROCESS_MODE_ALWAYS # the hotkey must still work while the sim is paused
	_cache_handler = IVCacheHandler.new(_cache_defaults, _cache_current, cache_file_name,
			cache_file_version)


func _shortcut_input(event: InputEvent) -> void:
	if !user_action or !event.is_action_pressed(user_action):
		return
	take_screenshot()
	get_viewport().set_input_as_handled()


# *****************************************************************************


## Captures the current view, then either requests the file dialog or saves quietly, per
## setting [code]screenshot_file_dialog[/code]. The image is captured before the dialog opens,
## so the file holds the moment the user asked for rather than the moment they finished
## choosing a name.
func take_screenshot() -> void:
	if _is_capturing:
		return
	_is_capturing = true
	var image := await capture_image()
	_is_capturing = false
	if !image:
		return
	_pending_image = image
	var use_dialog: bool = IVSettingsManager.get_setting(&"screenshot_file_dialog")
	if use_dialog:
		dialog_requested.emit(get_suggested_path())
		return
	_dim_view()
	save_pending(get_suggested_path())


## Renders the current view off-screen and returns it at the size set by
## [code]screenshot_width[/code] and [code]screenshot_aspect[/code]. Must be awaited. Returns
## null on failure (after pushing an error).
func capture_image() -> Image:
	# The off-screen render shares this world's environment, so a dim still fading from the
	# previous shot would be baked into this one.
	_end_dim()
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if !camera:
		push_error("IVScreenshotManager: no current camera to capture from")
		return null
	var source_size := viewport.get_visible_rect().size
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return null
	var width: int = IVSettingsManager.get_setting(&"screenshot_width")
	var aspect_index: int = IVSettingsManager.get_setting(&"screenshot_aspect")
	var output_size := get_output_size(width, aspect_index, source_size)
	var render_size := _get_render_size(output_size, source_size)
	var limit := _get_max_render_dimension()
	if render_size.x > limit or render_size.y > limit:
		push_error(("IVScreenshotManager: a %s x %s image needs a %s x %s render, over this " +
				"GPU's %s px limit. Reduce Width, or pick an aspect nearer the window's.")
				% [output_size.x, output_size.y, render_size.x, render_size.y, limit])
		return null
	var sub_viewport := _build_sub_viewport(render_size, viewport, camera)
	var image := await _render_once(sub_viewport)
	if !image or image.is_empty():
		image = await _render_once(sub_viewport)
	sub_viewport.queue_free()
	if !image or image.is_empty():
		push_error("IVScreenshotManager: the off-screen render returned no image")
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if render_size != output_size:
		@warning_ignore("integer_division") # centered crop; a half-pixel bias is irrelevant
		var offset := (render_size - output_size) / 2
		image = image.get_region(Rect2i(offset, output_size))
	return image


## Writes the image held by the last [method take_screenshot] to [param path] and caches its
## directory for the next quiet save. Called by [IVScreenshotDialog] on the user's selection.
func save_pending(path: String) -> void:
	if !_pending_image:
		push_error("IVScreenshotManager: no pending screenshot to save")
		return
	var image := _pending_image
	_pending_image = null
	var directory := path.get_base_dir()
	if !DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var err := image.save_png(path)
	if err != OK:
		push_error("IVScreenshotManager: could not save '%s': %s" % [path, error_string(err)])
		return
	_cache_handler.change_current(&"directory", directory)
	# A user:// path resolves somewhere buried under app-data, so report where it really went.
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))
	screenshot_saved.emit(path)


## Returns the final image size for [param width] and [param aspect_index] (an index into
## [member aspects]), given a source viewport of [param source_size].
func get_output_size(width: int, aspect_index: int, source_size: Vector2) -> Vector2i:
	var aspect := _get_aspect_ratio(aspect_index, source_size)
	return Vector2i(width, maxi(roundi(width / aspect), 1))


## Returns the next unused [member file_name_format] path in the last-used directory, or in
## [member fallback_directory] if none is cached yet. Always a native (globalized) path.
func get_suggested_path() -> String:
	var directory: String = _cache_current[&"directory"]
	if !directory or !DirAccess.dir_exists_absolute(directory):
		# Globalized because IVScreenshotDialog is ACCESS_FILESYSTEM and cannot resolve a
		# "user://" path: handed one, it opens in the project directory instead. IVSave caches
		# a globalized directory for the same reason.
		directory = ProjectSettings.globalize_path(fallback_directory)
		DirAccess.make_dir_recursive_absolute(directory)
	var index := 1
	var path := directory.path_join(file_name_format % index)
	while FileAccess.file_exists(path):
		index += 1
		path = directory.path_join(file_name_format % index)
	return path


# *****************************************************************************


func _get_aspect_ratio(aspect_index: int, source_size: Vector2) -> float:
	var source_aspect := source_size.x / source_size.y
	if aspect_index < 0 or aspect_index >= aspect_ratios.size():
		return source_aspect
	var ratio := aspect_ratios[aspect_index]
	if ratio <= 0.0: # ASPECT_PRESERVE
		return source_aspect
	return ratio


# The render keeps the source viewport's aspect and the output is cropped out of it, so a
# capture can only ever remove what was on screen. Sized to contain the output in both axes:
# a narrower target widens the render (cropped at the sides), a wider one heightens it
# (cropped top and bottom), and a matching one needs no crop at all.
func _get_render_size(output_size: Vector2i, source_size: Vector2) -> Vector2i:
	var source_aspect := source_size.x / source_size.y
	return Vector2i(
		maxi(output_size.x, roundi(output_size.y * source_aspect)),
		maxi(output_size.y, roundi(output_size.x / source_aspect)),
	)


# Shares the main viewport's World3D -- own_world_3d stays false, so find_world_3d() walks up
# to the root -- and so renders the live simulation without duplicating any of it.
#
# The camera is a plain Camera3D and must never be an IVCamera: IVCamera announces itself on
# IVGlobal.current_camera_changed, which would hand the fragment identifier, world controller,
# farwarp manager and sun-occlusion manager over to this throwaway camera. It copies the live
# camera's global transform exactly, and only the render size may differ: origin shifting and
# the global iv_farwarp_start shader parameter condition every vertex in the scene for the one
# real viewpoint, so a camera placed anywhere else would see geometry warped for someone else.
func _build_sub_viewport(render_size: Vector2i, source: Viewport, camera: Camera3D) -> SubViewport:
	var sub_viewport := SubViewport.new()
	sub_viewport.size = render_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Taken from the live viewport rather than the msaa_3d setting, so the capture matches
	# whatever the user actually composed against (IVGraphicsManager owns that mapping).
	sub_viewport.msaa_3d = source.msaa_3d
	add_child(sub_viewport)
	var capture_camera := Camera3D.new()
	capture_camera.keep_aspect = camera.keep_aspect
	capture_camera.projection = camera.projection
	capture_camera.fov = camera.fov
	capture_camera.size = camera.size
	capture_camera.near = camera.near
	capture_camera.far = camera.far
	capture_camera.cull_mask = camera.cull_mask
	sub_viewport.add_child(capture_camera)
	capture_camera.global_transform = camera.global_transform
	capture_camera.current = true
	return sub_viewport


# UPDATE_ONCE clears itself to UPDATE_DISABLED once it has drawn, so a retry has to re-arm it.
# Two frame_post_draw awaits: the first can return within the frame the viewport was armed in,
# the second only after it has actually drawn. IVBody2DCapturer needs the same pair plus a
# retry, and an empty first read is normal rather than an error.
func _render_once(sub_viewport: SubViewport) -> Image:
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return sub_viewport.get_texture().get_image()


# The Compatibility renderer has no RenderingDevice to ask, so fall back to the size every
# mainstream GPU meets.
func _get_max_render_dimension() -> int:
	const FALLBACK := 16384
	var rendering_device := RenderingServer.get_rendering_device()
	if !rendering_device:
		return FALLBACK
	return rendering_device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D)


# Environment adjustments are the only brightness stage that runs after tonemapping, and after
# is what this needs. The sky here is mostly black, so the pixels a dim can register in are the
# saturated ones -- the sun's core, the brighter stars, a lit planet. tonemap_exposure (what the
# Environment docs point to for scene brightness, and what IVWorldEnvironment uses for its
# Compatibility offset) is applied before the clamp, where those pixels already sit far above
# 1.0; scaling it leaves every one of them exactly as bright as it was.
func _dim_view() -> void:
	if dim_brightness >= 1.0:
		return
	_end_dim() # else the base brightness read below is a dimmed one, and the dim sticks
	# The same environment the off-screen render resolves, for the same reason: own_world_3d
	# stays false, so both the screen and the capture reach this one by walking up to the root.
	var environment := get_viewport().find_world_3d().environment
	if !environment or !environment.adjustment_enabled:
		return # the stage this dims through is off; under Compatibility that is deliberate
	_dim_environment = environment
	_dim_restore_brightness = environment.adjustment_brightness
	# Bound to this node, which is PROCESS_MODE_ALWAYS -- as the hotkey needs anyway, so the
	# acknowledgement still plays for a shot taken while the sim is paused.
	_dim_tween = create_tween()
	_dim_tween.tween_property(environment, ^"adjustment_brightness",
			_dim_restore_brightness * dim_brightness, dim_in_time)
	_dim_tween.tween_property(environment, ^"adjustment_brightness", _dim_restore_brightness,
			dim_out_time)


# Restores the environment and drops the tween. A dim that ran to completion has already landed
# on the base brightness, so this does real work only when a capture interrupts one in flight.
func _end_dim() -> void:
	if !_dim_tween:
		return
	_dim_tween.kill()
	_dim_tween = null
	_dim_environment.adjustment_brightness = _dim_restore_brightness
	_dim_environment = null
