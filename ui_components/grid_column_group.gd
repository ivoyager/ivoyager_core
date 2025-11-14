# grid_column_group.gd
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
class_name IVGridColumnGroup
extends RefCounted

## A group of [GridControl] instances that share the same column widths
##
## This class uses a [IVControlSizeGroup] for each column, which manages
## [member Control.custom_minimum_size] for all Control children.[br][br]
##
## [member GridContainer.columns] must be consistent for all added GridContainers
## and cannot change. Also, don't change child order. Children can only be added
## to or removed from the end. (I.e., no Control ever changes column.)[br][br]
##
## @experimental: HAS NOT BEEN TESTED!

var _grids: Array[GridContainer] = []
var _columns: int
var _column_size_groups: Array[IVControlSizeGroup] = []
var _control_grids: Dictionary[Control, GridContainer] = {}
var _control_columns: Dictionary[Control, int] = {}



func _init() -> void:
	IVStateManager.about_to_quit.connect(_on_about_to_quit)


func add_grid_container(grid: GridContainer) -> void:
	assert(!_grids.has(grid))
	if _grids.is_empty():
		_columns = grid.columns
		for i in _columns:
			var column_size_group := IVControlSizeGroup.new()
			_column_size_groups.append(column_size_group)
	assert(grid.columns == _columns)
	for i in grid.get_child_count():
		var child := grid.get_child(i) as Control
		assert(child, "All GridContainer children must be Controls")
		_add_control(child, grid, i % _columns)
	grid.child_order_changed.connect(_on_grid_child_order_changed.bind(grid))
	_grids.append(grid)


func _on_about_to_quit() -> void:
	for grid in _grids:
		grid.child_order_changed.disconnect(_on_grid_child_order_changed)
	for control in _control_columns:
		control.tree_exiting.disconnect(_on_control_tree_exiting)
	_grids.clear()
	_column_size_groups.clear()
	_control_grids.clear()
	_control_columns.clear()


func _add_control(control: Control, grid: GridContainer, column: int) -> void:
	_column_size_groups[column].add_control(control)
	_control_grids[control] = grid
	_control_columns[control] = column
	control.tree_exiting.connect(_on_control_tree_exiting.bind(control), CONNECT_ONE_SHOT)


func _on_control_tree_exiting(control: Control) -> void:
	var grid := _control_grids[control]
	assert(grid.get_child(-1) == control, "Only the last child can be removed")
	var column := _control_columns[control]
	var column_size_group := _column_size_groups[column]
	column_size_group.remove_control(control)
	_control_grids.erase(control)
	_control_columns.erase(control)


func _on_grid_child_order_changed(grid: GridContainer) -> void:
	# This is an addition if the last child isn't connected...
	if grid.get_child_count() == 0:
		return
	var last_child := grid.get_child(-1) as Control
	assert(last_child, "All GridContainer children must be Controls")
	if last_child.tree_exiting.is_connected(_on_control_tree_exiting):
		return
	_add_control(last_child, grid, grid.get_child_count() % _columns)
