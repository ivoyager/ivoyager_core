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
## bundle, [IVBody] ([code]body.gd[/code]) and [code]rings.shader[/code].
const RINGS_LOD_LEVELS := 9

# VRAM color formats a normal map must never have (would mean it was imported as
# sRGB color, not as a Normal Map). Load-time push_warning only.
const _NORMAL_COLOR_FORMATS := [
	Image.FORMAT_DXT1, Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA,
]



## Maps a [enum BaseMaterial3D.TextureParam] to the filename tag the preloader
## searches for under [member maps_search].
## Add entries (e.g. [code]BaseMaterial3D.TEXTURE_CLEARCOAT: &"clearcoat"[/code])
## before [signal IVStateManager.core_initialized] to ingest more channels; each
## tag must match [code][A-Za-z0-9_]+[/code]. A discovered file
## [code]<file_prefix>[.<file_tag>].<tag>.*[/code] is applied to the body's (or a
## shell's) material by [IVShellsModel].
static var texture_channels: Dictionary[int, StringName] = {
	BaseMaterial3D.TEXTURE_ALBEDO: &"albedo",
	BaseMaterial3D.TEXTURE_EMISSION: &"emission",
	BaseMaterial3D.TEXTURE_NORMAL: &"normal",
	BaseMaterial3D.TEXTURE_ROUGHNESS: &"roughness",
	BaseMaterial3D.TEXTURE_ORM: &"orm",
}
## Maps a surface/shell shader (as named in a [code]shells.tsv[/code] [code]shader[/code] cell)
## to its cubemap counterpart. When a body's discovered channels are [TextureLayered]s
## (files found under [member cubemaps_search]), [IVShellsModel] swaps the table-named shader
## for the variant here, so the tables never encode "cube vs. equirect" — the asset type
## decides. Add an entry to route a custom shader; a project with only equirect maps never
## triggers it. See [method IVShellsModel._build_shader_material].
static var cube_shader_variants: Dictionary[StringName, StringName] = {
	&"surface_shader": &"surface_cube_shader",
	&"cloud_shell_shader": &"cloud_shell_cube_shader",
	&"sun_surface_shader": &"sun_surface_cube_shader",
}
## [code]shells.tsv[/code] columns that are NOT [StandardMaterial3D] properties (read
## explicitly into the shell spec). Every other column is set on the shell material
## directly by [IVShellsModel] — to add a material override, just add that property's
## column. Each material column is validated per shell by [IVShellsModel] (as a
## [StandardMaterial3D] property, or a shader uniform when the shell names a shader).
static var shells_nonmaterial_fields: Array[StringName] = [
	&"surface_class", &"shell0", &"scale", &"file_tag", &"shader", &"process", &"process_args",
	&"is_sun", &"cast_shadow", &"exposure_ceiling", &"limb_exposure_ceiling",
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

## Directories searched for body 3D models. Prepend a directory to prioritize
## a custom override. A model authored at other than 1 m per unit must say so in its file
## name (see [method parse_model_scale]).
var models_search: Array[String] = ["res://addons/ivoyager_assets/models"]
## Directories searched for a body's surface [Mesh] resource (e.g. an OBJ imported as
## [ArrayMesh]). A mesh here replaces the shared sphere in [IVShellsModel], carrying the
## body's real figure and driven by its discovered channels. A
## self-defining [member models_search] PackedScene takes precedence.
var meshes_search: Array[String] = ["res://addons/ivoyager_assets/meshes"]
## Directories searched for body texture maps (channel maps + shell overlays).
var maps_search: Array[String] = ["res://addons/ivoyager_assets/maps"]
## Directories searched for cubemap body maps. Same filename convention as
## [member maps_search] (the [code]<res>[/code] token is the cube FACE size), but each
## file is a 6-face strip importing as a [CompressedCubemap] (see
## [code]addons/tools/bake_cubemap.py[/code]).
## Scanned AFTER maps_search, so a cubemap wins when a body has both — coexist-friendly.
var cubemaps_search: Array[String] = ["res://addons/ivoyager_assets/cubemaps"]
## Directories searched for 2D body textures (used in nav buttons, GUI, etc.).
var bodies_2d_search: Array[String] = ["res://addons/ivoyager_assets/bodies_2d"]
## Directories searched for rings textures.
var rings_search: Array[String] = ["res://addons/ivoyager_assets/rings"]

## Resolved paths for individually loaded assets. Keys correspond to the
## [code]get_*[/code] accessors below.
var asset_paths: Dictionary[StringName, String] = {
	fallback_body_texture_2d = "res://addons/ivoyager_assets/fallbacks/blank_grid_2d_globe.256.png",
}

## If non-empty, replaces the auto-composed map-filename pattern. Must define
## named groups [code]prefix[/code] and [code]tag[/code] (optionally [code]shell[/code]).
## You own its correctness; it is validated at load and ignored if invalid.
var map_filename_regex_override := ""

## Needed for visible Earth lights at night. Adjust by eye. Applies only to the by-eye
## emission channel: the physical one is a luminance and cannot differ by renderer, and
## IVExposureManager zeroes this channel outright while physical light runs.
var gl_compatibility_emission_energy_multiplier_multiplier := 2.5


var _symbol_atlas: Texture2D
var _symbol_textures: Array[AtlasTexture] = []
var _symbol_point_texture: Texture2D
var _body_resources: Dictionary[StringName, Array] = {}
var _rings_resources: Dictionary[String, Array] = {}
var _map_regex := RegEx.new()
var _range_tag_regex := RegEx.new()
var _model_scale_regex := RegEx.new()


func _init() -> void:
	IVStateManager.core_initialized.connect(_on_core_inited)



func get_symbol_atlas() -> Texture2D:
	return _symbol_atlas


## Returns the shared [AtlasTexture] for [param symbol_type], a row-major index
## into the atlas (see [member IVCoreSettings.symbol_atlas_path]). Not valid for
## -1 ("point"); use [method get_symbol_point_texture] for that.
func get_symbol_texture(symbol_type: int) -> AtlasTexture:
	return _symbol_textures[symbol_type]


## Returns a shared small-dot texture for the "point" (symbol type -1) indicator,
## so a picker button's icon (and thus height) stays consistent with the shapes.
func get_symbol_point_texture() -> Texture2D:
	return _symbol_point_texture


func get_body_texture_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][0]


