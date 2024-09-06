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
extends Object



static func print_plugin_name_and_version(plugin_config_path: String, append := "") -> void:
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load(plugin_config_path)
	if err != OK:
		assert(false, "Failed to load config '%s'" % plugin_config_path)
		return
	var name: String = plugin_cfg.get_value("plugin", "name")
	var version: String = plugin_cfg.get_value("plugin", "version")
	print("%s (plugin) %s%s" % [name, version, append])


# Below 3 methods copied from ivoyager_core/static/files.gd. We don't like to
# copy code, but make an exception here for EditorPlugin access.


static func config_exists(config_path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(config_path) == OK


static func get_config(config_path: String) -> ConfigFile:
	# Returns null if doesn't exist.
	var config := ConfigFile.new()
	var err := config.load(config_path)
	if err == OK:
		return config
	return null


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
