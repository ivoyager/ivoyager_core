# plugin_utils.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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

# Static utility class for working with config files.


static func print_name_and_version(plugin_config_path: String, append := "") -> void:
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load(plugin_config_path)
	if err != OK:
		print("ERROR: Failed to load config '%s'" % plugin_config_path)
		return
	var name: String = plugin_cfg.get_value("plugin", "name")
	var version: String = plugin_cfg.get_value("plugin", "version")
	print("%s (plugin) %s%s" % [name, version, append])


static func config_exists(config_path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(config_path) == OK


static func get_config(config_path: String) -> ConfigFile:
	# Returns null if read failure.
	var config := ConfigFile.new()
	var err := config.load(config_path)
	if err == OK:
		return config
	return null


static func get_config_with_override(config_path: String, override_config_path: String,
		section_prefix := "") -> ConfigFile:
	var config := get_config(config_path)
	if !config:
		assert(false, "Failed to load config '%s'" % config_path)
		return null
	var override_config := get_config(override_config_path)
	if !override_config:
		return config
	for section in override_config.get_sections():
		if section_prefix and !section.begins_with(section_prefix):
			continue
		for property in override_config.get_section_keys(section):
			config.set_value(section, property, override_config.get_value(section, property))
	return config


static func init_from_config(object: Object, config: ConfigFile, section: String) -> void:
	if !config.has_section(section):
		return
	for key in config.get_section_keys(section):
		var value: Variant = config.get_value(section, key)
		var slash_pos := key.find("/")
		if slash_pos == -1: # not a dictionary
			if not key in object:
				push_warning("WARNING: '%s' not in '%s'; check config file" % [key, object])
				continue
			object.set(key, value)
		else: # dictionary w/ key
			var dict_name := key.left(slash_pos)
			var dict_key := key.substr(slash_pos + 1)
			if not dict_name in object:
				push_warning("WARNING: '%s' not in '%s'; check config file" % [key, object])
				continue
			var dict: Dictionary = object.get(dict_name)
			if value == null:
				dict.erase(dict_key)
			else:
				dict[dict_key] = value

