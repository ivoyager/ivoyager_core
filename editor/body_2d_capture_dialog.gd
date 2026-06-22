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
@tool
extends AcceptDialog
class_name IVBody2DCaptureDialog

## Editor-only dialog that stages body 3D models and captures transparent 256²
## 2D icons into [code]res://addons/ivoyager_assets/bodies_2d[/code].
##
## Popped up by [IVEditorPlugin] from the Project > Tools menu. Lists bodies that
## need a [code]<file_prefix>.256.png[/code] icon — packed models (from
## [code]models/[/code]) and generic spheroids (one per surface map in
## [code]maps/[/code], flattened per the body's mean/equatorial radius). The
## selected body previews live (drag to orbit, right-drag to pan, wheel to zoom,
## sliders for light and brightness); captures are written via [IVBody2DIconSaver].
## Rendering is done by [IVBody2DCapturer].

## Emitted on close with the captured icons (keys = file_prefix, values = [Image]).
## The caller writes and imports them only after this dialog (and its 3D
## SubViewport) is freed — see [method IVBody2DIconSaver.save_image].
signal captures_ready(captured: Dictionary)

const MODELS_DIR := "res://addons/ivoyager_assets/models"
const MAPS_DIR := "res://addons/ivoyager_assets/maps"
const BODIES_2D_DIR := "res://addons/ivoyager_assets/bodies_2d"
const TABLES_DIR := "res://addons/ivoyager_core/tables"
const ORBIT_SPEED := 0.01
const ZOOM_STEP_IN := 0.9
const ZOOM_STEP_OUT := 1.1
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0

@onready var _model_list := %ModelList as ItemList
@onready var _status_label := %StatusLabel as Label
@onready var _capture_all_button := %CaptureAllButton as Button
@onready var _reset_button := %ResetButton as Button
@onready var _restart_button := %RestartButton as Button
@onready var _only_missing_toggle := %OnlyMissingToggle as CheckButton
@onready var _checker_rect := %CheckerRect as TextureRect
@onready var _preview_texture_rect := %PreviewTextureRect as TextureRect
@onready var _zoom_slider := %ZoomSlider as HSlider
@onready var _brightness_slider := %BrightnessSlider as HSlider
@onready var _key_azimuth_slider := %KeyAzimuthSlider as HSlider
@onready var _key_elevation_slider := %KeyElevationSlider as HSlider
@onready var _key_light_toggle := %KeyLightToggle as CheckButton
@onready var _fill_light_toggle := %FillLightToggle as CheckButton

var _capturer: IVBody2DCapturer
var _models: Array[Dictionary] = [] # model: {prefix,kind,glb_path}; spheroid: {prefix,kind,albedo,emission,oblateness}
var _current_index := -1
var _captured: Dictionary = {} # file_prefix (String) -> Image, written on close
var _aabb: AABB
var _yaw: float
var _pitch: float
var _zoom := 1.0
var _pan := Vector2.ZERO
var _brightness := 1.0
var _key_azimuth: float
var _key_elevation: float
var _current_kind: StringName


func _ready() -> void:
	title = "Capture Body 2D Icons"
	ok_button_text = "Capture & Save"
	dialog_hide_on_ok = false
	add_cancel_button("Close")
	set_unparent_when_invisible(true)

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
	_checker_rect.texture = _make_checker_texture()

	confirmed.connect(_on_capture_pressed)
	canceled.connect(_on_close)
	_model_list.item_selected.connect(_on_model_selected)
	_capture_all_button.pressed.connect(_on_capture_all)
	_reset_button.pressed.connect(_reset_pose)
	_restart_button.pressed.connect(_on_restart_pressed)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	_key_azimuth_slider.value_changed.connect(_on_key_light_changed)
	_key_elevation_slider.value_changed.connect(_on_key_light_changed)
	_key_light_toggle.toggled.connect(_capturer.set_key_light_enabled)
	_fill_light_toggle.toggled.connect(_capturer.set_fill_light_enabled)
	_only_missing_toggle.toggled.connect(_on_only_missing_toggled)
	_preview_texture_rect.gui_input.connect(_on_preview_gui_input)

	_refresh_list()


