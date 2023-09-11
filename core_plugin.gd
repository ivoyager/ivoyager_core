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

# *EVERYTHING* that this plugin does is specified by 'ivoyager.cfg' and
# 'ivoyager_override.cfg'. The latter is created in the project directory if
# it doesn't exist already. After modifying 'ivoyager_override.cfg', you can
# affect your changes by disabling and then re-enabling this plugin in your
# Project Settings.

const YMD := 20230910 # printed after version if version ends with '-dev'

var _config: ConfigFile # res://addons/ivoyager_core/ivoyager.cfg
var _config_override: ConfigFile # res://ivoyager_override.cfg
var _autoload_singletons: Array[String]


func _enter_tree() -> void:
	_print_plugin_version()
	_load_config()
	_load_or_create_config_override()
	if !_config or !_config_override:
		return
	_add_autoload_singletons.call_deferred()


func _exit_tree() -> void:
	print("Removing I, Voyager - Core...")
	_config = null
	_config_override = null
	_remove_autoload_singletons()


func _print_plugin_version() -> void:
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load("res://addons/ivoyager_core/plugin.cfg")
	if err != OK:
		print("ERROR: Failed to load 'plugin.cfg'!")
		return
	var version: String = plugin_cfg.get_value("plugin", "version")
	if version.ends_with("-dev"):
		version += " " + str(YMD)
	print("I, Voyager - Core (plugin) v%s - https://ivoyager.dev" % version)


func _load_config() -> void:
	_config = ConfigFile.new()
	var err := _config.load("res://addons/ivoyager_core/ivoyager.cfg")
	if err == OK:
		return
	print("ERROR: Failed to load 'res://addons/ivoyager_core/ivoyager.cfg'!")
	_config = null


func _load_or_create_config_override() -> void:
	_config_override = ConfigFile.new()
	var err := _config_override.load("res://ivoyager_override.cfg")
	if err == OK:
		# Print warning if config sections don't exactly match the template.
		var template_override = ConfigFile.new()
		template_override.load("res://addons/ivoyager_core/ivoyager_override.cfg")
		if _config_override.get_sections() != template_override.get_sections():
			print("WARNING: Sections in config file 'res://ivoyager_override.cfg' do not exactly "
					+ "match the template file 'res://addons/ivoyager_core/ivoyager_override.cfg'.")
			print("This may be due to a core plugin update. In any case, fix your file to match!")
		return
	print("Creating 'ivoyager_override.cfg' in your project directory.")
	print("Modify this file to change I, Voyager settings and classes.")
	var dir = DirAccess.open("res://addons/ivoyager_core/")
	err = dir.copy("res://addons/ivoyager_core/ivoyager_override.cfg", "res://ivoyager_override.cfg")
	if err != OK:
		print("ERROR: Failed to copy 'ivoyager_override.cfg' to the project directory!")
		_config_override = null
		return
	err = _config_override.load("res://ivoyager_override.cfg")
	if err != OK:
		print("ERROR: Failed to save 'res://ivoyager_override.cfg'!")
		_config_override = null


func _add_autoload_singletons() -> void:
	var paths: Dictionary = _config.get_value("autoloads", "paths")
	var overwrite: Dictionary = _config_override.get_value("autoloads",
			"merge_overwrite_autoload_paths")
	paths.merge(overwrite, true)
	for singleton_name in paths:
		_autoload_singletons.append(singleton_name)
		add_autoload_singleton(singleton_name, paths[singleton_name])


func _remove_autoload_singletons() -> void:
	while _autoload_singletons:
		var singleton_name: String = _autoload_singletons.pop_back()
		remove_autoload_singleton(singleton_name)



