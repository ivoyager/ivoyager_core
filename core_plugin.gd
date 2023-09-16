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

# *EVERYTHING* that this plugin does is specified by 'ivoyager_base.cfg' and
# 'ivoyager.cfg'. The latter is created in the project directory if
# it doesn't exist already. After modifying 'ivoyager.cfg', you can
# affect your changes by disabling and then re-enabling this plugin in your
# Project Settings.

var _base_cfg: ConfigFile # res://addons/ivoyager_core/ivoyager_base.cfg
var _override_cfg: ConfigFile # res://ivoyager.cfg
var _autoloads := {}
var _shader_globals := {}


func _enter_tree() -> void:
	_print_plugin_version()
	_load_base_cfg()
	_load_or_create_override_cfg()
	if !_base_cfg or !_override_cfg:
		return
	_add_autoloads.call_deferred()
	_add_shader_globals.call_deferred()


func _exit_tree() -> void:
	print("Removing I, Voyager - Core (plugin)")
	_base_cfg = null
	_override_cfg = null
	_remove_autoload_singletons()
	_remove_shader_globals()


func _print_plugin_version() -> void:
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load("res://addons/ivoyager_core/plugin.cfg")
	if err != OK:
		print("ERROR: Failed to load 'plugin.cfg'!")
		return
	var version: String = plugin_cfg.get_value("plugin", "version")
	print("I, Voyager - Core (plugin) v%s - https://ivoyager.dev" % version)


func _load_base_cfg() -> void:
	_base_cfg = ConfigFile.new()
	var err := _base_cfg.load("res://addons/ivoyager_core/ivoyager_base.cfg")
	if err == OK:
		return
	print("ERROR: Failed to load 'res://addons/ivoyager_core/ivoyager_base.cfg'!")
	_base_cfg = null


func _load_or_create_override_cfg() -> void:
	_override_cfg = ConfigFile.new()
	var err := _override_cfg.load("res://ivoyager.cfg")
	if err == OK:
		# Print warning if config sections don't exactly match the template.
		var template_cfg = ConfigFile.new()
		template_cfg.load("res://addons/ivoyager_core/ivoyager_template.cfg")
		if _override_cfg.get_sections() != template_cfg.get_sections():
			print("WARNING: Sections in config file 'res://ivoyager.cfg' do not exactly")
			print("match the template 'res://addons/ivoyager_core/ivoyager_template.cfg'.")
			print("This may be due to a core plugin update. In any case, fix your file to match!")
		return
	print("Creating 'ivoyager.cfg' in your project directory. Modify this file to to change")
	print("global program settings or to remove or replace autoloads or core classes used")
	print("by the plugin.")
	var dir = DirAccess.open("res://addons/ivoyager_core/")
	err = dir.copy("res://addons/ivoyager_core/ivoyager_template.cfg", "res://ivoyager.cfg")
	if err != OK:
		print("ERROR: Failed to copy 'ivoyager.cfg' to the project directory!")
		_override_cfg = null
		return
	err = _override_cfg.load("res://ivoyager.cfg")
	if err != OK:
		print("ERROR: Failed to save 'res://ivoyager.cfg'!")
		_override_cfg = null


func _add_autoloads() -> void:
	for autoload_name in _base_cfg.get_section_keys("autoload"):
		_autoloads[autoload_name] = _base_cfg.get_value("autoload", autoload_name)
	if _override_cfg.has_section("autoload_overrides"):
		for autoload_name in _override_cfg.get_section_keys("autoload_overrides"):
			var path_or_null: Variant = _override_cfg.get_value("autoload_overrides", autoload_name)
			if !path_or_null: # "" or null
				_autoloads.erase(autoload_name)
				continue
			_autoloads[autoload_name] = path_or_null
	for autoload_name in _autoloads:
		var path: String = _autoloads[autoload_name]
		add_autoload_singleton(autoload_name, path)


func _remove_autoload_singletons() -> void:
	for autoload_name in _autoloads:
		remove_autoload_singleton(autoload_name)
	_autoloads.clear()


func _add_shader_globals() -> void:
	for global_name in _base_cfg.get_section_keys("shader_globals"):
		_shader_globals[global_name] = _base_cfg.get_value("shader_globals", global_name)
	if _override_cfg.has_section("shader_globals_overrides"):
		for global_name in _override_cfg.get_section_keys("shader_globals_overrides"):
			var dict_or_null: Variant = _override_cfg.get_value("shader_globals_overrides", global_name)
			if !dict_or_null: # empty dict or null
				_shader_globals.erase(global_name)
				continue
			_shader_globals[global_name] = dict_or_null
	for global_name in _shader_globals:
		var dict: Dictionary = _shader_globals[global_name]
		ProjectSettings.set_setting("shader_globals/" + global_name, dict)
		# These don't show up in editor menu, but are in project.godot and show
		# up after restart.
	ProjectSettings.save() # Does this do anything...???


func _remove_shader_globals() -> void:
	for global_name in _shader_globals:
		ProjectSettings.set_setting("shader_globals/" + global_name, null)
	ProjectSettings.save() # Does this do anything...???
	_shader_globals.clear()