func _refresh_list() -> void:
	_populate_list()
	var has_items := not _models.is_empty()
	get_ok_button().disabled = not has_items
	_capture_all_button.disabled = not has_items
	if not has_items:
		_status_label.text = "No bodies to capture (uncheck \"Only missing icons\" to regenerate)."
		return
	_model_list.select(0)
	_on_model_selected(0)


# Builds the combined list of capturable bodies: packed models (models/*.glb) and
# spheroids (one per maps/ file_prefix). With "Only missing icons" on, skips any
# that already have a bodies_2d icon.
func _populate_list() -> void:
	_models.clear()
	_model_list.clear()
	var only_missing := _only_missing_toggle.button_pressed
	var oblateness := _parse_oblateness()
	var seen := {}
	for glb_path in _sorted_files(MODELS_DIR, "glb"):
		var prefix := IVBody2DCapturer.get_model_prefix(glb_path.get_file())
		if not _add_candidate(prefix, only_missing, seen):
			continue
		_models.append({&"prefix": prefix, &"kind": &"model", &"glb_path": glb_path})
	for map_path in _sorted_files(MAPS_DIR, "jpg"):
		var prefix := IVBody2DCapturer.get_model_prefix(map_path.get_file())
		if not _add_candidate(prefix, only_missing, seen):
			continue
		_models.append({
			&"prefix": prefix,
			&"kind": &"spheroid",
			&"albedo": IVFiles.find_resource_file([MAPS_DIR], prefix + ".albedo"),
			&"emission": IVFiles.find_resource_file([MAPS_DIR], prefix + ".emission"),
			&"oblateness": float(oblateness.get(prefix, 1.0)),
		})


func _sorted_files(dir: String, extension: String) -> PackedStringArray:
	var paths := IVFiles.list_resource_files([dir], extension)
	paths.sort()
	return paths


# Returns true (and adds the list row) if [param prefix] is a new candidate to show;
# records it in [param seen]. Skips duplicates and, when [param only_missing], bodies
# that already have an icon.
func _add_candidate(prefix: String, only_missing: bool, seen: Dictionary) -> bool:
	if seen.has(prefix):
		return false
	seen[prefix] = true
	var has_icon := not IVFiles.find_resource_file([BODIES_2D_DIR], prefix).is_empty()
	if only_missing and has_icon:
		return false
	_model_list.add_item(prefix + ("  ✓" if has_icon else ""))
	return true


func _on_only_missing_toggled(_pressed: bool) -> void:
	_refresh_list()


# Parses body tables for oblateness (polar / equatorial) keyed by file_prefix.
# IVTableData has no data at edit time, so read the .tsv directly; column order
# differs per table, so resolve columns by header name. Bodies with no
# equatorial_radius (moons, stars) are spheres (ratio 1.0).
func _parse_oblateness() -> Dictionary:
	var ratios := {}
	for table_name in ["stars", "planets", "moons"]:
		var file := FileAccess.open(TABLES_DIR.path_join(table_name + ".tsv"), FileAccess.READ)
		if not file:
			continue
		var header := file.get_line().split("\t")
		var i_prefix := header.find("file_prefix")
		var i_mean := header.find("mean_radius")
		var i_equatorial := header.find("equatorial_radius")
		if i_prefix == -1 or i_mean == -1:
			continue
		while not file.eof_reached():
			var cells := file.get_line().split("\t")
			if cells.size() <= i_prefix or cells.size() <= i_mean:
				continue
			var entity: String = cells[0]
			if entity.is_empty() or entity in ["Type", "Default", "Unit"] or entity.begins_with("Prefix"):
				continue
			var prefix: String = cells[i_prefix]
			if prefix.is_empty():
				continue
			var mean := cells[i_mean].to_float()
			var equatorial := mean
			if i_equatorial != -1 and cells.size() > i_equatorial and not cells[i_equatorial].is_empty():
				equatorial = cells[i_equatorial].to_float()
			if equatorial > 0.0:
				ratios[prefix] = (3.0 * mean - 2.0 * equatorial) / equatorial
	return ratios


