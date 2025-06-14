# theme_manager.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
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
class_name IVThemeManager
extends RefCounted

## Populates [member IVGlobal.themes].


# project vars
var global_font := &"gui_main" # these are defined in IVFontManager
var main_menu_font := &"large"
var splash_screen_font := &"medium"

var _themes: Dictionary[StringName, Theme] = IVGlobal.themes
var _fonts: Dictionary[StringName, FontFile] = IVGlobal.fonts



func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)



func _on_project_objects_instantiated() -> void:
	# Make themes available in IVGlobal dictionary
	
	var main := Theme.new()
	_themes[&"main"] = main
	main.default_font = _fonts[global_font]
	var color_picker_button_stylebox := StyleBoxTexture.new()
	main.set_stylebox("normal", "ColorPickerButton", color_picker_button_stylebox) # remove border
	
	var main_menu := Theme.new()
	_themes[&"main_menu"] = main_menu
	main_menu.default_font = _fonts[main_menu_font]
	
	var splash_screen := Theme.new()
	_themes[&"splash_screen"] = splash_screen
	splash_screen.default_font = _fonts[splash_screen_font]
