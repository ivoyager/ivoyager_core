# link_label.gd
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
class_name IVLinkLabel
extends RichTextLabel

## GUI widget that facilitates hyperlinks
##
## If [member open_external_url] == false (default), the link "url" value
## will be passed to [method IVWikiManager.open_page]. Set [param text] using
## an entity_name that exist in your internal or external wiki. Example
## [param text] value:
##
## [codeblock]
## [url="PLANET_EARTH"]Earth[/url]
## [/codeblock][br]
##
## If [member open_external_url] == true, this widget will open the specified
## external URL. Example [param text] value:
##
## [codeblock]
## [url="https://ivoyager.dev"]I, Voyager[/url]
## [/codeblock][br]
##
## Note that [param text] can also be set to a translation key that resolves
## to valid bbcode as above.[br][br]
##
## If changing text dynamically, it's sometimes better to call [method parse_bbcode]
## than to set [member text] directly.[br][br]
##
## This widget is parameterized for "short" labels with [param scroll_active]
## == false. But that can be edited. 

## Set true to open external URL. Otherwise, bbcode "url" value will be passed
## to [method IVWikiManager.open_page].
@export var open_external_url := false



func _ready() -> void:
	meta_clicked.connect(_on_meta_clicked)


func _on_meta_clicked(url: String) -> void:
	if open_external_url:
		prints("Opening external link:", url)
		OS.shell_open(url)
		return
	var wiki_manager: IVWikiManager = IVGlobal.program.get(&"WikiManager")
	if wiki_manager:
		wiki_manager.open_page(url)
