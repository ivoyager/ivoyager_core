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
@tool
class_name IVBody2DIconSaver
extends Object

## Editor-only helper that writes a captured icon [Image] into the bodies_2d
## asset directory as [code]<file_prefix>.256.png[/code] and (re)imports it with
## the same import settings as the existing icons.
##
## To match the set exactly it clones the [code][params][/code] of an existing
## icon's [code].import[/code] (the one value that differs from Godot's texture
## default is [code]compress/mode=1[/code]); without a template the new icon keeps
## Godot's defaults.

const BODIES_2D_DIR := "res://addons/ivoyager_assets/bodies_2d"
const ICON_SUFFIX := ".256.png"
const TEMPLATE_PREFIX := "Earth" ## An existing icon whose import params are cloned.


## Writes [param image] as [code]<prefix>.256.png[/code] plus its [code].import[/code]
## (cloned params) and returns the resource path, or [code]""[/code] on failure.
## Does NOT import — call [method reimport] once after the capture dialog's 3D
## SubViewport has been freed. Importing/thumbnailing a texture while a custom
## SubViewport is rendering corrupts the editor's GPU/preview state for that
## session (crashes on click/Reimport on some drivers), so writing and importing
## are deliberately deferred to a clean main-loop tick with no viewport active.
static func save_image(prefix: String, image: Image) -> String:
	var path := _save_png(prefix, image)
	if path.is_empty():
		return ""
	_write_import_file(path)
	return path


## Registers and (re)imports [param paths] in one pass. Call only after any custom
## 3D SubViewport used to render the icons has been freed (see [method save_image]).
static func reimport(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	var editor_file_system := EditorInterface.get_resource_filesystem()
	for path in paths:
		editor_file_system.update_file(path)
	editor_file_system.reimport_files(paths)


static func _save_png(prefix: String, image: Image) -> String:
	var path := BODIES_2D_DIR.path_join(prefix + ICON_SUFFIX)
	var err := image.save_png(path)
	if err != OK:
		push_error("Failed to save icon '%s' (error %s)" % [path, err])
		return ""
	return path


# Writes the new PNG's .import up front, cloning the importer and [params] from an
# existing icon so captured icons match the set's compression / fix_alpha_border
# settings. uid / path / dest_files are omitted so the importer generates them on
# the single reimport. Writing a complete .import first — rather than reimport →
# rewrite → reimport — avoids the inconsistent import state that broke thumbnails
# and crashed manual Reimport.
static func _write_import_file(png_path: String) -> void:
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
		cfg.set_value("remap", "importer", "texture")
		cfg.set_value("params", "compress/mode", 1)
		cfg.set_value("params", "mipmaps/generate", true)
		cfg.set_value("params", "process/fix_alpha_border", true)
	cfg.set_value("deps", "source_file", png_path)
	cfg.save(png_path + ".import")
