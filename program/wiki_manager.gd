# wiki_manager.gd
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
class_name IVWikiManager
extends RefCounted

## Centralizes wiki page requests and (if enabled) opens external wiki pages.
##
## This manager can be removed if external project does not use a wiki.[br][br]
##
## This manager uses language-specific "page title" dictionaries in
## [member IVTableData.wiki_page_titles_by_field]. To populate these,
## append wiki field names to [member IVTableInitializer.wiki_page_title_fields].[br][br]
##
## To enable external wiki, set [member open_external_page] = true. Set other
## properties for target url and default language as needed (by default, these
## are Wikipedia.org and English). To open an internal wiki, connect to
## [signal wiki_requested].[br][br]
##
## [member external_default_language] will be overriden if there is a setting
## "external_wiki_language".[br][br]
##
## TODO: IVLanguageManager and setting "language". Changing the language setting
## changes external url here from dictionary.
##

signal wiki_requested(page_title: String)


var page_title_table_field := &"en.wiki"

var open_external_page := false
var external_url_format := "https://%s.wikipedia.org/wiki/%s"
var external_default_language := "en" ## Manager uses setting "external_wiki_language" if present.


var _wiki_page_titles: Dictionary[StringName, String]
var _external_language: String



func _init() -> void:
	IVGlobal.project_inited.connect(_on_project_inited)



func has_page(entity_name: StringName) -> bool:
	return _wiki_page_titles.has(entity_name)


func open_page(entity_name: StringName) -> void:
	if !_wiki_page_titles.has(entity_name):
		return
	var page_title := _wiki_page_titles[entity_name]
	wiki_requested.emit(page_title)
	if open_external_page:
		OS.shell_open(external_url_format % [_external_language, page_title])



func _on_project_inited() -> void:
	if IVTableData.wiki_page_titles_by_field.has(page_title_table_field):
		_wiki_page_titles = IVTableData.wiki_page_titles_by_field[page_title_table_field]
	_external_language = external_default_language
	if IVGlobal.settings.has(&"external_wiki_language"):
		_external_language = IVGlobal.settings[&"external_wiki_language"]
	IVGlobal.setting_changed.connect(_settings_listener)


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting == &"external_wiki_language":
		_external_language = value
