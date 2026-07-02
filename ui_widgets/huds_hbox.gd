# huds_hbox.gd
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
class_name IVHUDsHBox
extends HBoxContainer

## An HBoxContainer widget containing a row of HUDs widgets for a class of
## [IVBody] or [IVSmallBodiesGroup]
##
## Specify either [member body_flags] or [member sbg_aliases], not both.[br][br]
##
## The row is [code][Label] [visibility checkboxes] [symbol & color pickers][/code].
## Checkboxes are symbol/name/orbit for a body or symbol/orbit for an SBG; the two
## pickers are an [IVSymbolPickerButton] and a shared [IVHUDsColorPickerButton]
## (one color for symbol, name and orbit). The checkbox group and the picker group
## each align across rows via ancestor [IVControlSizeGroup]s (see
## [member ancestor_column_groups]).

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
## Add an orbit-visibility [IVHUDsCheckBox]. Set false for bodies with no orbit
## (e.g., the Sun).
@export var orbits := true
## For coordinating "column" spacing among rows. If true, an ancestor Control is
## expected to have properties "column_group_1" and "column_group_2", each a
## [IVControlSizeGroup]. Column 1 is the visibility checkboxes; column 2 is the
## symbol and color pickers.
@export var ancestor_column_groups := false


var _enable_links := false


## Creates a new [IVHUDsHBox] instance using specified parameters.
@warning_ignore("shadowed_variable")
static func create(
		label_text := &"",
		link_label_key := &"",
		require_links_enabled := true,
		body_flags := 0,
		sbg_aliases: Array[StringName] = [],
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
	hbox.orbits = orbits
	hbox.ancestor_column_groups = ancestor_column_groups
	return hbox


func _ready() -> void:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:

	if IVGlobal.program.has(&"WikiManager"):
		_enable_links = (!require_links_enabled or
				IVTree.get_ancestor_bool(self, &"enable_huds_hbox_links"))

	# label
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

	# column 1: visibility checkboxes
	var checkboxes := HBoxContainer.new()
	checkboxes.size_flags_horizontal = SIZE_SHRINK_END
	checkboxes.alignment = ALIGNMENT_BEGIN
	if body_flags:
		checkboxes.add_child(IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.SYMBOLS, body_flags))
		checkboxes.add_child(IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.NAMES, body_flags))
		if orbits:
			checkboxes.add_child(IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.ORBITS, body_flags))
	else:
		checkboxes.add_child(IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.SYMBOLS, 0, sbg_aliases))
		if orbits:
			checkboxes.add_child(IVHUDsCheckBox.create(IVHUDsCheckBox.HUDsType.ORBITS, 0, sbg_aliases))
	add_child(checkboxes)
	_add_to_group(checkboxes, 1)

	# column 2: symbol picker + shared color picker
	var pickers := HBoxContainer.new()
	pickers.size_flags_horizontal = SIZE_SHRINK_END
	pickers.alignment = ALIGNMENT_CENTER
	pickers.add_child(IVSymbolPickerButton.create(body_flags, sbg_aliases))
	pickers.add_child(IVHUDsColorPickerButton.create(body_flags, sbg_aliases))
	add_child(pickers)
	_add_to_group(pickers, 2)


func _add_to_group(control: Control, column: int) -> void:
	if !ancestor_column_groups:
		return
	var group_name := StringName("column_group_%s" % column)
	var group: IVControlSizeGroup = IVTree.get_ancestor_object(self, group_name)
	assert(group, "An ancestor must have property '%s' with an IVControlSizeGroup" % group_name)
	group.add_control(control)
