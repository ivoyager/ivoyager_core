# huds_foldable.gd
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
class_name IVHUDsFoldable
extends FoldableContainer

## A FoldableContainer widget containing a row of HUDs widgets for a
## "superclass" of [IVBody] or [IVSmallBodiesGroup]
##
## This widget is constructed with an [IVHUDsHBox] after the title, so it
## appears much like an [IVHUDsHBox] except that it is foldable. It is expected
## to have [IVHUDsHBox]es as descendents (most sensibly in a VBoxContainer),
## and should probably represent the union all of its descendent body or SBG
## classes. If [member build_as_union] == true (default), [member body_flags]
## and [member sbg_aliases] will be set automatically as the union of all
## descendent [IVHUDsHBox] values. Other properties and
## [member FoldableContainer.title] should be set as needed.[br][br]
##
## See [IVHUDsHBox].



## If true, automatically set [member body_flags] and [member sbg_aliases] to
## represent the union of all [IVHUDsHBox] descendents. All descendents must be
## consistent in representing bodies or SBGs. (It will cause an error if the
## union results in a non-zero [member body_flags] AND a non-empty [member
## sbg_aliases].)
@export var build_as_union := true
## See [member IVHUDsHBox.body_flags]. If [member build_as_union] == true
## (default), this will be set automatically as the or'd union of all child
## [member IVHUDsHBox.body_flags].
@export var body_flags := 0
## See [member IVHUDsHBox.sbg_aliases]. If [member build_as_union] == true
## (default), this will be set automatically as the union of all child
## [member IVHUDsHBox.sbg_aliases].
@export var sbg_aliases: Array[StringName] = []
## See [member IVHUDsHBox.names_symbols].
@export var names_symbols := true
## See [member IVHUDsHBox.points].
@export var points := true
## See [member IVHUDsHBox.orbits].
@export var orbits := true
## See [member IVHUDsHBox.ancestor_column_groups].
@export var ancestor_column_groups := false



func _ready() -> void:
	if build_as_union:
		_set_union_properties()
	else:
		assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	var huds_hbox := IVHUDsHBox.create(&"", &"", true, body_flags, sbg_aliases, names_symbols,
			points, orbits, ancestor_column_groups)
	add_title_bar_control(huds_hbox)


func _set_union_properties() -> void:
	assert(!body_flags, "body_flags has value; don't set properties if build_as_union == true")
	assert(!sbg_aliases, "sbg_aliases has values; don't set properties if build_as_union == true")
	body_flags = 0
	sbg_aliases.clear()
	_set_union_properties_recursive(self)
	assert((!body_flags) != (!sbg_aliases), "Union has both body and SBG child IVHUDsHBoxes")


func _set_union_properties_recursive(control: Control) -> void:
	for child in control.get_children():
		var huds_hbox := child as IVHUDsHBox
		if huds_hbox:
			body_flags |= huds_hbox.body_flags
			IVUtils.merge_array(sbg_aliases, huds_hbox.sbg_aliases)
			continue
		var control_child := child as Control
		if control_child:
			_set_union_properties_recursive(control_child)