func get_body_texture_slice_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][1]


func get_body_packed_model(body_name: StringName) -> PackedScene:
	return _body_resources[body_name][2]


## Returns the uniform scale for [method get_body_packed_model], read from the model's own
## file name by [method parse_model_scale]. Meaningless when there is no packed model.
func get_body_model_scale(body_name: StringName) -> float:
	return _body_resources[body_name][3]


## Returns an ordered [Array] of shell specs for one body: element 0 is the
## surface (shell 0); elements 1..N are overlay render shells. Each spec is a
## [Dictionary] with keys [code]channels, tag, scale, shader, process, process_args, is_sun,
## cast_shadow, overrides[/code]. [code]tag[/code] is the body's own name for the shell (e.g.
## [code]CLOUDS[/code]), empty for a shell 0 taken from the body's surface class.
## Built from the body's [code]shells[/code] field and the [code]shells[/code] table;
## shell 0 falls back to the [code]shells.tsv[/code] row of the body's [code]surface_class[/code]
## when the body has no [code]shell0[/code] row of its own. Consumed by [IVShellsModel].
func get_body_shell_specs(body_name: StringName) -> Array:
	return _body_resources[body_name][4]


## Returns the [Mesh] that replaces the shared sphere for this body — its own mesh from
## [member meshes_search], else the generic mesh of its surface class
## ([code]fallback_mesh_path[/code] in surface_classes.tsv) — or [code]null[/code] for the
## shared sphere. Scale it by [method get_body_mesh_scale].
func get_body_mesh(body_name: StringName) -> Mesh:
	return _body_resources[body_name][5]


## Returns the body's [code]file_prefix[/code] — the token every one of its asset files is
## named for. Use it to name a file [i]for[/i] a body, e.g. a captured 2D icon.
func get_body_file_prefix(body_name: StringName) -> String:
	return _body_resources[body_name][6]


