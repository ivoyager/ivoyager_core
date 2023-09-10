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


const YMD := 20230910


func _enter_tree() -> void:
	# print version
	var plugin_cfg := ConfigFile.new()
	var err := plugin_cfg.load("res://addons/ivoyager_core/plugin.cfg")
	if err != OK:
		print("ERROR: Failed to load 'plugin.cfg'!")
		return
	var version: String = plugin_cfg.get_value("plugin", "version")
	if version.ends_with("-dev"):
		version += " " + str(YMD)
	print("I, Voyager - Core (plugin) v%s - https://ivoyager.dev" % version)
	
	# add autoload IVGlobal
#	add_autoload_singleton("IVGlobal", "global.gd")
	
	# add classes from ivoyager.cfg and/or ivoyager_overrides.cfg
	var ivoyager_cfg = ConfigFile.new()
	err = ivoyager_cfg.load("res://addons/ivoyager_core/ivoyager.cfg")
	if err != OK:
		print("ERROR: Failed to load 'ivoyager.cfg'!")
		return
	print(ivoyager_cfg.get_value("Test", "string_example"))


func _ready() -> void:
	pass


func _exit_tree() -> void:
	print("Removing I, Voyager - Core...")
#	remove_autoload_singleton("IVGlobal")

