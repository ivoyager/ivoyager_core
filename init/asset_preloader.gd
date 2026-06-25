# asset_preloader.gd
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
class_name IVAssetPreloader
extends RefCounted

## Loads and pregenerates resources from ivoyager_assets using dynamic
## specification in data tables.
##
## In typical setup, loading will commence right after splash screen is shown,
## on [signal IVStateManager.core_initialized]. When finished, emits [signal
## IVStateManager.assets_preloaded].

## Number of LOD textures expected per rings entry. Must agree with the asset
## bundle, [IVBody] and [code]rings.shader[/code].
const RINGS_LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader

# VRAM color formats a normal map must never have (would mean it was imported as
# sRGB color, not as a Normal Map). Load-time push_warning only.
const _NORMAL_COLOR_FORMATS := [
	Image.FORMAT_DXT1, Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA,
]


## This setting AND IVCoreSettings.use_threads must be true for loading to
## occur on thread.
##
## Dev note: As of Godot 4.4.1, loading on thread is slow (e.g., ~3000 msec
## versus ~800 msec for Planetarium on my laptop). Nevertheless, you might want
## it so your splash screen can be interactive.
##
## WARNING: Loading the same resource using different threads at the same time
## is hazardous. That can happen here only if these "procedural" resources are
## loaded elsewhere in the preload time window.
var use_thread := false
 ## Must exist in asset_paths.

## Directories searched for body 3D models. Prepend a directory to prioritize
## a custom override.
var models_search: Array[String] = ["res://addons/ivoyager_assets/models"] # prepend to prioritize
## Directories searched for body texture maps (channel maps + shell overlays).
var maps_search: Array[String] = ["res://addons/ivoyager_assets/maps"]
## Directories searched for 2D body textures (used in nav buttons, GUI, etc.).
var bodies_2d_search: Array[String] = ["res://addons/ivoyager_assets/bodies_2d"]
## Directories searched for rings textures.
var rings_search: Array[String] = ["res://addons/ivoyager_assets/rings"]

## Resolved paths for individually loaded assets. Keys correspond to the
## [code]get_*[/code] accessors below and to entries in [member fallback_starmap].
var asset_paths: Dictionary[StringName, String] = {
	blue_noise_1024 = "res://addons/ivoyager_assets/noise/blue_noise_1024.png",
	starmap_8k = "res://addons/ivoyager_assets/starmaps/starmap_8k.jpg",
	starmap_16k = "res://addons/ivoyager_assets/starmaps/starmap_16k.jpg",
	fallback_body_texture_2d = "res://addons/ivoyager_assets/fallbacks/blank_grid_2d_globe.256.png",
	fallback_body_albedo_map = "res://addons/ivoyager_assets/fallbacks/blank_grid.jpg",
}
## Key in [member asset_paths] used as starmap when the user-selected starmap
## isn't available.
var fallback_starmap := &"starmap_8k" # starmap_16k possibly removed for size reduction

## Maps a [enum BaseMaterial3D.TextureParam] to the filename tag the preloader
## searches for under [member maps_search], prepopulated with the universal three.
## Add entries (e.g. [code]BaseMaterial3D.TEXTURE_ROUGHNESS: &"roughness"[/code])
## before [signal IVStateManager.core_initialized] to ingest more channels; each
## tag must match [code][A-Za-z0-9_]+[/code]. A discovered file
## [code]<file_prefix>[.<file_tag>].<tag>.*[/code] is applied to the body's (or a
## shell's) material by [IVSpheroidModel].
var texture_channels: Dictionary[int, StringName] = {
	BaseMaterial3D.TEXTURE_ALBEDO: &"albedo",
	BaseMaterial3D.TEXTURE_EMISSION: &"emission",
	BaseMaterial3D.TEXTURE_NORMAL: &"normal",
}
## If non-empty, replaces the auto-composed map-filename pattern. Must define
## named groups [code]prefix[/code] and [code]tag[/code] (optionally [code]shell[/code]).
## You own its correctness; it is validated at load and ignored if invalid.
var map_filename_regex_override := ""


var _blue_noise_1024: Texture2D
var _starmap: Texture2D
var _body_resources: Dictionary[StringName, Array] = {}
var _rings_resources: Dictionary[String, Array] = {}
var _map_regex := RegEx.new()


func _init() -> void:
	IVStateManager.core_initialized.connect(_on_core_inited)



func get_blue_noise_1024() -> Texture2D:
	return _blue_noise_1024


func get_starmap() -> Texture2D:
	return _starmap