## Returns the generic semi-axes of this body's surface class
## ([code]fallback_triaxial_size[/code] in surface_classes.tsv), or [constant Vector3.ZERO].
## Any scaling of the three works: the consumer normalizes to the body's own mean radius.
func get_body_fallback_triaxial_size(body_name: StringName) -> Vector3:
	return _body_resources[body_name][8]


## Returns the uniform scale for [method get_body_mesh]: [constant IVUnits.KM] for the body's
## own mesh (authored at true size in km), or the factor that resizes a generic surface-class
## mesh to this body's mean radius. Meaningless when there is no mesh.
func get_body_mesh_scale(body_name: StringName) -> float:
	return _body_resources[body_name][7]


func get_rings_texture_arrays(rings_name: StringName) -> Array[Texture2DArray]:
	return _rings_resources[rings_name][0]


## Full-resolution (LOD 0) mipmapped alpha profile for the analytic ring-shadow
## term (see [code]shaders/_sun_occlusion.gdshaderinc[/code]): the shader picks
## the mip that matches the physical penumbra footprint.
func get_rings_shadow_profile_texture(rings_name: StringName) -> Texture2D:
	return _rings_resources[rings_name][1]


## Source [Image] of [method get_rings_shadow_profile_texture], retained for
## CPU sampling ([method IVSunOcclusionManager.get_ring_transmission]); reading back from
## the texture would stall on VRAM.
func get_rings_shadow_profile_image(rings_name: StringName) -> Image:
	return _rings_resources[rings_name][2]


## Returns a [code]{property: value}[/code] dictionary of material fields from [param table]
## [param row] — every set field except the entity name and [param nonmaterial_fields]. Each
## remaining field must name a [StandardMaterial3D] property or a shader uniform; it is applied
## blindly by [IVShellsModel], which validates it per shell.
func read_material_fields(table: StringName, row: int,
		nonmaterial_fields: Array[StringName]) -> Dictionary:
	var fields: Dictionary = {}
	IVTableData.db_build_dictionary(fields, table, row)
	fields.erase(&"name")
	for nonmaterial_field in nonmaterial_fields:
		fields.erase(nonmaterial_field)
		
	if IVGlobal.is_gl_compatibility:
		if fields.has(&"emission_energy_multiplier"):
			fields[&"emission_energy_multiplier"] *= gl_compatibility_emission_energy_multiplier_multiplier
	
	return fields


func _on_core_inited() -> void:
	var start_msec := Time.get_ticks_msec()
	if use_thread and IVCoreSettings.use_threads:
		WorkerThreadPool.add_task(_load_resources.bind(start_msec))
	else:
		_load_resources.call_deferred(start_msec)


func _load_resources(start_msec: int) -> void:
	_load_symbol_textures()
	_load_body_resources()
	_load_rings_resources()
	# Freeze published containers (incl. the nested per-shell dicts) so any future
	# write becomes a hard error rather than a silent race against [IVBodyFinisher]
	# reader workers.
	_deep_freeze_body_resources()
	_rings_resources.make_read_only()
	print("Loaded assets in %s msec" % (Time.get_ticks_msec() - start_msec))
	IVStateManager.state_auxiliary.set_asset_preloader_finished.call_deferred()


func _load_symbol_textures() -> void:
	var path := IVCoreSettings.symbol_atlas_path
	assert(ResourceLoader.exists(path))
	_symbol_atlas = load(path)
	# Slice the atlas into per-cell AtlasTextures (row-major), shared by the 2D
	# symbol sprite ([IVBodyPositionVisual]) and the picker widgets. The 3D point
	# shader samples the whole atlas directly instead (see [IVSBGPositionsVisual]).
	var columns := IVCoreSettings.symbol_atlas_columns
	var rows := IVCoreSettings.symbol_atlas_rows
	var cell_w := _symbol_atlas.get_width() / float(columns)
	var cell_h := _symbol_atlas.get_height() / float(rows)
	_symbol_textures.resize(columns * rows)
	for i in columns * rows:
		var col := i % columns
		@warning_ignore("integer_division")
		var row := i / columns
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = _symbol_atlas
		atlas_texture.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
		_symbol_textures[i] = atlas_texture
	_symbol_point_texture = _make_symbol_point_texture()


# Procedural white dot with a ~1px AA edge, for the "point" (symbol type -1)
# indicator; keeps a picker button's icon height consistent with the shapes.
func _make_symbol_point_texture() -> ImageTexture:
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


