# initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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
extends Node

# Autoload singleton 'IVInitializer'. Modify properties in ivoyager.cfg or use
# an initializer GDScript. (It's also possible to remove, replace or rename
# this autoload in ivoyager.cfg, but that's probably not a good idea.)

var init_delay := 5 # frames


func _enter_tree() -> void:
#	IVConfigs.init_from_config(self, "res://ivoyager.cfg", "initializer_")
	var init_countdown := init_delay
	while init_countdown > 0:
		await get_tree().process_frame
		init_countdown -= 1


