# huds_hbox.gd
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
class_name IVHUDsHBox
extends HBoxContainer

## An HBoxContainer widget containing a row of HUDs widgets for a class of
## [IVBody] or [IVSmallBodiesGroup]
##
## Specify either [member body_flags] or [member sbg_aliases], not both.[br][br]
##
## The row is constructed according to properties set, in the order[br]
## [code]    [Label or IVLinkLabel]  [names/symbols OR points]  [orbits]  [/code],[br]
## where "names/symbols", "points" and "orbits" are HBoxContainers each with two
## widgets (see property descriptions).

const SCENE := "res://addons/ivoyager_core/ui_widgets/huds_hbox.tscn"

## Row label text. If not set, skip label.
@export var label_text := &""
## Use [IVLinkLabel] instead of a [Label] using the specified [member
## label_text] as text and this value as the wiki page title key. If set, two other
## conditions must be met to have link lables: 1) [IVWikiManager] must
## be present (not default!). 2) [member require_links_enabled] is set to
## false OR an ancestor node has property "enable_huds_hbox_links" == true.
@export var link_label_key := &""
## If true (default), require ancestor property "enable_huds_hbox_links" == true
## to use IVLinkLabel. See [member link_label_key].
@export var require_links_enabled := true
## Specify a class of body by [enum IVBody.BodyFlags]. In most cases this should
## be one of the exclusive flags defined in data table "visual_groups.tsv"
## field "body_flags" (only these have default colors and visibilities).
## If not 0, [member sbg_aliases] must be empty.
@export var body_flags := 0
## Specify a class of small bodies by listing aliases matching
## [member IVSmallBodiesGroup.sbg_alias] (e.g., ["JT4", "JT5"] for both Trojan
## groups). If not empty, [member body_flags] must be 0.
@export var sbg_aliases: Array[StringName] = []
## Used only for bodies. Add two [IVHUDsCheckBox]es for names and symbols in an
## HBoxContainer.
@export var names_symbols := true
## Used only for SBGs. Add an [IVHUDsCheckBox] and an [IVHUDsColorPickerButton] for
## points in an HBoxContainer.
@export var points := true
## Add an [IVHUDsCheckBox] and an [IVHUDsColorPickerButton] for orbits in an
## HBoxContainer.
@export var orbits := true
## For coordinating "column" spacing among rows. If true, an ancestor Control is
## expected to have properties "column_group_1" and/or "column_group_2" (as
## needed), each specifying a [IVControlSizeGroup]. Column 1 is always
## "names/symbols" or "points", and column 2 is always "orbits".
@export var ancestor_column_groups := false


var _enable_links := false


@warning_ignore("shadowed_variable")
static func create(
		label_text := &"",
		link_label_key := &"",
		require_links_enabled := true,
		body_flags := 0,
		sbg_aliases: Array[StringName] = [],
		names_symbols := true,
		points := true,
		orbits := true,
		ancestor_column_groups := false
		) -> IVHUDsHBox:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	var hbox: IVHUDsHBox = (load(SCENE) as PackedScene).instantiate()
	hbox.label_text = label_text
	hbox.link_label_key = link_label_key
	hbox.require_links_enabled = require_links_enabled
	hbox.body_flags = body_flags
	hbox.sbg_aliases = sbg_aliases
	hbox.names_symbols = names_symbols
	hbox.points = points
	hbox.orbits = orbits
	hbox.ancestor_column_groups = ancestor_column_groups
	return hbox


func _ready() -> void:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVStateManager.core_inited.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	
	if IVGlobal.program.has(&"WikiManager"):
		_enable_links = (!require_links_enabled or
				IVUtils.get_tree_bool(self, &"enable_huds_hbox_links"))
	
	if label_text:
		if _enable_links and link_label_key:
			var bbcode := "[url=%s]%s[/url]" % [link_label_key, tr(label_text)]
			var link_label := IVLinkLabel.create(bbcode)
			link_label.size_flags_horizontal = SIZE_EXPAND_FILL
			add_child(link_label)
		else:
			var label := Label.new()
			label.text = label_text
			label.size_flags_horizontal = SIZE_EXPAND_FILL
			add_child(label)
	if body_flags:
		if names_symbols:
			var hbox := HBoxContainer.new()
			hbox.size_flags_horizontal = SIZE_SHRINK_CENTER
			hbox.alignment = ALIGNMENT_CENTER
			var names_ckbx := IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.NAMES, body_flags)
			var symbols_ckbx := IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.SYMBOLS, body_flags)
			hbox.add_child(names_ckbx)
			hbox.add_child(symbols_ckbx)
			add_child(hbox)
			_add_to_group(hbox, 1)
		else:
			var spacer := Control.new()
			add_child(spacer)
			_add_to_group(spacer, 1)
	else: # SBGs
		if points:
			var hbox := HBoxContainer.new()
			hbox.size_flags_horizontal = SIZE_SHRINK_CENTER
			hbox.alignment = ALIGNMENT_CENTER
			var points_ckbx := IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.POINTS, 0, sbg_aliases)
			var points_cpb := IVHUDsColorPickerButton.create(
					IVHUDsColorPickerButton.ColorHUDsType.POINTS, 0, sbg_aliases)
			hbox.add_child(points_ckbx)
			hbox.add_child(points_cpb)
			add_child(hbox)
			_add_to_group(hbox, 1)
		else:
			var spacer := Control.new()
			add_child(spacer)
			_add_to_group(spacer, 1)
	if orbits:
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_SHRINK_CENTER
		hbox.alignment = ALIGNMENT_CENTER
		var orbits_ckbx := IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.ORBITS, body_flags,
				sbg_aliases)
		var orbits_cpb := IVHUDsColorPickerButton.create(
				IVHUDsColorPickerButton.ColorHUDsType.ORBITS, body_flags, sbg_aliases)
		hbox.add_child(orbits_ckbx)
		hbox.add_child(orbits_cpb)
		add_child(hbox)
		_add_to_group(hbox, 2)
	else:
		var spacer := Control.new()
		add_child(spacer)
		_add_to_group(spacer, 2)


func _add_to_group(control: Control, column: int) -> void:
	if !ancestor_column_groups:
		return
	var group_name := StringName("column_group_%s" % column)
	var group: IVControlSizeGroup = IVUtils.get_tree_object(self, group_name)
	assert(group, "An ancestor must have property '%s' with an IVControlSizeGroup" % group_name)
	group.add_control(control)
