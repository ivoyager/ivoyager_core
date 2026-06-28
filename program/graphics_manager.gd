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

## Applies user graphics settings (antialiasing and directional shadow
## resolution) to the rendering server and main window viewport.
##
## Added by [IVCoreInitializer]. Settings [code]msaa_3d[/code], [code]fxaa[/code],
## [code]use_taa[/code] and [code]directional_shadow_size[/code] are defined in
## [IVSettingsManager] and exposed in [IVOptionsPopup]; this node applies them at
## startup and re-applies them live on change. [member msaa_settings] and [member
## shadow_size_settings] are the enumerations backing the MSAA and shadow dropdowns.
## [br][br]
##
## Renderer support differs: MSAA works in all renderers; FXAA is unavailable in
## the Compatibility renderer (including web exports); TAA is Forward+ only; and
## directional shadows are disabled on Compatibility (see [IVDynamicLight]).
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

## Enumeration backing the [code]directional_shadow_size[/code] dropdown in
## [IVOptionsPopup]. Mapped to a shadow atlas resolution in [method
## _apply_shadow_size]. Insertion order must equal value order (the popup uses
## the setting value as the dropdown item index).
var shadow_size_settings: Dictionary[StringName, int] = {
	SHADOW_2048 = 0,
	SHADOW_4096 = 1,
	SHADOW_8192 = 2,
	SHADOW_16384 = 3,
}

@onready var _window := get_tree().get_root()


func _ready() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	_apply_msaa()
	_apply_fxaa()
	_apply_taa()
	_apply_shadow_size()


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


func _apply_shadow_size() -> void:
	if IVGlobal.is_gl_compatibility:
		return # directional shadows are disabled on the Compatibility renderer
	var setting: int = IVSettingsManager.get_setting(&"directional_shadow_size")
	var size := 4096
	match setting:
		0:
			size = 2048
		2:
			size = 8192
		3:
			size = 16384
	RenderingServer.directional_shadow_atlas_set_size(size, false)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	match setting:
		&"msaa_3d":
			_apply_msaa()
		&"fxaa":
			_apply_fxaa()
		&"use_taa":
			_apply_taa()
		&"directional_shadow_size":
			_apply_shadow_size()
