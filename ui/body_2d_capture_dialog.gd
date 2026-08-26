# body_2d_capture_dialog.gd
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
extends AcceptDialog
class_name IVBody2DCaptureDialog

## Dev dialog that stages simulated bodies and captures transparent 256² 2D icons
## into [constant IVBody2DIconSaver.OUTPUT_DIR].
##
## Popped up by [IVBody2DCaptureManager]. Lists every body in the running simulation that
## can have a model, and stages the selected one by building a throwaway [IVBodyVisual] —
## so an icon shows the body exactly as the simulator does, cloud deck, atmospheric limb,
## cube shaders and all, without this dialog knowing any of that exists. The preview is live
## (drag to orbit, right-drag to pan, wheel to zoom, sliders for light and ambient), each
## shell can be toggled off, and each capture is written as soon as it is taken. Rendering is
## done by [IVBody2DCapturer].
##
## Captures are written to [code]user://[/code] and copied into the assets directory by hand;
## see [IVBody2DIconSaver].

const BODIES_2D_DIR := "res://addons/ivoyager_assets/bodies_2d"
const ORBIT_SPEED := 0.01
const ZOOM_STEP_IN := 0.9
const ZOOM_STEP_OUT := 1.1
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0

@onready var _body_list := %ModelList as ItemList
@onready var _status_label := %StatusLabel as Label
@onready var _capture_all_button := %CaptureAllButton as Button
@onready var _reset_button := %ResetButton as Button
@onready var _only_missing_toggle := %OnlyMissingToggle as CheckButton
@onready var _shells_label := %ShellsLabel as Label
@onready var _shell_toggles := %ShellToggles as VBoxContainer
@onready var _checker_rect := %CheckerRect as TextureRect
@onready var _preview_texture_rect := %PreviewTextureRect as TextureRect
@onready var _zoom_slider := %ZoomSlider as HSlider
@onready var _brightness_slider := %BrightnessSlider as HSlider
@onready var _ambient_slider := %AmbientSlider as HSlider
@onready var _key_azimuth_slider := %KeyAzimuthSlider as HSlider
@onready var _key_elevation_slider := %KeyElevationSlider as HSlider
@onready var _key_light_toggle := %KeyLightToggle as CheckButton
@onready var _fill_light_toggle := %FillLightToggle as CheckButton

var _asset_preloader: IVAssetPreloader
var _capturer: IVBody2DCapturer
var _body_names: Array[StringName] = []
var _current_index := -1
var _aabb: AABB
var _yaw: float
var _pitch: float
var _zoom := 1.0
var _pan := Vector2.ZERO
var _brightness := 1.0
var _key_azimuth: float
var _key_elevation: float
var _is_shells_model: bool