# Builds one shell's spec [Dictionary] from its shells.tsv row — a body row
# (SHELL_<body>_<tag>) or, for a shell 0 the body does not override, its surface-class row.
# [param tag] is the body's own name for this shell, empty for a surface-class row.
func _read_shell_spec(channels: Dictionary, channel_ranges: Dictionary, shell_row: int,
		tag: String) -> Dictionary:
	# cast_shadow and scale have no table Default; unset means the engine value / no resize.
	var cast_shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if IVTableData.db_has_value(&"shells", &"cast_shadow", shell_row):
		cast_shadow = IVTableData.get_db_int(&"shells", &"cast_shadow", shell_row)
	var shell_scale := 1.0
	if IVTableData.db_has_value(&"shells", &"scale", shell_row):
		shell_scale = IVTableData.get_db_float(&"shells", &"scale", shell_row)
	return {
		&"channels": channels,
		&"channel_ranges": channel_ranges,
		&"tag": tag,
		&"scale": shell_scale,
		&"shader": IVTableData.get_db_string_name(&"shells", &"shader", shell_row),
		&"process": IVTableData.get_db_string_name(&"shells", &"process", shell_row),
		&"process_args": IVTableData.get_db_array(&"shells", &"process_args", shell_row),
		&"is_sun": IVTableData.get_db_bool(&"shells", &"is_sun", shell_row),
		&"cast_shadow": cast_shadow,
		&"overrides": read_material_fields(&"shells", shell_row, shells_nonmaterial_fields),
	}


# Resolves every surface_classes.tsv row once, returning class row ->
# [shells.tsv default-surface row, generic Mesh or null, the mean radius that mesh
# represents, fallback albedo Color, generic semi-axes or Vector3.ZERO]. An absent
# fallback_mesh_path file is not an error: Core has to run without the asset bundle, and a
# class with no resolvable mesh falls through to its generic semi-axes, then to the sphere.
func _build_surface_class_index() -> Dictionary[int, Array]:
	var shells_rows: Dictionary[int, int] = {}
	for shell_row in IVTableData.get_n_rows(&"shells"):
		if !IVTableData.db_has_value(&"shells", &"surface_class", shell_row):
			continue
		var surface_class := IVTableData.get_db_int(&"shells", &"surface_class", shell_row)
		assert(!shells_rows.has(surface_class), "shells.tsv: >1 row for surface_class '%s'"
				% IVTableData.get_db_entity_name(&"surface_classes", surface_class))
		assert(IVTableData.get_db_bool(&"shells", &"shell0", shell_row),
				"shells.tsv '%s': a surface_class row must be shell0"
				% IVTableData.get_db_entity_name(&"shells", shell_row))
		assert(!IVTableData.db_has_value(&"shells", &"file_tag", shell_row),
				"shells.tsv '%s': a shell0 row has no file_tag; a surface's maps are named"
				% IVTableData.get_db_entity_name(&"shells", shell_row)
				+ " for file_prefix alone")
		shells_rows[surface_class] = shell_row
	var index: Dictionary[int, Array] = {}
	for surface_class in IVTableData.get_n_rows(&"surface_classes"):
		var class_name_ := IVTableData.get_db_entity_name(&"surface_classes", surface_class)
		assert(shells_rows.has(surface_class),
				"shells.tsv has no default-surface row for surface_class '%s'" % class_name_)
		var mesh: Mesh = null
		var mesh_path := IVTableData.get_db_string(&"surface_classes", &"fallback_mesh_path",
				surface_class)
		if mesh_path:
			if ResourceLoader.exists(mesh_path):
				mesh = load(mesh_path)
			else:
				push_warning("surface_classes.tsv '%s': fallback_mesh_path '%s' not found;"
						% [class_name_, mesh_path] + " falling back to the shared sphere")
		var mesh_size := IVTableData.get_db_float(&"surface_classes", &"fallback_mesh_size",
				surface_class)
		assert(!mesh or mesh_size > 0.0,
				"surface_classes.tsv '%s': fallback_mesh_path needs fallback_mesh_size"
				% class_name_)
		var fallback_color := IVTableData.get_db_color(&"surface_classes", &"fallback_color",
				surface_class)
		var triaxial_size := Vector3.ZERO
		if IVTableData.db_has_value(&"surface_classes", &"fallback_triaxial_size", surface_class):
			triaxial_size = IVTableData.get_db_vector3(&"surface_classes",
					&"fallback_triaxial_size", surface_class)
		index[surface_class] = [shells_rows[surface_class], mesh, mesh_size, fallback_color,
				triaxial_size]
	return index


