# global.gd
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
extends Node

# Autoload singleton 'IVGlobal'. Modify or replace in ivoyager_overrides.cfg.

# project settings here



func _ready() -> void:
	# Override base settings from 'res://ivoyager_overrides.cfg'.
	var config_overrides := ConfigFile.new()
	var err := config_overrides.load("res://ivoyager_override.cfg")
	if err != OK:
		print("ERROR: IVGlobal failed to load 'res://ivoyager_override.cfg'!")
		return
	var override_properties := config_overrides.get_section_keys("global_overrides")
	for property in override_properties:
		if not property in self:
			print(("WARNING: Cannot set property '%s' from ivoyager_overrides.cfg"
					+ " because it does not exist in global.gd") % property)
			continue
		var value: Variant = config_overrides.get_value("global_overrides", property)
		set(property, value)
	var append_arrays := config_overrides.get_section_keys("global_array_appends")
	for property in append_arrays:
		if not property in self:
			print(("WARNING: Cannot append array '%s' from ivoyager_overrides.cfg"
					+ " because it does not exist in global.gd") % property)
			continue
		var append: Array = config_overrides.get_value("global_array_appends", property)
		var array: Array = get(property)
		array.append_array(append)
	var merge_dicts := config_overrides.get_section_keys("global_dictionary_override_merges")
	for property in merge_dicts:
		if not property in self:
			print(("WARNING: Cannot merge dictionary '%s' from ivoyager_overrides.cfg"
					+ " because it does not exist in global.gd") % property)
			continue
		var merge: Dictionary = config_overrides.get_value("global_dictionary_override_merges",
				property)
		var dict: Dictionary = get(property)
		dict.merge(merge, true)

	print(name, " ready...")