func _on_model_selected(index: int) -> void:
	_current_index = index
	var entry := _models[index]
	var prefix: String = entry[&"prefix"]
	_current_kind = entry[&"kind"]
	if _current_kind == &"spheroid":
		var albedo_path: String = entry[&"albedo"]
		var emission_path: String = entry[&"emission"]
		var albedo_map: Texture2D = null
		if not albedo_path.is_empty():
			albedo_map = load(albedo_path)
		var emission_map: Texture2D = null
		if not emission_path.is_empty():
			emission_map = load(emission_path)
		var oblateness: float = entry[&"oblateness"]
		_aabb = _capturer.load_spheroid(albedo_map, emission_map, oblateness)
	else:
		var glb_path: String = entry[&"glb_path"]
		_aabb = _capturer.load_model(glb_path)
	_reset_pose()
	_status_label.text = "%s — drag: rotate · right-drag: pan · wheel: zoom" % prefix


func _reset_pose() -> void:
	_yaw = IVBody2DCapturer.DEFAULT_YAW
	_pitch = IVBody2DCapturer.DEFAULT_PITCH
	_zoom = 1.0
	_pan = Vector2.ZERO
	_brightness = IVBody2DCapturer.DEFAULT_BRIGHTNESS
	var key_dir := IVBody2DCapturer.KEY_DIR
	if _current_kind == &"spheroid":
		key_dir = IVBody2DCapturer.SPHEROID_KEY_DIR
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


func _on_key_light_changed(_value: float) -> void:
	_key_azimuth = _key_azimuth_slider.value
	_key_elevation = _key_elevation_slider.value
	_capturer.set_key_light(_key_azimuth, _key_elevation)


func _on_capture_pressed() -> void:
	if _current_index < 0:
		return
	var entry := _models[_current_index]
	var prefix: String = entry[&"prefix"]
	get_ok_button().disabled = true
	_status_label.text = "Capturing %s…" % prefix
	var image := await _capturer.capture_image()
	get_ok_button().disabled = false
	if !image:
		_status_label.text = "Capture failed for %s" % prefix
		return
	_captured[prefix] = image
	_status_label.text = "Captured %s — written on Close" % prefix
	_model_list.set_item_text(_current_index, prefix + "  ✓")
	var next_index := _current_index + 1
	if next_index < _models.size():
		_model_list.select(next_index)
		_on_model_selected(next_index)


func _on_capture_all() -> void:
	if _models.is_empty():
		return
	_capture_all_button.disabled = true
	get_ok_button().disabled = true
	var count := 0
	for i in _models.size():
		var entry := _models[i]
		var prefix: String = entry[&"prefix"]
		_model_list.select(i)
		_on_model_selected(i)
		_status_label.text = "Capturing %s… (%d/%d)" % [prefix, i + 1, _models.size()]
		var image := await _capturer.capture_image()
		if image:
			_captured[prefix] = image
			_model_list.set_item_text(i, prefix + "  ✓")
			count += 1
	_capture_all_button.disabled = false
	get_ok_button().disabled = false
	_status_label.text = "Captured %d icon(s) — written on Close" % count


# Hand the captured images to the caller, which writes + imports them after this
# dialog and its SubViewport are freed (a live SubViewport during import corrupts
# the editor's GPU/preview state for the session).
func _on_close() -> void:
	captures_ready.emit(_captured)
	queue_free()


# Writes the captured PNGs to disk, then restarts the editor so the fresh process
# imports them with clean thumbnails (the capture session's GPU state glitches
# in-session imports — see [IVBody2DIconSaver]).
func _on_restart_pressed() -> void:
	for prefix: String in _captured:
		var image: Image = _captured[prefix]
		IVBody2DIconSaver.save_image(prefix, image)
	EditorInterface.restart_editor()


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
