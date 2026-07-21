# map_convert_dialog.gd
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
class_name IVMapConvertDialog
extends AcceptDialog

## Editor dialog that converts equirectangular body maps in
## [code]ivoyager_assets/maps[/code] into cubemap strips in
## [code]ivoyager_assets/cubemaps[/code], removing the pole pinch.
##
## The in-editor equivalent of [code]bake_cubemap.py --batch[/code], for projects without
## its Python toolchain. [IVMapConverter] does the reprojection and [IVCubeStripSaver] the
## writing; this only chooses the work and reports it.
##
## Scope matches the script's batch rule: every channel map found, including shell overlays
## such as [code]Earth.clouds.albedo[/code] and bodies with no surface albedo such as the
## Sun. What a cubemap actually needs is a shader with an entry in [member
## IVAssetPreloader.cube_shader_variants]; all three shipped surface shaders have one, and a
## body whose custom shader does not warns at load and falls back to its equirect map. That
## is not decidable here without resolving the tables, so it is not filtered on.

## Emitted on close with the resource paths written. The caller reimports them once this
## dialog and its [SubViewport] are freed — a backstop that catches anything the editor's
## own filesystem scan has not already picked up, and deferred because importing while a
## [SubViewport] renders corrupts editor GPU state (see [IVCubeStripSaver]).
signal conversions_ready(paths: PackedStringArray)

## Emitted when the user chooses to restart. The caller restarts only after this dialog
## and its [SubViewport] have actually gone — see [method IVCubeStripSaver.save_strip].
signal restart_requested()

const MAPS_DIR := "res://addons/ivoyager_assets/maps"
const MAP_EXTENSIONS: Array[String] = ["jpg", "jpeg", "png"]

var _bodies: Array[Dictionary] = [] # {file_prefix, sources: {channel: path}, converted: int}
var _exclusions: Array[String] = []
var _written_paths := PackedStringArray()
var _converter: IVMapConverter
var _is_converting := false

var _body_list: ItemList
var _status_label: Label
var _exclusions_label: Label
var _only_unconverted: CheckButton
var _convert_all_button: Button
var _restart_button: Button


func _ready() -> void:
	title = "Map Convert"
	ok_button_text = "Convert Selected"
	dialog_hide_on_ok = false # OK repeats the work; the added button is the way out
	add_cancel_button("Close")
	set_unparent_when_invisible(true)
	_build_ui()
	_set_initial_size()
	_converter = IVMapConverter.new()
	add_child(_converter)
	confirmed.connect(_convert_selected)
	canceled.connect(_on_close)
	_refresh()


# A wrapping Label reports a minimum WIDTH of 1, so on an early layout pass it can be
# measured at near-zero width, wrap to hundreds of lines, and grow the dialog past the
# screen -- and a Window never shrinks back. Every autowrap Label here gets a real minimum
# width to make that impossible.
const _WRAP_WIDTH := 560


func _set_initial_size() -> void:
	var usable := DisplayServer.screen_get_usable_rect(
			DisplayServer.window_get_current_screen())
	size = Vector2i(mini(760, usable.size.x - 80), mini(560, usable.size.y - 80))