func get_body_texture_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][0]


func get_body_texture_slice_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][1]


func get_body_model_type(body_name: StringName) -> int:
	return _body_resources[body_name][2]


func get_body_packed_model(body_name: StringName) -> PackedScene:
	return _body_resources[body_name][3]


func get_body_model_scale(body_name: StringName) -> float:
	return _body_resources[body_name][4]


func get_body_disable_auto_visual_range(body_name: StringName) -> bool:
	return _body_resources[body_name][5]


func get_body_map_offset(body_name: StringName) -> float:
	return _body_resources[body_name][6]


## Returns an ordered [Array] of shell specs for one body: element 0 is the
## surface (shell 0); elements 1..N are overlay render shells. Each spec is a
## [Dictionary] with keys [code]channels, shader, process, transparency,
## overrides[/code] (plus [code]scale[/code] for overlays). Built from the body's
## [code]shells[/code] field and the [code]shells[/code] table. Consumed by [IVSpheroidModel].
func get_body_shell_specs(body_name: StringName) -> Array:
	return _body_resources[body_name][7]


func get_rings_texture_arrays(rings_name: StringName) -> Array[Texture2DArray]:
	return _rings_resources[rings_name][0]


func get_rings_shadow_caster_texture(rings_name: StringName) -> Texture2D:
	return _rings_resources[rings_name][1]


func _on_core_inited() -> void:
	var start_msec := Time.get_ticks_msec()
	if use_thread and IVCoreSettings.use_threads:
		WorkerThreadPool.add_task(_load_resources.bind(start_msec))
	else:
		_load_resources.call_deferred(start_msec)


func _load_resources(start_msec: int) -> void:
	_load_starmap()
	_load_blue_noise_1024()
	_load_body_resources()
	_load_rings_resources()
	# Freeze published containers (incl. the nested per-shell dicts) so any future
	# write becomes a hard error rather than a silent race against [IVBodyFinisher]
	# reader workers.
	_deep_freeze_body_resources()
	_rings_resources.make_read_only()
	print("Loaded assets in %s msec" % (Time.get_ticks_msec() - start_msec))
	IVStateManager.state_auxiliary.set_asset_preloader_finished.call_deferred()


func _load_blue_noise_1024() -> void:
	var path := asset_paths[&"blue_noise_1024"]
	assert(ResourceLoader.exists(path))
	_blue_noise_1024 = load(path)


func _load_starmap() -> void:
	var path: String
	match IVSettingsManager.get_setting(&"starmap"):
		IVGlobal.StarmapSize.STARMAP_8K:
			path = asset_paths[&"starmap_8k"]
		IVGlobal.StarmapSize.STARMAP_16K:
			path = asset_paths[&"starmap_16k"]
	if !ResourceLoader.exists(path):
		path = asset_paths[fallback_starmap]
	assert(ResourceLoader.exists(path))
	_starmap = load(path)


## Builds one shell's spec [Dictionary] from its [code]shells[/code]-table row, or
## model defaults if [param shell_row] is -1 (a surface with no row). [param is_surface]
## (shell 0) omits [code]scale[/code] (the surface ranks as 1.0) and has no file_tag.
func _read_shell_spec(channels: Dictionary, shell_row: int, is_surface: bool) -> Dictionary:
	if shell_row == -1:
		return {
			&"channels": channels,
			&"shader": &"",
			&"process": [],
			&"transparency": BaseMaterial3D.TRANSPARENCY_DISABLED,
			&"overrides": {},
		}
	var overrides: Dictionary = {}
	IVTableData.db_build_dictionary(overrides, &"shells", shell_row, IVSpheroidModel.material_fields)
	var spec: Dictionary = {
		&"channels": channels,
		&"shader": IVTableData.get_db_string_name(&"shells", &"shader", shell_row),
		&"process": IVTableData.get_db_array(&"shells", &"process", shell_row),
		&"transparency": IVTableData.get_db_int(&"shells", &"transparency", shell_row),
		&"overrides": overrides,
	}
	if not is_surface:
		spec[&"scale"] = IVTableData.get_db_float(&"shells", &"scale", shell_row)
	return spec


