# state_auxiliary.gd
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
class_name IVStateAuxiliary
extends RefCounted

## Provides class-specific API for state management.
##
## This component exists to decouple [IVStateManager] and keep its API
## general-use. All methods and signals are intended for class-specific use
## only.[br][br]

# Dev note: Don't add any non-Godot class dependencies!

# To IVStateManager
## Emitted from [IVAssetPreloader] (via [method set_asset_preloader_finished])
## to notify [IVStateManager] that asset preloading has completed.
signal asset_preloader_finished()
## Emitted from [IVSaveManager] to notify [IVStateManager] that procedural
## nodes are about to be freed prior to a game load.
signal about_to_free_procedural_nodes_for_load()
## Emitted from [IVSaveManager] when game load has begun.
signal game_loading()
## Emitted from [IVSaveManager] when game load has completed.
## [param user_paused_on_load] preserves the saved user-pause state.
signal game_loaded(user_paused_on_load: bool)
## Emitted to track outstanding system-tree-build work; [param incr] is +1
## (work started) or -1 (work finished).
signal tree_building_count_changed(incr: int)

# From IVStateManager
## Signal from [IVStateManager] to [IVTableSystemBuilder] to build the system
## tree.
signal ready_for_system_tree_build()


## IVAssetPreloader only.
func set_asset_preloader_finished() -> void:
	asset_preloader_finished.emit()


## IVSaveManager only.
func set_about_to_free_procedural_nodes_for_load() -> void:
	about_to_free_procedural_nodes_for_load.emit()


## IVSaveManager only.
func set_game_loading() -> void:
	game_loading.emit()


## IVSaveManager only.
func set_game_loaded(user_paused_on_load: bool) -> void:
	game_loaded.emit(user_paused_on_load)


## Increments or decrements the system-tree-build counter. [param incr] must
## be exactly +1 or -1. Emits [signal tree_building_count_changed].
func change_tree_building_count(incr: int) -> void:
	assert(absi(incr) == 1)
	tree_building_count_changed.emit(incr)