func _add_wrapping_label(parent: Control, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(_WRAP_WIDTH, 0)
	if color != Color.WHITE:
		label.add_theme_color_override(&"font_color", color)
	parent.add_child(label)
	return label


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 38) # clears the button bar
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var header := Label.new()
	header.text = "Equirectangular maps to convert to cubemaps:"
	column.add_child(header)

	var resolution_note := _add_wrapping_label(column, Color(0.62, 0.62, 0.62))
	resolution_note.text = ("Each face is baked at the smallest power of two at or above "
			+ "1/4 of the source width. A quarter matches the source's average texel "
			+ "density at the equator, and the importer stores only powers of two — it "
			+ "upscales any other size, which would cost that VRAM for less detail. "
			+ "Resampling is unavoidable and uneven either way: a face samples about 20% "
			+ "coarser than the equirect equator at its centre and about 55% finer at its "
			+ "edges, and far coarser at the poles, which an equirectangular map wildly "
			+ "oversamples. Rounding up to the power of two oversamples further, up to 2x.")

	_only_unconverted = CheckButton.new()
	_only_unconverted.text = "Only bodies with unconverted channels"
	_only_unconverted.button_pressed = true
	_only_unconverted.toggled.connect(_on_only_unconverted_toggled)
	column.add_child(_only_unconverted)

	_body_list = ItemList.new()
	_body_list.select_mode = ItemList.SELECT_MULTI
	_body_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_list.custom_minimum_size = Vector2(_WRAP_WIDTH, 140)
	column.add_child(_body_list)

	_status_label = _add_wrapping_label(column)
	_exclusions_label = _add_wrapping_label(column, Color(0.62, 0.62, 0.62))

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_convert_all_button = Button.new()
	_convert_all_button.text = "Convert All Listed"
	_convert_all_button.pressed.connect(_convert_all)
	buttons.add_child(_convert_all_button)
	_restart_button = Button.new()
	_restart_button.text = "Save && Restart Editor"
	_restart_button.pressed.connect(_on_restart)
	buttons.add_child(_restart_button)

	var note := _add_wrapping_label(column, Color(0.92, 0.85, 0.5))
	note.text = ("Strips are written as they are converted, and the editor may import "
			+ "them on its own while this is still open. Restarting when you are done is "
			+ "recommended: a fresh process imports them with clean thumbnails. "
			+ "Compressing large cubemaps takes minutes (BC7).")


# The same file-name rule as bake_cubemap.py's scan_maps, via the regex IVAssetPreloader
# composes: an optional shell token can be told from the channel tag only because the tag
# alternation is an exact list of channel names rather than a wildcard. A shell overlay is
# keyed under prefix AND shell together ("Earth.clouds"), which is both how the preloader
# finds the strip again and what the strip has to be named.
func _scan() -> void:
	_bodies.clear()
	_exclusions.clear()
	var channels: Array = IVCubeStripSaver.CHANNELS.keys()
	var tags := PackedStringArray()
	for channel: StringName in channels:
		tags.append(String(channel))
	var regex := RegEx.new()
	var error := regex.compile("^(?<prefix>[^.]+)(?:[.](?<shell>[^.]+))?[.](?<tag>%s)[.].*$"
			% "|".join(tags))
	if error != OK:
		push_error("Map Convert: bad file-name pattern")
		return

	var sources: Dictionary[String, Dictionary] = {}
	var unrecognized := PackedStringArray()
	for extension in MAP_EXTENSIONS:
		for path in IVFiles.list_resource_files([MAPS_DIR], extension, false):
			var found := regex.search(path.get_file())
			if !found:
				unrecognized.append(path.get_file())
				continue
			var file_prefix := found.get_string("prefix")
			var shell := found.get_string("shell")
			if !shell.is_empty():
				file_prefix += "." + shell
			if !sources.has(file_prefix):
				sources[file_prefix] = {}
			var body_sources: Dictionary = sources[file_prefix]
			body_sources[StringName(found.get_string("tag"))] = path

	for file_prefix: String in sources:
		var body_sources: Dictionary = sources[file_prefix]
		_bodies.append({&"file_prefix": file_prefix, &"sources": body_sources,
				&"converted": _count_converted(file_prefix, body_sources)})
	_bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_prefix: String = a[&"file_prefix"]
			var b_prefix: String = b[&"file_prefix"]
			return a_prefix < b_prefix)

	if !unrecognized.is_empty():
		_exclusions.append("Not converted, no registered channel tag in the name: "
				+ ", ".join(unrecognized))


func _count_converted(file_prefix: String, body_sources: Dictionary) -> int:
	var count := 0
	for channel: StringName in body_sources:
		if !_find_existing(file_prefix, channel).is_empty():
			count += 1
	return count


# Matches on the .import rather than the png, so a strip written this session but not yet
# imported still counts as converted.
func _find_existing(file_prefix: String, channel: StringName) -> String:
	var directory := DirAccess.open(IVCubeStripSaver.CUBEMAPS_DIR)
	if !directory:
		return ""
	var wanted := "%s.%s." % [file_prefix, channel]
	for file_name in directory.get_files():
		if file_name.get_extension() == "import" and file_name.begins_with(wanted):
			return IVCubeStripSaver.CUBEMAPS_DIR.path_join(file_name.get_basename())
	return ""


