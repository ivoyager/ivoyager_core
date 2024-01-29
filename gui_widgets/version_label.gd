# version_label.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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

# GUI widget.
#
# If IVCoreSettings.project_name == "", will show ivoyager_core version.


var use_name := false
var multiline := true # <project_name>\n<version> or use space


func _ready() -> void:
	set_label()


func set_label() -> void:
	# Call directly if properties changed after added to tree.
	var sep := "\n" if multiline else " "
	var is_project := IVCoreSettings.project_name != ""
	text = ""
	if use_name:
		text += (IVCoreSettings.project_name if is_project else "I, Voyager") + sep
	text += IVCoreSettings.project_version if is_project else IVGlobal.ivoyager_version

