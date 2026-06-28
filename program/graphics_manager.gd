# graphics_manager.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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
class_name IVGraphicsManager
extends Node

## Applies user antialiasing settings to the main window viewport.
##
## Added by [IVCoreInitializer]. Settings [code]msaa_3d[/code], [code]fxaa[/code]
## and [code]use_taa[/code] are defined in [IVSettingsManager] and exposed in
## [IVOptionsPopup]; this node applies them at startup and re-applies them live
## on change. [member msaa_settings] is the enumeration backing the MSAA option
## dropdown.[br][br]
##
## Renderer support differs: MSAA works in all renderers; FXAA is unavailable in
## the Compatibility renderer (including web exports); TAA is Forward+ only.
## Unsupported settings are skipped here and hidden by [IVOptionsPopup].

## Enumeration backing the [code]msaa_3d[/code] dropdown in [IVOptionsPopup].
## Values match [enum Viewport.MSAA]. Insertion order must equal value order
## (the popup uses the setting value as the dropdown item index).
var msaa_settings: Dictionary[StringName, int] = {
	MSAA_DISABLED = 0,
	MSAA_2X = 1,
	MSAA_4X = 2,
	MSAA_8X = 3,
}

@onready var _window := get_tree().get_root()


func _ready() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	_apply_msaa()
	_apply_fxaa()
	_apply_taa()


func _apply_msaa() -> void:
	var setting: int = IVSettingsManager.get_setting(&"msaa_3d")
	match setting:
		1:
			_window.msaa_3d = Viewport.MSAA_2X
		2:
			_window.msaa_3d = Viewport.MSAA_4X
		3:
			_window.msaa_3d = Viewport.MSAA_8X
		_:
			_window.msaa_3d = Viewport.MSAA_DISABLED


func _apply_fxaa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # FXAA unsupported in the Compatibility renderer (incl. web)
	var enable_fxaa: bool = IVSettingsManager.get_setting(&"fxaa")
	_window.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if enable_fxaa
			else Viewport.SCREEN_SPACE_AA_DISABLED)


func _apply_taa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # TAA is Forward+ only
	var enable_taa: bool = IVSettingsManager.get_setting(&"use_taa")
	_window.use_taa = enable_taa


func _settings_listener(setting: StringName, _value: Variant) -> void:
	match setting:
		&"msaa_3d":
			_apply_msaa()
		&"fxaa":
			_apply_fxaa()
		&"use_taa":
			_apply_taa()