func _refresh() -> void:
	_scan()
	_body_list.clear()
	for body in _bodies:
		var body_sources: Dictionary = body[&"sources"]
		var converted: int = body[&"converted"]
		var total := body_sources.size()
		if _only_unconverted.button_pressed and converted == total:
			continue
		var names := PackedStringArray()
		for channel: StringName in body_sources:
			names.append(String(channel))
		names.sort()
		var index := _body_list.add_item("%s — %s  (%d/%d converted)"
				% [body[&"file_prefix"], ", ".join(names), converted, total])
		_body_list.set_item_metadata(index, body)
	_exclusions_label.text = "\n".join(_exclusions)
	if _body_list.item_count == 0:
		_status_label.text = "Nothing to convert."
	else:
		_status_label.text = "%d bodies listed. Select one or more, or convert all." \
				% _body_list.item_count
	_update_buttons()


func _update_buttons() -> void:
	var idle := !_is_converting and _body_list.item_count > 0
	get_ok_button().disabled = !idle
	_convert_all_button.disabled = !idle
	_restart_button.disabled = _is_converting or _written_paths.is_empty()


func _on_only_unconverted_toggled(_pressed: bool) -> void:
	_refresh()


func _convert_selected() -> void:
	var selected := _body_list.get_selected_items()
	if selected.is_empty():
		_status_label.text = "Select at least one body first."
		return
	var chosen: Array[Dictionary] = []
	for index in selected:
		var body: Dictionary = _body_list.get_item_metadata(index)
		chosen.append(body)
	await _convert_bodies(chosen)


func _convert_all() -> void:
	var chosen: Array[Dictionary] = []
	for index in _body_list.item_count:
		var body: Dictionary = _body_list.get_item_metadata(index)
		chosen.append(body)
	await _convert_bodies(chosen)


func _convert_bodies(chosen: Array[Dictionary]) -> void:
	if _is_converting:
		return
	_is_converting = true
	_update_buttons()
	var converted_count := 0
	for body in chosen:
		var file_prefix: String = body[&"file_prefix"]
		var body_sources: Dictionary = body[&"sources"]
		for channel: StringName in body_sources:
			var source_path: String = body_sources[channel]
			_status_label.text = "Converting %s %s…" % [file_prefix, channel]
			# Let the label paint before the GPU work blocks the frame.
			await get_tree().process_frame
			var strip := await _converter.convert(source_path, channel == &"normal")
			if !strip:
				_status_label.text = "Failed on %s %s — see Output." % [file_prefix, channel]
				continue
			@warning_ignore("integer_division")
			var face_size := strip.get_width() / 3
			var path := IVCubeStripSaver.save_strip(file_prefix, channel, face_size, strip)
			if !path.is_empty():
				_written_paths.append(path)
				converted_count += 1
	_is_converting = false
	_refresh()
	_status_label.text = ("Converted %d channel(s); %d strip(s) written this session."
			% [converted_count, _written_paths.size()])


# Hands the written paths to the caller, which imports them after this dialog and its
# SubViewport are freed (a live SubViewport during import corrupts the editor's GPU state
# for the session). Both frees are queued, and the caller awaits two frames before
# importing, so they have run by then.
func _on_close() -> void:
	_free_converter()
	conversions_ready.emit(_written_paths)
	_written_paths = PackedStringArray()
	# Nothing else holds this dialog: set_unparent_when_invisible() only detaches it, so
	# without this it survives as an orphan and is reported leaked at exit.
	queue_free()


# Writes are already on disk, so a restart just lets a fresh process import them with
# clean thumbnails — the same escape hatch IVBody2DCaptureDialog offers. The caller does
# the restarting: calling EditorInterface.restart_editor() from here would end the process
# before either queued free ran, and both would be reported leaked at exit.
func _on_restart() -> void:
	_free_converter()
	_written_paths = PackedStringArray()
	restart_requested.emit()


func _free_converter() -> void:
	if !_converter:
		return
	_converter.queue_free()
	_converter = null
