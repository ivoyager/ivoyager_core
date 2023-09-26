# core_plugin.gd
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
extends EditorPlugin

# EVERYTHING that this plugin does is specified by 'res://addons/ivoyager_core/
# ivoyager_core.cfg' and 'res://ivoyager_override.cfg'. The latter is created
# in your project directory if it doesn't exist already.
#
# You can modify ivoyager_core functionality by:
#
#   1. Modifying 'res://ivoyager_override.cfg' (to change anything), or
#   2. Modifying IVInitializer and IVGlobal values and dictionaries via script
#      (to change anything except autoloads and shader globals).
#
# If you modify autoloads or shader globals, you'll need to disable and re-
# enable the plugin (or quit and restart the editor) for your changes to have
# effect.

const configs := preload("res://addons/ivoyager_core/static/configs.gd")

var _config: ConfigFile # with overrides

var _autoloads := {}
var _shader_globals := {}


func _enter_tree() -> void:
	configs.print_plugin_with_version("res://addons/ivoyager_core/plugin.cfg",
			" - https://ivoyager.dev")
	_config = configs.get_config_with_override("res://addons/ivoyager_core/ivoyager_core.cfg",
			"res://ivoyager_override.cfg", true, "core_")
	if !_config:
		return
	if !configs.config_exists("res://ivoyager_override.cfg"):
		_create_override_config()
	_add_autoloads.call_deferred()
	_add_shader_globals.call_deferred()


func _exit_tree() -> void:
	print("Removing I, Voyager - Core (plugin)")
	_config = null
	_remove_autoload_singletons()
	_remove_shader_globals()


func _create_override_config() -> void:
	print(
		"\nCreating 'ivoyager_override.cfg' in your project directory. Modify this file to\n"
		+ "change autoload singletons, shader globals, IVGlobal settings, or IVInitializer\n"
		+ "program classes.\n"
	)
	var override_config := ConfigFile.new()
	var err := override_config.save("res://ivoyager_override.cfg")
	assert(err == OK, "Failed to save 'res://ivoyager_override.cfg'")


func _add_autoloads() -> void:
	for autoload_name in _config.get_section_keys("core_autoload"):
		var value: Variant = _config.get_value("core_autoload", autoload_name)
		if value: # could be null or "" to negate
			assert(typeof(value) == TYPE_STRING,
					"'%s' must specify a path as String" % autoload_name)
			_autoloads[autoload_name] = value
	for autoload_name in _autoloads:
		var path: String = _autoloads[autoload_name]
		add_autoload_singleton(autoload_name, path)


func _remove_autoload_singletons() -> void:
	for autoload_name in _autoloads:
		remove_autoload_singleton(autoload_name)
	_autoloads.clear()


func _add_shader_globals() -> void:
	for global_name in _config.get_section_keys("core_shader_globals"):
		var value: Variant = _config.get_value("core_shader_globals", global_name)
		if value: # could be null or {} to negate
			assert(typeof(value) == TYPE_DICTIONARY,
				"'%s' must specify a Dictionary" % global_name)
			_shader_globals[global_name] = value
	for global_name in _shader_globals:
		var dict: Dictionary = _shader_globals[global_name]
		ProjectSettings.set_setting("shader_globals/" + global_name, dict)
		# These don't show up in editor menu immediately, but are in project.godot
		# and show up in editor menu after restart.
	ProjectSettings.save() # Does this do anything...???


func _remove_shader_globals() -> void:
	for global_name in _shader_globals:
		ProjectSettings.set_setting("shader_globals/" + global_name, null)
	ProjectSettings.save() # Does this do anything...???
	_shader_globals.clear()

