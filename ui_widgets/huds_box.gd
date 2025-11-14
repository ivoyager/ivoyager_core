# huds_box.gd
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
class_name IVHUDsBox
extends VBoxContainer

## A BoxContainer widget that has all user interface for HUDs
##
## To enable wiki link labels ([IVLinkLabel]) instead of plain [Label]s for each
## row, set [member enable_wiki_links] to true. [IVWikiManager] must also be
## added in [IVCoreInitializer].

## Theme type variation used by [IVHUDsFoldable] decendents. If &"" (default),
## the foldable widgets will keep looking up the Node tree for this "tree
## property". The property is set in [IVTopUI] for a global GUI value.
@export var foldables_theme_type_variation := &""

## "Column 1" size group available for descendent Controls.
var column_group_1 := IVControlSizeGroup.new()
## "Column 2" size group available for descendent Controls.
var column_group_2 := IVControlSizeGroup.new()


func _ready() -> void:
	column_group_1.add_control($BodiesHeaders/NamesSymbolsHeader as Control)
	column_group_2.add_control($BodiesHeaders/OrbitsHeader as Control)
	column_group_1.add_control($SBGsHeaders/PointsHeader as Control)
	column_group_2.add_control($SBGsHeaders/OrbitsHeader as Control)
	
	
