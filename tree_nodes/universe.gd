# universe.gd
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
class_name IVUniverse
extends Node3D

# *****************************************************************************
#
#          Developers! Look in these files to get started:
#             res://addons/ivoyager_core/singletons/core_initializer.gd
#             res://addons/ivoyager_core/singletons/core_settings.gd
#             res://ivoyager_override.cfg
#
# *****************************************************************************

## Default simulator root node.
##
## An instance of this class named 'Universe' is the main scene and simulator
## root node in [url=https://github.com/ivoyager]I, Voyager's Planetarium and
## Project Template[/url]. To change this, have a Node3D named 'Universe' in
## the scene tree or set member [code]universe[/code] or [code]universe_path[/code]
## in IVCoreInitializer ["addons/ivoyager_core/singletons/core_initializer.gd"].[br][br]
##
## We use origin shifting to prevent 'imprecision shakes' caused by vast scale
## differences, e.g, when viewing a small body at 1e9 km from the sun. To do
## so, [IVCamera] adjusts the translation of this node (or substitute root
## node) every frame.[br][br]
##
## If [code]pause_only_stops_time = true[/code] in IVCoreSettings
## (["addons/ivoyager_core/singletons/core_settings.gd"]), then [IVStateManager]
## will set [code]pause_mode = PAUSE_MODE_PROCESS[/code] in this node and in
## [IVTopGUI]. In this mode, [IVCamera] can still move, visuals work (some are
## responsve to camera) and user can interact with the world, and only
## [IVTimekeeper] pauses to stop time.

const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY ## Don't free on load.
const PERSIST_PROPERTIES: Array[StringName] = [&"persist"]


## This dictionary is not used by ivoyager_core but is available for game save
## persistence by external projects if ivoyager_tree_saver plugin is also
## present. It can hold Godot built-ins, nested containers or other 'persist 
## objects'. For details on save/load persistence, see
## [url]https://github.com/ivoyager/ivoyager_tree_saver[/url].
var persist := {}
