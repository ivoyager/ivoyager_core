# version_label.gd
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
class_name IVVersionLabel
extends Label

## Label widget that displays project version with prepended or appended text.
##
## Gets project version from ProjectSettings/application/config/version.
##
## Godot ISSUE as of 4.5.1: Prepending "something\nv" doesn't create a line
## break, even though paragraph_separator is default "\\n"

## Prepended text. E.g., "v" if not included in ProjectSettings.
@export var prepend := ""
## Appended text.
@export var append := ""


func _ready() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version")
	text = prepend + version + append