func _ready() -> void:
	title = "Capture Body 2D Icons"
	ok_button_text = "Capture & Save"
	dialog_hide_on_ok = false
	add_cancel_button("Close")

	_asset_preloader = IVGlobal.program[&"AssetPreloader"]
	_capturer = IVBody2DCapturer.new()
	_capturer.bind_nodes(
		%PreviewViewport as SubViewport,
		%Camera as Camera3D,
		%KeyLight as DirectionalLight3D,
		%FillLight as DirectionalLight3D,
		%YawPivot as Node3D,
		%PitchPivot as Node3D,
		%ModelHolder as Node3D,
	)
	_preview_texture_rect.texture = (%PreviewViewport as SubViewport).get_texture()
	# A transparent-background viewport hands back PREMULTIPLIED colour -- a partly covered
	# edge texel is the resolve of covered samples against nothing, and an atmosphere limb
	# draws with blend_premul_alpha outright. Drawn with the ordinary straight-alpha blend the
	# preview would show every partly transparent texel at alpha times its true colour, which
	# over a limb's ring is the whole ring, dimmed to invisible against the checker behind it.
	var preview_material := CanvasItemMaterial.new()
	preview_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_preview_texture_rect.material = preview_material
	_checker_rect.texture = _make_checker_texture()
	# The label carries the standing instruction; the resolved path goes to the console, where
	# it can be copied. A user:// path is long enough to drive this dialog's minimum size.
	print("IVBody2DCaptureDialog: captures will be saved to ",
			IVBody2DIconSaver.get_output_directory())

	confirmed.connect(_on_capture_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_body_list.item_selected.connect(_on_body_selected)
	_capture_all_button.pressed.connect(_on_capture_all)
	_reset_button.pressed.connect(_on_reset_pressed)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	_ambient_slider.value_changed.connect(_on_ambient_changed)
	_key_azimuth_slider.value_changed.connect(_on_key_light_changed)
	_key_elevation_slider.value_changed.connect(_on_key_light_changed)
	_key_light_toggle.toggled.connect(_capturer.set_key_light_enabled)
	_fill_light_toggle.toggled.connect(_capturer.set_fill_light_enabled)
	_only_missing_toggle.toggled.connect(_on_only_missing_toggled)
	_preview_texture_rect.gui_input.connect(_on_preview_gui_input)

	_refresh_list()
	_select_current_sim_body()


## Selects [param body_name] and stages it, returning whether it was in the list.
func select_body_name(body_name: StringName) -> bool:
	var index := _body_names.find(body_name)
	if index == -1:
		return false
	_body_list.select(index)
	_on_body_selected(index)
	return true


# Open on whatever is selected in the simulator, so capturing the body you are looking at
# takes no hunting through the list. Silent when there is no GUI to ask.
func _select_current_sim_body() -> void:
	var top_ui: IVTopUI = IVGlobal.program.get(&"TopUI")
	if !top_ui or !top_ui.selection_manager:
		return
	var body_name := top_ui.selection_manager.get_body_name()
	if body_name:
		select_body_name(body_name)


func _refresh_list() -> void:
	_populate_list()
	var has_items := not _body_names.is_empty()
	get_ok_button().disabled = not has_items
	_capture_all_button.disabled = not has_items
	if not has_items:
		_status_label.text = "No bodies to capture (uncheck \"Only missing icons\" to regenerate)."
		return
	_body_list.select(0)
	_on_body_selected(0)


# Lists simulated bodies rather than asset files, so the tool can only ever offer what the
# sim can actually show. With "Only missing icons" on, skips any that already have one.
func _populate_list() -> void:
	const DISABLE_MODEL_SPACE := IVBody.BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	_body_names.clear()
	_body_list.clear()
	var only_missing := _only_missing_toggle.button_pressed
	var sorted_names := PackedStringArray()
	for body_name: StringName in IVBody.bodies:
		sorted_names.append(body_name)
	sorted_names.sort()
	for sorted_name in sorted_names:
		var body_name := StringName(sorted_name)
		var body: IVBody = IVBody.bodies[body_name]
		if body.flags & DISABLE_MODEL_SPACE:
			continue
		var prefix := _asset_preloader.get_body_file_prefix(body_name)
		if prefix.is_empty():
			continue
		var has_icon := not IVFiles.find_resource_file([BODIES_2D_DIR], prefix).is_empty()
		if only_missing and has_icon:
			continue
		_body_names.append(body_name)
		_body_list.add_item(prefix + ("  ✓" if has_icon else ""))


func _on_only_missing_toggled(_pressed: bool) -> void:
	_refresh_list()


func _on_body_selected(index: int) -> void:
	_current_index = index
	var body_name := _body_names[index]
	var body: IVBody = IVBody.bodies[body_name]
	var visual := body.make_body_visual()
	if !visual:
		_status_label.text = "%s has no model" % body_name
		return
	# A packed spacecraft model carries a placeholder table radius (every craft is 5 m)
	# against a model spanning tens of metres, so the same multiple of it would put the camera
	# inside; 0 stages it on its own bounding radius instead.
	var reference_radius := 0.0
	if !_asset_preloader.get_body_packed_model(body_name):
		reference_radius = body.get_camera_radius()
	_aabb = _capturer.stage_visual(visual, reference_radius)
	_is_shells_model = _capturer.get_staged_model() is IVShellsModel
	_rebuild_shell_toggles(body_name)
	_reset_pose()
	_status_label.text = ("%s — drag: rotate · right-drag: pan · wheel: zoom"
			% _asset_preloader.get_body_file_prefix(body_name))
	await _fit_zoom_to_body()


# Sizes every body the same way the existing icon set is sized — filling the frame — which
# the bounding-box fit alone cannot do (see [method IVBody2DCapturer.solve_fit_zoom]).
func _fit_zoom_to_body() -> void:
	# Twice: the first measurement can land on a frame drawn before the new pose reached the
	# GPU, and the fit is its own fixed point, so a second pass costs two frames and either
	# confirms the first or corrects it.
	var index := _current_index
	for _iteration in 2:
		var fitted := await _capturer.solve_fit_zoom(_zoom)
		if _current_index != index:
			return # body switched, or the dialog closed, while the fit render was in flight
		_set_zoom(fitted)


# One checkbox per shell, in shell order, named by the body's own tag for it (SURFACE,
# CLOUDS, LIMB). Packed-scene models have no shells and get no section.
func _rebuild_shell_toggles(body_name: StringName) -> void:
	for child in _shell_toggles.get_children():
		child.queue_free()
	var shells := _get_shell_nodes()
	_shells_label.visible = not shells.is_empty()
	_shell_toggles.visible = not shells.is_empty()
	if shells.is_empty():
		return
	var specs := _asset_preloader.get_body_shell_specs(body_name)
	for shell_index in shells.size():
		var label := "SURFACE" if shell_index == 0 else "Shell %s" % shell_index
		if shell_index < specs.size():
			var spec: Dictionary = specs[shell_index]
			var tag: String = spec[&"tag"]
			if tag:
				label = tag
		var toggle := CheckButton.new()
		toggle.text = label
		toggle.button_pressed = true
		toggle.toggled.connect(_on_shell_toggled.bind(shells[shell_index]))
		_shell_toggles.add_child(toggle)


func _on_shell_toggled(pressed: bool, shell: IVShellsModel) -> void:
	shell.visible = pressed


# Shell 0 is the staged model itself and the parent of overlay shells 1..N.
func _get_shell_nodes() -> Array[IVShellsModel]:
	var shells: Array[IVShellsModel] = []
	var surface := _capturer.get_staged_model() as IVShellsModel
	if !surface:
		return shells
	shells.append(surface)
	for child in surface.get_children():
		var shell := child as IVShellsModel
		if shell:
			shells.append(shell)
	return shells


func _on_reset_pressed() -> void:
	_reset_pose()
	await _fit_zoom_to_body()


func _reset_pose() -> void:
	_yaw = IVBody2DCapturer.DEFAULT_YAW
	_pitch = IVBody2DCapturer.DEFAULT_PITCH
	_zoom = 1.0
	_pan = Vector2.ZERO
	_brightness = IVBody2DCapturer.DEFAULT_BRIGHTNESS
	var key_dir := IVBody2DCapturer.KEY_DIR
	if _is_shells_model:
		key_dir = IVBody2DCapturer.SHELLS_KEY_DIR
	var azimuth_elevation := IVBody2DCapturer.direction_to_azimuth_elevation(key_dir)
	_key_azimuth = azimuth_elevation.x
	_key_elevation = azimuth_elevation.y
	_zoom_slider.set_value_no_signal(_zoom)
	_brightness_slider.set_value_no_signal(_brightness)
	_key_azimuth_slider.set_value_no_signal(_key_azimuth)
	_key_elevation_slider.set_value_no_signal(_key_elevation)
	_key_light_toggle.set_pressed_no_signal(true)
	_fill_light_toggle.set_pressed_no_signal(true)
	_capturer.set_key_light_enabled(true)
	_capturer.set_fill_light_enabled(true)
	_capturer.set_key_light(_key_azimuth, _key_elevation)
	_capturer.set_brightness(_brightness)
	_capturer.set_ambient(_ambient_slider.value)
	_apply_pose()


func _apply_pose() -> void:
	_capturer.frame_camera(_aabb, _yaw, _pitch, _zoom, _pan)


func _on_preview_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_yaw -= motion.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - motion.relative.y * ORBIT_SPEED, -PI / 2.0, PI / 2.0)
			_apply_pose()
		elif (motion.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)) != 0:
			var extent := maxf(_preview_texture_rect.size.x, 1.0)
			_pan.x += motion.relative.x / extent
			_pan.y += motion.relative.y / extent
			_apply_pose()
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * ZOOM_STEP_IN)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom * ZOOM_STEP_OUT)


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_zoom_slider.set_value_no_signal(_zoom)
	_apply_pose()


