# core_editor_plugin.gd
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

# This file adds autoloads and shader globals for ivoyager_core. You can change
# these by editing res://ivoyager_override.cfg in your project directory. See
# res://addons/ivoyager_core/core.cfg for base values and comments.
#
# If you modify autoloads or shader globals, you'll need to disable and re-
# enable the plugin (or quit and restart the editor) for your changes to have
# effect.

var _config: ConfigFile # with overrides

var _autoloads := {}
var _shader_globals := {}


func _enter_tree() -> void:
	await get_tree().process_frame # load after ivoyager_table_importer
	if !_is_enable_ok():
		_disable_self()
		return
	const plugin_utils := preload("plugin_utils.gd")
	plugin_utils.print_plugin_name_and_version("res://addons/ivoyager_core/plugin.cfg",
			" - https://ivoyager.dev")
	_config = plugin_utils.get_config_with_override("res://addons/ivoyager_core/core.cfg",
			"res://ivoyager_override.cfg", "core_")
	if !_config:
		return
	if !plugin_utils.config_exists("res://ivoyager_override.cfg"):
		_create_override_config()
	_add_autoloads()
	_add_shader_globals()


func _exit_tree() -> void:
	print("Removing I, Voyager - Core (plugin)")
	_config = null
	_remove_autoloads()
	_remove_shader_globals()


func _is_enable_ok() -> bool:
	if !get_editor_interface().is_plugin_enabled("ivoyager_table_importer"):
		push_warning("Cannot enable 'ivoyager_core' without 'ivoyager_table_reader'")
		return false
	return true


func _disable_self() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_editor_interface().set_plugin_enabled("ivoyager_core", false)


func _create_override_config() -> void:
	print(
		"\nCreating 'ivoyager_override.cfg' in your project directory. Modify this file to change\n"
		+ "autoload singletons, shader globals, base settings defined in singletons/core_settings.gd\n"
		+ "or base classes defined in singletons/core_initializer.gd.\n"
	)
	var dir = DirAccess.open("res://addons/ivoyager_core/")
	var err := dir.copy("res://addons/ivoyager_core/override_template.cfg",
			"res://ivoyager_override.cfg")
	if err != OK:
		print("ERROR: Failed to copy 'ivoyager_override.cfg' to the project directory!")


func _add_autoloads() -> void:
	for autoload_name in _config.get_section_keys("core_autoload"):
		var value: Variant = _config.get_value("core_autoload", autoload_name)
		if value: # could be null or "" to negate
			assert(typeof(value) == TYPE_STRING,
					"'%s' must specify a path as String" % autoload_name)
			_autoloads[autoload_name] = value
	for autoload_name in _autoloads:
#		await get_tree().process_frame
		var path: String = _autoloads[autoload_name]
		add_autoload_singleton(autoload_name, path)


func _remove_autoloads() -> void:
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

