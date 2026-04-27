# assets_dialog.gd
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
@tool
extends AcceptDialog
class_name IVAssetsDialog

## Editor-only AcceptDialog that prompts the user to download or update
## [code]res://addons/ivoyager_assets[/code].
##
## Popped up by [IVEditorPlugin] when the assets directory is missing or its
## version doesn't match the version specified in the plugin config. Pressing
## "Download" hands off to [IVAssetsLoader].


const ASSETS_REPOSITORY := "https://github.com/ivoyager/asset_downloads"

## Dialog text (with one [code]%s[/code] for expected version) used when no
## ivoyager_assets directory is present.
const MISSING_FORMAT := """I, Voyager requires assets to run!

Press "Download" to download assets v%s and install at res://addons/ivoyager_assets.

Press "Close" to manage assets manually.
"""

## Dialog text (with three [code]%s[/code] slots for present, expected, expected
## versions) used when ivoyager_assets is present but at the wrong version.
const MISMATCH_FORMAT := """res://addons/ivoyager_assets v%s does not match expected v%s.

Press "Download" to download v%s and replace existing ivoyager_assets.

Press "Close" to manage assets manually.
"""

@onready var _close_button := add_cancel_button("Close")
@onready var _progress_bar: ProgressBar = %ProgressBar



func _ready() -> void:
	dialog_hide_on_ok = false
	ok_button_text = "Download"
	set_unparent_when_invisible(true)
	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)
	(%RepositoryRTL as RichTextLabel).meta_clicked.connect(_on_meta_clicked)


## Sets the dialog body text. Pass an empty [param present_version] (the
## default) when there's no existing assets directory.
func update_dialog(expected_version: String, present_version := "") -> void:
	var label := %DialogLabel as Label
	if present_version == "":
		label.text = MISSING_FORMAT % expected_version
	else:
		label.text = MISMATCH_FORMAT % [present_version, expected_version, expected_version]


## Updates the progress bar; intended to be connected to
## [signal IVAssetsLoader.progress_changed].
func update_progress(progress: float) -> void:
	_progress_bar.value = progress


func _on_confirmed() -> void:
	get_ok_button().disabled = true
	_close_button.disabled = true
	_progress_bar.remove_theme_color_override(&"font_color")
	(%DownloadLabel as Label).remove_theme_color_override(&"font_color")


func _on_meta_clicked(_meta: Variant) -> void:
	OS.shell_open(ASSETS_REPOSITORY)