func _on_zoom_changed(value: float) -> void:
	_zoom = value
	_apply_pose()


func _on_brightness_changed(value: float) -> void:
	_brightness = value
	_capturer.set_brightness(value)


func _on_ambient_changed(value: float) -> void:
	_capturer.set_ambient(value)


func _on_key_light_changed(_value: float) -> void:
	_key_azimuth = _key_azimuth_slider.value
	_key_elevation = _key_elevation_slider.value
	_capturer.set_key_light(_key_azimuth, _key_elevation)


func _on_capture_pressed() -> void:
	if _current_index < 0:
		return
	var prefix := _asset_preloader.get_body_file_prefix(_body_names[_current_index])
	get_ok_button().disabled = true
	_status_label.text = "Capturing %s…" % prefix
	var path := await _capture_to_file(prefix)
	get_ok_button().disabled = false
	if path.is_empty():
		_status_label.text = "Capture failed for %s" % prefix
		return
	_status_label.text = "Saved %s" % path.get_file()
	_body_list.set_item_text(_current_index, prefix + "  ✓")
	var next_index := _current_index + 1
	if next_index < _body_names.size():
		_body_list.select(next_index)
		_on_body_selected(next_index)


func _on_capture_all() -> void:
	if _body_names.is_empty():
		return
	_capture_all_button.disabled = true
	get_ok_button().disabled = true
	var count := 0
	for index in _body_names.size():
		var prefix := _asset_preloader.get_body_file_prefix(_body_names[index])
		_body_list.select(index)
		await _on_body_selected(index)
		_status_label.text = "Capturing %s… (%d/%d)" % [prefix, index + 1, _body_names.size()]
		var path := await _capture_to_file(prefix)
		if not path.is_empty():
			_body_list.set_item_text(index, prefix + "  ✓")
			count += 1
	_capture_all_button.disabled = false
	get_ok_button().disabled = false
	_status_label.text = "Saved %d icon(s)" % count


func _capture_to_file(prefix: String) -> String:
	var image := await _capturer.capture_image()
	if !image:
		return ""
	return IVBody2DIconSaver.save_image(prefix, image)


# The staged visual is a live 3D copy of a simulated body; drop it as soon as the dialog is
# out of sight rather than holding it for a reopen that may never come.
func _on_visibility_changed() -> void:
	if visible:
		return
	_capturer.clear_visual()
	_current_index = -1


# Small tiled checker so the transparent background reads as transparent.
func _make_checker_texture() -> ImageTexture:
	const SIZE := 16
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var light := Color(0.27, 0.27, 0.27)
	var dark := Color(0.19, 0.19, 0.19)
	for y in SIZE:
		for x in SIZE:
			var is_light := (((x >> 3) + (y >> 3)) & 1) == 0
			image.set_pixel(x, y, light if is_light else dark)
	return ImageTexture.create_from_image(image)
