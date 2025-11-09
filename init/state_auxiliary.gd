# state_auxiliary.gd
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
class_name IVStateAuxiliary
extends RefCounted

## Provides specific class API for state management.
##
## All methods are intended for specific class use only. This is to decouple
## [IVStateManager] and keep its API general use.[br][br]
##
## Dev note: Don't add [i]any[/i] non-Godot class dependencies!

signal asset_preloader_finished()
signal about_to_free_procedural_nodes()
signal game_loading()
signal game_loaded(is_user_pause: bool)
signal engine_paused_changed(engine_paused: bool)
signal tree_building_count_changed(incr: int)


## IVAssetPreloader only.
func set_asset_preloader_finished() -> void:
	asset_preloader_finished.emit()


## IVSaveManager only.
func set_about_to_free_procedural_nodes() -> void:
	about_to_free_procedural_nodes.emit()


## IVSaveManager only.
func set_game_loading() -> void:
	game_loading.emit()


## IVSaveManager only.
func set_game_loaded(is_user_pause: bool) -> void:
	game_loaded.emit(is_user_pause)


## IVTimekeeper only.
func set_engine_paused(engine_paused: bool) -> void:
	engine_paused_changed.emit(engine_paused)


func change_tree_building_count(incr: int) -> void:
	assert(absi(incr) == 1)
	tree_building_count_changed.emit(incr)