func _load_body_resources() -> void:
	const METER := IVUnits.METER

	# shells.tsv material columns are validated per-shell in IVShellsModel, which has the
	# resolved shader so it can check both StandardMaterial3D properties and shader uniforms;
	# a row may name either, so there is no table-wide check.
	_compose_file_regexes()
	var maps_index := _build_maps_index() # prefix(lower) -> shell -> {TextureParam: res_path}
	var surface_class_index := _build_surface_class_index()

	var fallback_texture_2d_path := asset_paths[&"fallback_body_texture_2d"]
	assert(ResourceLoader.exists(fallback_texture_2d_path))
	var fallback_texture_2d: Texture2D = load(fallback_texture_2d_path)

	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			
			var body_name := IVTableData.get_db_entity_name(table, row)
			var file_prefix := IVTableData.get_db_string(table, &"file_prefix", row)
			assert(file_prefix)
			var surface_class := IVTableData.get_db_int(table, &"surface_class", row)
			assert(surface_class != -1, "%s: every body needs a surface_class" % body_name)
			var class_entry: Array = surface_class_index[surface_class]

			var texture_2d: Texture2D = IVFiles.find_and_load_resource(bodies_2d_search, file_prefix)
			if !texture_2d:
				texture_2d = fallback_texture_2d
			
			var texture_slice_2d: Texture2D = null
			if IVTableData.get_db_bool(table, &"star", row):
				texture_slice_2d = IVFiles.find_and_load_resource(bodies_2d_search,
						file_prefix + "_slice")
			
			var packed_model: PackedScene = null
			var model_scale := METER
			var model_path := IVFiles.find_resource_file(models_search, file_prefix)
			if model_path:
				packed_model = load(model_path)
				model_scale = parse_model_scale(model_path.get_file()) * METER
			
			# A body's own Mesh (e.g. an OBJ -> ArrayMesh) replaces the shared sphere and is
			# authored at true size in km. Without one, the body's surface class may name a
			# generic mesh, which stands in for any body of that class and so must be resized
			# to this one. Consumed in IVBodyVisual's shells-model branch as the mesh_override.
			var mesh := IVFiles.find_and_load_resource(meshes_search, file_prefix) as Mesh
			var mesh_scale := IVUnits.KM
			if !mesh:
				mesh = class_entry[1]
				if mesh:
					var mean_radius := IVTableData.get_db_float(table, &"mean_radius", row)
					var generic_radius: float = class_entry[2]
					mesh_scale = IVUnits.KM * mean_radius / generic_radius

			# Discovered texture channels per shell from the single-pass maps index
			# (shell &"surface" = files with no shell token in the name).
			var shell_channels: Dictionary = {}
			var shell_channel_ranges: Dictionary = {}
			var by_shell: Dictionary = maps_index.get(file_prefix.to_lower(), {})
			for shell: StringName in by_shell:
				var param_paths: Dictionary = by_shell[shell]
				var channels: Dictionary = {}
				var channel_ranges: Dictionary = {}
				for param: int in param_paths:
					var map_path: String = param_paths[param]
					var range_tags := parse_range_tags(map_path.get_file())
					if range_tags:
						channel_ranges[param] = range_tags
					# A cubemap map imports as CompressedCubemap (a TextureLayered) and an
					# equirect one as CompressedTexture2D, so the resource type alone selects
					# the sampling path — the cubemaps/ directory is only a convention.
					# NB: CompressedCubemap does NOT extend Cubemap; both derive from
					# TextureLayered, so `is Cubemap` would be false for every imported one.
					var resource: Variant = load(map_path)
					if resource is TextureLayered:
						var cube_texture: TextureLayered = resource
						channels[param] = cube_texture
					else:
						var texture: Texture2D = resource
						channels[param] = texture
						_warn_channel_texture(param, texture, map_path)
				shell_channels[shell] = channels
				shell_channel_ranges[shell] = channel_ranges

			var surface_channels: Dictionary = shell_channels.get_or_add(&"surface", {})
			var surface_ranges: Dictionary = shell_channel_ranges.get_or_add(&"surface", {})

			# A body's shells are listed in its "shells" field (ARRAY[STRING]); each tag names
			# a row SHELL_<body_name>_<tag>. The one flagged shell0 is the surface and wholly
			# replaces the body's surface-class default row (never a merge); the rest are
			# overlays, which need a scale to sit off the surface.
			var surface_row := -1
			var surface_tag := ""
			var overlay_rows: Array[int] = []
			var overlay_tags: Array[String] = []
			for tag: String in IVTableData.get_db_array(table, &"shells", row):
				var shell_row := IVTableData.get_row(StringName("SHELL_%s_%s" % [body_name, tag]))
				if shell_row == -1:
					push_warning("Body %s: 'shells' lists '%s' with no matching shells.tsv row"
							% [body_name, tag])
					continue
				if !IVTableData.get_db_bool(&"shells", &"shell0", shell_row):
					assert(IVTableData.db_has_value(&"shells", &"scale", shell_row),
							"shells.tsv '%s': an overlay shell needs a scale"
							% IVTableData.get_db_entity_name(&"shells", shell_row))
					overlay_rows.append(shell_row)
					overlay_tags.append(tag)
				elif surface_row == -1:
					assert(!IVTableData.db_has_value(&"shells", &"file_tag", shell_row),
							"shells.tsv '%s': a shell0 row has no file_tag; a surface's maps"
							% IVTableData.get_db_entity_name(&"shells", shell_row)
							+ " are named for file_prefix alone")
					surface_row = shell_row
					surface_tag = tag
				else:
					push_warning("Body %s: more than one shell0 row; only one is the surface" % body_name)
			if surface_row == -1:
				surface_row = class_entry[0]
			var shell_specs: Array = [
					_read_shell_spec(surface_channels, surface_ranges, surface_row, surface_tag)]
			for overlay_index in overlay_rows.size():
				var overlay_row := overlay_rows[overlay_index]
				var file_tag := IVTableData.get_db_string_name(&"shells", &"file_tag", overlay_row)
				var channels: Dictionary = shell_channels.get(file_tag, {})
				var ranges: Dictionary = shell_channel_ranges.get(file_tag, {})
				shell_specs.append(_read_shell_spec(channels, ranges, overlay_row,
						overlay_tags[overlay_index]))

			# A surface with no color map would otherwise render white (an unbound sampler,
			# or the StandardMaterial3D default). Hand IVShellsModel the surface class's
			# fallback_color instead. Only shell 0: an overlay such as an atmospheric limb
			# legitimately has no channels and gets its color from its own shader.
			var has_surface_color := surface_channels.has(BaseMaterial3D.TEXTURE_ALBEDO)
			if !has_surface_color:
				has_surface_color = surface_channels.has(BaseMaterial3D.TEXTURE_EMISSION)
			if !has_surface_color:
				var class_fallback_color: Color = class_entry[3]
				shell_specs[0][&"fallback_color"] = _get_fallback_color(class_fallback_color,
						table, row)

			var resources := [
				texture_2d,
				texture_slice_2d,
				packed_model,
				model_scale,
				shell_specs,
				mesh,
				file_prefix,
				mesh_scale,
				class_entry[4],
			]

			_body_resources[body_name] = resources


