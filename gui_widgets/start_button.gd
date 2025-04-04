# start_button.gd
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
class_name IVStartButton
extends Button



func _ready() -> void:
	IVGlobal.state_changed.connect(_on_state_changed)


func _pressed() -> void:
	disabled = true
	_start.call_deferred() # let button disable


func _start() -> void:
	IVGlobal.start_requested.emit()


func _on_state_changed(state: Dictionary[StringName, Variant]) -> void:
	disabled = !state.is_ok_to_start
