# log_initializer.gd
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
class_name IVLogInitializer
extends RefCounted

# Inits a debug file specified in IVCoreSettings when in debug mode.

func _init() -> void:
	if !OS.is_debug_build() or !IVCoreSettings.debug_log_path:
		return
	# TEST34
	var debug_log := FileAccess.open(IVCoreSettings.debug_log_path, FileAccess.WRITE)
	if !debug_log:
		print("ERROR! Could not open debug log at ", IVCoreSettings.debug_log_path)
		return
	IVGlobal.debug_log = debug_log
	IVGlobal.initializers_inited.connect(_remove_self)


func _remove_self() -> void:
	IVGlobal.program.erase(&"LogInitializer")
