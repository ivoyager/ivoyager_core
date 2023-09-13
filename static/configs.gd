# configs.gd
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
class_name IVConfigs
extends Object

# Static utility class for working with config files.


static func init_from_config(object: Object, cfg_path: String, section_prefix := "") -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(cfg_path)
	if err != OK:
		print("ERROR: Failed to load ", cfg_path)
		return
	
	var section := section_prefix + "overrides"
	if cfg.has_section(section):
		for property in cfg.get_section_keys(section):
			if not property in object:
				print("WARNING: Property '%s' in %s [%s] is not in %s; cannot modify!"
						% [property, cfg_path, section, object])
				continue
			var value: Variant = cfg.get_value(section, property)
			object.set(property, value)
	
	section = section_prefix + "array_erases"
	if cfg.has_section(section):
		for property in cfg.get_section_keys(section):
			if not property in object:
				print("WARNING: Property '%s' in %s [%s] is not in %s; cannot modify!"
						% [property, cfg_path, section, object])
				continue
			var array: Array = object.get(property)
			var erases: Array = cfg.get_value(section, property)
			for value in erases:
				array.erase(value)
	
	section = section_prefix + "array_appends"
	if cfg.has_section(section):
		for property in cfg.get_section_keys(section):
			if not property in object:
				print("WARNING: Property '%s' in %s [%s] is not in %s; cannot modify!"
						% [property, cfg_path, section, object])
				continue
			var array: Array = object.get(property)
			var append: Array = cfg.get_value(section, property)
			array.append_array(append)
	
	section = section_prefix + "dictionary_merge_overwrite_erase_nulls"
	if cfg.has_section(section):
		for property in cfg.get_section_keys(section):
			if not property in object:
				print("WARNING: Property '%s' in %s [%s] is not in %s; cannot modify!"
						% [property, cfg_path, section, object])
				continue
			var dict: Dictionary = object.get(property)
			var merge_erase: Dictionary = cfg.get_value(section, property)
			dict.merge(merge_erase, true)
			for key in merge_erase:
				if merge_erase[key] == null:
					dict.erase(key)
