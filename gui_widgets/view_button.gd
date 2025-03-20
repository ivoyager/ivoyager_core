# view_button.gd
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
class_name IVViewButton
extends Button

## GUI widget.
##
## Pre-built (default) buttons must have pre-set text that is a key in
## IVViewManager.table_views, e.g., "VIEW_HOME", "VIEW_ZOOM", etc. (not the
## translated name).
##
## TODO: Make this class work as user-added too. (Those are presently a
## subclass in IVViewSaveFlow.)

var _is_default_button: bool


func _init(is_default_button := true) -> void:
	_is_default_button = is_default_button


func _ready() -> void:
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	assert(view_manager.has_table_view(text), "No default view with name = " + text)
	pressed.connect(view_manager.set_table_view.bind(text))
