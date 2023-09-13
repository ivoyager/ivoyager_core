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
var _cfg: ConfigFile # res://ivoyager.cfg
var _autoload_singletons: Array[String]


func _enter_tree() -> void:
	_print_plugin_version()
	_load_base_cfg()
	_load_or_create_cfg()
	if !_base_cfg or !_cfg:
		return
	_add_autoload_singletons.call_deferred()


func _exit_tree() -> void:
	print("Removing I, Voyager - Core (plugin)")
	_base_cfg = null
	_cfg = null
	_remove_autoload_singletons()


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


func _load_or_create_cfg() -> void:
	_cfg = ConfigFile.new()
	var err := _cfg.load("res://ivoyager.cfg")
	if err == OK:
		# Print warning if config sections don't exactly match the template.
		var template_cfg = ConfigFile.new()
		template_cfg.load("res://addons/ivoyager_core/ivoyager_template.cfg")
		if _cfg.get_sections() != template_cfg.get_sections():
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
		_cfg = null
		return
	err = _cfg.load("res://ivoyager.cfg")
	if err != OK:
		print("ERROR: Failed to save 'res://ivoyager.cfg'!")
		_cfg = null


func _add_autoload_singletons() -> void:
	var paths: Dictionary = _base_cfg.get_value("autoloads", "paths")
	var overwrite: Dictionary = _cfg.get_value("autoloads",
			"merge_overwrite_autoload_paths")
	paths.merge(overwrite, true)
	for singleton_name in paths:
		var path: String = paths[singleton_name]
		if path:
			_autoload_singletons.append(singleton_name)
			add_autoload_singleton(singleton_name, path)


func _remove_autoload_singletons() -> void:
	while _autoload_singletons:
		var singleton_name: String = _autoload_singletons.pop_back()
		remove_autoload_singleton(singleton_name)



