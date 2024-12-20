# plugin_utils.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVPluginUtils
extends Object

## Static plugin and config functions
##
## All functions are safe to call in-editor (from EditorPlugin) or at runtime.[br][br]
##
## Functions are copied and reused in other (freestanding) 'ivoyager_' plugins
## as needed. This file contains the 'master' versions.


## Supply only the base name from the plugin path.
## Assumes plugin.cfg path is "res://addons/<plugin>/plugin.cfg".[br][br]
##
## This is for runtime usage! EditorPlugin should use the EditorInterface
## function of the same name instead.
static func is_plugin_enabled(plugin: String) -> bool:
	var path := "res://addons/" + plugin + "/plugin.cfg"
	var plugin_paths: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled")
	return plugin_paths.has(path)


## Assumes plugin.cfg path is "res://addons/<plugin>/plugin.cfg".[br][br]
## WARNING: For this function to work in exported project, add "*.cfg" or specific cofig file to
## Project/Export.../Resources/"Filters to export non-resource files/folders".
static func print_plugin_name_and_version(plugin: String, append := "") -> void:
	var path := "res://addons/" + plugin + "/plugin.cfg"
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load(path)
	if err != OK:
		assert(false, "Failed to load config '%s'" % path)
		return
	var plugin_name: String = plugin_cfg.get_value("plugin", "name")
	var version: String = plugin_cfg.get_value("plugin", "version")
	print("%s (plugin) %s%s" % [plugin_name, version, append])


## WARNING: For this function to work in exported project, add "*.cfg" or specific cofig file to
## Project/Export.../Resources/"Filters to export non-resource files/folders".
static func config_exists(config_path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(config_path) == OK


## Returns null if doesn't exist.[br][br]
## WARNING: For this function to work in exported project, add "*.cfg" or specific cofig file to
## Project/Export.../Resources/"Filters to export non-resource files/folders".
static func get_config(config_path: String) -> ConfigFile:
	var config := ConfigFile.new()
	var err := config.load(config_path)
	if err == OK:
		return config
	return null


## Specify one or two override configs. The last one has the final say.
## There is no error if override(s) configs don't exist or fail to load.[br][br]
## WARNING: For this function to work in exported project, add "*.cfg" or specific cofig files to
## Project/Export.../Resources/"Filters to export non-resource files/folders".
static func get_config_with_override(config_path: String, override_config_path: String,
		override_config_path2 := "") -> ConfigFile:
	var config := get_config(config_path)
	if !config:
		assert(false, "Failed to load config '%s'" % config_path)
		return null
	var override_config := get_config(override_config_path)
	if !override_config:
		return config
	for section in override_config.get_sections():
		for property in override_config.get_section_keys(section):
			config.set_value(section, property, override_config.get_value(section, property))
	if !override_config_path2:
		return config
	override_config = get_config(override_config_path2)
	if !override_config:
		return config
	for section in override_config.get_sections():
		for property in override_config.get_section_keys(section):
			config.set_value(section, property, override_config.get_value(section, property))
	return config


## I, Voyager plugins have a 'base' ivoyager_config (not the plugin.cfg!) that
## can be overridden by project level override(s) at "res://ivoyager_override.cfg"
## and "res://ivoyager_override2.cfg" (if they exist). 
static func get_ivoyager_config(base_ivoyager_config_path: String) -> ConfigFile:
	return get_config_with_override(base_ivoyager_config_path,
			"res://ivoyager_override.cfg", "res://ivoyager_override2.cfg")