func _load_body_resources() -> void:
	const METER := IVUnits.METER
	
	_compose_map_regex()
	var maps_index := _build_maps_index() # prefix(lower) -> shell -> {TextureParam: res_path}
	
	var fallback_texture_2d_path := asset_paths[&"fallback_body_texture_2d"]
	assert(ResourceLoader.exists(fallback_texture_2d_path))
	var fallback_texture_2d: Texture2D = load(fallback_texture_2d_path)
	
	var fallback_albedo_map_path := asset_paths[&"fallback_body_albedo_map"]
	assert(ResourceLoader.exists(fallback_albedo_map_path))
	var fallback_albedo_map: Texture2D = load(fallback_albedo_map_path)
	
	var file_adj_rows: Dictionary[String, int] = {}
	var file_adj_files: Array[String] = IVTableData.get_db_field_array(&"file_adjustments", &"file")
	for i in file_adj_files.size():
		file_adj_rows[file_adj_files[i]] = i
		
	
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			
			var body_name := IVTableData.get_db_entity_name(table, row)
			var file_prefix := IVTableData.get_db_string(table, &"file_prefix", row)
			assert(file_prefix)
			
			var texture_2d: Texture2D = IVFiles.find_and_load_resource(bodies_2d_search, file_prefix)
			if !texture_2d:
				texture_2d = fallback_texture_2d
			
			var texture_slice_2d: Texture2D = null
			if IVTableData.get_db_bool(table, &"star", row):
				texture_slice_2d = IVFiles.find_and_load_resource(bodies_2d_search,
						file_prefix + "_slice")
			
			var model_type := IVTableData.get_db_int(table, &"model_type", row)
			var packed_model: PackedScene = null
			var model_scale := METER
			var disable_auto_visual_range := false
			var model_path := IVFiles.find_resource_file(models_search, file_prefix)
			if model_path:
				packed_model = load(model_path)
				var model_file := model_path.get_file()
				if file_adj_rows.has(model_file):
					model_scale = IVTableData.get_db_float(&"file_adjustments", &"model_scale",
							file_adj_rows[model_file])
					disable_auto_visual_range = IVTableData.get_db_bool(&"file_adjustments",
							&"disable_auto_visual_range", file_adj_rows[model_file])
			
			# Discovered texture channels per shell from the single-pass maps index
			# (shell &"surface" = files with no shell token in the name).
			var shell_channels: Dictionary = {}
			var surface_albedo_file := ""
			var surface_emission_file := ""
			var by_shell: Dictionary = maps_index.get(file_prefix.to_lower(), {})
			for shell: StringName in by_shell:
				var param_paths: Dictionary = by_shell[shell]
				var channels: Dictionary = {}
				for param: int in param_paths:
					var map_path: String = param_paths[param]
					var texture: Texture2D = load(map_path)
					channels[param] = texture
					_warn_channel_texture(param, texture, map_path)
					if shell == &"surface":
						if param == BaseMaterial3D.TEXTURE_ALBEDO:
							surface_albedo_file = map_path.get_file()
						elif param == BaseMaterial3D.TEXTURE_EMISSION:
							surface_emission_file = map_path.get_file()
				shell_channels[shell] = channels

			# map_offset rotates the equirectangular projection (applied to the model
			# basis); shells inherit it. Read from the surface albedo (else emission)
			# file in file_adjustments; the two must agree if both are present.
			var map_offset := 0.0
			if surface_albedo_file and file_adj_rows.has(surface_albedo_file):
				map_offset = IVTableData.get_db_float(&"file_adjustments", &"map_offset",
						file_adj_rows[surface_albedo_file])
			if surface_emission_file and file_adj_rows.has(surface_emission_file):
				var emission_offset := IVTableData.get_db_float(&"file_adjustments",
						&"map_offset", file_adj_rows[surface_emission_file])
				assert(map_offset == 0.0 or map_offset == emission_offset,
						"emission and albedo must have equal map_offset in file_adjustments.tsv"
						+ " (only one needs to be specified)")
				map_offset = emission_offset

			# Surface always exists; fall back to the blank grid if it has no albedo
			# and no emission.
			var surface_channels: Dictionary = shell_channels.get_or_add(&"surface", {})
			var has_surface_color := surface_channels.has(BaseMaterial3D.TEXTURE_ALBEDO)
			has_surface_color = has_surface_color or surface_channels.has(BaseMaterial3D.TEXTURE_EMISSION)
			if not has_surface_color:
				surface_channels[BaseMaterial3D.TEXTURE_ALBEDO] = fallback_albedo_map

			# Shell 0 (the surface) always exists and is the one shell with no
			# "scale" value. Shells with a row in shells.tsv are listed in the body's
			# "shells" field (ARRAY[STRING]); each tag names a row SHELL_<body_name>_<tag>.
			var surface_row := -1
			var overlay_rows: Array[int] = []
			for tag: String in IVTableData.get_db_array(table, &"shells", row):
				var shell_row := IVTableData.get_row(StringName("SHELL_%s_%s" % [body_name, tag]))
				if shell_row == -1:
					push_warning("Body %s: 'shells' lists '%s' with no matching shells.tsv row"
							% [body_name, tag])
					continue
				if IVTableData.db_has_value(&"shells", &"scale", shell_row):
					overlay_rows.append(shell_row)
				elif surface_row == -1:
					surface_row = shell_row # the surface: the one shell with no scale
				else:
					push_warning("Body %s: more than one shell without 'scale'; only one is the surface"
							% body_name)
			var shell_specs: Array = [_read_shell_spec(surface_channels, surface_row, true)]
			for overlay_row in overlay_rows:
				var file_tag := IVTableData.get_db_string_name(&"shells", &"file_tag", overlay_row)
				var channels: Dictionary = shell_channels.get(file_tag, {})
				shell_specs.append(_read_shell_spec(channels, overlay_row, false))

			var resources := [
				texture_2d,
				texture_slice_2d,
				model_type,
				packed_model,
				model_scale,
				disable_auto_visual_range,
				map_offset,
				shell_specs,
			]

			_body_resources[body_name] = resources


