# language_manager.gd
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
class_name IVLanguageManager
extends RefCounted

## Manages localization and allows for "Language" as a cached user option.
##
## We're ready for localization! Please let us know if you can do a
## translation at [url]https://github.com/orgs/ivoyager/discussions[/url].


## User settings/options used by [IVSettingsManager] and [IVOptionsPopup].
## These classes expect a sequential enum-like dictionary (values 0, 1, ...).
## Setting 0 is expected to be "automatic" (get from operating system).
static var language_settings: Dictionary[StringName, int] = {
	LANGUAGE_AUTOMATIC = 0,
	LANGUAGE_EN = 1,
}
## Language codes for all existing translations. Order here must match
## [member language_settings] (skipping LANGUAGE_AUTOMATIC). The first
## element is used as the fallback language.
static var language_codes: Array[String] = ["en"]



static func get_code_for_setting(language_setting: int) -> String:
	if language_setting == 0:
		var os_code := OS.get_locale_language() # returns "en", not "en_US"
		if language_codes.has(os_code):
			return os_code
		return language_codes[0]
	return language_codes[language_setting - 1]



func _init() -> void:
	IVGlobal.setting_changed.connect(_settings_listener)
	var language_setting: int = IVGlobal.settings[&"language"]
	_set_language(language_setting)



func _set_language(language_setting: int) -> void:
	var code := get_code_for_setting(language_setting)
	TranslationServer.set_locale(code)


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting == &"language":
		var language_setting: int = value
		_set_language(language_setting)
