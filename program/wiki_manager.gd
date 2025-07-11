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
## To enable external wiki, set [member open_external_page] = true. Set other
## properties for target url and default language (Wikipedia.org and "en" by default).
## Or connect to [signal wiki_requested] to manage an internal wiki.[br][br]
##
## [member default_language] will be overriden if there is a setting "wiki_language"
## that differs (requires restart).[br][br]
##
##
## WIP - Depricate [signal IVGlobal.wiki_requested]. All GUI must call API directly.



signal wiki_requested(page_title: String)


var open_external_page := false
var url_format := "https://%s.wikipedia.org/wiki/%s"
var default_language := "en" ## Overridden by setting "wiki_language", if present.

var _wiki_lookup := IVTableData.wiki_lookup
var _language: String



#var _wiki_titles: Dictionary = IVTableData.wiki_lookup
#var _wiki: String = IVGlobal.wiki # "wiki" (internal), "en.wikipedia", etc.
#var _wiki_url: String 



func _init() -> void:
	if !IVCoreSettings.enable_wiki:
		return
	IVGlobal.project_inited.connect(_on_project_inited)
	IVGlobal.wiki_requested.connect(_open)


func _on_project_inited() -> void:
	_language = default_language
	if IVGlobal.settings.has(&"wiki_language"):
		_language = IVGlobal.settings[&"wiki_language"]


func has_page(entity_name: StringName) -> bool:
	return _wiki_lookup.has(entity_name)


func open_page(entity_name: StringName) -> void:
	if !_wiki_lookup.has(entity_name):
		return
	var page_title := _wiki_lookup[entity_name]
	wiki_requested.emit(page_title)
	if open_external_page:
		OS.shell_open(url_format % [_language, page_title])


# DEPRICATE: Use function calls
func _open(page_title: String) -> void:
	wiki_requested.emit(page_title)
	OS.shell_open(url_format % [_language, page_title])
