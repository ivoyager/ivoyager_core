# universe.gd
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
class_name IVUniverse
extends Node3D

# DEPRICATE

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY ## Don't free on load.
const PERSIST_PROPERTIES: Array[StringName] = [&"persist"]


## This dictionary is not used by ivoyager_core but is available for game save
## persistence by external projects if ivoyager_save plugin is also
## present. It can hold Godot built-ins, nested containers or other 'persist 
## objects'. For details on save/load persistence, see
## [url]https://github.com/ivoyager/ivoyager_save[/url].
var persist := {}
