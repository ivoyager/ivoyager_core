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

## A [RichTextLabel] widget that facilitates hyperlinks
##
## If [member open_external_url] is false (default), the link "url" value
## will be passed to [method IVWikiManager.open_page]. Set [param text] using
## an entity_name that exist in your internal or external wiki. Example
## [param text]:
##
## [codeblock]
## [url=PLANET_EARTH]Earth[/url]
## [/codeblock][br]
##
## If [member open_external_url] is true, this widget will open the specified
## external URL directly. Example [param text]:
##
## [codeblock]
## Visit our homepage at [url=https://ivoyager.dev]I, Voyager[/url]!
## [/codeblock][br]
##
## [param text] can also be set to a translation key that resolves to valid
## bbcode as above.[br][br]
##
## If changing text dynamically, it's better to call [method parse_bbcode]
## than to set [member text] directly.[br][br]
##
## By default, this widget is parameterized for "short" texts without scroll
## or autowrap and with fit_content == true (so it acts like a Label in a
## Container context). Edit [RichTextLabel] properties if something different
## is needed. 

const SCENE := "res://addons/ivoyager_core/gui_widgets/link_label.tscn"


## Set true to open an external URL directly. Otherwise, bbcode "url" value
## will be passed to [method IVWikiManager.open_page].
@export var open_external_url := false



@warning_ignore("shadowed_variable_base_class", "shadowed_variable")
static func create(text: String, open_external_url := false) -> IVLinkLabel:
	var label: IVLinkLabel = (load(SCENE) as PackedScene).instantiate()
	label.text = text
	label.open_external_url = open_external_url
	return label


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