func _compose_map_regex() -> void:
	# Compose [member _map_regex] so the "tag" group is an exact alternation of
	# registered tags - this is what lets the optional "shell" token be told apart
	# from the tag. A valid override replaces the default.
	if map_filename_regex_override:
		if _map_regex.compile(map_filename_regex_override) == OK and _map_regex_has_groups():
			return
		push_error("map_filename_regex_override invalid or missing prefix/tag groups;"
				+ " using composed default")
	var word := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	var tags: Array[String] = []
	for param: int in texture_channels:
		var tag := String(texture_channels[param])
		if word.search(tag):
			tags.append(tag)
		else:
			push_error("texture_channels tag '%s' is not [A-Za-z0-9_]+; ignored" % tag)
	tags.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var pattern := "^(?<prefix>[^.]+)(?:[.](?<shell>[^.]+))?[.](?<tag>%s)(?:[.].*)?$" % "|".join(tags)
	var err := _map_regex.compile(pattern)
	assert(err == OK, "composed map regex failed to compile: %s" % pattern)


func _map_regex_has_groups() -> bool:
	# Functional check: a synthetic "<prefix>.<tag>" must yield both named groups.
	var any_tag := ""
	for param: int in texture_channels:
		any_tag = String(texture_channels[param])
		break
	var regex_match := _map_regex.search("ivprefix.%s" % any_tag)
	if not regex_match:
		return false
	return regex_match.get_string("prefix") == "ivprefix" and regex_match.get_string("tag") == any_tag


func _build_maps_index() -> Dictionary:
	# prefix(lower) -> shell(StringName) -> {TextureParam(int): res_path}. One pass
	# replaces a per-(body x channel) directory scan.
	var index: Dictionary = {}
	var tag_to_param: Dictionary = {}
	for param: int in texture_channels:
		tag_to_param[String(texture_channels[param])] = param
	for dir_path in maps_search:
		_scan_maps_dir(dir_path, index, tag_to_param, true)
	return index


func _scan_maps_dir(dir_path: String, index: Dictionary, tag_to_param: Dictionary,
		descend: bool) -> void:
	# Only ".import" files exist in exported projects, so we match those and strip
	# the suffix (same idiom as [method IVFiles.find_resource_file]).
	var dir := DirAccess.open(dir_path)
	if !dir:
		return
	dir.include_hidden = false
	dir.include_navigational = false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name:
		if dir.current_is_dir():
			if descend:
				_scan_maps_dir(dir_path.path_join(file_name), index, tag_to_param, false)
		elif file_name.get_extension() == "import":
			var map_basename := file_name.get_basename() # strips ".import"
			var regex_match := _map_regex.search(map_basename)
			if regex_match:
				var tag := regex_match.get_string("tag")
				if tag_to_param.has(tag):
					var prefix := regex_match.get_string("prefix").to_lower()
					var shell := regex_match.get_string("shell")
					var shell_key: StringName = &"surface" if shell == "" else StringName(shell)
					var by_shell: Dictionary = index.get_or_add(prefix, {})
					var by_param: Dictionary = by_shell.get_or_add(shell_key, {})
					by_param[tag_to_param[tag]] = dir_path.path_join(map_basename)
		file_name = dir.get_next()


