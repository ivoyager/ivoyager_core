# body_2d_icon_saver.gd
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
class_name IVBody2DIconSaver
extends Object

## Writes a captured icon [Image] to [constant OUTPUT_DIR] as
## [code]<file_prefix>.256.png[/code], alongside an [code].import[/code] sidecar matching the
## existing icon set.
##
## Output goes to [code]user://[/code] rather than into the assets directory, because a
## running build must not write to [code]res://[/code]. To add an icon to the set, copy
## [b]both[/b] files into [constant BODIES_2D_DIR]; the sidecar already names that
## destination, so the copy imports with the set's own settings instead of Godot's texture
## defaults.

const OUTPUT_DIR := "user://body_icons"
const BODIES_2D_DIR := "res://addons/ivoyager_assets/bodies_2d" ## Where to copy the results.
const ICON_SUFFIX := ".256.png"
const TEMPLATE_PREFIX := "Earth" ## An existing icon whose import params are cloned.


## Writes [param image] and its [code].import[/code] to [constant OUTPUT_DIR] and returns the
## PNG's path, or [code]""[/code] on failure. Reads the project's own [code]res://[/code]
## files to clone import params, so call only where [code]OS.has_feature("editor")[/code].
static func save_image(prefix: String, image: Image) -> String:
	if !DirAccess.dir_exists_absolute(OUTPUT_DIR):
		var dir_error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
		if dir_error != OK:
			push_error("Failed to create '%s' (error %s)" % [OUTPUT_DIR, dir_error])
			return ""
	var path := OUTPUT_DIR.path_join(prefix + ICON_SUFFIX)
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("Failed to save icon '%s' (error %s)" % [path, save_error])
		return ""
	_write_import_file(path, prefix)
	return path


## Returns [constant OUTPUT_DIR] as a native path. A [code]user://[/code] path resolves
## somewhere under app-data, so this is what to show someone who has to go find the files.
static func get_output_directory() -> String:
	return ProjectSettings.globalize_path(OUTPUT_DIR)


# Clones the importer and [params] from an existing icon so a captured one carries the set's
# compression / fix_alpha_border settings. source_file names the res:// destination rather
# than this file's own user:// path: the pair exists to be copied into the assets directory,
# and that is the only place an importer will ever read it. uid / path / dest_files are
# omitted so the importer generates them on first import there.
static func _write_import_file(png_path: String, prefix: String) -> void:
	var cfg := ConfigFile.new()
	var template_res := IVFiles.find_resource_file([BODIES_2D_DIR], TEMPLATE_PREFIX)
	var template_cfg := ConfigFile.new()
	var cloned := false
	if !template_res.is_empty() and template_cfg.load(template_res + ".import") == OK:
		if template_cfg.has_section("params"):
			cfg.set_value("remap", "importer", template_cfg.get_value("remap", "importer", "texture"))
			if template_cfg.has_section_key("remap", "type"):
				cfg.set_value("remap", "type", template_cfg.get_value("remap", "type"))
			for key in template_cfg.get_section_keys("params"):
				cfg.set_value("params", key, template_cfg.get_value("params", key))
			cloned = true
	if !cloned:
		push_warning("No '%s' icon to clone import params from; using texture defaults"
				% TEMPLATE_PREFIX)
		cfg.set_value("remap", "importer", "texture")
		cfg.set_value("params", "compress/mode", 1)
		cfg.set_value("params", "mipmaps/generate", true)
		cfg.set_value("params", "process/fix_alpha_border", true)
	cfg.set_value("deps", "source_file", BODIES_2D_DIR.path_join(prefix + ICON_SUFFIX))
	cfg.save(png_path + ".import")