# Under physical light (IVExposureManager registered), the class color is rescaled in
# linear light so its luminance equals the albedo the exposure metering assumes for this
# body (its meter_albedo, else its albedo, else the manager default) - a mapless surface
# then exposes like any calibrated map instead of blowing out. Both consuming
# albedo_color paths are source_color (sRGB), hence the decode/re-encode. Hue and alpha
# are the class color's own; a saturated channel caps the scale so hue survives.
func _get_fallback_color(class_color: Color, table: StringName, row: int) -> Color:
	var exposure_manager_var: Variant = IVGlobal.program.get(&"ExposureManager")
	if exposure_manager_var == null:
		return class_color
	var exposure_manager: IVExposureManager = exposure_manager_var
	var albedo := exposure_manager.default_albedo
	# meter_albedo ahead of albedo, the order IVExposureManager._get_albedo() takes:
	# the two must agree or this surface renders at a level metering did not assume.
	for field: StringName in [&"meter_albedo", &"albedo"]:
		if !IVTableData.db_has_value(table, field, row):
			continue
		var table_albedo := IVTableData.get_db_float(table, field, row)
		if table_albedo > 0.0: # empty cell reads non-positive; treat as unknown
			albedo = table_albedo
			break
	var linear := class_color.srgb_to_linear()
	var luminance := linear.get_luminance()
	if luminance <= 0.0:
		return Color(albedo, albedo, albedo).linear_to_srgb()
	var scale := albedo / luminance
	var max_channel := maxf(linear.r, maxf(linear.g, linear.b))
	if max_channel * scale > 1.0:
		scale = 1.0 / max_channel
	linear = Color(linear.r * scale, linear.g * scale, linear.b * scale, class_color.a)
	return linear.linear_to_srgb()