func _warn_channel_texture(param: int, texture: Texture2D, map_path: String) -> void:
	# Best-effort checks decipherable from the texture itself (no .import reading).
	var image := texture.get_image()
	if !image:
		return
	if param == BaseMaterial3D.TEXTURE_NORMAL and image.get_format() in _NORMAL_COLOR_FORMATS:
		push_warning("Normal map '%s' has a color/sRGB format; import it as a Normal Map"
				% map_path.get_file())
	var width := image.get_width()
	var height := image.get_height()
	if height > 0 and width != 2 * height:
		push_warning("Map '%s' is %sx%s; expected 2:1 equirectangular"
				% [map_path.get_file(), width, height])


func _deep_freeze_body_resources() -> void:
	# make_read_only() freezes only the immediate container; recurse into the
	# ordered shell specs (index 7) and their nested channel dicts so worker-thread
	# reads are race-free. (Each spec's "process" array is already frozen by the
	# table postprocessor, or is an empty literal.)
	for body_name in _body_resources:
		var resources: Array = _body_resources[body_name]
		var shell_specs: Array = resources[7]
		for spec: Dictionary in shell_specs:
			var channels: Dictionary = spec[&"channels"]
			channels.make_read_only()
			var overrides: Dictionary = spec[&"overrides"]
			overrides.make_read_only()
			spec.make_read_only()
		shell_specs.make_read_only()
		resources.make_read_only()
	_body_resources.make_read_only()


func _load_rings_resources() -> void:
	
	const BACKSCATTER_FILE_FORMAT := "%s.backscatter.%s"
	const FORWARDSCATTER_FILE_FORMAT := "%s.forwardscatter.%s"
	const UNLITSIDE_FILE_FORMAT := "%s.unlitside.%s"
	
	for row in IVTableData.get_n_rows(&"rings"):
		var rings_name := IVTableData.get_db_entity_name(&"rings", row)
		var file_prefix := IVTableData.get_db_string(&"rings", &"file_prefix", row)
		var shadow_lod := IVTableData.get_db_int(&"rings", &"shadow_lod", row)
		shadow_lod = mini(shadow_lod, RINGS_LOD_LEVELS - 1)
		
		var texture_arrays: Array[Texture2DArray] = []
		var shadow_image_rgba: Image
		for lod in RINGS_LOD_LEVELS:
			var file_elements := [file_prefix, lod]
			var backscatter_file := BACKSCATTER_FILE_FORMAT % file_elements
			var backscatter: Texture2D = IVFiles.find_and_load_resource(rings_search, backscatter_file)
			assert(backscatter, "Failed to load '%s'" % backscatter_file)
			var forwardscatter_file := FORWARDSCATTER_FILE_FORMAT % file_elements
			var forwardscatter: Texture2D = IVFiles.find_and_load_resource(rings_search, forwardscatter_file)
			assert(forwardscatter, "Failed to load '%s'" % forwardscatter_file)
			var unlitside_file := UNLITSIDE_FILE_FORMAT % file_elements
			var unlitside: Texture2D = IVFiles.find_and_load_resource(rings_search, unlitside_file)
			assert(unlitside, "Failed to load '%s'" % unlitside_file)
			
			# We load as textures, convert to images, then reconvert back to
			# texture arrays. This is not ideal, but I was unable to save
			# Texture2DArray as a file resource as of Godot 4.2 (it's a
			# Resource, so it should be saveable).
			var backscatter_image := backscatter.get_image()
			var forwardscatter_image := forwardscatter.get_image()
			var unlitside_image := unlitside.get_image()
			var lod_images: Array[Image] = [backscatter_image, forwardscatter_image, unlitside_image]
			var texture_array := Texture2DArray.new() # backscatter/forwardscatter/unlitside for LOD
			texture_array.create_from_images(lod_images)
			texture_arrays.append(texture_array)
			if lod == shadow_lod:
				shadow_image_rgba = backscatter_image # all have the same alpha channel
		
		# Rebuild the shadow caster texture as smaller FORMAT_R8, alpha only.
		# We could have this premade in ivoyager_assets, but it gives us
		# flexibility with LOD to do here.
		var shadow_width := shadow_image_rgba.get_width()
		var shadow_image_r8 := Image.create_empty(shadow_width, 1, false, Image.FORMAT_R8)
		for x in shadow_width:
			var color := shadow_image_rgba.get_pixel(x, 0)
			color.r = color.a
			shadow_image_r8.set_pixel(x, 0, color)
		var shadow_caster_texture := ImageTexture.create_from_image(shadow_image_r8)
		
		_rings_resources[rings_name] = [texture_arrays, shadow_caster_texture]
