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

## Manages response to [code]open_wiki_requested[/code] signal from IVGlobal.
##
## FIXME: Many loose ends after shift to Table Importer plugin...
##
## For internal wiki, set IVCoreSettings.enable_wiki and IVCoreSettings.use_internal_wiki. You
## can then either 1) extend this class and override _open_internal_wiki(), or
## 2) hook up directly to IVGlobal signal "open_wiki_requested". If the latter,
## you can safely erase this class from IVCoreInitializer.prog_refs.


#var _wiki_titles: Dictionary = IVTableData.wiki_lookup
var _wiki: String = IVGlobal.wiki # "wiki" (internal), "en.wikipedia", etc.
var _wiki_url: String 



func _init() -> void:
	if !IVCoreSettings.enable_wiki:
		return
	IVGlobal.open_wiki_requested.connect(_open_wiki)
	if !IVCoreSettings.use_internal_wiki:
		_wiki_url = "https://" + _wiki + ".org/wiki/"



func _open_wiki(wiki_title: String) -> void:
	if _wiki_url:
		var url := _wiki_url + wiki_title
		prints("Opening external link:", url)
		OS.shell_open(url)
	else:
		_open_internal_wiki(wiki_title)


func _open_internal_wiki(_wiki_title: String) -> void:
	pass