## Reads the optional range tags out of a texture's file name, as
## [code][Vector3 lo, Vector3 hi][/code], or an empty array when it carries none.
##
## A tag is [code].l<digits>[/code] or [code].h<digits>[/code] holding the physical linear
## value that the file's 0.0 and 1.0 stand for, in units of 1e-4 — five digits, so
## [code].h09823[/code] is 0.9823 and the five digits reach 9.9999. A packed texture stores
## [code](physical - lo) / (hi - lo)[/code], so the shader recovers physical light with one
## affine step; see [code]PHOTOMETRIC_MODEL.md[/code]. Untagged files return an empty array
## and every consumer then leaves them exactly as they were, which is why this is additive.
##
## [b]Each tag is independently optional and defaults to the identity[/b] (lo 0.0, hi 1.0),
## so a name carries only what is not already true — [code].l02462[/code] alone, never a
## redundant [code].h10000[/code] beside it.
##
## [b]A channel letter narrows a tag to one channel[/b]: [code]lr[/code] [code]lg[/code]
## [code]lb[/code] and [code]hr[/code] [code]hg[/code] [code]hb[/code] override red, green or
## blue. Channel tags are applied after the un-narrowed ones whatever order the name lists
## them in, so [code].h10504.hr13168[/code] and [code].hr13168.h10504[/code] are the same
## texture — a base for the channels that agree plus an override for the one that does not.
##
## [b]Over-unity is expressible and is meant to be.[/b] A [code]hi[/code] above 1.0 says the
## texture holds reflectance a channel really reaches past white — an over-saturated bright
## terrain, or a body whose opposition surge the shading model cannot reach. Clamping it into
## [0, 1] at build time is the information-erasing alternative this exists to avoid.
##
## [b]Why the file name.[/b] These numbers describe how these bytes were packed and are
## meaningless against any other file, so keeping them anywhere else invites a silent
## desync — the failure mode being a body that renders at the wrong level with nothing to
## show for it. The name is the one channel the asset build tree owns end to end.
func parse_range_tags(file_name: String) -> Array:
	var lo := Vector3.ZERO
	var hi := Vector3.ONE
	var found := false
	# Two passes so a channel tag wins over an un-narrowed one regardless of name order;
	# within a pass a repeated tag simply takes the last, which the producer never emits.
	for narrowed: bool in [false, true]:
		for regex_match: RegExMatch in _range_tag_regex.search_all(file_name):
			var channel := regex_match.get_string("channel")
			if channel.is_empty() == narrowed:
				continue
			var value := regex_match.get_string("digits").to_int() * 1e-4
			var is_lo := regex_match.get_string("letter") == "l"
			if channel.is_empty():
				if is_lo:
					lo = Vector3.ONE * value
				else:
					hi = Vector3.ONE * value
			else:
				var axis := "rgb".find(channel)
				if is_lo:
					lo[axis] = value
				else:
					hi[axis] = value
			found = true
	if not found:
		return []
	# A non-increasing range would invert or flatten the map; refuse rather than render it.
	if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z:
		push_error("Range tags in '%s' are not increasing (lo %s, hi %s); ignored"
				% [file_name, lo, hi])
		return []
	return [lo, hi]


