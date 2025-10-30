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
## Specify either [member body_flags] or [sbg_alias], not both.[br][br]
##
## The row is constructed according to properties set, in the order[br]
## [code]    [Label or IVLinkLabel]  [names/symbols OR points]  [orbits]  [/code],[br]
## where "names/symbols", "points" and "orbits" are HBoxContainers each with two
## widgets (see property descriptions).

const SCENE := "res://addons/ivoyager_core/gui_widgets/huds_hbox.tscn"

## Add a [Label] with specified text.
@export var label_text: StringName
## Instead of a [Label], add an [IVLinkLabel] using the specified [member
## label_text] as text and this value as the wiki page title key. If set, two other
## conditions must be met to have hyperlink lables: 1) [IVWikiManager] must
## be present (not default!). 2) [member ancestor_enable_wiki_links] is set to
## true OR an ancestor Control has property "enable_wiki_links" == true.
@export var link_page_title_key: StringName
## Require ancestor Control property "enable_wiki_links" before using link labels.
## See [member link_label_bbcode].
@export var require_ancestor_enable_wiki_links := true
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
## expected to have properties "column_group_1" and "column_group_2"
## (or at least one for each item here after the label), each specifying a
## [IVControlSizeGroup]. 
@export var ancestor_column_groups := false


var _enable_wiki_links := false


@warning_ignore("shadowed_variable")
static func create(
		label_text := &"",
		link_page_title_key := &"",
		require_ancestor_enable_wiki_links := true,
		body_flags := 0,
		sbg_aliases: Array[StringName] = [],
		names_symbols := true,
		points := true,
		orbits := true,
		ancestor_column_groups := false
	) -> IVHUDsHBox:
	var hbox: IVHUDsHBox = (load(SCENE) as PackedScene).instantiate()
	hbox.label_text = label_text
	hbox.link_page_title_key = link_page_title_key
	hbox.require_ancestor_enable_wiki_links = require_ancestor_enable_wiki_links
	hbox.body_flags = body_flags
	hbox.sbg_aliases = sbg_aliases
	hbox.names_symbols = names_symbols
	hbox.points = points
	hbox.orbits = orbits
	hbox.ancestor_column_groups = ancestor_column_groups
	return hbox


func _ready() -> void:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	if IVGlobal.program.has(&"WikiManager"):
		if (!require_ancestor_enable_wiki_links or
				IVUtils.get_control_tree_property(get_parent_control(), &"enable_wiki_links")):
			_enable_wiki_links = true
	
	var parent := get_parent_control()
	if _enable_wiki_links and link_page_title_key:
		var bbcode := "[url=%s]%s[/url]" % [link_page_title_key, tr(label_text)]
		var link_label := IVLinkLabel.create(bbcode)
		link_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(link_label)
	elif label_text:
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
			_add_to_group(hbox, 1, parent)
		else:
			var spacer := Control.new()
			add_child(spacer)
			_add_to_group(spacer, 1, parent)
	else:
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
			_add_to_group(hbox, 1, parent)
		else:
			var spacer := Control.new()
			add_child(spacer)
			_add_to_group(spacer, 1, parent)
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
		_add_to_group(hbox, 2, parent)
	else:
		var spacer := Control.new()
		add_child(spacer)
		_add_to_group(spacer, 2, parent)


func _add_to_group(control: Control, column: int, parent: Control) -> void:
	if !ancestor_column_groups:
		return
	var group_name := "column_group_%s" % column
	var group: IVControlSizeGroup = IVUtils.get_control_tree_property(parent, group_name)
	assert(group, "An ancestor Control must have property '%s' with an IVControlSizeGroup" %
			group_name)
	group.add_control(control)
