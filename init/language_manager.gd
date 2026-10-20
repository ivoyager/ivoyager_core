# language_manager.gd
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
class_name IVLanguageManager
extends RefCounted

## Adds I, Voyager's translations and manages "Language" as a cached user option.
##
## At init, this class adds the translations in [member translations] to
## [TranslationServer], then sets the locale from the user's "language" setting.
## A preinitializer may remove any or all of them to opt out.[br][br]
##
## A project lists its own translations in Project Settings (Localization >
## Translations, which is [code]internationalization/locale/translations[/code]
## in project.godot). Godot adds those at startup, ahead of [member translations],
## and where two translations have the same key it uses the first one added. So a
## project overrides an I, Voyager text by giving its key new text in a
## translation listed there.[br][br]
##
## WARNING: The first-added rule holds among translations whose locale matches
## the current locale exactly, and any such match beats a partial one (e.g., a
## "de_DE" translation when the locale is "de"). This class sets language-only
## locales, so an overriding translation needs one too: a CSV column "de", not
## "de_DE".[br][br]
##
## To add a language, add its column to the CSV files, then add its code to
## [member language_codes], its "LANGUAGE_" text key to [member language_settings]
## and its .translation files to [member translations]. A key left empty in that
## column shows the text of Godot's fallback locale
## ([code]internationalization/locale/fallback[/code], "en" by default).[br][br]
##
## The user can change the language at runtime. GUI that holds a text key retranslates
## itself. GUI that composes its text from translated pieces must rebuild it: on
## [constant Node.NOTIFICATION_TRANSLATION_CHANGED] if it needs only [method
## Object.tr], or on [signal IVGlobal.ui_dirty], which this class emits after the
## change, if it also needs [IVQFormat] or [IVWikiManager], which follow the language
## only after the notification.[br][br]
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
## Language codes of the languages offered, in [member language_settings] order
## after LANGUAGE_AUTOMATIC. Automatic selects the system language if it is
## here, otherwise the first code.
static var language_codes: Array[String] = ["en"]
## Translation files added to [TranslationServer] at init: I, Voyager Core's and
## the Units plugin's. Read once, so modify it in a preinitializer.
static var translations: Array[String] = [
	"res://addons/ivoyager_core/text/chemicals_text.en.translation",
	"res://addons/ivoyager_core/text/entities_text.en.translation",
	"res://addons/ivoyager_core/text/gui_text.en.translation",
	"res://addons/ivoyager_core/text/hints_text.en.translation",
	"res://addons/ivoyager_core/text/keyboard_text.en.translation",
	"res://addons/ivoyager_core/text/long_text.en.translation",
	"res://addons/ivoyager_units/text/units_numbers_text.en.translation",
]



## Returns the language code that [param language_setting] selects. A setting
## outside [member language_settings] counts as automatic.
static func get_language_code_for_setting(language_setting: int) -> String:
	if language_setting > 0 and language_setting <= language_codes.size():
		return language_codes[language_setting - 1]
	var os_code := OS.get_locale_language() # "de" for system locale "de_DE"
	if language_codes.has(os_code):
		return os_code
	return language_codes[0]



func _init() -> void:
	assert(language_settings.size() == language_codes.size() + 1,
			"language_settings needs LANGUAGE_AUTOMATIC plus a key for each language code")
	var startup_locale := TranslationServer.get_locale()
	for path in translations:
		var translation: Translation = load(path)
		TranslationServer.add_translation(translation)
	var language_setting: int = IVSettingsManager.get_setting(&"language")
	_set_language(language_setting)
	if TranslationServer.get_locale() == startup_locale:
		# GUI already in the tree translated its text before these translations
		# existed, and only a locale change retranslates it.
		IVGlobal.get_tree().notification(MainLoop.NOTIFICATION_TRANSLATION_CHANGED)
	IVSettingsManager.changed.connect(_settings_listener)
	IVGlobal.translations_imported.emit()



func _set_language(language_setting: int) -> void:
	var code := get_language_code_for_setting(language_setting)
	TranslationServer.set_locale(code)
	IVQFormat.reset() # it keeps its own translated copies of unit and number names


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting == &"language":
		var language_setting: int = value
		_set_language(language_setting)
		if IVStateManager.started_or_about_to_start: # else the start emits it
			# Deferred because IVWikiManager hears this setting after this class.
			IVGlobal.ui_dirty.emit.call_deferred()