## Reads the optional scale tag out of a packed model's file name: the number of metres one
## model unit stands for. [code]Eros.1_10.glb[/code] is 10, [code]Hyperion.1_1000.glb[/code]
## is 1000, and a name carrying no tag is 1.0 — which is what the spacecraft models are.
##
## The tag is [code].1_<N>[/code] with N a whole number of metres, the form both model
## builders in [code]addons/tools[/code] emit. There is no decimal form, and a body's
## [code]file_prefix[/code] must not itself end in [code].1_<digits>[/code].
##
## [b]Why the file name.[/b] A model is authored at whatever scale its author chose, and that
## fact belongs to those bytes alone — stating it anywhere else invites the silent desync this
## exists to avoid, the failure mode being a body rendering at the wrong size with nothing to
## show for it. [method parse_range_tags] reads a texture's own reflectance range the same way.
func parse_model_scale(file_name: String) -> float:
	var regex_match := _model_scale_regex.search(file_name)
	if !regex_match:
		return 1.0
	var meters := regex_match.get_string("meters").to_int()
	if meters == 0:
		push_error("Model scale tag in '%s' is zero; using 1 m" % file_name)
		return 1.0
	return float(meters)


func _compose_file_regexes() -> void:
	# The two file-name tag grammars are fixed and unrelated to the map pattern, so they
	# compile first: a valid map_filename_regex_override returns before the tail below.
	var err := _range_tag_regex.compile(
			"[.](?<letter>[lh])(?<channel>[rgb]?)(?<digits>\\d{5})(?=[.]|$)")
	assert(err == OK, "range tag regex failed to compile")
	err = _model_scale_regex.compile("[.]1_(?<meters>\\d+)(?=[.]|$)")
	assert(err == OK, "model scale regex failed to compile")
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
	err = _map_regex.compile(pattern)
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
	# prefix(lower) -> shell(StringName) -> {TextureParam(int): path}. One pass replaces a
	# per-(body x channel) directory scan. Equirect maps first, then cubemaps with
	# overwrite, so a cubemap wins when a body ships both formats. Nothing here records
	# WHICH format won; the loaded resource type says so (see [method _load_body_resources]).
	var index: Dictionary = {}
	var tag_to_param: Dictionary = {}
	for param: int in texture_channels:
		tag_to_param[String(texture_channels[param])] = param
	for dir_path in maps_search:
		_scan_maps_dir(dir_path, index, tag_to_param, true)
	for dir_path in cubemaps_search:
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
	# ordered shell specs (index 4) and their nested channel dicts so worker-thread
	# reads are race-free. (Each spec's "process_args" array is already frozen by the
	# table postprocessor, or is an empty literal.)
	for body_name in _body_resources:
		var resources: Array = _body_resources[body_name]
		var shell_specs: Array = resources[4]
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

		var texture_arrays: Array[Texture2DArray] = []
		var profile_image_rgba: Image
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
			if lod == 0:
				profile_image_rgba = backscatter_image # all have the same alpha channel

		# Full-resolution mipmapped alpha profile for the analytic ring-shadow
		# term; the source image is retained for CPU sampling. See
		# get_rings_shadow_profile_texture() / get_rings_shadow_profile_image().
		var shadow_profile_image := _make_alpha_r8_image(profile_image_rgba)
		@warning_ignore("return_value_discarded")
		shadow_profile_image.generate_mipmaps() # can't fail: R8 is uncompressed
		var shadow_profile_texture := ImageTexture.create_from_image(shadow_profile_image)

		_rings_resources[rings_name] = [texture_arrays, shadow_profile_texture,
				shadow_profile_image]


# Returns a width x 1 FORMAT_R8 image holding [param image_rgba]'s alpha channel.
func _make_alpha_r8_image(image_rgba: Image) -> Image:
	var width := image_rgba.get_width()
	var image_r8 := Image.create_empty(width, 1, false, Image.FORMAT_R8)
	for x in width:
		var color := image_rgba.get_pixel(x, 0)
		color.r = color.a
		image_r8.set_pixel(x, 0, color)
	return image_r8
