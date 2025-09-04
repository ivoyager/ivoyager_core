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
## This manager is not added in base configuration! Add it to
## [member IVCoreInitializer.program_refcounteds] if needed.[br][br]
##
## This manager uses language-specific "page titles" that are specified in *.tsv
## data tables for table entities or wiki-linked text keys. Relevant dictionaries
## are in [IVTableData]. To populate these dictionaries, wiki field names must
## be specified in the call to [method IVTableData.postprocess_tables] by
## appending to [member IVTableInitializer.wiki_page_title_fields].[br][br]
##
## To enable external wiki pages (e.g., Wikipedia.org), set [member open_external_page]
## to [code]true[/code] and add to or modify [member external_url_formats] for
## supported languages.[br][br]
##
## To implement an internal wiki, connect to [signal wiki_requested]. You'll
## likely want to create and specify new page title field(s) in your data tables.


## Connect to implement an internal wiki mechanic. (I, Voyager Core emits but
## does not connect to this signal.)
signal wiki_requested(page_title: String)


## Set true to open external URL specified in [member external_url_formats].
var open_external_page := false
## Table column field names indexed by language codes.
var table_fields: Dictionary[StringName, StringName] = {
	en = &"en.wikipedia"
}
## External URL format strings indexed by language codes. Page title will be
## inserted at "%s". Used only if [member open_external_page] == true. If used,
## this dictionary must have the same keys as [member table_fields].
var external_url_formats: Dictionary[StringName, String] = {
	en = "https://en.wikipedia.org/wiki/%s"
}
## Fallback if the current language code is not in [member table_fields].
var fallback_language_code := &"en"


var _wiki_page_titles: Dictionary[StringName, String]
var _external_url_format: String



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
		OS.shell_open(_external_url_format % page_title)


func _on_project_inited() -> void:
	if IVTableData.wiki_page_titles_by_field.is_empty():
		push_warning("IVWikiManager is present but no page title fields were set in IVTableData")
		# Bail out here: has_page() will always return false & open_page() does nothing.
		return
	var fallback_table_field := table_fields[fallback_language_code]
	assert(IVTableData.has_wiki_page_titles(fallback_table_field), "Fallback table field not found")
	IVGlobal.setting_changed.connect(_settings_listener)
	_set_language()


func _set_language() -> void:
	var language_setting: int = IVGlobal.settings[&"language"]
	var code := IVLanguageManager.get_code_for_setting(language_setting)
	if !table_fields.has(code):
		code = fallback_language_code
	var table_field := table_fields[code]
	assert(IVTableData.has_wiki_page_titles(table_field))
	_wiki_page_titles = IVTableData.get_wiki_page_titles(table_field)
	if !open_external_page:
		return
	assert(external_url_formats.has(code))
	_external_url_format = external_url_formats[code]


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"language":
		_set_language()
